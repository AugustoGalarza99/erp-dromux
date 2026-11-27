-- Deshace el cambio 009. Los pedidos y presupuestos ya creados conservan el nombre guardado.
begin;

CREATE OR REPLACE FUNCTION public.access_audit_events_list(p_company uuid, p_page integer DEFAULT 0)
 RETURNS TABLE(created_at timestamp with time zone, action text, actor_email text, target_email text, target_role_name text, detail jsonb, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'administrador' then
    raise exception 'Solo el administrador puede ver el historial de accesos' using errcode = '42501';
  end if;
  if p_page is null or p_page < 0 or p_page > 100000 then
    raise exception 'Página inválida';
  end if;
  return query
    select e.creado_en, e.accion, a.email::text, t.email::text, r.nombre, e.detalle, count(*) over ()
    from public.ajustes_auditoria_accesos e
    left join auth.users a on a.id = e.autor_id
    left join auth.users t on t.id = e.usuario_destino_id
    left join public.ajustes_roles r on r.id = e.rol_destino_id and r.empresa_id = e.empresa_id
    where e.empresa_id = p_company
    order by e.creado_en desc, e.id desc
    limit 25 offset p_page * 25;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_purchase_request(p_company uuid, p_note text, p_needed_by date, p_priority text, p_lines jsonb, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_existing public.compras_pedidos_antiduplicado%rowtype;
  v_payload jsonb;
  v_number bigint;
  v_request uuid;
  v_label text;
  v_line jsonb;
  v_item uuid;
  v_quantity numeric;
  v_code text;
  v_name text;
  v_unit text;
  v_note text;
  v_index smallint := 0;
  v_seen uuid[] := '{}';
begin
  if auth.uid() is null
     or not (private.has_permission(p_company, 'compras_pedidos', 'crear')
             or private.has_permission(p_company,'compras_pedidos','crear')) then
    raise exception 'Sin permiso para crear pedidos de compra' using errcode = '42501';
  end if;
  if p_request_id is null then raise exception 'Identificador de solicitud inválido'; end if;
  if p_priority is null or p_priority not in ('normal', 'urgente')
     or (p_needed_by is not null
         and (p_needed_by < current_date - 1 or p_needed_by > current_date + 730))
     or length(coalesce(p_note, '')) > 500
     or jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) not between 1 and 200 then
    raise exception 'Datos del pedido inválidos';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('purchase-request:' || p_company::text || ':' || p_request_id::text, 0));
  v_payload := jsonb_build_object('note', btrim(coalesce(p_note, '')),
    'needed_by', p_needed_by, 'priority', p_priority, 'lines', p_lines);
  select * into v_existing from public.compras_pedidos_antiduplicado
  where empresa_id = p_company and solicitud_id = p_request_id;
  if found then
    if v_existing.autor_id <> auth.uid() or v_existing.solicitud_datos <> v_payload then
      raise exception 'Esta solicitud ya se usó con otro pedido';
    end if;
    return v_existing.pedido_id;
  end if;

  perform 1 from public.empresas c where c.id = p_company and c.activo for share;
  if not found then raise exception 'Empresa inactiva'; end if;

  -- Nombre visible: el cargado en el perfil o, si falta, la parte local del correo (sin el dominio).
  select coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                  nullif(split_part(coalesce(u.email, ''), '@', 1), ''), 'Usuario')
  into v_label from auth.users u where u.id = auth.uid();

  insert into public.empresas_numeradores(empresa_id,documento) values (p_company,'pedido_interno')
  on conflict (empresa_id,documento) do nothing;
  update public.empresas_numeradores c
  set proximo_numero = c.proximo_numero + 1
  where c.empresa_id = p_company and c.documento = 'pedido_interno'
  returning c.proximo_numero - 1 into v_number;

  insert into public.compras_pedidos(
    empresa_id, numero, solicitado_por, solicitante_nombre, prioridad, fecha_necesaria, nota
  ) values (
    p_company, v_number, auth.uid(), left(coalesce(v_label, 'Usuario'), 200),
    p_priority, p_needed_by, btrim(coalesce(p_note, ''))
  ) returning id into v_request;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(v_line) is distinct from 'object'
       or coalesce(v_line ->> 'quantity', '') !~ '^[0-9]+(\.[0-9]{1,6})?$' then
      raise exception 'Línea de pedido inválida';
    end if;
    v_quantity := (v_line ->> 'quantity')::numeric;
    if v_quantity <= 0 or v_quantity >= 1000000000000 then
      raise exception 'Cantidad fuera de rango';
    end if;
    v_note := btrim(coalesce(v_line ->> 'note', ''));
    if length(v_note) > 200 then raise exception 'La nota de una línea es demasiado larga'; end if;

    v_index := v_index + 1;
    if coalesce(v_line ->> 'item_id', '') <> '' then
      if (v_line ->> 'item_id') !~
         '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
        raise exception 'Línea de pedido inválida';
      end if;
      v_item := (v_line ->> 'item_id')::uuid;
      if v_item = any (v_seen) then raise exception 'Un ítem no puede repetirse en el pedido'; end if;
      v_seen := v_seen || v_item;
      select i.codigo, i.nombre, u.simbolo into v_code, v_name, v_unit
      from public.stock_items i
      join public.stock_unidades u on u.empresa_id = i.empresa_id and u.id = i.unidad_id
      where i.empresa_id = p_company and i.id = v_item and i.activo and not i.archivado
      for share of i;
      if not found then raise exception 'El pedido contiene un ítem inexistente o inactivo'; end if;
      insert into public.compras_pedidos_lineas(
        empresa_id, pedido_id, linea, item_id, item_codigo, item_nombre, unidad_simbolo, cantidad, nota
      ) values (p_company, v_request, v_index, v_item, v_code, v_name, v_unit, v_quantity, v_note);
    else
      v_name := btrim(coalesce(v_line ->> 'free_text', ''));
      v_unit := btrim(coalesce(v_line ->> 'unit', ''));
      if length(v_name) not between 2 and 160 or length(v_unit) > 20 then
        raise exception 'Escribí qué necesitás (2 a 160 caracteres) y una unidad de hasta 20';
      end if;
      insert into public.compras_pedidos_lineas(
        empresa_id, pedido_id, linea, item_id, item_codigo, item_nombre, unidad_simbolo, cantidad, nota
      ) values (p_company, v_request, v_index, null, null, v_name, v_unit, v_quantity, v_note);
    end if;
  end loop;

  insert into public.compras_pedidos_antiduplicado(empresa_id, solicitud_id, pedido_id, solicitud_datos, autor_id)
  values (p_company, p_request_id, v_request, v_payload, auth.uid());
  return v_request;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_quote(p_company uuid, p_customer uuid, p_name text, p_tax_id text, p_email text, p_phone text, p_address text, p_valid_until date, p_note text, p_show_tax boolean, p_lines jsonb, p_request_id uuid, p_tax_included boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_payload jsonb; v_existing public.ventas_presupuestos%rowtype; v_customer public.ventas_clientes%rowtype;
  v_name text; v_tax_id text; v_email text; v_phone text; v_address text;
  v_line jsonb; v_item public.stock_items%rowtype; v_res record; v_unit_symbol text;
  v_qty numeric; v_disc numeric; v_reason text; v_cap numeric; v_unit numeric; v_total numeric;
  v_lines jsonb := '[]'::jsonb; v_seen uuid[] := '{}'; v_n smallint := 0;
  v_net numeric := 0; v_tax numeric := 0; v_breakdown jsonb; v_id uuid := gen_random_uuid(); v_number bigint;
  v_label text; v_item_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'ventas', 'crear')
     or not private.has_permission(p_company, 'ventas', 'ver') then
    raise exception 'Necesitás permiso para crear presupuestos' using errcode = '42501';
  end if;
  if p_request_id is null or p_lines is null or jsonb_typeof(p_lines) <> 'array'
     or jsonb_array_length(p_lines) not between 1 and 200 then
    raise exception 'Revisá los productos del presupuesto (entre 1 y 200)';
  end if;
  if coalesce(p_show_tax, true) and coalesce(p_tax_included, false) then
    raise exception 'Elegí mostrar el IVA discriminado o sumarlo sin discriminar, no las dos cosas';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('quote:' || p_company::text || ':' || p_request_id::text, 0));
  v_payload := jsonb_build_object('customer', p_customer, 'name', btrim(coalesce(p_name, '')),
    'tax_id', btrim(coalesce(p_tax_id, '')), 'email', btrim(coalesce(p_email, '')),
    'phone', btrim(coalesce(p_phone, '')), 'address', btrim(coalesce(p_address, '')),
    'valid_until', p_valid_until, 'note', btrim(coalesce(p_note, '')),
    'show_tax', coalesce(p_show_tax, true), 'lines', p_lines)
    || case when coalesce(p_tax_included, false) then jsonb_build_object('tax_included', true) else '{}'::jsonb end;
  select * into v_existing from public.ventas_presupuestos where empresa_id = p_company and solicitud_id = p_request_id;
  if found then
    if v_existing.creado_por <> auth.uid() or v_existing.solicitud_datos <> v_payload then
      raise exception 'Esta solicitud ya se utilizó con otros datos';
    end if;
    return v_existing.id;
  end if;
  -- Estas validaciones van DESPUÉS de la idempotencia: un reintento tardío devuelve el presupuesto ya creado.
  if p_valid_until is null or p_valid_until < v_today or p_valid_until > v_today + 365 then
    raise exception 'La vigencia debe estar entre hoy y un año';
  end if;
  if length(coalesce(p_note, '')) > 1000 then raise exception 'Las condiciones son demasiado largas'; end if;
  perform 1 from public.empresas where id = p_company and activo for share;
  if not found then raise exception 'La empresa no está activa'; end if;

  if p_customer is not null then
    select * into v_customer from public.ventas_clientes
    where empresa_id = p_company and id = p_customer and activo for share;
    if not found then raise exception 'Elegí un cliente activo'; end if;
    v_name := v_customer.nombre; v_tax_id := v_customer.identificacion_fiscal; v_email := v_customer.email;
    v_phone := v_customer.telefono; v_address := v_customer.direccion;
  else
    v_name := btrim(coalesce(p_name, '')); v_tax_id := btrim(coalesce(p_tax_id, ''));
    v_email := btrim(coalesce(p_email, '')); v_phone := btrim(coalesce(p_phone, ''));
    v_address := btrim(coalesce(p_address, ''));
    if length(v_name) not between 2 and 160 or length(v_tax_id) > 30 or length(v_email) > 160
       or length(v_phone) > 40 or length(v_address) > 240 then
      raise exception 'Indicá el nombre del interesado (hasta 160 caracteres) y revisá sus datos';
    end if;
  end if;

  select coalesce(s.descuento_maximo_porcentaje, 0) into v_cap from (select 1) x
  left join public.ventas_precios_config s on s.empresa_id = p_company;

  -- Se conserva el orden en que se cargaron las líneas (es el orden que ve el cliente en el PDF).
  for v_line in select t.value from jsonb_array_elements(p_lines) with ordinality as t(value, ord) order by t.ord loop
    v_n := v_n + 1;
    begin
      v_qty := (v_line ->> 'quantity')::numeric;
    exception when others then v_qty := null;
    end;
    if v_qty is null or v_qty <= 0 or v_qty >= 1000000000000 or v_qty <> round(v_qty, 6) then
      raise exception 'La cantidad de la línea % es inválida', v_n;
    end if;
    begin
      v_item_id := (v_line ->> 'item_id')::uuid;
    exception when others then v_item_id := null;
    end;
    select * into v_item from public.stock_items
    where empresa_id = p_company and id = v_item_id and activo and tipo_item = 'producto_terminado';
    if v_item_id is null or not found then raise exception 'La línea % tiene un producto inactivo o que no es terminado', v_n; end if;
    if v_item.id = any (v_seen) then raise exception 'Cada producto puede figurar una sola vez'; end if;
    v_seen := v_seen || v_item.id;
    select * into v_res from private.sale_resolve_price(p_company, p_customer, v_item.id);
    if v_res.price is null or v_res.price <= 0 then raise exception 'Definí el precio de venta de %', v_item.nombre; end if;

    begin
      v_disc := coalesce(nullif(btrim(v_line ->> 'discount_percent'), '')::numeric, 0);
    exception when others then v_disc := -1;
    end;
    v_reason := nullif(btrim(v_line ->> 'discount_reason'), '');
    if v_disc = 0 then v_reason := null; end if;
    if v_disc < 0 or v_disc >= 100 or v_disc <> round(v_disc, 2) then
      raise exception 'El descuento de % es inválido', v_item.nombre;
    end if;
    if length(coalesce(v_reason, '')) > 200 then raise exception 'El motivo del descuento es demasiado largo'; end if;
    if v_disc > v_cap then
      if private.get_user_role(p_company) is distinct from 'administrador' then
        raise exception 'El descuento de % supera el máximo permitido (% %%)', v_item.nombre, v_cap;
      end if;
      if length(regexp_replace(coalesce(v_reason, ''), '[^[:alnum:]]', '', 'g')) < 3 then
        raise exception 'Indicá el motivo del descuento de %', v_item.nombre;
      end if;
    end if;
    v_unit := round(v_res.price * (1 - v_disc / 100), 2);
    if v_disc > 0 and v_unit <= 0 then raise exception 'El descuento de % deja el precio en cero', v_item.nombre; end if;
    v_total := round(v_qty * v_unit, 2);
    v_net := v_net + v_total;
    if v_net >= 10000000000000000 then raise exception 'El total supera el máximo permitido'; end if;
    select simbolo into v_unit_symbol from public.stock_unidades where empresa_id = p_company and id = v_item.unidad_id;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'item_id', v_item.id, 'item_code', v_item.codigo, 'item_name', v_item.nombre, 'unit_symbol', v_unit_symbol,
      'quantity', v_qty, 'price_list_id', v_res.list_id, 'list_unit_price', v_res.price,
      'discount_percent', v_disc, 'discount_reason', v_reason, 'unit_price', v_unit,
      'line_total', v_total, 'tax_percent', v_res.tax_percent));
  end loop;

  -- IVA por alícuota. Discriminado: sobre la base de cada alícuota. Sumado sin discriminar (consumidor final):
  -- línea por línea, para que los precios con IVA que ve el cliente sumen exactamente el total.
  select coalesce(jsonb_agg(jsonb_build_object('rate', g.rate, 'base', g.base, 'tax', g.tax) order by g.rate), '[]'::jsonb)
  into v_breakdown
  from (select (e ->> 'tax_percent')::numeric as rate, sum((e ->> 'line_total')::numeric) as base,
          case when coalesce(p_tax_included, false)
            then sum(round((e ->> 'line_total')::numeric * (e ->> 'tax_percent')::numeric / 100, 2))
            else round(sum((e ->> 'line_total')::numeric) * (e ->> 'tax_percent')::numeric / 100, 2) end as tax
        from jsonb_array_elements(v_lines) e group by 1) g;
  select coalesce(sum((b ->> 'tax')::numeric), 0) into v_tax from jsonb_array_elements(v_breakdown) b;
  if v_net + v_tax >= 10000000000000000 then raise exception 'El total supera el máximo permitido'; end if;

  insert into public.empresas_numeradores(empresa_id,documento) values (p_company,'presupuesto') on conflict do nothing;
  update public.empresas_numeradores set proximo_numero = proximo_numero + 1
  where empresa_id = p_company and documento = 'presupuesto' returning proximo_numero - 1 into v_number;
  -- Si el perfil guarda un identificador en vez de un nombre, se muestra "Usuario".
  select coalesce(nullif(btrim(case when p.nombre ~* '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    then null else p.nombre end), ''), 'Usuario') into v_label
  from (select 1) x left join public.ajustes_perfiles p on p.id = auth.uid();

  insert into public.ventas_presupuestos(id, empresa_id, numero, solicitud_id, solicitud_datos, cliente_id, cliente_nombre,
    cliente_identificacion_fiscal, cliente_email, cliente_telefono, cliente_direccion, vigente_hasta, nota, mostrar_impuesto,
    impuesto_incluido, total_neto, total_impuesto, total_bruto, impuestos_detalle, creado_por, creado_por_nombre)
  values (v_id, p_company, v_number, p_request_id, v_payload, p_customer, v_name, v_tax_id, v_email, v_phone,
    v_address, p_valid_until, btrim(coalesce(p_note, '')), coalesce(p_show_tax, true),
    coalesce(p_tax_included, false), v_net, v_tax,
    v_net + v_tax, v_breakdown, auth.uid(), coalesce(v_label, 'Usuario'));

  v_n := 0;
  for v_line in select value from jsonb_array_elements(v_lines) loop
    v_n := v_n + 1;
    insert into public.ventas_presupuestos_lineas(empresa_id, presupuesto_id, linea, item_id, item_codigo, item_nombre, unidad_simbolo,
      cantidad, lista_precio_id, precio_unitario_lista, descuento_porcentaje, descuento_motivo, precio_unitario, total_linea,
      impuesto_porcentaje)
    values (p_company, v_id, v_n, (v_line ->> 'item_id')::uuid, v_line ->> 'item_code', v_line ->> 'item_name',
      v_line ->> 'unit_symbol', (v_line ->> 'quantity')::numeric, (v_line ->> 'price_list_id')::uuid,
      (v_line ->> 'list_unit_price')::numeric, (v_line ->> 'discount_percent')::numeric,
      v_line ->> 'discount_reason', (v_line ->> 'unit_price')::numeric, (v_line ->> 'line_total')::numeric,
      (v_line ->> 'tax_percent')::numeric);
  end loop;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_price_list_history(p_company uuid, p_list uuid, p_item uuid, p_page integer DEFAULT 0)
 RETURNS TABLE(changed_at timestamp with time zone, item_id uuid, item_code text, item_name text, old_net_price numeric, new_net_price numeric, method text, method_value numeric, cost_snapshot numeric, source text, reason text, changed_by_label text, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
  perform private.price_require_cost_view(p_company);
  return query
  select h.cambiado_en, h.item_id, i.codigo, i.nombre, h.precio_neto_anterior, h.precio_neto_nuevo, h.metodo, h.metodo_valor,
    h.costo_copia, h.origen, h.motivo,
    coalesce(nullif(btrim((select p.nombre from public.ajustes_perfiles p where p.id = h.cambiado_por)), ''), 'Usuario'),
    count(*) over ()
  from public.ventas_listas_items_historial h
  join public.stock_items i on i.empresa_id = h.empresa_id and i.id = h.item_id
  where h.empresa_id = p_company and h.lista_precio_id = p_list and (p_item is null or h.item_id = p_item)
  order by h.cambiado_en desc, h.id
  limit 50 offset greatest(coalesce(p_page, 0), 0) * 50;
end;
$function$;

drop function if exists private.etiqueta_soporte(uuid, uuid);

commit;

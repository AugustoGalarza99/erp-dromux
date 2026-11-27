-- 02b. Funciones (segunda parte).
begin;
set local check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.erp_price_settings(p_company uuid)
 RETURNS TABLE(default_tax_percent numeric, min_margin_percent numeric, commission_percent numeric, structure_percent numeric, max_discount_percent numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.price_require_cost_view(p_company);
  return query select coalesce(s.impuesto_porcentaje_predeterminado, 21::numeric), coalesce(s.margen_minimo_porcentaje, 0::numeric),
    coalesce(s.comision_porcentaje, 0::numeric), coalesce(s.estructura_porcentaje, 0::numeric),
    coalesce(s.descuento_maximo_porcentaje, 0::numeric)
  from (select 1) x left join public.ventas_precios_config s on s.empresa_id = p_company;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_product_costs(p_company uuid, p_search text DEFAULT ''::text)
 RETURNS TABLE(item_id uuid, code text, name text, item_type text, unit_symbol text, cost numeric, price numeric, margin numeric, margin_percent numeric, status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_item record; v_cost numeric;
begin
  if auth.uid() is null or not private.has_permission(p_company,'finanzas','ver')
    or not private.has_permission(p_company,'items','ver') then
    raise exception 'Necesitás acceso a finanzas y productos' using errcode='42501'; end if;
  if length(coalesce(p_search,''))>100 then raise exception 'Búsqueda demasiado larga'; end if;
  for v_item in select i.id,i.codigo,i.nombre,i.tipo_item,i.precio_venta_unitario,u.simbolo,
    i.costo_unitario_referencia,f.producto_id has_formula
    from public.stock_items i join public.stock_unidades u on u.empresa_id=i.empresa_id and u.id=i.unidad_id
    left join public.produccion_formulas f on f.empresa_id=i.empresa_id and f.producto_id=i.id
    where i.empresa_id=p_company and i.activo and i.tipo_item in ('producto_terminado','semielaborado')
    and (coalesce(p_search,'')='' or i.nombre ilike '%'||p_search||'%'
      or i.codigo ilike '%'||p_search||'%') order by i.nombre limit 100 loop
    v_cost:=null;
    if v_item.has_formula is not null then
      begin
        v_cost:=private.production_unit_cost(p_company,v_item.id);
      exception when raise_exception then v_cost:=null;
      end;
    else v_cost:=v_item.costo_unitario_referencia; end if;
    item_id:=v_item.id; code:=v_item.codigo; name:=v_item.nombre;
    item_type:=v_item.tipo_item; unit_symbol:=v_item.simbolo;
    cost:=v_cost; price:=v_item.precio_venta_unitario;
    margin:=case when v_cost is not null and price is not null then price-v_cost end;
    margin_percent:=case when price>0 and v_cost is not null
      then round(100*(price-v_cost)/price,2) end;
    status:=case when v_cost is null then 'Costo incompleto'
      when price is null then 'Sin precio de venta' else 'Listo' end;
    return next;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_production_alerts(p_company uuid)
 RETURNS TABLE(alert_key text, fingerprint text, severity text, title text, detail text, destination text, occurred_on date)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null or not private.has_permission(p_company,'inicio','ver') then
    raise exception 'Sin acceso al centro operativo' using errcode='42501';
  end if;
  return query select base.alert_key,base.fingerprint,base.severity,
    base.title,base.detail,base.destination,base.occurred_on
    from private.erp_production_alerts(p_company) base;
  if private.has_permission(p_company,'produccion_resumen','ver')
    and private.has_permission(p_company,'stock_saldos','ver') then
    return query
    select 'reservation:'||j.id::text||':'||r.componente_id::text,
      greatest(0,r.cantidad_requerida-coalesce(e.consumed,0)-r.cantidad_reservada)::text
        ||':'||coalesce(j.fecha_limite::text,''),
      case when j.fecha_limite <= v_today+3 then 'critical' else 'warning' end,
      'Faltan insumos para una orden',
      i.nombre||' · Faltan '||
        greatest(0,r.cantidad_requerida-coalesce(e.consumed,0)-r.cantidad_reservada)::text
        ||' '||u.simbolo||' para '||p.nombre,
      '/production/orders?job='||j.id::text,
      coalesce(j.fecha_limite,v_today)
    from public.produccion_ordenes_reservas r
    join public.produccion_ordenes j on j.empresa_id=r.empresa_id and j.id=r.orden_id
    join public.stock_items i on i.empresa_id=r.empresa_id and i.id=r.componente_id
    join public.stock_items p on p.empresa_id=j.empresa_id and p.id=j.producto_id
    join public.stock_unidades u on u.empresa_id=i.empresa_id and u.id=i.unidad_id
    left join lateral (
      select sum(case when ev.tipo='entrega' then ev.cantidad else -ev.cantidad end) consumed
      from public.produccion_ordenes_eventos ev
      where ev.empresa_id=r.empresa_id and ev.orden_id=r.orden_id
        and ev.componente_id=r.componente_id
    ) e on true
    where r.empresa_id=p_company and not i.stock_infinito
      and j.estado in ('pendiente','en_proceso')
      and r.cantidad_requerida-coalesce(e.consumed,0)>r.cantidad_reservada;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_production_dashboard(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null
    or not private.has_permission(p_company,'produccion_resumen','ver') then
    raise exception 'Sin acceso a producción' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'queued', (select count(*) from public.produccion_ordenes
      where empresa_id = p_company and estado = 'pendiente'),
    'in_progress', (select count(*) from public.produccion_ordenes
      where empresa_id = p_company and estado = 'en_proceso'),
    'overdue', (select count(*) from public.produccion_ordenes
      where empresa_id = p_company and estado in ('pendiente', 'en_proceso')
        and fecha_limite < v_today),
    'next', (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb)
      from (select j.id as id, j.estado as status, j.fecha_limite as due_on, j.nota as note,
        j.cantidad_planificada as planned_quantity, i.nombre as product_name
        from public.produccion_ordenes j
        join public.stock_items i on i.empresa_id = j.empresa_id and i.id = j.producto_id
        where j.empresa_id = p_company and j.estado in ('pendiente', 'en_proceso')
        order by j.fecha_limite asc nulls last, j.creado_en asc
        limit 5) p)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_public_price_list(p_company uuid, p_search text DEFAULT ''::text)
 RETURNS TABLE(id uuid, code text, name text, unit_symbol text, price numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'ventas','ver') then
    raise exception 'Sin permiso para consultar precios' using errcode='42501'; end if;
  if length(coalesce(p_search,''))>100 then raise exception 'Búsqueda demasiado larga'; end if;
  return query select i.id,i.codigo,i.nombre,u.simbolo,i.precio_venta_unitario
    from public.stock_items i join public.stock_unidades u
      on u.empresa_id=i.empresa_id and u.id=i.unidad_id
    where i.empresa_id=p_company and i.activo and i.tipo_item='producto_terminado'
      and (p_search='' or i.codigo ilike '%'||p_search||'%'
        or i.nombre ilike '%'||p_search||'%')
    order by i.nombre,i.id limit 300;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_quote_detail(p_company uuid, p_quote uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date; v_q public.ventas_presupuestos%rowtype;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'ventas', 'ver') then
    raise exception 'Sin acceso a ventas' using errcode = '42501';
  end if;
  select * into v_q from public.ventas_presupuestos where empresa_id = p_company and id = p_quote;
  if not found then raise exception 'Presupuesto inexistente'; end if;
  return jsonb_build_object(
    'id', v_q.id, 'number', v_q.numero, 'customer_name', v_q.cliente_nombre, 'customer_tax_id', v_q.cliente_identificacion_fiscal,
    'customer_email', v_q.cliente_email, 'customer_phone', v_q.cliente_telefono,
    'customer_address', v_q.cliente_direccion, 'status', v_q.estado,
    'effective_status', case when v_q.estado = 'abierto' and v_q.vigente_hasta < v_today then 'vencido' else v_q.estado end,
    'valid_until', v_q.vigente_hasta, 'note', v_q.nota, 'show_tax', v_q.mostrar_impuesto, 'tax_included', v_q.impuesto_incluido, 'net_total', v_q.total_neto,
    'tax_total', v_q.total_impuesto, 'gross_total', v_q.total_bruto, 'tax_breakdown', v_q.impuestos_detalle,
    'created_at', v_q.creado_en, 'created_by_label', v_q.creado_por_nombre,
    'lines', coalesce((select jsonb_agg(jsonb_build_object(
        'line_no', l.linea, 'item_code', l.item_codigo, 'item_name', l.item_nombre, 'unit_symbol', l.unidad_simbolo,
        'quantity', l.cantidad, 'list_unit_price', l.precio_unitario_lista, 'discount_percent', l.descuento_porcentaje,
        'unit_price', l.precio_unitario, 'line_total', l.total_linea, 'tax_percent', l.impuesto_porcentaje,
        'line_gross', case when v_q.impuesto_incluido then round(l.total_linea * (1 + l.impuesto_porcentaje / 100), 2) end) order by l.linea)
      from public.ventas_presupuestos_lineas l where l.empresa_id = v_q.empresa_id and l.presupuesto_id = v_q.id), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_quotes_page(p_company uuid, p_search text DEFAULT ''::text, p_status text DEFAULT 'all'::text, p_page integer DEFAULT 0, p_size integer DEFAULT 25)
 RETURNS TABLE(id uuid, number bigint, customer_name text, customer_tax_id text, status text, effective_status text, valid_until date, net_total numeric, gross_total numeric, created_at timestamp with time zone, created_by_label text, line_count bigint, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_term text := lower(btrim(coalesce(p_search, ''))); v_size integer := least(greatest(coalesce(p_size, 25), 1), 100);
begin
  if auth.uid() is null or not private.has_permission(p_company, 'ventas', 'ver') then
    raise exception 'Sin acceso a ventas' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('all', 'abierto', 'vencido', 'aceptado', 'rechazado', 'cancelado') then
    raise exception 'Filtro inválido';
  end if;
  return query
  select q.id, q.numero, q.cliente_nombre, q.cliente_identificacion_fiscal, q.estado,
    case when q.estado = 'abierto' and q.vigente_hasta < v_today then 'vencido' else q.estado end,
    q.vigente_hasta, q.total_neto, q.total_bruto, q.creado_en, q.creado_por_nombre,
    (select count(*) from public.ventas_presupuestos_lineas l where l.empresa_id = q.empresa_id and l.presupuesto_id = q.id),
    count(*) over ()
  from public.ventas_presupuestos q
  where q.empresa_id = p_company
    and (v_term = '' or q.numero::text = v_term or position(v_term in lower(q.cliente_nombre)) > 0
         or position(v_term in lower(q.cliente_identificacion_fiscal)) > 0)
    and (p_status = 'all'
         or (p_status = 'vencido' and q.estado = 'abierto' and q.vigente_hasta < v_today)
         or (p_status = 'abierto' and q.estado = 'abierto' and q.vigente_hasta >= v_today)
         or (p_status in ('aceptado', 'rechazado', 'cancelado') and q.estado = p_status))
  order by q.creado_en desc, q.id
  limit v_size offset greatest(coalesce(p_page, 0), 0) * v_size;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_replenishment_forecast(p_company uuid)
 RETURNS TABLE(item_id uuid, item_code text, item_name text, unit_symbol text, physical numeric, usable numeric, reserved numeric, free numeric, pending_purchase numeric, minimum_stock numeric, consumed_60d numeric, history_days integer, daily_use numeric, days_left numeric, supplier_id uuid, supplier_name text, lead_time_days integer, suggested_quantity numeric, alert_level text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with scope as (
    select i.id, i.codigo, i.nombre, i.stock_minimo, i.usa_lotes, u.simbolo
    from public.stock_items i
    join public.stock_unidades u on u.empresa_id=i.empresa_id and u.id=i.unidad_id
    where i.empresa_id=p_company and i.activo and not i.stock_infinito
      and i.tipo_item in ('materia_prima','semielaborado','insumo')
      and auth.uid() is not null
      and private.has_permission(p_company,'stock_saldos','ver')
      and true
      and private.has_permission(p_company,'produccion_reposicion','ver')
  ), snapshot as (
    select i.*,
      coalesce(b.physical,0) as physical,
      coalesce(us.usable,0) as usable,
      coalesce(r.reserved,0) as reserved,
      coalesce(po.pending,0) as pending_purchase,
      coalesce(m.consumed,0) as consumed_60d,
      m.first_issue,
      s.proveedor_id,s.supplier_name,coalesce(s.lead_days,7) as lead_days
    from scope i
    left join lateral (
      select sum(b.cantidad) physical from public.stock_saldos b
      where b.empresa_id=p_company and b.item_id=i.id
    ) b on true
    left join lateral (
      select sum(q.cantidad) usable from (
        select b.cantidad from public.stock_saldos b
        join public.stock_depositos w on w.empresa_id=b.empresa_id
          and w.id=b.deposito_id and w.activo
        where b.empresa_id=p_company and b.item_id=i.id and not i.usa_lotes
        union all
        select lb.cantidad from public.stock_lotes_saldos lb
        join public.stock_depositos w on w.empresa_id=lb.empresa_id
          and w.id=lb.deposito_id and w.activo
        join public.stock_lotes l on l.empresa_id=lb.empresa_id
          and l.item_id=lb.item_id and l.id=lb.lote_id
        where lb.empresa_id=p_company and lb.item_id=i.id and i.usa_lotes
          and (l.vencimiento is null or l.vencimiento >=
            (now() at time zone 'America/Argentina/Buenos_Aires')::date)
      ) q
    ) us on true
    left join lateral (
      select sum(a.cantidad) reserved from public.produccion_reservas_ubicaciones a
      join public.produccion_ordenes j on j.empresa_id=a.empresa_id and j.id=a.orden_id
      where a.empresa_id=p_company and a.componente_id=i.id
        and j.estado in ('pendiente','en_proceso')
    ) r on true
    left join lateral (
      select sum(l.cantidad-l.cantidad_recibida) pending
      from public.compras_ordenes_lineas l
      join public.compras_ordenes o on o.empresa_id=l.empresa_id and o.id=l.orden_compra_id
      where l.empresa_id=p_company and l.item_id=i.id
        and o.estado in ('abierta','parcial')
    ) po on true
    left join lateral (
      select sum(-m.variacion) consumed, min(m.creado_en) first_issue
      from public.stock_movimientos m
      where m.empresa_id=p_company and m.item_id=i.id and m.tipo='egreso'
        and m.creado_en >= now()-interval '60 days'
    ) m on true
    left join lateral (
      select si.proveedor_id,s.nombre supplier_name,s.demora_dias lead_days
      from public.compras_proveedores_items si
      join public.compras_proveedores s on s.empresa_id=si.empresa_id
        and s.id=si.proveedor_id and s.activo
      where si.empresa_id=p_company and si.item_id=i.id
      order by si.preferido desc,s.nombre,s.id limit 1
    ) s on true
  ), metrics as (
    select x.*,
      greatest(0,x.usable-x.reserved) as free_stock,
      case when x.first_issue is null then 0
        else least(60,greatest(1,
          (now() at time zone 'America/Argentina/Buenos_Aires')::date
            - (x.first_issue at time zone 'America/Argentina/Buenos_Aires')::date + 1))
      end as observation_days
    from snapshot x
  ), demand as (
    select x.*,
      case when observation_days>=14 then round(consumed_60d/observation_days,6)
        else 0::numeric end as rate
    from metrics x
  )
  select d.id,d.codigo,d.nombre,d.simbolo,d.physical,d.usable,d.reserved,d.free_stock,
    d.pending_purchase,d.stock_minimo,d.consumed_60d,d.observation_days,d.rate,
    case when d.rate>0 then round(d.free_stock/d.rate,1) else null end,
    d.proveedor_id,d.supplier_name,d.lead_days,
    greatest(0,ceil(greatest(d.stock_minimo,
      d.rate*(d.lead_days+7)) - d.free_stock-d.pending_purchase)),
    case
      when d.free_stock<=0 and d.pending_purchase<=0 then 'critical'
      when d.rate>0 and d.free_stock/d.rate<=d.lead_days then 'critical'
      when d.free_stock<d.stock_minimo then 'warning'
      when d.rate>0 and d.free_stock/d.rate<=d.lead_days+7 then 'warning'
      else 'ok'
    end
  from demand d
  order by case
    when d.free_stock<=0 and d.pending_purchase<=0 then 0
    when d.rate>0 and d.free_stock/d.rate<=d.lead_days then 0
    when d.free_stock<d.stock_minimo then 1
    when d.rate>0 and d.free_stock/d.rate<=d.lead_days+7 then 1
    else 2 end,d.nombre;
$function$;

CREATE OR REPLACE FUNCTION public.erp_resolve_sale_price(p_company uuid, p_customer uuid, p_item uuid)
 RETURNS TABLE(net_price numeric, currency text, tax_percent numeric, gross_price numeric, price_list_id uuid, source text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
  if auth.uid() is null or not private.has_permission(p_company, 'ventas', 'ver') then
    raise exception 'Sin acceso a ventas' using errcode = '42501';
  end if;
  return query select r.price, 'ARS'::text, r.tax_percent,
    case when r.price is not null then round(r.price * (1 + r.tax_percent / 100), 2) end, r.list_id, r.source
  from private.sale_resolve_price(p_company, p_customer, p_item) r;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_sale_discount_policy(p_company uuid)
 RETURNS TABLE(max_discount_percent numeric, can_exceed boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
  if auth.uid() is null or not private.has_permission(p_company, 'ventas', 'ver') then
    raise exception 'Sin acceso a ventas' using errcode = '42501';
  end if;
  return query select coalesce((select s.descuento_maximo_porcentaje from public.ventas_precios_config s
      where s.empresa_id = p_company), 0::numeric),
    (private.get_user_role(p_company) is not distinct from 'administrador'
      and private.has_permission(p_company, 'ventas', 'crear'));
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_sale_prices(p_company uuid, p_customer uuid, p_items uuid[])
 RETURNS TABLE(item_id uuid, net_price numeric, price_list_id uuid, list_name text, source text, tax_percent numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
  if auth.uid() is null or not private.has_permission(p_company, 'ventas', 'ver') then
    raise exception 'Sin acceso a ventas' using errcode = '42501';
  end if;
  if p_items is null or cardinality(p_items) > 200 then
    raise exception 'Consultá hasta 200 productos por vez';
  end if;
  return query
  select i.id, r.price, r.list_id, l.nombre, r.source, r.tax_percent
  from public.stock_items i
  cross join lateral private.sale_resolve_price(p_company, p_customer, i.id) r
  left join public.ventas_listas_precios l on l.empresa_id = p_company and l.id = r.list_id
  where i.empresa_id = p_company and i.id = any (p_items);
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_sales_profit_summary(p_company uuid)
 RETURNS TABLE(sales_total numeric, covered_revenue numeric, covered_cost numeric, estimated_profit numeric, missing_lines bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'finanzas','ver')
    or not private.has_permission(p_company,'ventas','ver') then
    raise exception 'Necesitás acceso a finanzas y ventas' using errcode='42501'; end if;
  return query with net_lines as (
    select l.total_linea-coalesce(a.credit,0) revenue,
      l.cantidad-coalesce(a.quantity,0) quantity,
      l.costo_unitario_estimado cost
    from public.ventas_lineas l
    left join lateral (
      select sum(al.cantidad) filter(where al.reingresado) quantity,
        sum(al.credito_importe) credit
      from public.ventas_ajustes_lineas al
      where al.empresa_id=l.empresa_id and al.venta_id=l.venta_id
        and al.venta_linea=l.linea
    ) a on true where l.empresa_id=p_company
  ) select coalesce(sum(n.revenue),0),
    coalesce(sum(n.revenue) filter(where n.cost is not null),0),
    coalesce(sum(n.quantity*n.cost),0),
    coalesce(sum(n.revenue-n.quantity*n.cost) filter(where n.cost is not null),0),
    count(*) filter(where n.cost is null and n.quantity>0)
  from net_lines n;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_set_finished_product_price(p_company uuid, p_item uuid, p_price numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or private.get_user_role(p_company)<>'administrador'
    or not private.has_permission(p_company,'ventas','editar') then
    raise exception 'Solo un administrador puede editar precios'
      using errcode='42501'; end if;
  if p_price is null or p_price<0 or p_price>=10000000000000000
    or p_price<>round(p_price,2) then
    raise exception 'Indicá un precio válido en pesos con dos decimales'; end if;
  update public.stock_items set precio_venta_unitario=p_price
    where empresa_id=p_company and id=p_item and activo
      and tipo_item='producto_terminado';
  if not found then raise exception 'Producto terminado inexistente o inactivo'; end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.exchange_rate_overview(p_company uuid)
 RETURNS TABLE(id uuid, name text, active boolean, current_rate numeric, effective_on date)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not (private.has_permission(p_company,'compras_proveedores','ver') or private.has_permission(p_company,'costos_materiales','ver')) then
    raise exception 'Sin acceso a cotizaciones' using errcode='42501'; end if;
  return query select t.id,t.nombre,t.activo,r.ars_por_usd,r.vigente_desde
    from public.finanzas_tipos_cambio t left join lateral (
      select e.ars_por_usd,e.vigente_desde from public.finanzas_cotizaciones e
      where e.empresa_id=t.empresa_id and e.tipo_cambio_id=t.id
        and e.vigente_desde<=(now() at time zone 'America/Argentina/Buenos_Aires')::date
      order by e.vigente_desde desc,e.creado_en desc,e.id desc limit 1
    ) r on true where t.empresa_id=p_company and not t.archivado order by t.nombre;
end; $function$;

CREATE OR REPLACE FUNCTION public.finish_production_job(p_company uuid, p_job uuid, p_actual_quantity numeric, p_output_lot text, p_expires_on date, p_variance_note text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.produccion_ordenes%rowtype;
  v_track_lots boolean; v_expected record; v_cost numeric; v_output uuid;
  v_run uuid; v_mismatch boolean:=false; v_lot text:=nullif(btrim(p_output_lot),'');
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_ordenes','crear')
    or not private.has_permission(p_company,'stock','crear') then
    raise exception 'Necesitás permiso de producción y stock' using errcode='42501'; end if;
  if p_request_id is null or p_actual_quantity is null or p_actual_quantity<=0
    or p_actual_quantity>=1000000000000
    or p_actual_quantity<>round(p_actual_quantity,6)
    or length(coalesce(p_variance_note,''))>400 then
    raise exception 'Indicá el rendimiento real con hasta seis decimales'; end if;
  select * into v_job from public.produccion_ordenes
    where empresa_id=p_company and id=p_job for update;
  if not found then raise exception 'Orden inexistente'; end if;
  if v_job.estado='terminada' then
    if v_job.solicitud_cierre_id<>p_request_id
      or v_job.cantidad_real<>p_actual_quantity
      or v_job.producto_lote is distinct from v_lot
      or v_job.producto_vencimiento is distinct from p_expires_on
      or v_job.nota_diferencia is distinct from nullif(btrim(p_variance_note),'') then
      raise exception 'Esta orden ya fue completada con otros datos'; end if;
    return v_job.fabricacion_id;
  end if;
  if v_job.estado<>'en_proceso' then
    raise exception 'Iniciá la orden y registrá sus insumos antes de terminar'; end if;
  select i.usa_lotes into v_track_lots from public.stock_items i
    where i.empresa_id=p_company and i.id=v_job.producto_id and i.activo for share;
  if not found then raise exception 'El producto está inactivo'; end if;
  if v_track_lots and v_lot is null then
    raise exception 'Indicá el lote del producto que vas a ingresar'; end if;
  if not v_track_lots and (v_lot is not null or p_expires_on is not null) then
    raise exception 'Este producto no usa lotes; dejá lote y vencimiento vacíos'; end if;
  if p_actual_quantity<>v_job.cantidad_esperada then v_mismatch:=true; end if;
  for v_expected in select (x->>'component_id')::uuid componente_id,
    (x->>'quantity')::numeric cantidad
    from jsonb_array_elements(v_job.formula_copia) x loop
    if (select coalesce(sum(case when e.tipo='entrega' then e.cantidad else -e.cantidad end),0)
      from public.produccion_ordenes_eventos e where e.empresa_id=p_company and e.orden_id=p_job
        and e.componente_id=v_expected.componente_id)<>v_expected.cantidad then
      v_mismatch:=true; end if;
  end loop;
  if exists(select 1 from public.produccion_ordenes_eventos e
    where e.empresa_id=p_company and e.orden_id=p_job
      and not exists(select 1 from jsonb_array_elements(v_job.formula_copia) x
        where x->>'component_id'=e.componente_id::text)
    group by e.componente_id
    having sum(case when e.tipo='entrega' then e.cantidad else -e.cantidad end)>0) then
    v_mismatch:=true; end if;
  if v_mismatch and length(btrim(coalesce(p_variance_note,'')))<5 then
    raise exception 'Explicá la diferencia entre lo previsto y lo fabricado'; end if;
  select round(coalesce(sum(case when e.tipo='entrega' then 1 else -1 end
    *e.cantidad*e.costo_unitario),0),2) into v_cost
    from public.produccion_ordenes_eventos e where e.empresa_id=p_company and e.orden_id=p_job;
  if v_cost<0 then raise exception 'Los consumos de la orden son inconsistentes'; end if;
  if not exists(select 1 from public.produccion_ordenes_eventos e
    where e.empresa_id=p_company and e.orden_id=p_job and e.tipo='entrega'
      and e.cantidad>(select coalesce(sum(r.cantidad),0)
        from public.produccion_ordenes_eventos r where r.empresa_id=e.empresa_id
          and r.entrega_id=e.id)) then
    raise exception 'No quedan insumos consumidos para fabricar el producto'; end if;
  v_run:=gen_random_uuid();
  v_output:=public.post_stock_operation(p_company,v_job.producto_id,
    v_job.deposito_id,null,'ingreso',p_actual_quantity,
    'Fabricación orden '||p_job::text,gen_random_uuid(),v_lot,p_expires_on);
  insert into public.produccion_fabricaciones(id,empresa_id,producto_id,formula_version,
    cantidad,deposito_id,operacion_producto_id,costo_estimado,solicitud_id,
    solicitud_datos,nota,autor_id)
  values(v_run,p_company,v_job.producto_id,v_job.formula_version,
    p_actual_quantity,v_job.deposito_id,v_output,v_cost,p_request_id,
    jsonb_build_object('job',p_job,'actual_quantity',p_actual_quantity,
      'output_lot',v_lot,'expiry',p_expires_on),v_job.nota,auth.uid());
  update public.produccion_ordenes set estado='terminada',cantidad_real=p_actual_quantity,
    producto_lote=v_lot,producto_vencimiento=p_expires_on,
    nota_diferencia=nullif(btrim(p_variance_note),''),fabricacion_id=v_run,
    solicitud_cierre_id=p_request_id,terminado_en=clock_timestamp()
    where empresa_id=p_company and id=p_job;
  if v_job.plan_id is not null then
    update public.produccion_planes set estado='terminado',fabricacion_id=v_run,
      solicitud_cierre_id=p_request_id,terminado_en=clock_timestamp()
      where empresa_id=p_company and id=v_job.plan_id and estado='planificado';
    if not found then raise exception 'La planificación fue modificada'; end if;
  end if;
  return v_run;
end;
$function$;

CREATE OR REPLACE FUNCTION public.finish_production_job_adjusted(p_company uuid, p_job uuid, p_actual_quantity numeric, p_output_lot text, p_expires_on date, p_variance_note text, p_request_id uuid, p_adjustments jsonb DEFAULT '[]'::jsonb, p_packaging jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_job public.produccion_ordenes%rowtype;
  v_adj jsonb;
  v_index integer := 0;
  v_part integer;
  v_kind text;
  v_component uuid;
  v_warehouse uuid;
  v_lot text;
  v_quantity numeric;
  v_note text;
  v_left numeric;
  v_take numeric;
  v_event record;
  v_seen uuid[] := '{}';
  v_pack jsonb;
  v_packs jsonb := '[]'::jsonb;
  v_count numeric;
  v_unit text;
  v_total numeric := 0;
  v_complete boolean := true;
  v_options jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_ordenes','crear')
    or not private.has_permission(p_company, 'stock', 'crear') then
    raise exception 'Necesitás permiso de producción y stock' using errcode = '42501';
  end if;
  if p_request_id is null
    or p_adjustments is null or jsonb_typeof(p_adjustments) <> 'array'
    or jsonb_array_length(p_adjustments) > 300
    or p_packaging is null or jsonb_typeof(p_packaging) <> 'object' then
    raise exception 'Revisá los ajustes y el recuento de envases';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('finish-job:' || p_company::text || ':' || p_job::text, 0));
  select * into v_job from public.produccion_ordenes where empresa_id = p_company and id = p_job for update;
  if not found then raise exception 'Orden inexistente'; end if;

  -- Reintento de una orden ya terminada: no se repiten ajustes; la función original valida que sean los mismos datos.
  if v_job.estado = 'terminada' then
    return public.finish_production_job(p_company, p_job, p_actual_quantity, p_output_lot,
      p_expires_on, p_variance_note, p_request_id);
  end if;
  if v_job.estado <> 'en_proceso' then
    raise exception 'Iniciá la orden y registrá sus insumos antes de terminar';
  end if;

  -- Devolver exige además producción:update (lo valida return_production_material): avisar antes de mover nada.
  if exists (select 1 from jsonb_array_elements(p_adjustments) a where a.value->>'kind' = 'devolucion')
    and not private.has_permission(p_company,'produccion_ordenes','editar') then
    raise exception 'Necesitás permiso para devolver insumos al stock' using errcode = '42501';
  end if;

  -- Ajustes de insumos.
  for v_adj in select value from jsonb_array_elements(p_adjustments) loop
    v_index := v_index + 1;
    if jsonb_typeof(v_adj) <> 'object' then raise exception 'Ajuste inválido en la línea %', v_index; end if;
    v_kind := v_adj->>'kind';
    -- Validar formato antes de convertir: evita errores crudos de conversión.
    if coalesce(v_adj->>'component_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or coalesce(v_adj->>'quantity', '') !~ '^[0-9]{1,12}(\.[0-9]{1,6})?$'
      or (nullif(v_adj->>'warehouse_id', '') is not null
        and v_adj->>'warehouse_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
      raise exception 'Ajuste inválido en la línea %', v_index;
    end if;
    v_component := (v_adj->>'component_id')::uuid;
    v_quantity := (v_adj->>'quantity')::numeric;
    v_note := left('Ajuste al terminar: ' || coalesce(nullif(btrim(v_adj->>'note'), ''), 'diferencia de consumo'), 300);
    if coalesce(v_kind, '') not in ('entrega', 'devolucion') or v_component is null
      or v_quantity is null or v_quantity <= 0 or v_quantity >= 1000000000000
      or v_quantity <> round(v_quantity, 6) then
      raise exception 'Ajuste inválido en la línea %', v_index;
    end if;
    if v_component = any(v_seen) then
      raise exception 'Hay dos ajustes para el mismo insumo (línea %)', v_index;
    end if;
    v_seen := array_append(v_seen, v_component);

    if v_kind = 'entrega' then
      v_warehouse := (v_adj->>'warehouse_id')::uuid;
      v_lot := nullif(btrim(v_adj->>'lot_code'), '');
      if v_warehouse is null then raise exception 'Indicá el depósito del insumo adicional (línea %)', v_index; end if;
      perform public.issue_production_material(p_company, p_job, v_component, v_warehouse, v_lot,
        v_quantity, v_note, md5(p_request_id::text || ':adj:' || v_index::text)::uuid);
    else
      v_left := v_quantity;
      v_part := 0;
      for v_event in
        select e.id,
          e.cantidad - coalesce((select sum(r.cantidad) from public.produccion_ordenes_eventos r
            where r.empresa_id = e.empresa_id and r.entrega_id = e.id and r.tipo = 'devolucion'), 0) as open_quantity
        from public.produccion_ordenes_eventos e
        where e.empresa_id = p_company and e.orden_id = p_job
          and e.componente_id = v_component and e.tipo = 'entrega'
        order by e.creado_en desc, e.id desc
      loop
        exit when v_left <= 0;
        if v_event.open_quantity > 0 then
          v_take := least(v_event.open_quantity, v_left);
          v_part := v_part + 1;
          perform public.return_production_material(p_company, p_job, v_event.id, v_take, v_note,
            md5(p_request_id::text || ':ret:' || v_index::text || ':' || v_part::text)::uuid);
          v_left := v_left - v_take;
        end if;
      end loop;
      if v_left > 0 then
        raise exception 'La devolución supera lo entregado de ese insumo (línea %)', v_index;
      end if;
    end if;
  end loop;

  -- Recuento de envases (informativo: no mueve stock). El resto sin envasar se calcula si todos los envases
  -- tienen la misma unidad que el producto.
  if exists (select 1 from jsonb_object_keys(p_packaging)) then
    if exists (
      select 1 from jsonb_each(p_packaging) e
      where not exists (select 1 from jsonb_array_elements(coalesce(v_job.opciones_trabajo->'packaging', '[]')) x
          where x->>'id' = e.key)
        or (jsonb_typeof(e.value) not in ('number', 'null'))
        or (jsonb_typeof(e.value) = 'number'
          and ((e.value#>>'{}')::numeric < 0 or (e.value#>>'{}')::numeric >= 1000000000
            or (e.value#>>'{}')::numeric <> trunc((e.value#>>'{}')::numeric)))
    ) then
      raise exception 'El recuento de envases debe usar los envasados de la orden con cantidades enteras';
    end if;
    select u.simbolo into v_unit
      from public.stock_items i
      join public.stock_unidades u on u.empresa_id = i.empresa_id and u.id = i.unidad_id
      where i.empresa_id = p_company and i.id = v_job.producto_id;
    for v_pack in select value from jsonb_array_elements(coalesce(v_job.opciones_trabajo->'packaging', '[]')) loop
      v_count := case when p_packaging ? (v_pack->>'id')
        then nullif(p_packaging->>(v_pack->>'id'), '')::numeric
        else nullif(v_pack->>'actual_count', '')::numeric end;
      v_packs := v_packs || jsonb_build_array(v_pack || jsonb_build_object('actual_count', v_count));
      if v_count is null or (v_pack->>'unit') is distinct from v_unit then
        v_complete := false;
      else
        v_total := v_total + v_count * (v_pack->>'capacity')::numeric;
      end if;
    end loop;
    if v_complete and v_total > p_actual_quantity then
      raise exception 'Los envases contados suman más de lo fabricado: revisá los recuentos';
    end if;
    v_options := coalesce(v_job.opciones_trabajo, '{}'::jsonb)
      || jsonb_build_object('packaging', v_packs,
        'unpackaged_quantity', case when v_complete and jsonb_array_length(v_packs) > 0
          then to_jsonb(round(p_actual_quantity - v_total, 6)) else 'null'::jsonb end);
    update public.produccion_ordenes
      set opciones_trabajo = v_options, detalles_actualizado_en = clock_timestamp()
      where empresa_id = p_company and id = p_job;
  end if;

  return public.finish_production_job(p_company, p_job, p_actual_quantity, p_output_lot,
    p_expires_on, p_variance_note, p_request_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_item_detail(p_company uuid, p_item uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cost boolean; v_result jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'items','ver') then
    raise exception 'Sin permiso para consultar ítems' using errcode='42501'; end if;
  v_cost:=private.can_see_reference_cost(p_company);
  select jsonb_build_object(
    'id',i.id,'company_id',i.empresa_id,'code',i.codigo,'name',i.nombre,'item_type',i.tipo_item,
    'category_id',i.categoria_id,'unit_id',i.unidad_id,'barcode',i.codigo_barras,'description',i.descripcion,
    'minimum_stock',i.stock_minimo,'track_lots',i.usa_lotes,'infinite_stock',i.stock_infinito,
    'active',i.activo,'archived',i.archivado,
    'reference_unit_cost',case when v_cost then i.costo_unitario_referencia end,
    'reference_cost_usd',case when v_cost then i.costo_referencia_usd end,
    'reference_exchange_rate_type_id',case when v_cost then i.tipo_cambio_referencia_id end,
    'cost_visible',v_cost,'created_at',i.creado_en,'updated_at',i.actualizado_en,
    'category',case when c.id is null then null
      else jsonb_build_object('id',c.id,'name',c.nombre,'active',c.activo) end,
    'unit',jsonb_build_object('id',u.id,'name',u.nombre,'symbol',u.simbolo,'active',u.activo))
  into v_result
  from public.stock_items i
  join public.stock_unidades u on u.empresa_id=i.empresa_id and u.id=i.unidad_id
  left join public.stock_categorias c on c.empresa_id=i.empresa_id and c.id=i.categoria_id
  where i.empresa_id=p_company and i.id=p_item;
  if v_result is null then raise exception 'El ítem no existe en esta empresa'; end if;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.import_items(p_company uuid, p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then raise exception 'Iniciá sesión' using errcode='42501'; end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'Datos de importación inválidos'; end if;
  if not private.can_see_reference_cost(p_company) and exists(
    select 1 from jsonb_array_elements(p_rows) r
    where jsonb_typeof(r.value)='object' and private.row_has_cost(r.value)) then
    raise exception 'Solo Administración o Compras pueden importar costos' using errcode='42501'; end if;
  return private.import_items(p_company,p_rows);
end;
$function$;

CREATE OR REPLACE FUNCTION public.import_price_list_items(p_company uuid, p_list uuid, p_rows jsonb, p_apply boolean, p_reason text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_list public.ventas_listas_precios%rowtype; v_row jsonb; v_code text; v_price numeric; v_item uuid; v_old numeric;
  v_matched int := 0; v_changed int := 0; v_unchanged int := 0;
  v_unmatched jsonb := '[]'::jsonb; v_invalid jsonb := '[]'::jsonb; v_sample jsonb := '[]'::jsonb;
  v_seen text[] := '{}'; v_prev jsonb; v_result jsonb;
begin
  perform private.price_require_admin(p_company);
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0
     or jsonb_array_length(p_rows) > 500 then
    raise exception 'Enviá entre 1 y 500 filas por vez';
  end if;
  if p_apply then
    if p_request_id is null then raise exception 'Identificador de solicitud inválido'; end if;
    select * into v_list from public.ventas_listas_precios where empresa_id = p_company and id = p_list for update;
  else
    select * into v_list from public.ventas_listas_precios where empresa_id = p_company and id = p_list;
  end if;
  if not found or v_list.archivado then raise exception 'Lista inexistente o archivada'; end if;
  if p_apply then
    select resultado into v_prev from public.ventas_precios_antiduplicado
    where empresa_id = p_company and solicitud_id = p_request_id and lista_precio_id = p_list and tipo = 'importacion';
    if v_prev is not null then return v_prev; end if;
    if exists (select 1 from public.ventas_precios_antiduplicado where empresa_id = p_company and solicitud_id = p_request_id) then
      raise exception 'Ese identificador ya se usó en otra operación';
    end if;
  end if;

  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_code := btrim(coalesce(v_row ->> 'code', ''));
    begin
      v_price := (v_row ->> 'price')::numeric;
    exception when others then
      v_price := null;
    end;
    if v_code = '' or length(v_code) > 60 or v_price is null or v_price < 0
       or v_price >= 10000000000000000 or v_price <> round(v_price, 2) then
      if jsonb_array_length(v_invalid) < 50 then v_invalid := v_invalid || to_jsonb(left(v_code, 60)); end if;
      continue;
    end if;
    if v_code = any (v_seen) then
      if jsonb_array_length(v_invalid) < 50 then v_invalid := v_invalid || to_jsonb(v_code || ' (repetido)'); end if;
      continue;
    end if;
    v_seen := v_seen || v_code;
    select id into v_item from public.stock_items
    where empresa_id = p_company and codigo = v_code and activo and tipo_item = 'producto_terminado';
    if v_item is null then
      if jsonb_array_length(v_unmatched) < 50 then v_unmatched := v_unmatched || to_jsonb(v_code); end if;
      continue;
    end if;
    v_matched := v_matched + 1;
    select precio_neto into v_old from public.ventas_listas_items
    where empresa_id = p_company and lista_precio_id = p_list and item_id = v_item;
    if v_old is not distinct from private.price_round(v_price, v_list.redondeo) then
      v_unchanged := v_unchanged + 1; continue;
    end if;
    v_changed := v_changed + 1;
    if jsonb_array_length(v_sample) < 200 then
      v_sample := v_sample || jsonb_build_object('item_id', v_item, 'code', v_code,
        'old_price', v_old, 'new_price', private.price_round(v_price, v_list.redondeo));
    end if;
    if p_apply then
      perform private.price_write(p_company, p_list, v_item, private.price_round(v_price, v_list.redondeo),
        'fijo', private.price_round(v_price, v_list.redondeo), null, true, 'importacion', p_reason);
    end if;
  end loop;

  v_result := jsonb_build_object('applied', p_apply, 'received', jsonb_array_length(p_rows),
    'matched', v_matched, 'changed', v_changed, 'unchanged', v_unchanged,
    'unmatched', v_unmatched, 'invalid', v_invalid, 'sample', v_sample);
  if p_apply then
    insert into public.ventas_precios_antiduplicado(empresa_id, solicitud_id, lista_precio_id, tipo, resultado, creado_por)
    values (p_company, p_request_id, p_list, 'importacion', v_result, auth.uid());
  end if;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.issue_delivery_note(p_company uuid, p_kind text, p_job uuid, p_recipient text, p_note text, p_lines jsonb, p_request uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_payload jsonb;
  v_existing public.stock_remitos%rowtype;
  v_job public.produccion_ordenes%rowtype;
  v_line jsonb;
  v_item public.stock_items%rowtype;
  v_warehouse text;
  v_symbol text;
  v_id uuid;
  v_number bigint;
  v_line_no integer := 0;
  v_quantity numeric;
  v_warehouse_id uuid;
  v_lot text;
  v_operation uuid;
  v_event uuid;
begin
  if auth.uid() is null
    or not private.has_permission(p_company, 'stock', 'crear')
    or (p_kind = 'produccion' and
      not private.has_permission(p_company,'produccion_ordenes','crear')) then
    raise exception 'Necesitás permiso para entregar stock y registrar fabricación'
      using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('produccion','materiales','productos')
    or (p_kind = 'produccion') is distinct from (p_job is not null)
    or p_request is null
    or length(btrim(coalesce(p_recipient, ''))) not between 3 and 120
    or length(btrim(coalesce(p_note, ''))) not between 3 and 300
    or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) not between 1 and 500 then
    raise exception 'Revisá tipo de remito, destinatario e insumos';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('delivery:' || p_company::text || ':' || p_request::text, 0));
  v_payload := jsonb_build_object('kind', p_kind, 'job', p_job,
    'recipient', btrim(p_recipient), 'note', btrim(p_note), 'lines', p_lines);
  select * into v_existing from public.stock_remitos
    where empresa_id = p_company and solicitud_id = p_request;
  if found then
    if v_existing.autor_id <> auth.uid() or v_existing.solicitud_datos <> v_payload then
      raise exception 'Esta solicitud ya se usó con otros datos';
    end if;
    return v_existing.id;
  end if;
  if p_job is not null then
    select * into v_job from public.produccion_ordenes
      where empresa_id = p_company and id = p_job for update;
    if not found or v_job.estado not in ('pendiente', 'en_proceso') then
      raise exception 'La orden de fabricación no admite más entregas';
    end if;
  end if;
  perform 1 from public.empresas where id = p_company and activo for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  insert into public.empresas_numeradores(empresa_id,documento) values (p_company,'remito')
    on conflict do nothing;
  update public.empresas_numeradores set proximo_numero = proximo_numero + 1
    where empresa_id = p_company and documento = 'remito' returning proximo_numero - 1 into v_number;
  insert into public.stock_remitos(empresa_id, numero, solicitud_id,
    solicitud_datos, tipo, orden_id, destinatario, nota, autor_id)
  values (p_company, v_number, p_request, v_payload,
    p_kind, p_job, btrim(p_recipient), btrim(p_note), auth.uid())
  returning id into v_id;

  for v_line in select value from jsonb_array_elements(p_lines) x(value) loop
    v_line_no := v_line_no + 1;
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'Cada renglón debe contener un ítem'; end if;
    v_quantity := (v_line ->> 'quantity')::numeric;
    v_warehouse_id := (v_line ->> 'warehouse_id')::uuid;
    v_lot := nullif(btrim(v_line ->> 'lot_code'), '');
    if (v_line ->> 'item_id') is null or v_warehouse_id is null
      or v_quantity is null or v_quantity <= 0 or v_quantity >= 1000000000000
      or v_quantity <> round(v_quantity, 6) or length(coalesce(v_lot, '')) > 80 then
      raise exception 'Revisá ítem, cantidad, depósito y lote de cada renglón';
    end if;
    select * into v_item from public.stock_items
      where empresa_id = p_company and id = (v_line ->> 'item_id')::uuid
        and activo for share;
    if not found then raise exception 'El ítem está inactivo o no existe'; end if;
    if (p_kind = 'produccion'
        and v_item.tipo_item not in ('materia_prima', 'semielaborado', 'insumo'))
      or (p_kind = 'materiales'
        and v_item.tipo_item not in ('materia_prima', 'semielaborado', 'insumo'))
      or (p_kind = 'productos'
        and v_item.tipo_item not in ('semielaborado', 'producto_terminado')) then
      raise exception 'El tipo de ítem no corresponde a este remito';
    end if;
    select w.nombre into v_warehouse from public.stock_depositos w
      where w.empresa_id = p_company and w.id = v_warehouse_id and w.activo for share;
    if not found then raise exception 'Elegí un depósito de origen activo'; end if;
    select u.simbolo into v_symbol from public.stock_unidades u
      where u.empresa_id = p_company and u.id = v_item.unidad_id;
    if p_kind = 'produccion' then
      v_event := public.issue_production_material(p_company, p_job,
        v_item.id, v_warehouse_id, v_lot, v_quantity,
        'Remito Nº ' || v_number || ' · ' || left(btrim(p_note), 250),
        gen_random_uuid());
      select operacion_stock_id into v_operation from public.produccion_ordenes_eventos
        where empresa_id = p_company and id = v_event;
    else
      v_event := null;
      v_operation := public.post_stock_operation(p_company, v_item.id,
        v_warehouse_id, null, 'egreso', v_quantity,
        'Remito Nº ' || v_number || ' · ' || left(btrim(p_note), 250),
        gen_random_uuid(), v_lot, null);
    end if;
    insert into public.stock_remitos_lineas(empresa_id, remito_id, linea,
      item_id, item_codigo, item_nombre, unidad_simbolo, deposito_id,
      deposito_nombre, lote_codigo, cantidad, operacion_stock_id, evento_produccion_id)
    values (p_company, v_id, v_line_no, v_item.id, v_item.codigo, v_item.nombre,
      coalesce(v_symbol, ''), v_warehouse_id, v_warehouse, v_lot,
      v_quantity, v_operation, v_event);
  end loop;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.issue_production_material(p_company uuid, p_job uuid, p_component uuid, p_warehouse uuid, p_lot text, p_quantity numeric, p_note text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.produccion_ordenes%rowtype;
  v_previous public.produccion_ordenes_eventos%rowtype;
  v_cost numeric; v_operation uuid; v_event uuid;
  v_lot text:=nullif(btrim(p_lot),'');
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_ordenes','crear')
    or not private.has_permission(p_company,'stock','crear') then
    raise exception 'Necesitás permiso de producción y stock' using errcode='42501'; end if;
  if p_request_id is null or p_component is null or p_warehouse is null
    or p_quantity is null or p_quantity<=0 or p_quantity>=1000000000000
    or p_quantity<>round(p_quantity,6)
    or length(btrim(coalesce(p_note,''))) not between 3 and 300 then
    raise exception 'Revisá el insumo, cantidad, depósito y motivo'; end if;
  select * into v_job from public.produccion_ordenes
    where empresa_id=p_company and id=p_job for update;
  if not found then raise exception 'Orden inexistente'; end if;
  select * into v_previous from public.produccion_ordenes_eventos
    where empresa_id=p_company and solicitud_id=p_request_id;
  if found then
    if v_previous.autor_id<>auth.uid() or v_previous.tipo<>'entrega'
      or v_previous.orden_id<>p_job or v_previous.componente_id<>p_component
      or v_previous.deposito_id<>p_warehouse or v_previous.cantidad<>p_quantity
      or v_previous.lote_codigo is distinct from v_lot
      or v_previous.nota<>btrim(p_note) then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_previous.id;
  end if;
  if v_job.estado not in ('pendiente','en_proceso') then
    raise exception 'La orden ya no admite insumos'; end if;
  if p_component=v_job.producto_id then
    raise exception 'El producto fabricado no puede consumirse a sí mismo'; end if;
  perform 1 from public.stock_items i where i.empresa_id=p_company and i.id=p_component
    and i.activo and i.tipo_item in ('materia_prima','semielaborado','insumo') for share;
  if not found then raise exception 'Elegí una materia prima o un semielaborado activo'; end if;
  select round(r.costo_estimado/r.cantidad,2) into v_cost
    from public.produccion_fabricaciones r
    where r.empresa_id=p_company and r.producto_id=p_component
    order by r.creado_en desc limit 1;
  v_cost:=coalesce(v_cost,private.production_unit_cost(p_company,p_component));
  perform pg_catalog.set_config('dromux.production_job',p_job::text,true);
  v_operation:=public.post_stock_operation(p_company,p_component,p_warehouse,
    null,'egreso',p_quantity,'Orden producción '||p_job::text,
    gen_random_uuid(),v_lot,null);
  perform pg_catalog.set_config('dromux.production_job','',true);
  insert into public.produccion_ordenes_eventos(empresa_id,orden_id,solicitud_id,tipo,
    componente_id,deposito_id,lote_codigo,cantidad,costo_unitario,operacion_stock_id,
    nota,autor_id)
  values(p_company,p_job,p_request_id,'entrega',p_component,p_warehouse,
    v_lot,p_quantity,v_cost,v_operation,btrim(p_note),auth.uid())
  returning id into v_event;
  if v_job.estado='pendiente' then
    update public.produccion_ordenes set estado='en_proceso',iniciado_en=clock_timestamp()
      where empresa_id=p_company and id=p_job;
  end if;
  return v_event;
end;
$function$;

CREATE OR REPLACE FUNCTION public.issue_sale_delivery_note(p_company uuid, p_sale uuid, p_recipient text, p_note text, p_lines jsonb, p_request uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_sale public.ventas%rowtype;
  v_previous public.stock_remitos%rowtype;
  v_line public.ventas_lineas%rowtype;
  v_entry jsonb;
  v_payload jsonb;
  v_id uuid;
  v_number bigint;
  v_line_no integer := 0;
  v_quantity numeric;
  v_already numeric;
  v_returned numeric;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'ventas', 'ver')
    or not private.has_permission(p_company, 'stock', 'ver')
    or not private.has_permission(p_company, 'stock', 'crear') then
    raise exception 'Necesitás acceso a ventas y stock para emitir el remito'
      using errcode = '42501'; end if;
  if p_sale is null or p_request is null
    or length(btrim(coalesce(p_recipient, ''))) not between 3 and 120
    or length(btrim(coalesce(p_note, ''))) not between 3 and 300
    or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) not between 1 and 200 then
    raise exception 'Revisá la venta, el destinatario y los renglones'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('delivery:' || p_company::text || ':' || p_request::text, 0));
  v_payload := jsonb_build_object('kind', 'venta', 'sale', p_sale,
    'recipient', btrim(p_recipient), 'note', btrim(p_note), 'lines', p_lines);
  select * into v_previous from public.stock_remitos
    where empresa_id = p_company and solicitud_id = p_request;
  if found then
    if v_previous.autor_id <> auth.uid() or v_previous.solicitud_datos <> v_payload then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_previous.id;
  end if;
  select * into v_sale from public.ventas
    where empresa_id = p_company and id = p_sale for update;
  if not found then raise exception 'Venta inexistente'; end if;
  if exists (select 1 from public.ventas_ajustes a
    where a.empresa_id = p_company and a.venta_id = p_sale and a.tipo = 'anulacion') then
    raise exception 'Una venta anulada no puede generar nuevos remitos'; end if;
  perform 1 from public.empresas where id = p_company and activo for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  insert into public.empresas_numeradores(empresa_id,documento) values (p_company,'remito')
    on conflict do nothing;
  update public.empresas_numeradores set proximo_numero = proximo_numero + 1
    where empresa_id = p_company and documento = 'remito' returning proximo_numero - 1 into v_number;
  insert into public.stock_remitos(empresa_id, numero, solicitud_id,
    solicitud_datos, tipo, venta_id, destinatario, nota, autor_id)
  values (p_company, v_number, p_request, v_payload, 'venta', p_sale,
    btrim(p_recipient), btrim(p_note), auth.uid()) returning id into v_id;
  for v_entry in select value from jsonb_array_elements(p_lines) x(value) loop
    v_line_no := v_line_no + 1;
    if jsonb_typeof(v_entry) <> 'object' then
      raise exception 'Renglón de venta inválido'; end if;
    v_quantity := (v_entry ->> 'quantity')::numeric;
    if (v_entry ->> 'line_no') is null or v_quantity is null
      or v_quantity <= 0 or v_quantity >= 1000000000000
      or v_quantity <> round(v_quantity, 6) then
      raise exception 'Revisá las cantidades entregadas'; end if;
    select * into v_line from public.ventas_lineas
      where empresa_id = p_company and venta_id = p_sale
        and linea = (v_entry ->> 'line_no')::smallint;
    if not found then raise exception 'Producto no incluido en la venta'; end if;
    if exists (select 1 from public.stock_remitos_lineas l
      where l.empresa_id = p_company and l.remito_id = v_id
        and l.venta_linea = v_line.linea) then
      raise exception 'Cada producto de la venta puede figurar una vez por remito'; end if;
    select coalesce(sum(l.cantidad), 0) into v_already
      from public.stock_remitos_lineas l
      join public.stock_remitos d on d.empresa_id = l.empresa_id and d.id = l.remito_id
      where d.empresa_id = p_company and d.venta_id = p_sale
        and d.estado = 'emitido' and l.venta_linea = v_line.linea;
    select coalesce(sum(a.cantidad), 0) into v_returned
      from public.ventas_ajustes_lineas a
      where a.empresa_id = p_company and a.venta_id = p_sale
        and a.venta_linea = v_line.linea;
    if v_quantity > v_line.cantidad - v_returned - v_already then
      raise exception 'Esta entrega supera el saldo disponible del producto vendido'; end if;
    insert into public.stock_remitos_lineas(empresa_id, remito_id, linea,
      item_id, item_codigo, item_nombre, unidad_simbolo, deposito_id, deposito_nombre,
      lote_codigo, cantidad, operacion_stock_id, venta_id, venta_linea)
    values (p_company, v_id, v_line_no, v_line.item_id, v_line.item_codigo,
      v_line.item_nombre, v_line.unidad_simbolo, v_line.deposito_id,
      v_line.deposito_codigo, v_line.lote_codigo, v_quantity,
      v_line.operacion_stock_id, p_sale, v_line.linea);
  end loop;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.item_cost_context(p_company uuid, p_item uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'items','ver')
    or not private.has_permission(p_company,'costos_materiales','ver') then
    raise exception 'Sin acceso a los costos del proveedor' using errcode='42501'; end if;
  return (select jsonb_build_object('supplier_id',q.proveedor_id,'supplier_name',s.nombre,
    'currency_code',q.moneda,'unit_price',q.precio_unitario)
    from public.compras_proveedores_items q join public.compras_proveedores s on s.empresa_id=q.empresa_id and s.id=q.proveedor_id
    where q.empresa_id=p_company and q.item_id=p_item and q.preferido);
end; $function$;

CREATE OR REPLACE FUNCTION public.list_production_items(p_company uuid, p_include_inactive boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cost boolean;
begin
  if auth.uid() is null then raise exception 'Iniciá sesión' using errcode='42501'; end if;
  if not private.has_permission(p_company,'items','ver') then return '[]'::jsonb; end if;
  v_cost:=private.can_see_reference_cost(p_company);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',i.id,'code',i.codigo,'name',i.nombre,'active',i.activo,'item_type',i.tipo_item,
      'track_lots',i.usa_lotes,'infinite_stock',i.stock_infinito,'yield_enabled',i.usa_rendimiento,
      'yield_factor',i.factor_rendimiento,
      'reference_unit_cost',case when v_cost then i.costo_unitario_referencia end,
      'has_reference_cost',i.costo_unitario_referencia is not null,
      'units',jsonb_build_object('symbol',u.simbolo)
    ) order by i.nombre,i.id)
    from (select * from public.stock_items
      where empresa_id=p_company and (coalesce(p_include_inactive,false) or activo)
        and tipo_item in ('materia_prima','semielaborado','producto_terminado','insumo')
      order by nombre,id limit 500) i
    join public.stock_unidades u on u.empresa_id=i.empresa_id and u.id=i.unidad_id),'[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.list_production_jobs(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_costs boolean;
begin
  if auth.uid() is null then raise exception 'Iniciá sesión' using errcode='42501'; end if;
  -- Sin permiso devuelve lista vacía, igual que la consulta anterior bajo RLS.
  if not (private.has_permission(p_company,'produccion_ordenes','ver') or private.has_permission(p_company,'produccion_resumen','ver')) then return '[]'::jsonb; end if;
  v_costs:=private.can_see_production_costs(p_company);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',j.id,'number',j.numero,'yield_factor',j.factor_rendimiento,'expected_output',j.cantidad_esperada,
      'document_snapshot',j.documento_copia,'work_options',j.opciones_trabajo,
      'details_updated_at',j.detalles_actualizado_en,'product_id',j.producto_id,'plan_id',j.plan_id,
      'planned_quantity',j.cantidad_planificada,'actual_quantity',j.cantidad_real,
      'warehouse_id',j.deposito_id,'due_on',j.fecha_limite,'formula_version',j.formula_version,
      'formula_snapshot',case when v_costs then j.formula_copia
        else private.strip_snapshot_cost(j.formula_copia) end,
      'status',j.estado,'note',j.nota,'cancel_reason',j.motivo_cancelacion,'variance_note',j.nota_diferencia,
      'output_lot',j.producto_lote,'output_expiry',j.producto_vencimiento,'run_id',j.fabricacion_id,
      'created_at',j.creado_en,'started_at',j.iniciado_en,'completed_at',j.terminado_en,
      'production_job_events',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',e.id,'kind',e.tipo,'issue_id',e.entrega_id,'component_id',e.componente_id,
          'warehouse_id',e.deposito_id,'lot_code',e.lote_codigo,'quantity',e.cantidad,
          'unit_cost',case when v_costs then e.costo_unitario end,'note',e.nota,'created_at',e.creado_en)
          order by e.creado_en,e.id)
        from public.produccion_ordenes_eventos e where e.empresa_id=j.empresa_id and e.orden_id=j.id),'[]'::jsonb)
    ) order by j.creado_en desc,j.id)
    from (select * from public.produccion_ordenes
      where empresa_id=p_company and not archivado
      order by creado_en desc,id limit 70) j),'[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.list_production_plans(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_costs boolean;
begin
  if auth.uid() is null then raise exception 'Iniciá sesión' using errcode='42501'; end if;
  -- Sin permiso devuelve lista vacía, igual que la consulta anterior bajo RLS.
  if not private.has_permission(p_company,'produccion_planificacion','ver') then return '[]'::jsonb; end if;
  v_costs:=private.can_see_production_costs(p_company);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',p.id,'product_id',p.producto_id,'warehouse_id',p.deposito_id,'quantity',p.cantidad,
      'formula_version',p.formula_version,'estimated_cost',case when v_costs then p.costo_estimado end,
      'component_snapshot',case when v_costs then p.componentes_copia
        else private.strip_snapshot_cost(p.componentes_copia) end,
      'due_on',p.fecha_limite,'note',p.nota,'status',p.estado,'run_id',p.fabricacion_id,'created_at',p.creado_en
    ) order by p.creado_en desc,p.id)
    from (select * from public.produccion_planes
      where empresa_id=p_company and not archivado
      order by creado_en desc,id limit 100) p),'[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.list_production_runs(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_costs boolean;
begin
  if auth.uid() is null then raise exception 'Iniciá sesión' using errcode='42501'; end if;
  -- Sin permiso devuelve lista vacía, igual que la consulta anterior bajo RLS.
  if not (private.has_permission(p_company,'produccion_ordenes','ver') or private.has_permission(p_company,'produccion_resumen','ver')) then return '[]'::jsonb; end if;
  v_costs:=private.can_see_production_costs(p_company);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',r.id,'product_id',r.producto_id,'quantity',r.cantidad,'formula_version',r.formula_version,
      'estimated_cost',case when v_costs then r.costo_estimado end,'created_at',r.creado_en,
      'warehouse_id',r.deposito_id,
      'production_run_lines',coalesce((
        select jsonb_agg(jsonb_build_object(
          'component_id',l.componente_id,'quantity',l.cantidad,'lot_code',l.lote_codigo,
          'warehouse_id',l.deposito_id,'unit_cost',case when v_costs then l.costo_unitario end)
          order by l.componente_id)
        from public.produccion_fabricaciones_lineas l where l.empresa_id=r.empresa_id and l.fabricacion_id=r.id),'[]'::jsonb)
    ) order by r.creado_en desc,r.id)
    from (select * from public.produccion_fabricaciones
      where empresa_id=p_company and not archivado
      order by creado_en desc,id limit 30) r),'[]'::jsonb);
end;
$function$;

create or replace function public.my_company_access()
returns table(company_id uuid, company_name text, company_slug text, company_active boolean, role_id uuid, role_name text, role_code text, company_modules jsonb)
language sql
stable
security definer
set search_path to ''
as $function$
  select cu.empresa_id, c.nombre, c.identificador, c.activo, cu.rol_id, r.nombre, r.codigo, c.modulos
  from public.empresas_usuarios cu
  join public.empresas c on c.id = cu.empresa_id
  join public.ajustes_roles r on r.id = cu.rol_id and r.empresa_id = cu.empresa_id
  where cu.usuario_id = (select auth.uid()) and cu.activo
  union all
  select c.id, c.nombre, c.identificador, c.activo, null::uuid, 'Soporte Dromux', 'soporte', c.modulos
  from public.empresas c
  where c.activo and exists (
    select 1 from private.soporte_operadores so
    where so.usuario_id = (select auth.uid()) and so.activo
  ) and not exists (
    select 1 from public.empresas_usuarios cu
    where cu.empresa_id = c.id and cu.usuario_id = (select auth.uid()) and cu.activo
  )
$function$;

CREATE OR REPLACE FUNCTION public.post_production_run(p_company uuid, p_product uuid, p_request_id uuid, p_quantity numeric, p_warehouse uuid, p_output_lot text, p_expires_on date, p_note text, p_inputs jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_payload jsonb;
  v_existing public.produccion_fabricaciones%rowtype;
  v_formula public.produccion_formulas%rowtype;
  v_line record;
  v_input jsonb;
  v_required numeric;
  v_cost numeric;
  v_run uuid;
  v_operation uuid;
  v_output uuid;
  v_wh uuid;
  v_lot text;
  v_posted jsonb := '[]'::jsonb;
  v_post jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_ordenes','crear')
    or not private.has_permission(p_company,'stock','crear') then
    raise exception 'Necesitás permisos de producción y movimientos de stock' using errcode='42501';
  end if;
  if p_request_id is null or p_quantity is null or p_quantity <= 0
    or p_quantity >= 1000000000000 or p_quantity <> round(p_quantity,6)
    or p_product is null or p_warehouse is null or p_inputs is null
    or jsonb_typeof(p_inputs) <> 'array' or length(btrim(p_note)) not between 3 and 400 then
    raise exception 'Datos de producción inválidos';
  end if;
  v_payload := jsonb_build_object('product',p_product,'quantity',p_quantity,
    'warehouse',p_warehouse,'lot',nullif(btrim(p_output_lot),''),
    'expiry',p_expires_on,'note',btrim(p_note),'inputs',p_inputs);
  select * into v_existing from public.produccion_fabricaciones
  where empresa_id=p_company and solicitud_id=p_request_id;
  if found then
    if v_existing.solicitud_datos <> v_payload or v_existing.autor_id <> auth.uid() then
      raise exception 'Esta solicitud ya se usó con otros datos';
    end if;
    return v_existing.id;
  end if;
  select * into v_formula from public.produccion_formulas
  where empresa_id=p_company and producto_id=p_product for share;
  if not found then raise exception 'El producto no tiene fórmula'; end if;
  perform 1 from public.stock_items where empresa_id=p_company and id=p_product and activo for share;
  if not found then raise exception 'El producto está inactivo'; end if;
  if jsonb_array_length(p_inputs) <> (select count(*) from public.produccion_formulas_lineas
    where empresa_id=p_company and producto_id=p_product) then
    raise exception 'Seleccioná depósito y lote para cada componente';
  end if;
  v_cost := private.production_unit_cost(p_company,p_product);
  -- Se registra todo dentro de la misma transacción de PostgreSQL.
  v_run := gen_random_uuid();
  for v_line in select l.componente_id,l.cantidad,i.usa_lotes
    from public.produccion_formulas_lineas l join public.stock_items i
      on i.empresa_id=l.empresa_id and i.id=l.componente_id
    where l.empresa_id=p_company and l.producto_id=p_product order by l.componente_id loop
    select value into v_input from jsonb_array_elements(p_inputs) value
    where value->>'component_id'=v_line.componente_id::text;
    if not found or (select count(*) from jsonb_array_elements(p_inputs) value
      where value->>'component_id'=v_line.componente_id::text) <> 1 then
      raise exception 'Cada componente debe figurar una sola vez';
    end if;
    v_wh := (v_input->>'warehouse_id')::uuid;
    v_lot := nullif(btrim(v_input->>'lot_code'),'');
    v_required := v_line.cantidad*p_quantity/v_formula.cantidad_base;
    if v_required <= 0 or v_required >= 1000000000000 or v_required <> round(v_required,6) then
      raise exception 'La cantidad requerida no admite más de seis decimales';
    end if;
    v_operation := public.post_stock_operation(p_company,v_line.componente_id,v_wh,null,
      'egreso',v_required,'Producción '||v_run::text,gen_random_uuid(),v_lot,null);
    v_posted := v_posted || jsonb_build_array(jsonb_build_object(
      'component',v_line.componente_id,'warehouse',v_wh,'quantity',v_required,
      'lot',v_lot,'cost',private.production_unit_cost(p_company,v_line.componente_id),
      'operation',v_operation));
  end loop;
  v_output := public.post_stock_operation(p_company,p_product,p_warehouse,null,
    'ingreso',p_quantity,'Producción '||v_run::text,gen_random_uuid(),
    nullif(btrim(p_output_lot),''),p_expires_on);
  insert into public.produccion_fabricaciones(id,empresa_id,producto_id,formula_version,cantidad,
    deposito_id,operacion_producto_id,costo_estimado,solicitud_id,solicitud_datos,nota,autor_id)
  values(v_run,p_company,p_product,v_formula.version,p_quantity,p_warehouse,
    v_output,round(v_cost*p_quantity,2),p_request_id,v_payload,btrim(p_note),auth.uid());
  for v_post in select value from jsonb_array_elements(v_posted) loop
    insert into public.produccion_fabricaciones_lineas(empresa_id,fabricacion_id,componente_id,deposito_id,
      cantidad,lote_codigo,costo_unitario,operacion_stock_id)
    values(p_company,v_run,(v_post->>'component')::uuid,(v_post->>'warehouse')::uuid,
      (v_post->>'quantity')::numeric,v_post->>'lot',(v_post->>'cost')::numeric,
      (v_post->>'operation')::uuid);
  end loop;
  return v_run;
end;
$function$;

CREATE OR REPLACE FUNCTION public.post_sale(p_company uuid, p_customer uuid, p_note text, p_lines jsonb, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_existing public.ventas%rowtype;
  v_payload jsonb;
  v_customer public.ventas_clientes%rowtype;
  v_line jsonb;
  v_item public.stock_items%rowtype;
  v_warehouse_code text;
  v_unit_symbol text;
  v_sale uuid;
  v_number bigint;
  v_line_no smallint := 0;
  v_item_id uuid;
  v_warehouse uuid;
  v_quantity numeric;
  v_lot text;
  v_unit_price numeric;
  v_line_total numeric;
  v_total numeric := 0;
  v_operation uuid;
  v_cost numeric;
  v_posted jsonb := '[]'::jsonb;
  v_post jsonb;
  v_res record;
  v_disc numeric;
  v_reason text;
  v_base numeric;
  v_cap numeric;
begin
  if auth.uid() is null or not private.has_permission(p_company,'ventas','crear')
    or not private.has_permission(p_company,'stock','crear') then
    raise exception 'Necesitás permisos de ventas y stock' using errcode='42501';
  end if;
  if p_request_id is null or p_customer is null or p_note is null
    or length(btrim(p_note)) not between 3 and 500
    or p_lines is null or jsonb_typeof(p_lines) <> 'array'
    or jsonb_array_length(p_lines) not between 1 and 40 then
    raise exception 'Revisá cliente, observaciones y productos';
  end if;
  -- Serializa reintentos simultáneos con la misma clave de solicitud.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('sale:'||p_company::text||':'||p_request_id::text,0));
  v_payload := jsonb_build_object('customer',p_customer,'note',btrim(p_note),'lines',p_lines);
  select * into v_existing from public.ventas
    where empresa_id=p_company and solicitud_id=p_request_id;
  if found then
    if v_existing.autor_id <> auth.uid() or v_existing.solicitud_datos <> v_payload then
      raise exception 'Esta solicitud ya se utilizó con otros datos';
    end if;
    return v_existing.id;
  end if;
  perform 1 from public.empresas where id=p_company and activo for share;
  if not found then raise exception 'La empresa no está activa'; end if;
  select * into v_customer from public.ventas_clientes
    where empresa_id=p_company and id=p_customer and activo for share;
  if not found then raise exception 'Elegí un cliente activo'; end if;
  v_sale := gen_random_uuid();
  -- Orden estable de ítems para reducir conflictos entre ventas concurrentes.
  for v_line in select value from jsonb_array_elements(p_lines) as t(value)
      order by value->>'item_id' loop
    v_line_no := v_line_no+1;
    v_item_id := (v_line->>'item_id')::uuid;
    v_warehouse := (v_line->>'warehouse_id')::uuid;
    v_quantity := (v_line->>'quantity')::numeric;
    v_lot := nullif(btrim(v_line->>'lot_code'),'');
    if v_item_id is null or v_warehouse is null or v_quantity is null
      or v_quantity <= 0 or v_quantity >= 1000000000000
      or v_quantity <> round(v_quantity,6)
      or length(coalesce(v_lot,'')) > 80 then
      raise exception 'La cantidad, el depósito o el lote son inválidos';
    end if;
    if exists(select 1 from jsonb_array_elements(v_posted) as x(entry)
      where entry->>'item_id'=v_item_id::text) then
      raise exception 'Cada producto puede figurar una sola vez por venta';
    end if;
    select * into v_item from public.stock_items
      where empresa_id=p_company and id=v_item_id and activo
        and tipo_item='producto_terminado' for share;
    if not found then raise exception 'El producto está inactivo o no es terminado'; end if;
    select * into v_res from private.sale_resolve_price(p_company,p_customer,v_item_id);
    if v_res.price is null then
      raise exception 'Definí el precio de venta de %',v_item.nombre;
    end if;
    select s.descuento_maximo_porcentaje into v_cap from public.ventas_precios_config s where s.empresa_id=p_company;
    v_cap := coalesce(v_cap,0);
    v_disc := coalesce(nullif(btrim(v_line->>'discount_percent'),'')::numeric,0);
    v_reason := nullif(btrim(v_line->>'discount_reason'),'');
    if v_disc = 0 then v_reason := null; end if;
    if v_disc < 0 or v_disc >= 100 or v_disc <> round(v_disc,2) then
      raise exception 'El descuento de % es inválido',v_item.nombre;
    end if;
    if length(coalesce(v_reason,'')) > 200 then
      raise exception 'El motivo del descuento es demasiado largo';
    end if;
    if v_disc > v_cap then
      if private.get_user_role(p_company) is distinct from 'administrador' then
        raise exception 'El descuento de % supera el máximo permitido (% %%)',v_item.nombre,v_cap;
      end if;
      if length(regexp_replace(coalesce(v_reason,''),'[^[:alnum:]]','','g')) < 3 then
        raise exception 'Indicá el motivo del descuento de %',v_item.nombre;
      end if;
    end if;
    v_base := v_res.price;
    if v_disc > 0 and round(v_base*(1-v_disc/100),2) <= 0 then
      raise exception 'El descuento de % deja el precio en cero',v_item.nombre;
    end if;
    if (v_line->>'expected_unit_price') is null
      or (v_line->>'expected_unit_price')::numeric <> round(v_base*(1-v_disc/100),2) then
      raise exception 'El precio de % cambió. Actualizá la pantalla y revisá la venta',v_item.nombre;
    end if;
    select simbolo into v_unit_symbol from public.stock_unidades
      where empresa_id=p_company and id=v_item.unidad_id;
    select codigo into v_warehouse_code from public.stock_depositos
      where empresa_id=p_company and id=v_warehouse and activo for share;
    if not found then raise exception 'Elegí un depósito activo'; end if;
    v_unit_price := round(v_base*(1-v_disc/100),2);
    v_line_total := round(v_quantity*v_unit_price,2);
    v_total := v_total+v_line_total;
    if v_total >= 10000000000000000 then
      raise exception 'El total supera el máximo permitido';
    end if;
    select round(r.costo_estimado/r.cantidad,2) into v_cost
    from public.produccion_fabricaciones r where r.empresa_id=p_company and r.producto_id=v_item_id
    order by r.creado_en desc limit 1;
    v_cost := coalesce(v_cost,v_item.costo_unitario_referencia);
    v_operation := public.post_stock_operation(p_company,v_item_id,v_warehouse,null,
      'egreso',v_quantity,'Venta '||v_sale::text,gen_random_uuid(),v_lot,null);
    v_posted := v_posted || jsonb_build_array(jsonb_build_object(
      'item_id',v_item_id,'warehouse_id',v_warehouse,'warehouse_code',v_warehouse_code,
      'item_code',v_item.codigo,'item_name',v_item.nombre,'unit_symbol',v_unit_symbol,
      'lot_code',v_lot,'quantity',v_quantity,'unit_price',v_unit_price,
      'line_total',v_line_total,'estimated_unit_cost',v_cost,'operation',v_operation,
      'price_list_id',v_res.list_id,'list_unit_price',v_base,'discount_percent',v_disc,
      'discount_reason',v_reason,'tax_percent',v_res.tax_percent));
  end loop;
  insert into public.empresas_numeradores(empresa_id,documento) values(p_company,'venta') on conflict do nothing;
  update public.empresas_numeradores set proximo_numero=proximo_numero+1
    where empresa_id=p_company and documento='venta' returning proximo_numero-1 into v_number;
  insert into public.ventas(id,empresa_id,numero,solicitud_id,solicitud_datos,
    cliente_id,cliente_nombre,cliente_identificacion_fiscal,nota,total,autor_id)
  values(v_sale,p_company,v_number,p_request_id,v_payload,p_customer,
    v_customer.nombre,v_customer.identificacion_fiscal,btrim(p_note),v_total,auth.uid());
  v_line_no := 0;
  for v_post in select value from jsonb_array_elements(v_posted) loop
    v_line_no := v_line_no+1;
    insert into public.ventas_lineas(empresa_id,venta_id,linea,item_id,item_codigo,item_nombre,
      unidad_simbolo,deposito_id,deposito_codigo,lote_codigo,cantidad,precio_unitario,
      total_linea,costo_unitario_estimado,operacion_stock_id,
      lista_precio_id,precio_unitario_lista,descuento_porcentaje,descuento_motivo,impuesto_porcentaje)
    values(p_company,v_sale,v_line_no,
      (v_post->>'item_id')::uuid,v_post->>'item_code',v_post->>'item_name',
      v_post->>'unit_symbol',(v_post->>'warehouse_id')::uuid,v_post->>'warehouse_code',
      v_post->>'lot_code',(v_post->>'quantity')::numeric,(v_post->>'unit_price')::numeric,
      (v_post->>'line_total')::numeric,(v_post->>'estimated_unit_cost')::numeric,
      (v_post->>'operation')::uuid,
      (v_post->>'price_list_id')::uuid,(v_post->>'list_unit_price')::numeric,
      (v_post->>'discount_percent')::numeric,v_post->>'discount_reason',
      (v_post->>'tax_percent')::numeric);
  end loop;
  return v_sale;
end;
$function$;

CREATE OR REPLACE FUNCTION public.post_sale_payment(p_company uuid, p_sale uuid, p_amount numeric, p_method text, p_paid_on date, p_reference text, p_note text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_existing public.ventas_cobros%rowtype;
  v_sale public.ventas%rowtype;
  v_paid numeric;
  v_payment uuid;
  v_reference text := btrim(p_reference);
  v_note text := btrim(p_note);
begin
  if auth.uid() is null or not private.has_permission(p_company,'finanzas','crear')
    or not private.has_permission(p_company,'ventas','ver') then
    raise exception 'Necesitás permisos de Finanzas y Ventas' using errcode='42501';
  end if;
  if p_sale is null or p_request_id is null or p_amount is null or p_amount <= 0
    or p_amount >= 10000000000000000 or p_amount <> round(p_amount,2)
    or p_method is null or p_method not in ('efectivo','transferencia','tarjeta','cheque','otro')
    or p_paid_on is null or v_reference is null or length(v_reference) > 100
    or v_note is null or length(v_note) > 500 then
    raise exception 'Revisá monto, fecha, medio de pago y referencia';
  end if;
  -- Bloquea cobros y anulaciones de una misma venta, también si hay dos operadores.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('receivable:'||p_company::text||':'||p_sale::text,0));
  select * into v_existing from public.ventas_cobros
  where empresa_id=p_company and solicitud_id=p_request_id;
  if found then
    if v_existing.autor_id <> auth.uid() or v_existing.venta_id <> p_sale
      or v_existing.importe <> p_amount or v_existing.medio_pago <> p_method
      or v_existing.fecha_pago <> p_paid_on or v_existing.referencia <> v_reference
      or v_existing.nota <> v_note then
      raise exception 'La solicitud ya fue utilizada con otros datos';
    end if;
    return v_existing.id;
  end if;
  select * into v_sale from public.ventas where empresa_id=p_company and id=p_sale;
  if not found then raise exception 'Venta inexistente'; end if;
  select coalesce(sum(p.importe),0) into v_paid from public.ventas_cobros p
  where p.empresa_id=p_company and p.venta_id=p_sale
    and not exists(select 1 from public.ventas_cobros_reversiones r
      where r.empresa_id=p.empresa_id and r.cobro_id=p.id);
  if p_amount > v_sale.total-v_paid then
    raise exception 'El cobro supera el saldo pendiente de la venta';
  end if;
  insert into public.ventas_cobros(empresa_id,venta_id,solicitud_id,importe,medio_pago,
    fecha_pago,referencia,nota,autor_id)
  values(p_company,p_sale,p_request_id,p_amount,p_method,
    p_paid_on,v_reference,v_note,auth.uid()) returning id into v_payment;
  return v_payment;
end;
$function$;

CREATE OR REPLACE FUNCTION public.post_sale_payment_to_account(p_company uuid, p_sale uuid, p_amount numeric, p_method text, p_paid_on date, p_reference text, p_note text, p_request_id uuid, p_account uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid; v_saved uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'finanzas','crear') then
    raise exception 'Sin permiso para registrar cobros' using errcode='42501'; end if;
  perform 1 from public.finanzas_cuentas where empresa_id=p_company and id=p_account and activo;
  if not found then raise exception 'Elegí una cuenta activa'; end if;
  v_id := public.post_sale_payment(p_company,p_sale,p_amount,p_method,p_paid_on,
    p_reference,p_note,p_request_id);
  select cuenta_id into v_saved from public.finanzas_cobros_cuentas
    where empresa_id=p_company and cobro_id=v_id;
  if found and v_saved<>p_account then raise exception 'Este cobro ya pertenece a otra cuenta'; end if;
  insert into public.finanzas_cobros_cuentas(empresa_id,cobro_id,cuenta_id,autor_id)
  values(p_company,v_id,p_account,auth.uid()) on conflict do nothing;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.post_sale_with_payment(p_company uuid, p_customer uuid, p_note text, p_lines jsonb, p_request_id uuid, p_payment_request_id uuid, p_payment_mode text, p_amount numeric, p_method text, p_account uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_sale uuid; v_total numeric; v_previous public.ventas_cobros_antiduplicado%rowtype;
begin
  if p_payment_mode not in ('pendiente','parcial','pagado') or p_payment_mode is null then
    raise exception 'Elegí cómo quedará el cobro de la venta'; end if;
  if p_payment_mode='pendiente' then
    if p_amount is not null or p_method is not null or p_account is not null
      or p_payment_request_id is not null then
      raise exception 'La venta pendiente no debe incluir datos de cobro'; end if;
  else
    if auth.uid() is null or not private.has_permission(p_company,'finanzas','crear')
      or not private.has_permission(p_company,'ventas','ver') then
      raise exception 'Necesitás permiso para registrar cobros' using errcode='42501'; end if;
    if p_payment_request_id is null or p_amount is null or p_amount<=0
      or p_amount<>round(p_amount,2) or p_account is null
      or p_method not in ('efectivo','transferencia','tarjeta','cheque','otro') then
      raise exception 'Indicá monto, medio de pago y cuenta'; end if;
    perform 1 from public.finanzas_cuentas a
      where a.empresa_id=p_company and a.id=p_account and a.activo
        and (p_method<>'efectivo' or a.tipo='caja');
    if not found then raise exception 'Elegí una cuenta activa compatible con el medio de pago'; end if;
  end if;
  -- La función original comprueba idempotencia, precios y stock en la misma transacción.
  v_sale:=public.post_sale(p_company,p_customer,p_note,p_lines,p_request_id);
  select * into v_previous from public.ventas_cobros_antiduplicado
    where empresa_id=p_company and solicitud_id=p_request_id;
  if found then
    if v_previous.autor_id<>auth.uid() or v_previous.venta_id<>v_sale
      or v_previous.solicitud_cobro_id is distinct from p_payment_request_id
      or v_previous.modo_pago<>p_payment_mode
      or v_previous.importe is distinct from p_amount
      or v_previous.medio_pago is distinct from p_method
      or v_previous.cuenta_id is distinct from p_account then
      raise exception 'Esta solicitud ya se usó con otra forma de cobro'; end if;
    return v_sale;
  end if;
  select total into v_total from public.ventas where empresa_id=p_company and id=v_sale;
  if p_payment_mode<>'pendiente' then
    if p_amount>v_total or (p_payment_mode='pagado' and p_amount<>v_total)
      or (p_payment_mode='parcial' and p_amount>=v_total) then
      raise exception 'El cobro no coincide con el total de la venta'; end if;
  end if;
  insert into public.ventas_cobros_antiduplicado(empresa_id,solicitud_id,venta_id,solicitud_cobro_id,
    modo_pago,importe,medio_pago,cuenta_id,autor_id)
  values(p_company,p_request_id,v_sale,p_payment_request_id,p_payment_mode,
    p_amount,p_method,p_account,auth.uid());
  if p_payment_mode<>'pendiente' then
    perform public.post_sale_payment_to_account(p_company,v_sale,p_amount,p_method,
      (now() at time zone 'America/Argentina/Buenos_Aires')::date,
      '','Cobro al registrar la venta',p_payment_request_id,p_account);
  end if;
  return v_sale;
end;
$function$;

CREATE OR REPLACE FUNCTION public.post_stock_operation(p_company uuid, p_item uuid, p_warehouse uuid, p_to_warehouse uuid, p_kind text, p_quantity numeric, p_note text, p_request_id uuid, p_lot_code text, p_expires_on date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_reserved numeric; v_own numeric; v_usable numeric;
  v_slot_reserved numeric; v_slot_own numeric; v_slot_physical numeric;
  v_track boolean; v_lot uuid; v_expiry date;
  v_job uuid; v_operation uuid; v_infinite boolean; v_existing public.stock_operaciones%rowtype;
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null or not private.has_permission(p_company,'stock','crear') then
    raise exception 'Sin permiso para registrar movimientos' using errcode='42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('production-reservations:'||p_company::text,0));
  if p_request_id is not null and exists (
    select 1 from public.stock_operaciones o
    where o.empresa_id=p_company and o.solicitud_id=p_request_id
  ) then
    return private.post_stock_operation(p_company,p_item,p_warehouse,
      p_to_warehouse,p_kind,p_quantity,p_note,p_request_id,p_lot_code,p_expires_on);
  end if;
  select i.stock_infinito into v_infinite from public.stock_items i
    where i.empresa_id=p_company and i.id=p_item and i.activo for share;
  if coalesce(v_infinite,false) then
    if p_request_id is null or p_warehouse is null or p_kind not in ('ingreso','egreso')
      or p_to_warehouse is not null or p_quantity is null or p_quantity<=0
      or p_quantity>=1000000000000 or p_quantity<>round(p_quantity,6)
      or length(btrim(coalesce(p_note,''))) not between 3 and 500
      or nullif(btrim(coalesce(p_lot_code,'')),'') is not null
      or p_expires_on is not null then
      raise exception 'Movimiento inválido para un ítem de stock infinito';
    end if;
    perform 1 from public.empresas c where c.id=p_company and c.activo for share;
    if not found then raise exception 'La empresa está suspendida'; end if;
    perform 1 from public.stock_depositos w where w.empresa_id=p_company
      and w.id=p_warehouse and w.activo for share;
    if not found then raise exception 'Elegí un depósito activo'; end if;
    v_job:=nullif(pg_catalog.current_setting('dromux.production_job',true),'')::uuid;
    if v_job is not null and p_kind='egreso' and not exists (
      select 1 from public.produccion_ordenes j where j.empresa_id=p_company
        and j.id=v_job and j.estado in ('pendiente','en_proceso')) then
      raise exception 'Orden de fabricación no activa';
    end if;
    insert into public.stock_operaciones(empresa_id,solicitud_id,item_id,deposito_id,
      tipo,cantidad,nota,autor_id)
    values(p_company,p_request_id,p_item,p_warehouse,p_kind,p_quantity,btrim(p_note),auth.uid())
    on conflict(empresa_id,solicitud_id) do nothing returning id into v_operation;
    if v_operation is null then
      select * into v_existing from public.stock_operaciones o
        where o.empresa_id=p_company and o.solicitud_id=p_request_id;
      if v_existing.item_id is distinct from p_item
        or v_existing.deposito_id is distinct from p_warehouse
        or v_existing.deposito_destino_id is not null or v_existing.tipo<>p_kind
        or v_existing.cantidad<>p_quantity or v_existing.nota<>btrim(p_note)
        or v_existing.autor_id<>auth.uid() then
        raise exception 'Esta solicitud ya se usó con otros datos';
      end if;
      return v_existing.id;
    end if;
    return v_operation;
  end if;
  perform private.rebalance_production_reservations(p_company);
  if p_kind in ('egreso','transferencia') and p_item is not null
    and p_warehouse is not null and p_quantity>0 then
    v_job:=nullif(pg_catalog.current_setting('dromux.production_job',true),'')::uuid;
    if v_job is not null and p_kind='egreso' then
      perform 1 from public.produccion_ordenes j where j.empresa_id=p_company
        and j.id=v_job and j.estado in ('pendiente','en_proceso');
      if not found then raise exception 'Orden de fabricación no activa'; end if;
    end if;
    select i.usa_lotes into v_track from public.stock_items i
      where i.empresa_id=p_company and i.id=p_item;
    if v_track then
      select l.id,l.vencimiento into v_lot,v_expiry from public.stock_lotes l
        where l.empresa_id=p_company and l.item_id=p_item
          and lower(l.codigo)=lower(btrim(p_lot_code));
      if v_lot is null then raise exception 'Elegí un lote existente'; end if;
      if p_kind='egreso' and v_expiry<v_today then
        raise exception 'El lote está vencido. Elegí uno vigente'; end if;
      select coalesce(b.cantidad,0) into v_slot_physical
        from public.stock_lotes_saldos b where b.empresa_id=p_company
          and b.item_id=p_item and b.deposito_id=p_warehouse and b.lote_id=v_lot;
    else
      select coalesce(b.cantidad,0) into v_slot_physical
        from public.stock_saldos b where b.empresa_id=p_company
          and b.item_id=p_item and b.deposito_id=p_warehouse;
    end if;
    v_slot_physical:=coalesce(v_slot_physical,0);
    select coalesce(sum(a.cantidad),0),
      coalesce(sum(a.cantidad) filter(where a.orden_id=v_job),0)
      into v_slot_reserved,v_slot_own
      from public.produccion_reservas_ubicaciones a
      join public.produccion_ordenes j on j.empresa_id=a.empresa_id and j.id=a.orden_id
      where a.empresa_id=p_company and a.componente_id=p_item
        and a.deposito_id=p_warehouse
        and a.lote_id is not distinct from v_lot
        and j.estado in ('pendiente','en_proceso');
    if p_quantity>greatest(0,v_slot_physical-v_slot_reserved
      +case when p_kind='egreso' then v_slot_own else 0 end) then
      raise exception 'Stock libre insuficiente en el depósito y lote elegidos';
    end if;
    if p_kind='egreso' then
      select coalesce(sum(a.cantidad),0),
        coalesce(sum(a.cantidad) filter(where a.orden_id=v_job),0)
        into v_reserved,v_own from public.produccion_reservas_ubicaciones a
        join public.produccion_ordenes j on j.empresa_id=a.empresa_id and j.id=a.orden_id
        where a.empresa_id=p_company and a.componente_id=p_item
          and j.estado in ('pendiente','en_proceso');
      if v_track then
        select coalesce(sum(lb.cantidad),0) into v_usable
          from public.stock_lotes_saldos lb
          join public.stock_depositos w on w.empresa_id=lb.empresa_id
            and w.id=lb.deposito_id and w.activo
          join public.stock_lotes l on l.empresa_id=lb.empresa_id
            and l.item_id=lb.item_id and l.id=lb.lote_id
          where lb.empresa_id=p_company and lb.item_id=p_item
            and (l.vencimiento is null or l.vencimiento>=v_today);
      else
        select coalesce(sum(b.cantidad),0) into v_usable
          from public.stock_saldos b
          join public.stock_depositos w on w.empresa_id=b.empresa_id
            and w.id=b.deposito_id and w.activo
          where b.empresa_id=p_company and b.item_id=p_item;
      end if;
      if p_quantity>greatest(0,v_usable-v_reserved+v_own) then
        raise exception 'Stock comprometido para fabricación: saldo libre insuficiente';
      end if;
    end if;
  end if;
  v_operation:=private.post_stock_operation(p_company,p_item,p_warehouse,
    p_to_warehouse,p_kind,p_quantity,p_note,p_request_id,p_lot_code,p_expires_on);
  if p_kind in ('ingreso','egreso','transferencia') then
    perform private.rebalance_production_reservations(p_company);
  end if;
  return v_operation;
end;
$function$;

CREATE OR REPLACE FUNCTION public.post_treasury_entry(p_company uuid, p_account uuid, p_kind text, p_amount numeric, p_order uuid, p_note text, p_on date, p_request uuid, p_target uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old public.finanzas_movimientos%rowtype; v_id uuid; v_total numeric; v_paid numeric;
begin
  if auth.uid() is null or not private.has_permission(p_company,'finanzas','crear') then
    raise exception 'Sin permiso para registrar movimientos' using errcode='42501'; end if;
  perform 1 from public.empresas where id=p_company and activo for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  if p_request is null or p_amount is null or p_amount<=0 or p_amount<>round(p_amount,2)
    or p_kind not in ('ingreso','egreso','pago_proveedor','transferencia_salida')
    or p_note is null or length(btrim(p_note)) not between 3 and 240
    or p_on is null or p_on>(now() at time zone 'America/Argentina/Buenos_Aires')::date
    or (p_kind='pago_proveedor') is distinct from (p_order is not null)
    or (p_kind='transferencia_salida') is distinct from (p_target is not null)
    or p_account=p_target then raise exception 'Revisá los datos del movimiento'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('treasury:'||p_company::text,0));
  select * into v_old from public.finanzas_movimientos
    where empresa_id=p_company and solicitud_id=p_request and tipo=p_kind;
  if found then
    if v_old.cuenta_id<>p_account or v_old.importe<>p_amount
      or v_old.orden_compra_id is distinct from p_order or v_old.nota<>btrim(p_note)
      or v_old.fecha<>p_on or v_old.autor_id<>auth.uid()
      or (p_kind='transferencia_salida' and not exists (
        select 1 from public.finanzas_movimientos t where t.empresa_id=p_company
        and t.solicitud_id=p_request and t.tipo='transferencia_entrada' and t.cuenta_id=p_target))
      then raise exception 'La solicitud ya se usó con otros datos'; end if;
    return v_old.id;
  end if;
  perform 1 from public.finanzas_cuentas where empresa_id=p_company and id=p_account and activo;
  if not found then raise exception 'Cuenta de origen inexistente o inactiva'; end if;
  if p_target is not null then
    perform 1 from public.finanzas_cuentas where empresa_id=p_company and id=p_target and activo;
    if not found then raise exception 'Cuenta de destino inexistente o inactiva'; end if;
  end if;
  if p_order is not null then
    select coalesce(sum(l.cantidad*l.precio_unitario),0) into v_total
      from public.compras_ordenes o join public.compras_ordenes_lineas l
      on l.empresa_id=o.empresa_id and l.orden_compra_id=o.id
      where o.empresa_id=p_company and o.id=p_order and o.estado in ('abierta','parcial','recibida');
    if v_total=0 then raise exception 'Seleccioná una orden de compra abierta'; end if;
    select coalesce(sum(importe),0) into v_paid from public.finanzas_movimientos
      where empresa_id=p_company and orden_compra_id=p_order;
    if p_amount>round(v_total,2)-v_paid then
      raise exception 'El pago supera el saldo de la orden'; end if;
  end if;
  insert into public.finanzas_movimientos(empresa_id,cuenta_id,solicitud_id,tipo,
    importe,orden_compra_id,nota,fecha,autor_id)
  values(p_company,p_account,p_request,p_kind,p_amount,p_order,btrim(p_note),p_on,auth.uid())
  returning id into v_id;
  if p_target is not null then
    insert into public.finanzas_movimientos(empresa_id,cuenta_id,solicitud_id,tipo,
      importe,nota,fecha,autor_id)
    values(p_company,p_target,p_request,'transferencia_entrada',p_amount,btrim(p_note),p_on,auth.uid());
  end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.preview_item_import(p_company uuid, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return private.prepare_item_import(p_company,p_rows);
end; $function$;

CREATE OR REPLACE FUNCTION public.production_formula_cost(p_company uuid, p_product uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.can_see_production_costs(p_company) then
    raise exception 'Solo un administrador con acceso a finanzas puede consultar costos' using errcode='42501'; end if;
  return private.production_unit_cost(p_company,p_product);
end;
$function$;

CREATE OR REPLACE FUNCTION public.production_output_by_product(p_company uuid, p_from date, p_to date, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 25, p_offset integer DEFAULT 0, p_tz text DEFAULT 'America/Argentina/Buenos_Aires'::text)
 RETURNS TABLE(product_id uuid, product_code text, product_name text, unit_symbol text, orders bigint, planned_quantity numeric, expected_quantity numeric, actual_quantity numeric, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_search text := lower(btrim(coalesce(p_search, '')));
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_estadistica','ver') then
    raise exception 'Sin permiso para ver la producción' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_from > p_to or p_to - p_from > 3660 then
    raise exception 'Elegí un rango de fechas válido (hasta 10 años)';
  end if;
  if p_limit is null or p_limit not between 1 and 100 or p_offset is null or p_offset < 0 then
    raise exception 'Paginación inválida';
  end if;
  if length(v_search) > 80 then
    raise exception 'La búsqueda es demasiado larga';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_tz) then
    raise exception 'Zona horaria inválida';
  end if;
  return query
    select g.producto_id, g.codigo, g.nombre, g.simbolo, g.orders, g.planned, g.expected, g.actual,
      count(*) over ()
    from (
      select j.producto_id, i.codigo, i.nombre, u.simbolo,
        count(*) as orders,
        sum(j.cantidad_planificada) as planned,
        sum(j.cantidad_esperada) as expected,
        sum(j.cantidad_real) as actual
      from public.produccion_ordenes j
      join public.stock_items i on i.empresa_id = j.empresa_id and i.id = j.producto_id
      join public.stock_unidades u on u.empresa_id = i.empresa_id and u.id = i.unidad_id
      where j.empresa_id = p_company
        and j.estado = 'terminada'
        and j.terminado_en >= (p_from::timestamp at time zone p_tz)
        and j.terminado_en < ((p_to + 1)::timestamp at time zone p_tz)
        and (v_search = ''
          or position(v_search in lower(i.nombre)) > 0
          or position(v_search in lower(i.codigo)) > 0)
      group by j.producto_id, i.codigo, i.nombre, u.simbolo
    ) g
    order by g.actual desc, g.nombre, g.producto_id
    limit p_limit offset p_offset;
end;
$function$;

CREATE OR REPLACE FUNCTION public.production_output_summary(p_company uuid, p_from date, p_to date, p_bucket text DEFAULT 'month'::text, p_product uuid DEFAULT NULL::uuid, p_tz text DEFAULT 'America/Argentina/Buenos_Aires'::text)
 RETURNS TABLE(bucket_start date, unit_symbol text, orders bigint, planned_quantity numeric, expected_quantity numeric, actual_quantity numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_estadistica','ver') then
    raise exception 'Sin permiso para ver la producción' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_from > p_to or p_to - p_from > 3660 then
    raise exception 'Elegí un rango de fechas válido (hasta 10 años)';
  end if;
  if p_bucket not in ('day', 'week', 'month') then
    raise exception 'Agrupá por día, semana o mes';
  end if;
  if p_bucket = 'day' and p_to - p_from > 366 then
    raise exception 'Para agrupar por día elegí un rango de hasta un año';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_tz) then
    raise exception 'Zona horaria inválida';
  end if;
  return query
    select date_trunc(p_bucket, j.terminado_en at time zone p_tz)::date,
      u.simbolo,
      count(*),
      sum(j.cantidad_planificada),
      sum(j.cantidad_esperada),
      sum(j.cantidad_real)
    from public.produccion_ordenes j
    join public.stock_items i on i.empresa_id = j.empresa_id and i.id = j.producto_id
    join public.stock_unidades u on u.empresa_id = i.empresa_id and u.id = i.unidad_id
    where j.empresa_id = p_company
      and j.estado = 'terminada'
      and j.terminado_en >= (p_from::timestamp at time zone p_tz)
      and j.terminado_en < ((p_to + 1)::timestamp at time zone p_tz)
      and (p_product is null or j.producto_id = p_product)
    group by 1, 2
    order by 1, 2;
end;
$function$;

CREATE OR REPLACE FUNCTION public.purchase_item_options(p_company uuid, p_search text DEFAULT ''::text)
 RETURNS TABLE(id uuid, code text, name text, unit_symbol text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not (private.has_permission(p_company,'compras_ordenes','ver') or private.has_permission(p_company,'compras_proveedores','ver')) then
    raise exception 'Sin permiso para consultar ítems de compra' using errcode = '42501';
  end if;
  if length(coalesce(p_search, '')) > 100 then
    raise exception 'Búsqueda demasiado larga';
  end if;
  return query
    select i.id, i.codigo, i.nombre, u.simbolo
    from public.stock_items i
    join public.stock_unidades u on u.empresa_id = i.empresa_id and u.id = i.unidad_id
    where i.empresa_id = p_company and i.activo
      and (coalesce(p_search, '') = ''
        or i.nombre ilike '%' || p_search || '%'
        or i.codigo ilike '%' || p_search || '%'
        or i.codigo_barras ilike '%' || p_search || '%')
    order by i.nombre, i.id
    limit 30;
end;
$function$;

CREATE OR REPLACE FUNCTION public.purchase_material_options(p_company uuid, p_search text DEFAULT ''::text, p_supplier uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, code text, name text, unit_symbol text, item_type text, reference_unit_cost numeric, supplier_unit_price numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not ((private.has_permission(p_company,'compras_ordenes','ver') or private.has_permission(p_company,'compras_proveedores','ver')) and private.has_permission(p_company,'costos_materiales','ver')) then
    raise exception 'Sin permiso para consultar ítems de compra' using errcode='42501'; end if;
  if length(coalesce(p_search,''))>100 then raise exception 'Búsqueda demasiado larga'; end if;
  return query select i.id,i.codigo,i.nombre,u.simbolo,i.tipo_item,i.costo_unitario_referencia,
    case when si.moneda='USD' then
      round(si.precio_unitario*private.current_fx_rate(p_company,si.tipo_cambio_id)
        *(1+si.ajuste_porcentaje/100),2)
    else round(si.precio_unitario*(1+si.ajuste_porcentaje/100),2) end
  from public.stock_items i
  join public.stock_unidades u on u.empresa_id=i.empresa_id and u.id=i.unidad_id
  left join public.compras_proveedores_items si on si.empresa_id=i.empresa_id
    and si.item_id=i.id and si.proveedor_id=p_supplier
  where i.empresa_id=p_company and i.activo
    and (p_supplier is null or si.item_id is not null)
    and (coalesce(p_search,'')='' or i.nombre ilike '%'||p_search||'%'
      or i.codigo ilike '%'||p_search||'%' or i.codigo_barras ilike '%'||p_search||'%')
  order by i.nombre,i.id limit 50;
end;
$function$;

CREATE OR REPLACE FUNCTION public.purchase_receivable_lines(p_company uuid, p_order uuid)
 RETURNS TABLE(line_no smallint, item_id uuid, item_code text, item_name text, unit_symbol text, quantity numeric, received_quantity numeric, unit_price numeric, track_lots boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.has_permission(p_company,'compras_ordenes','ver') then
    raise exception 'Sin permiso para consultar órdenes' using errcode = '42501';
  end if;
  return query
    select l.linea, l.item_id, l.item_codigo, l.item_nombre,
      l.unidad_simbolo, l.cantidad, l.cantidad_recibida, l.precio_unitario,
      i.usa_lotes
    from public.compras_ordenes_lineas l
    join public.stock_items i on i.empresa_id = l.empresa_id and i.id = l.item_id
    where l.empresa_id = p_company and l.orden_compra_id = p_order
    order by l.linea;
end;
$function$;

CREATE OR REPLACE FUNCTION public.purchase_request_item_options(p_company uuid, p_search text DEFAULT ''::text)
 RETURNS TABLE(id uuid, code text, name text, unit_symbol text, item_type text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_term text := lower(btrim(coalesce(p_search, '')));
begin
  if auth.uid() is null
     or not (private.has_permission(p_company, 'compras_pedidos', 'crear')
             or private.has_permission(p_company,'compras_pedidos','crear')) then
    raise exception 'Sin permiso para armar pedidos de compra' using errcode = '42501';
  end if;
  if length(v_term) > 100 then raise exception 'Búsqueda demasiado larga'; end if;
  return query
    select i.id, i.codigo, i.nombre, u.simbolo, i.tipo_item
    from public.stock_items i
    join public.stock_unidades u on u.empresa_id = i.empresa_id and u.id = i.unidad_id
    where i.empresa_id = p_company and i.activo and not i.archivado
      and i.tipo_item in ('materia_prima', 'insumo', 'semielaborado')
      and (v_term = '' or position(v_term in lower(i.codigo || ' ' || i.nombre)) > 0)
    order by i.nombre, i.id
    limit 20;
end;
$function$;

CREATE OR REPLACE FUNCTION public.purchase_supplier_quotes(p_company uuid, p_supplier uuid DEFAULT NULL::uuid, p_item uuid DEFAULT NULL::uuid)
 RETURNS TABLE(supplier_id uuid, supplier_name text, supplier_active boolean, item_id uuid, item_code text, item_name text, unit_symbol text, reference_unit_cost numeric, unit_price numeric, supplier_sku text, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not ((private.has_permission(p_company,'compras_ordenes','ver') or private.has_permission(p_company,'compras_proveedores','ver')) and private.has_permission(p_company,'costos_materiales','ver')) then
    raise exception 'Sin permiso para ver cotizaciones' using errcode = '42501';
  end if;
  return query
    select s.id, s.nombre, s.activo, i.id, i.codigo, i.nombre, u.simbolo,
      i.costo_unitario_referencia, si.precio_unitario, si.proveedor_codigo, si.actualizado_en
    from public.compras_proveedores_items si
    join public.compras_proveedores s
      on s.empresa_id = si.empresa_id and s.id = si.proveedor_id
    join public.stock_items i
      on i.empresa_id = si.empresa_id and i.id = si.item_id
    join public.stock_unidades u
      on u.empresa_id = i.empresa_id and u.id = i.unidad_id
    where si.empresa_id = p_company
      and (p_supplier is null or si.proveedor_id = p_supplier)
      and (p_item is null or si.item_id = p_item)
    order by i.nombre, si.precio_unitario, s.nombre
    limit 500;
end;
$function$;

CREATE OR REPLACE FUNCTION public.purchase_suppliers_for_items(p_company uuid, p_items uuid[])
 RETURNS TABLE(id uuid, name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'compras_ordenes','ver') then
    raise exception 'Sin permiso para consultar proveedores' using errcode='42501'; end if;
  if p_items is null or coalesce(array_length(p_items,1),0) not between 1 and 40
    or (select count(distinct x) from unnest(p_items) x)<>array_length(p_items,1)
    or array_position(p_items,null) is not null then
    raise exception 'Seleccioná entre uno y cuarenta ítems distintos'; end if;
  return query select s.id,s.nombre from public.compras_proveedores s
    join public.compras_proveedores_items si on si.empresa_id=s.empresa_id
      and si.proveedor_id=s.id and si.item_id=any(p_items)
    join public.stock_items i on i.empresa_id=si.empresa_id and i.id=si.item_id and i.activo
    where s.empresa_id=p_company and s.activo
    group by s.id,s.nombre having count(distinct si.item_id)=array_length(p_items,1)
    order by s.nombre limit 100;
end;
$function$;

CREATE OR REPLACE FUNCTION public.recalculate_production_reservations(p_company uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not (private.has_permission(p_company,'produccion_disponibilidad','ver') or private.has_permission(p_company,'produccion_ordenes','ver'))
    or not private.has_permission(p_company,'stock_saldos','ver') then
    raise exception 'Necesitás acceso a producción y stock' using errcode='42501';
  end if;
  perform private.rebalance_production_reservations(p_company);
end;
$function$;

CREATE OR REPLACE FUNCTION public.receive_purchase_order(p_company uuid, p_order uuid, p_request_id uuid, p_note text, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_note text := btrim(p_note);
  v_order public.compras_ordenes%rowtype;
  v_existing public.compras_recepciones%rowtype;
  v_receipt uuid;
  v_entry jsonb;
  v_line_no smallint;
  v_item uuid;
  v_order_quantity numeric(18, 6);
  v_received numeric(18, 6);
  v_price numeric(18, 2);
  v_quantity numeric(18, 6);
  v_warehouse uuid;
  v_warehouse_code text;
  v_lot_code text;
  v_expires date;
  v_operation uuid;
  v_count integer := 0;
begin
  if auth.uid() is null
     or not private.has_permission(p_company,'compras_ordenes','crear')
     or not private.has_permission(p_company, 'stock', 'crear') then
    raise exception 'Sin permiso para recibir compras y registrar stock'
      using errcode = '42501';
  end if;

  if p_request_id is null or p_order is null or v_note is null
     or length(v_note) not between 3 and 430
     or jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) not between 1 and 200 then
    raise exception 'Datos de recepción inválidos';
  end if;

  perform 1 from public.empresas c
  where c.id = p_company and c.activo for share;
  if not found then raise exception 'La empresa no está activa'; end if;

  -- Todas las recepciones de una orden compiten por la misma fila.
  select * into v_order from public.compras_ordenes o
  where o.empresa_id = p_company and o.id = p_order for update;
  if not found then raise exception 'Orden inexistente'; end if;

  select * into v_existing from public.compras_recepciones r
  where r.empresa_id = p_company and r.solicitud_id = p_request_id;
  if found then
    if v_existing.orden_compra_id is distinct from p_order
       or v_existing.autor_id is distinct from auth.uid()
       or v_existing.nota is distinct from v_note
       or v_existing.solicitud_datos is distinct from p_lines then
      raise exception 'Esta solicitud ya se usó con otros datos';
    end if;
    return v_existing.id;
  end if;

  if v_order.estado not in ('abierta', 'parcial') then
    raise exception 'La orden ya no admite recepciones';
  end if;

  insert into public.compras_recepciones(
    empresa_id, orden_compra_id, solicitud_id, solicitud_datos, nota, autor_id
  ) values (p_company, p_order, p_request_id, p_lines, v_note, auth.uid())
  returning id into v_receipt;

  for v_entry in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(v_entry) is distinct from 'object'
       or coalesce(v_entry->>'line_no', '') !~ '^[1-9][0-9]?$'
       or coalesce(v_entry->>'quantity', '') !~ '^[0-9]+(\.[0-9]{1,6})?$'
       or coalesce(v_entry->>'warehouse_id', '') !~
          '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
       or length(coalesce(v_entry->>'lot_code', '')) > 80
       or (v_entry->>'expires_on' is not null
         and (v_entry->>'expires_on') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') then
      raise exception 'Línea de recepción inválida';
    end if;

    v_line_no := (v_entry->>'line_no')::smallint;
    v_quantity := (v_entry->>'quantity')::numeric;
    v_warehouse := (v_entry->>'warehouse_id')::uuid;
    v_lot_code := nullif(btrim(v_entry->>'lot_code'), '');
    v_expires := nullif(v_entry->>'expires_on', '')::date;

    if v_quantity <= 0 or v_quantity >= 1000000000000 then
      raise exception 'La cantidad debe ser mayor a cero';
    end if;

    select l.item_id, l.cantidad, l.cantidad_recibida, l.precio_unitario
    into v_item, v_order_quantity, v_received, v_price
    from public.compras_ordenes_lineas l
    where l.empresa_id = p_company and l.orden_compra_id = p_order
      and l.linea = v_line_no for update;
    if not found then raise exception 'Línea inexistente en la orden'; end if;
    if v_received + v_quantity > v_order_quantity then
      raise exception 'La cantidad supera lo pendiente en la línea %', v_line_no;
    end if;

    -- Reutiliza la operación transaccional y las reglas de depósito/lote.
    v_operation := public.post_stock_operation(
      p_company, v_item, v_warehouse, null, 'ingreso', v_quantity,
      'Recepción OC #' || v_order.numero::text || ' · ' || v_note,
      gen_random_uuid(), v_lot_code, v_expires
    );

    select op.lote_codigo, op.lote_vencimiento
    into v_lot_code, v_expires
    from public.stock_operaciones op
    where op.empresa_id = p_company and op.id = v_operation;

    select w.codigo into v_warehouse_code from public.stock_depositos w
    where w.empresa_id = p_company and w.id = v_warehouse;

    insert into public.compras_recepciones_lineas(
      empresa_id, recepcion_id, orden_compra_id, linea, item_id,
      deposito_id, deposito_codigo, cantidad, precio_unitario, lote_codigo, vencimiento,
      operacion_stock_id
    ) values (
      p_company, v_receipt, p_order, v_line_no, v_item,
      v_warehouse, v_warehouse_code, v_quantity, v_price, v_lot_code, v_expires,
      v_operation
    );

    update public.compras_ordenes_lineas l
    set cantidad_recibida = l.cantidad_recibida + v_quantity
    where l.empresa_id = p_company and l.orden_compra_id = p_order
      and l.linea = v_line_no;

    v_count := v_count + 1;
  end loop;

  update public.compras_ordenes o
  set estado = case
    when not exists (
      select 1 from public.compras_ordenes_lineas l
      where l.empresa_id = p_company and l.orden_compra_id = p_order
        and l.cantidad_recibida < l.cantidad
    ) then 'recibida' else 'parcial' end
  where o.empresa_id = p_company and o.id = p_order;

  return v_receipt;
end;
$function$;

CREATE OR REPLACE FUNCTION public.refund_sale_credit(p_company uuid, p_sale uuid, p_account uuid, p_amount numeric, p_reason text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_existing public.ventas_reintegros%rowtype; v_available numeric;
  v_entry uuid; v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'finanzas','crear')
    or not private.has_permission(p_company,'finanzas','ver')
    or not private.has_permission(p_company,'ventas','editar') then
    raise exception 'Sin permiso para registrar devoluciones de dinero' using errcode='42501'; end if;
  if p_sale is null or p_account is null or p_request_id is null or p_amount is null
    or p_amount<=0 or p_amount<>round(p_amount,2)
    or length(btrim(coalesce(p_reason,''))) not between 5 and 240 then
    raise exception 'Indicá cuenta, importe y motivo del reintegro'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('receivable:'||p_company::text||':'||p_sale::text,0));
  select * into v_existing from public.ventas_reintegros
    where empresa_id=p_company and solicitud_id=p_request_id;
  if found then
    if v_existing.autor_id<>auth.uid() or v_existing.venta_id<>p_sale
      or v_existing.cuenta_id<>p_account or v_existing.importe<>p_amount
      or v_existing.motivo<>btrim(p_reason) then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_existing.id;
  end if;
  select b.credit_due into v_available from public.sale_credit_balance(p_company,p_sale) b;
  if v_available is null or p_amount>v_available then
    raise exception 'El reintegro supera el crédito disponible'; end if;
  v_entry:=public.post_treasury_entry(p_company,p_account,'egreso',p_amount,
    null,'Reintegro venta '||p_sale::text,
    (now() at time zone 'America/Argentina/Buenos_Aires')::date,p_request_id,null);
  insert into public.ventas_reintegros(empresa_id,venta_id,solicitud_id,cuenta_id,
    movimiento_finanzas_id,importe,motivo,autor_id)
  values(p_company,p_sale,p_request_id,p_account,v_entry,p_amount,btrim(p_reason),auth.uid())
  returning id into v_id;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.reject_purchase_request(p_company uuid, p_request uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row public.compras_pedidos%rowtype; v_reason text := btrim(coalesce(p_reason, ''));
begin
  if auth.uid() is null or not (private.has_permission(p_company,'compras_pedidos','gestionar') and private.has_permission(p_company,'compras_pedidos','editar')) then
    raise exception 'Sin permiso para rechazar pedidos' using errcode = '42501';
  end if;
  if length(v_reason) not between 5 and 500 then
    raise exception 'Indicá el motivo (5 a 500 caracteres)';
  end if;
  select * into v_row from public.compras_pedidos
  where id = p_request and empresa_id = p_company for update;
  if not found then raise exception 'Pedido inexistente'; end if;
  if v_row.estado <> 'pendiente' then raise exception 'El pedido ya fue resuelto'; end if;
  update public.compras_pedidos
  set estado = 'rechazado', nota_resolucion = v_reason,
      resuelto_por = auth.uid(), resuelto_en = clock_timestamp()
  where id = p_request;
end;
$function$;

CREATE OR REPLACE FUNCTION public.remove_price_list_item(p_company uuid, p_list uuid, p_item uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old numeric;
begin
  perform private.price_require_admin(p_company);
  perform 1 from public.ventas_listas_precios where empresa_id = p_company and id = p_list and not archivado for share;
  if not found then raise exception 'Lista inexistente o archivada'; end if;
  select precio_neto into v_old from public.ventas_listas_items
  where empresa_id = p_company and lista_precio_id = p_list and item_id = p_item for update;
  if not found then return; end if;
  delete from public.ventas_listas_items_metodo where empresa_id = p_company and lista_precio_id = p_list and item_id = p_item;
  delete from public.ventas_listas_items where empresa_id = p_company and lista_precio_id = p_list and item_id = p_item;
  insert into public.ventas_listas_items_historial(empresa_id, lista_precio_id, item_id, precio_neto_anterior, precio_neto_nuevo,
    origen, motivo, cambiado_por)
  values (p_company, p_list, p_item, v_old, null, 'quitado', left(coalesce(p_reason, ''), 200), auth.uid());
end;
$function$;

create or replace function public.restore_archived_record(p_company uuid, p_resource text, p_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare v_target record; v_row jsonb;
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if auth.uid() is null or not private.has_permission(p_company,v_target.permission,'eliminar') then
    raise exception 'Sin permiso para recuperar el registro' using errcode='42501'; end if;
  execute format('select to_jsonb(t) from public.%I t where empresa_id=$1 and %I=$2 and archivado for update',v_target.table_name,v_target.id_field)
    into v_row using p_company,p_id;
  if v_row is null then raise exception 'No se encontró el registro archivado'; end if;
  if p_resource='items' and coalesce((v_row->>'activo_antes_de_archivar')::boolean,true) then
    perform 1 from public.finanzas_tipos_cambio t where t.empresa_id=p_company and (
      t.id=(v_row->>'tipo_cambio_referencia_id')::uuid or exists(
        select 1 from public.compras_proveedores_items q where q.empresa_id=p_company and q.item_id=p_id and q.tipo_cambio_id=t.id)) for share;
    if exists(select 1 from public.finanzas_tipos_cambio t where t.empresa_id=p_company and not t.activo and (
      t.id=(v_row->>'tipo_cambio_referencia_id')::uuid or exists(
        select 1 from public.compras_proveedores_items q where q.empresa_id=p_company and q.item_id=p_id and q.tipo_cambio_id=t.id))) then
      raise exception 'Recuperá primero los tipos de dólar que usa este ítem'; end if;
  elsif p_resource='formulas' then
    perform 1 from public.stock_items i where i.empresa_id=p_company and (i.id=p_id or exists(
      select 1 from public.produccion_formulas_lineas l where l.empresa_id=p_company and l.producto_id=p_id and l.componente_id=i.id)) for share;
    if exists(select 1 from public.stock_items i where i.empresa_id=p_company and not i.activo and (i.id=p_id or exists(
      select 1 from public.produccion_formulas_lineas l where l.empresa_id=p_company and l.producto_id=p_id and l.componente_id=i.id))) then
      raise exception 'Recuperá o activá primero el producto y sus componentes'; end if;
  end if;
  if p_resource in ('items','tipos_cambio') then
    execute format('update public.%I set archivado=false,activo=coalesce(activo_antes_de_archivar,true),activo_antes_de_archivar=null where empresa_id=$1 and %I=$2',v_target.table_name,v_target.id_field)
      using p_company,p_id;
  else
    execute format('update public.%I set archivado=false where empresa_id=$1 and %I=$2',v_target.table_name,v_target.id_field) using p_company,p_id;
  end if;
end
$function$;

CREATE OR REPLACE FUNCTION public.return_production_material(p_company uuid, p_job uuid, p_issue uuid, p_quantity numeric, p_note text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.produccion_ordenes%rowtype;
  v_issue public.produccion_ordenes_eventos%rowtype;
  v_previous public.produccion_ordenes_eventos%rowtype;
  v_open numeric; v_expiry date; v_operation uuid; v_event uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_ordenes','editar')
    or not private.has_permission(p_company,'stock','crear') then
    raise exception 'Necesitás permiso para devolver insumos al stock' using errcode='42501'; end if;
  if p_request_id is null or p_quantity is null or p_quantity<=0
    or p_quantity>=1000000000000 or p_quantity<>round(p_quantity,6)
    or length(btrim(coalesce(p_note,''))) not between 3 and 300 then
    raise exception 'Revisá cantidad y motivo de devolución'; end if;
  select * into v_job from public.produccion_ordenes
    where empresa_id=p_company and id=p_job for update;
  if not found then raise exception 'Orden inexistente'; end if;
  select * into v_previous from public.produccion_ordenes_eventos
    where empresa_id=p_company and solicitud_id=p_request_id;
  if found then
    if v_previous.autor_id<>auth.uid() or v_previous.tipo<>'devolucion'
      or v_previous.orden_id<>p_job or v_previous.entrega_id<>p_issue
      or v_previous.cantidad<>p_quantity or v_previous.nota<>btrim(p_note) then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_previous.id;
  end if;
  if v_job.estado<>'en_proceso' then raise exception 'La orden ya no admite devoluciones'; end if;
  select * into v_issue from public.produccion_ordenes_eventos
    where empresa_id=p_company and orden_id=p_job and id=p_issue and tipo='entrega';
  if not found then raise exception 'Elegí una salida de insumo de esta orden'; end if;
  select v_issue.cantidad-coalesce(sum(e.cantidad),0) into v_open
    from public.produccion_ordenes_eventos e
    where e.empresa_id=p_company and e.entrega_id=p_issue and e.tipo='devolucion';
  if p_quantity>v_open then raise exception 'La devolución supera el saldo de esa salida'; end if;
  if v_issue.lote_codigo is not null then
    select l.vencimiento into v_expiry from public.stock_lotes l
      where l.empresa_id=p_company and l.item_id=v_issue.componente_id
        and lower(l.codigo)=lower(v_issue.lote_codigo);
    if not found then raise exception 'No se encuentra el lote de origen'; end if;
  end if;
  v_operation:=public.post_stock_operation(p_company,v_issue.componente_id,
    v_issue.deposito_id,null,'ingreso',p_quantity,
    'Devolución orden '||p_job::text,gen_random_uuid(),v_issue.lote_codigo,v_expiry);
  insert into public.produccion_ordenes_eventos(empresa_id,orden_id,solicitud_id,tipo,
    entrega_id,componente_id,deposito_id,lote_codigo,cantidad,costo_unitario,
    operacion_stock_id,nota,autor_id)
  values(p_company,p_job,p_request_id,'devolucion',p_issue,v_issue.componente_id,
    v_issue.deposito_id,v_issue.lote_codigo,p_quantity,v_issue.costo_unitario,
    v_operation,btrim(p_note),auth.uid()) returning id into v_event;
  return v_event;
end;
$function$;

CREATE OR REPLACE FUNCTION public.reverse_sale_payment(p_company uuid, p_payment uuid, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_payment public.ventas_cobros%rowtype;
  v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'finanzas','editar') then
    raise exception 'Sin permiso para anular cobros' using errcode='42501';
  end if;
  if p_payment is null or p_reason is null or length(btrim(p_reason)) not between 5 and 300 then
    raise exception 'Indicá un motivo de anulación de al menos cinco caracteres';
  end if;
  select * into v_payment from public.ventas_cobros
    where empresa_id=p_company and id=p_payment;
  if not found then raise exception 'Cobro inexistente'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('receivable:'||p_company::text||':'||v_payment.venta_id::text,0));
  if exists(select 1 from public.ventas_cobros_reversiones
    where empresa_id=p_company and cobro_id=p_payment) then
    raise exception 'Este cobro ya fue anulado';
  end if;
  insert into public.ventas_cobros_reversiones(empresa_id,venta_id,cobro_id,motivo,autor_id)
  values(p_company,v_payment.venta_id,p_payment,btrim(p_reason),auth.uid())
  returning id into v_id;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sale_credit_balance(p_company uuid, p_sale uuid)
 RETURNS TABLE(net_total numeric, paid numeric, refunded numeric, credit_due numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'finanzas','ver')
    or not private.has_permission(p_company,'ventas','ver') then
    raise exception 'Sin permiso para consultar saldos' using errcode='42501'; end if;
  return query select greatest(0,s.total-coalesce((select sum(a.credito_total)
      from public.ventas_ajustes a where a.empresa_id=p_company and a.venta_id=p_sale),0)),
    coalesce((select sum(p.importe) from public.ventas_cobros p
      where p.empresa_id=p_company and p.venta_id=p_sale and not exists(
        select 1 from public.ventas_cobros_reversiones r
        where r.empresa_id=p.empresa_id and r.cobro_id=p.id)),0),
    coalesce((select sum(f.importe) from public.ventas_reintegros f
      where f.empresa_id=p_company and f.venta_id=p_sale),0),
    greatest(0,
      coalesce((select sum(p.importe) from public.ventas_cobros p
        where p.empresa_id=p_company and p.venta_id=p_sale and not exists(
          select 1 from public.ventas_cobros_reversiones r
          where r.empresa_id=p.empresa_id and r.cobro_id=p.id)),0)
      - greatest(0,s.total-coalesce((select sum(a.credito_total)
        from public.ventas_ajustes a where a.empresa_id=p_company and a.venta_id=p_sale),0))
      - coalesce((select sum(f.importe) from public.ventas_reintegros f
        where f.empresa_id=p_company and f.venta_id=p_sale),0))
  from public.ventas s where s.empresa_id=p_company and s.id=p_sale;
end;
$function$;

CREATE OR REPLACE FUNCTION public.sale_receivables(p_company uuid, p_page integer DEFAULT 0, p_search text DEFAULT ''::text)
 RETURNS TABLE(sale_id uuid, sale_number bigint, customer_name text, total numeric, paid numeric, outstanding numeric, created_at timestamp with time zone, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'finanzas','ver')
    or not private.has_permission(p_company,'ventas','ver') then
    raise exception 'Necesitás permisos de Finanzas y Ventas' using errcode='42501'; end if;
  if p_page is null or p_page<0 or p_page>100000
    or length(coalesce(p_search,''))>100 then
    raise exception 'Página o búsqueda inválida'; end if;
  return query with amounts as (
    select p.venta_id,sum(p.importe) paid_amount from public.ventas_cobros p
    where p.empresa_id=p_company and not exists(
      select 1 from public.ventas_cobros_reversiones r
      where r.empresa_id=p.empresa_id and r.cobro_id=p.id)
    group by p.venta_id
  ), credits as (
    select a.venta_id,sum(a.credito_total) credit_amount
    from public.ventas_ajustes a where a.empresa_id=p_company group by a.venta_id
  ), filtered as (
    select s.id,s.numero,s.cliente_nombre,
      greatest(0,s.total-coalesce(c.credit_amount,0)) net,
      coalesce(a.paid_amount,0) paid_amount,s.creado_en
    from public.ventas s
    left join amounts a on a.venta_id=s.id
    left join credits c on c.venta_id=s.id
    where s.empresa_id=p_company and (btrim(coalesce(p_search,''))=''
      or s.cliente_nombre ilike '%'||btrim(p_search)||'%'
      or s.numero::text ilike '%'||btrim(p_search)||'%')
  )
  select f.id,f.numero,f.cliente_nombre,f.net,f.paid_amount,
    greatest(0,f.net-f.paid_amount),f.creado_en,count(*) over()
  from filtered f order by f.creado_en desc,f.id desc
  limit 25 offset p_page*25;
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_company_profile(p_company uuid, p_legal_name text, p_tax_id text, p_tax_condition text, p_address text, p_phone text, p_email text, p_website text, p_logo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_head bytea;
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'administrador'
     or not private.has_permission(p_company, 'ventas', 'editar') then
    raise exception 'Solo un administrador puede editar los datos de la empresa' using errcode = '42501';
  end if;
  if length(coalesce(p_legal_name, '')) > 160 or length(coalesce(p_tax_id, '')) > 30
     or length(coalesce(p_tax_condition, '')) > 60 or length(coalesce(p_address, '')) > 240
     or length(coalesce(p_phone, '')) > 40 or length(coalesce(p_email, '')) > 160
     or length(coalesce(p_website, '')) > 160 then
    raise exception 'Algún dato de la empresa es demasiado largo';
  end if;
  -- p_logo nulo = conservar el logo actual; '' = quitarlo.
  if coalesce(p_logo, '') <> '' then
    if p_logo !~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$' or length(p_logo) > 3000000 then
      raise exception 'El logo debe ser una imagen PNG, JPG o WebP de hasta 2 MB';
    end if;
    v_head := decode(substr(split_part(p_logo, ',', 2), 1, 16), 'base64');
    if not ((p_logo like 'data:image/png;%' and substring(v_head from 1 for 4) = '\x89504e47'::bytea)
         or (p_logo like 'data:image/jpeg;%' and substring(v_head from 1 for 3) = '\xffd8ff'::bytea)
         or (p_logo like 'data:image/webp;%' and substring(v_head from 1 for 4) = 'RIFF'::bytea
             and substring(v_head from 9 for 4) = 'WEBP'::bytea)) then
      raise exception 'El archivo del logo no es una imagen válida';
    end if;
  end if;
  insert into public.empresas_perfil(empresa_id, razon_social, identificacion_fiscal, condicion_fiscal, direccion, telefono, email,
    sitio_web, logo, actualizado_por)
  values (p_company, btrim(coalesce(p_legal_name, '')), btrim(coalesce(p_tax_id, '')),
    btrim(coalesce(p_tax_condition, '')), btrim(coalesce(p_address, '')), btrim(coalesce(p_phone, '')),
    btrim(coalesce(p_email, '')), btrim(coalesce(p_website, '')), coalesce(p_logo, ''), auth.uid())
  on conflict (empresa_id) do update set razon_social = excluded.razon_social, identificacion_fiscal = excluded.identificacion_fiscal,
    condicion_fiscal = excluded.condicion_fiscal, direccion = excluded.direccion, telefono = excluded.telefono,
    email = excluded.email, sitio_web = excluded.sitio_web,
    logo = case when p_logo is null then public.empresas_perfil.logo else excluded.logo end,
    actualizado_en = clock_timestamp(), actualizado_por = auth.uid();
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_item_sale_settings(p_company uuid, p_item uuid, p_tax numeric, p_content numeric, p_content_unit uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.price_require_admin(p_company);
  if not exists (select 1 from public.stock_items where empresa_id = p_company and id = p_item
                 and tipo_item = 'producto_terminado') then
    raise exception 'Producto terminado inexistente';
  end if;
  if p_tax is not null and p_tax not between 0 and 100 then raise exception 'IVA inválido'; end if;
  if (p_content is null) <> (p_content_unit is null) or (p_content is not null and p_content <= 0) then
    raise exception 'Indicá contenido y unidad juntos (contenido mayor a 0)';
  end if;
  insert into public.ventas_items_config(empresa_id, item_id, impuesto_porcentaje, contenido_cantidad, contenido_unidad_id, actualizado_por)
  values (p_company, p_item, p_tax, p_content, p_content_unit, auth.uid())
  on conflict (empresa_id, item_id) do update set impuesto_porcentaje = excluded.impuesto_porcentaje,
    contenido_cantidad = excluded.contenido_cantidad, contenido_unidad_id = excluded.contenido_unidad_id,
    actualizado_en = clock_timestamp(), actualizado_por = auth.uid();
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_item_with_cost(p_company uuid, p_item uuid, p_row jsonb, p_expected_updated_at timestamp with time zone, p_preserve_cost boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row jsonb:=p_row; v_preserve boolean:=p_preserve_cost;
begin
  if auth.uid() is null then raise exception 'Iniciá sesión' using errcode='42501'; end if;
  if jsonb_typeof(p_row) is distinct from 'object' then raise exception 'Datos del ítem inválidos'; end if;
  if not private.can_see_reference_cost(p_company) then
    if p_item is null then
      if private.row_has_cost(p_row) then
        raise exception 'Solo Administración o Compras pueden definir costos' using errcode='42501'; end if;
    else
      -- Quien no gestiona costos puede editar la ficha, pero el costo vigente se conserva.
      v_preserve:=true;
      v_row:=p_row-'costo_referencia_ars'-'costo_usd'-'tipo_dolar'-'supplier_id'-'exchange_type_id'-'proveedor';
    end if;
  end if;
  return private.save_item_with_cost(p_company,p_item,v_row,p_expected_updated_at,v_preserve);
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_price_list(p_company uuid, p_id uuid, p_name text, p_currency text, p_valid_from date, p_valid_to date, p_is_default boolean, p_base_list uuid, p_base_discount numeric, p_rounding_step numeric, p_note text, p_archived boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid; v_old public.ventas_listas_precios%rowtype;
begin
  perform private.price_require_admin(p_company);
  perform pg_advisory_xact_lock(hashtextextended('price_lists:' || p_company::text, 0));
  if coalesce(btrim(p_name), '') = '' or length(btrim(p_name)) > 80 then
    raise exception 'Indicá un nombre de hasta 80 caracteres';
  end if;
  if p_currency is null or p_currency not in ('ARS', 'USD') then raise exception 'Moneda inválida'; end if;
  if p_valid_from is not null and p_valid_to is not null and p_valid_to < p_valid_from then
    raise exception 'La vigencia hasta no puede ser anterior a la vigencia desde';
  end if;
  if p_base_list is not null and not exists (
    select 1 from public.ventas_listas_precios where empresa_id = p_company and id = p_base_list and not archivado) then
    raise exception 'Lista base inexistente o archivada';
  end if;
  if p_base_list is null and coalesce(p_base_discount, 0) <> 0 then
    raise exception 'El descuento sobre base requiere una lista base';
  end if;
  if coalesce(p_archived, false) and coalesce(p_is_default, false) then
    raise exception 'Una lista archivada no puede ser la predeterminada';
  end if;
  if coalesce(p_rounding_step, 0) < 0 then raise exception 'Redondeo inválido'; end if;

  if p_id is null then
    insert into public.ventas_listas_precios(empresa_id, nombre, moneda, lista_base_id, descuento_base_porcentaje,
      redondeo, vigente_desde, vigente_hasta, es_predeterminada, nota, creado_por)
    values (p_company, btrim(p_name), p_currency, p_base_list, coalesce(p_base_discount, 0),
      coalesce(p_rounding_step, 0), p_valid_from, p_valid_to, false, coalesce(left(p_note, 300), ''), auth.uid())
    returning id into v_id;
  else
    select * into v_old from public.ventas_listas_precios where empresa_id = p_company and id = p_id for update;
    if not found then raise exception 'Lista inexistente'; end if;
    v_id := p_id;
    if p_archived and exists (
      select 1 from public.ventas_listas_precios d where d.empresa_id = p_company and d.lista_base_id = p_id and not d.archivado) then
      raise exception 'Archivá primero las listas derivadas de esta lista';
    end if;
    update public.ventas_listas_precios set nombre = btrim(p_name), moneda = p_currency, lista_base_id = p_base_list,
      descuento_base_porcentaje = coalesce(p_base_discount, 0), redondeo = coalesce(p_rounding_step, 0),
      vigente_desde = p_valid_from, vigente_hasta = p_valid_to, nota = coalesce(left(p_note, 300), ''),
      archivado = coalesce(p_archived, false), es_predeterminada = case when coalesce(p_archived, false) then false else es_predeterminada end
    where empresa_id = p_company and id = p_id;
  end if;
  if coalesce(p_is_default, false) then
    update public.ventas_listas_precios set es_predeterminada = false where empresa_id = p_company and es_predeterminada and id <> v_id;
    update public.ventas_listas_precios set es_predeterminada = true where empresa_id = p_company and id = v_id and not archivado;
  end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_price_settings(p_company uuid, p_default_tax numeric, p_min_margin numeric, p_commission numeric, p_structure numeric, p_max_discount numeric DEFAULT NULL::numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.price_require_admin(p_company, true);
  if p_default_tax is null or p_default_tax not between 0 and 100
     or p_min_margin is null or p_min_margin < 0 or p_min_margin >= 100
     or p_commission is null or p_commission not between 0 and 100
     or p_structure is null or p_structure not between 0 and 100
     or (p_max_discount is not null and (p_max_discount < 0 or p_max_discount >= 100)) then
    raise exception 'Revisá los porcentajes (IVA 0–100, margen mínimo y descuento máximo menores a 100)';
  end if;
  insert into public.ventas_precios_config(empresa_id, impuesto_porcentaje_predeterminado, margen_minimo_porcentaje,
    comision_porcentaje, estructura_porcentaje, descuento_maximo_porcentaje, actualizado_por)
  values (p_company, p_default_tax, p_min_margin, p_commission, p_structure, coalesce(p_max_discount, 0), auth.uid())
  on conflict (empresa_id) do update set impuesto_porcentaje_predeterminado = excluded.impuesto_porcentaje_predeterminado,
    margen_minimo_porcentaje = excluded.margen_minimo_porcentaje, comision_porcentaje = excluded.comision_porcentaje,
    estructura_porcentaje = excluded.estructura_porcentaje,
    descuento_maximo_porcentaje = coalesce(p_max_discount, public.ventas_precios_config.descuento_maximo_porcentaje),
    actualizado_en = clock_timestamp(), actualizado_por = auth.uid();
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_production_document_settings(p_company uuid, p_logo text, p_code text, p_revision text, p_labels jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_label jsonb;
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'administrador' then
    raise exception 'Solo el administrador configura el formato' using errcode='42501'; end if;
  perform 1 from public.empresas where id=p_company and activo for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  if p_logo is null or length(p_logo)>120000 or length(btrim(coalesce(p_code,''))) not between 1 and 40
    or length(btrim(coalesce(p_revision,''))) not between 1 and 20
    or p_labels is null or jsonb_typeof(p_labels)<>'array' or jsonb_array_length(p_labels)>12 then
    raise exception 'Revisá logo, código, revisión y hasta doce campos'; end if;
  if p_logo<>'' and p_logo !~ '^data:image/png;base64,[A-Za-z0-9+/]+={0,2}$' then
    raise exception 'El logo debe ser PNG'; end if;
  if p_logo<>'' and encode(substring(decode(split_part(p_logo,',',2),'base64') from 1 for 8),'hex')<>'89504e470d0a1a0a' then
    raise exception 'El archivo no es un logo PNG válido'; end if;
  for v_label in select value from jsonb_array_elements(p_labels) loop
    if jsonb_typeof(v_label)<>'string' or length(btrim(v_label#>>'{}')) not between 2 and 80 then
      raise exception 'Cada título debe tener entre 2 y 80 caracteres'; end if;
  end loop;
  if (select count(distinct lower(btrim(value))) from jsonb_array_elements_text(p_labels))<>jsonb_array_length(p_labels) then
    raise exception 'No repitas títulos de observaciones'; end if;
  insert into public.produccion_documentos_config(empresa_id,logo,documento_codigo,revision,observaciones_etiquetas)
    values(p_company,p_logo,btrim(p_code),btrim(p_revision),p_labels)
  on conflict(empresa_id) do update set logo=excluded.logo,documento_codigo=excluded.documento_codigo,
    revision=excluded.revision,observaciones_etiquetas=excluded.observaciones_etiquetas,actualizado_en=clock_timestamp();
end; $function$;

CREATE OR REPLACE FUNCTION public.save_production_formula(p_company uuid, p_product uuid, p_batch_quantity numeric, p_lines jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_line jsonb;
  v_component uuid;
  v_quantity numeric;
  v_version integer;
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_formulas','editar') then
    raise exception 'Sin permiso para editar fórmulas' using errcode='42501';
  end if;
  if p_batch_quantity is null or p_batch_quantity <= 0 or p_batch_quantity >= 1000000000000
    or p_batch_quantity <> round(p_batch_quantity,6)
    or p_lines is null or jsonb_typeof(p_lines) <> 'array'
    or jsonb_array_length(p_lines) not between 1 and 500 then
    raise exception 'Indicá rendimiento y componentes válidos';
  end if;
  -- Una sola edición de fórmulas por empresa evita ciclos por escrituras simultáneas.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('formula:'||p_company::text,0));
  perform 1 from public.stock_items i where i.empresa_id=p_company and i.id=p_product
    and i.activo and i.tipo_item in ('producto_terminado','semielaborado') for share;
  if not found then raise exception 'Elegí un producto terminado o semielaborado activo'; end if;
  insert into public.produccion_formulas(empresa_id,producto_id,cantidad_base)
  values(p_company,p_product,p_batch_quantity)
  on conflict(empresa_id,producto_id) do update set
    cantidad_base=excluded.cantidad_base,version=produccion_formulas.version+1,actualizado_en=now()
  returning version into v_version;
  delete from public.produccion_formulas_lineas where empresa_id=p_company and producto_id=p_product;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_component := (v_line->>'component_id')::uuid;
    v_quantity := (v_line->>'quantity')::numeric;
    if v_quantity is null or v_quantity <= 0 or v_quantity >= 1000000000000
      or v_quantity <> round(v_quantity,6) then raise exception 'Cantidad de componente inválida'; end if;
    perform 1 from public.stock_items i where i.empresa_id=p_company and i.id=v_component
      and i.activo and i.tipo_item in ('materia_prima','semielaborado','insumo') for share;
    if not found then raise exception 'Elegí materias primas, semielaborados o insumos activos'; end if;
    insert into public.produccion_formulas_lineas(empresa_id,producto_id,componente_id,cantidad)
    values(p_company,p_product,v_component,v_quantity);
  end loop;
  -- Calcula recursivamente y revierte la transacción si aparece un ciclo o falta un costo.
  perform private.production_unit_cost(p_company,p_product);
  return v_version;
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_production_formula_v2(p_company uuid, p_product uuid, p_batch_quantity numeric, p_lines jsonb, p_yield_enabled boolean, p_yield_factor numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_formulas','editar') then
    raise exception 'Sin permiso para editar fórmulas' using errcode='42501'; end if;
  if p_yield_enabled is null or p_yield_factor is null or p_yield_factor<=0 or p_yield_factor>1000
    or p_yield_factor<>round(p_yield_factor,6) then raise exception 'Factor de rendimiento inválido'; end if;
  perform public.save_production_formula(p_company,p_product,p_batch_quantity,p_lines);
  update public.stock_items set usa_rendimiento=p_yield_enabled,
    factor_rendimiento=case when p_yield_enabled then p_yield_factor else 1 end
    where empresa_id=p_company and id=p_product;
end; $function$;

CREATE OR REPLACE FUNCTION public.save_production_packaging_type(p_company uuid, p_id uuid, p_name text, p_capacity numeric, p_unit uuid, p_active boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_envasado','editar') then
    raise exception 'Sin permiso para gestionar envasados' using errcode='42501'; end if;
  perform 1 from public.empresas where id=p_company and activo for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  if length(btrim(coalesce(p_name,''))) not between 2 and 100 or p_capacity is null or p_capacity<=0
    or p_capacity>=1000000000000 or p_capacity<>round(p_capacity,6) or p_active is null then
    raise exception 'Nombre y capacidad inválidos'; end if;
  perform 1 from public.stock_unidades where empresa_id=p_company and id=p_unit and activo;
  if not found then raise exception 'Elegí una unidad activa'; end if;
  if p_id is null then
    insert into public.produccion_tipos_envase(empresa_id,nombre,capacidad,unidad_id,activo)
      values(p_company,btrim(p_name),p_capacity,p_unit,p_active) returning id into v_id;
  else
    update public.produccion_tipos_envase set nombre=btrim(p_name),capacidad=p_capacity,unidad_id=p_unit,activo=p_active
      where empresa_id=p_company and id=p_id returning id into v_id;
    if v_id is null then raise exception 'Envasado inexistente'; end if;
  end if;
  return v_id;
end; $function$;

CREATE OR REPLACE FUNCTION public.save_production_work_details(p_company uuid, p_job uuid, p_counts jsonb, p_observations jsonb, p_expected timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.produccion_ordenes%rowtype; v_pack jsonb; v_result jsonb:='[]'; v_count numeric;
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_ordenes','editar') then
    raise exception 'Sin permiso para actualizar la orden' using errcode='42501'; end if;
  perform 1 from public.empresas where id=p_company and activo for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  select * into v_job from public.produccion_ordenes where empresa_id=p_company and id=p_job for update;
  if not found or v_job.estado='cancelada' then raise exception 'Orden inexistente o cancelada'; end if;
  if p_expected is null or v_job.detalles_actualizado_en<>p_expected then raise exception 'Los controles cambiaron. Reabrí el formulario'; end if;
  if jsonb_typeof(p_counts) is distinct from 'object' or jsonb_typeof(p_observations) is distinct from 'object'
    or length(p_observations::text)>10000 or length(p_counts::text)>5000 then raise exception 'Datos de controles inválidos'; end if;
  if exists(select 1 from jsonb_each(p_observations) e where jsonb_typeof(e.value)<>'string'
    or length(e.value#>>'{}')>500 or not (coalesce(v_job.documento_copia->'labels','[]') ? e.key)) then
    raise exception 'Usá los campos originales de la orden'; end if;
  if exists(select 1 from jsonb_each(p_counts) e where not exists(
    select 1 from jsonb_array_elements(coalesce(v_job.opciones_trabajo->'packaging','[]')) x where x->>'id'=e.key)) then
    raise exception 'Envasado no asociado a esta orden'; end if;
  for v_pack in select value from jsonb_array_elements(coalesce(v_job.opciones_trabajo->'packaging','[]')) loop
    v_count:=nullif(p_counts->>(v_pack->>'id'),'')::numeric;
    if v_count is not null and (v_count<0 or v_count>=1000000000 or v_count<>trunc(v_count)) then
      raise exception 'La cantidad real de envases debe ser entera y no negativa'; end if;
    v_result:=v_result||jsonb_build_array(v_pack||jsonb_build_object('actual_count',v_count));
  end loop;
  update public.produccion_ordenes set opciones_trabajo=jsonb_build_object('packaging',v_result,'observations',p_observations),
    detalles_actualizado_en=clock_timestamp() where empresa_id=p_company and id=p_job;
end; $function$;

CREATE OR REPLACE FUNCTION public.save_supplier_quote(p_company uuid, p_supplier uuid, p_item uuid, p_price numeric, p_sku text, p_currency text, p_exchange_type uuid, p_adjustment numeric, p_expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_create_only boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_existing public.compras_proveedores_items%rowtype;
begin
  if auth.uid() is null or not private.has_permission(p_company,'compras_proveedores','editar') then
    raise exception 'Sin permiso para modificar precios' using errcode='42501'; end if;
  if p_item is null or p_supplier is null or p_price is null or p_price<0
    or p_price>=10000000000000000 or p_price<>round(p_price,2)
    or length(coalesce(p_sku,''))>80 or p_currency is null or p_currency not in ('ARS','USD')
    or p_adjustment is null or p_adjustment not between -99.99 and 1000
    or p_adjustment<>round(p_adjustment,2)
    or (p_currency='USD' and p_exchange_type is null)
    or (p_currency='ARS' and p_exchange_type is not null) then
    raise exception 'Revisá precio, moneda y tipo de dólar'; end if;
  perform 1 from public.empresas c where c.id=p_company and c.activo for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('supplier-quote:'||p_company::text||':'||p_supplier::text||':'||p_item::text,0));
  select * into v_existing from public.compras_proveedores_items q where q.empresa_id=p_company
    and q.proveedor_id=p_supplier and q.item_id=p_item for update;
  if found then
    if p_create_only then raise exception 'Este ítem ya está asociado. Usá Editar precio en su ficha'; end if;
    if p_expected_updated_at is null or v_existing.actualizado_en<>p_expected_updated_at then
      raise exception 'El precio cambió mientras lo editabas. Cerrá la ventana y volvé a abrirlo'; end if;
    update public.compras_proveedores_items set precio_unitario=p_price,proveedor_codigo=btrim(coalesce(p_sku,'')),
      moneda=p_currency,tipo_cambio_id=p_exchange_type,ajuste_porcentaje=p_adjustment
      where empresa_id=p_company and proveedor_id=p_supplier and item_id=p_item;
  else
    if not p_create_only then raise exception 'La relación ya no existe. Agregá el ítem nuevamente'; end if;
    insert into public.compras_proveedores_items(empresa_id,proveedor_id,item_id,precio_unitario,proveedor_codigo,
      moneda,tipo_cambio_id,ajuste_porcentaje)
      values(p_company,p_supplier,p_item,p_price,btrim(coalesce(p_sku,'')),p_currency,p_exchange_type,p_adjustment);
  end if;
end; $function$;

CREATE OR REPLACE FUNCTION public.set_company_member(p_company uuid, p_user uuid, p_role uuid, p_active boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_old_code text;
  v_new_code text;
  v_old_active boolean;
  v_old_role uuid;
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'administrador' then
    raise exception 'Solo el administrador puede editar usuarios' using errcode = '42501';
  end if;
  if p_active is null then raise exception 'Estado inválido'; end if;
  select r.codigo into v_new_code from public.ajustes_roles r where r.id = p_role and r.empresa_id = p_company;
  if v_new_code is null then raise exception 'El rol no pertenece a esta empresa'; end if;
  perform 1 from public.empresas where id = p_company for update;
  select r.codigo, cu.activo, cu.rol_id into v_old_code, v_old_active, v_old_role
    from public.empresas_usuarios cu
    join public.ajustes_roles r on r.id = cu.rol_id and r.empresa_id = cu.empresa_id
    where cu.empresa_id = p_company and cu.usuario_id = p_user for update of cu;
  if v_old_code is null then raise exception 'El usuario no pertenece a esta empresa'; end if;
  if p_user = auth.uid() and not p_active then
    raise exception 'No podés suspender tu propia cuenta';
  end if;
  if v_old_code = 'administrador' and v_old_active and (v_new_code <> 'administrador' or not p_active)
    and (select count(*) from public.empresas_usuarios cu
      join public.ajustes_roles r on r.id = cu.rol_id and r.empresa_id = cu.empresa_id
      where cu.empresa_id = p_company and cu.activo and r.codigo = 'administrador') <= 1 then
    raise exception 'Debe permanecer al menos un administrador activo';
  end if;
  update public.empresas_usuarios set rol_id = p_role, activo = p_active
    where empresa_id = p_company and usuario_id = p_user;
  perform private.log_access_event(p_company, 'miembro_editado', p_user, p_role, jsonb_build_object(
    'before', jsonb_build_object('role_id', v_old_role, 'role', v_old_code, 'active', v_old_active),
    'after', jsonb_build_object('role_id', p_role, 'role', v_new_code, 'active', p_active)));
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_preferred_supplier(p_company uuid, p_item uuid, p_supplier uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_quote public.compras_proveedores_items%rowtype;
begin
  if auth.uid() is null or not private.has_permission(p_company,'compras_proveedores','editar') then
    raise exception 'Sin permiso para elegir proveedor principal' using errcode='42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('preferred:'||p_company::text||':'||p_item::text,0));
  select * into v_quote from public.compras_proveedores_items
    where empresa_id=p_company and item_id=p_item and proveedor_id=p_supplier;
  if not found then raise exception 'Cotización inexistente'; end if;
  perform 1 from public.compras_proveedores where empresa_id=p_company and id=p_supplier and activo;
  if not found then raise exception 'Elegí un proveedor activo'; end if;
  if v_quote.moneda='USD' and
    private.current_fx_rate(p_company,v_quote.tipo_cambio_id) is null then
    raise exception 'Cargá primero la cotización de ese dólar';
  end if;
  update public.compras_proveedores_items set preferido=false
    where empresa_id=p_company and item_id=p_item and preferido;
  update public.compras_proveedores_items set preferido=true
    where empresa_id=p_company and item_id=p_item and proveedor_id=p_supplier;
  perform private.sync_preferred_material_cost(p_company,p_item);
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_price_list_item(p_company uuid, p_list uuid, p_item uuid, p_method text, p_value numeric, p_reason text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_list public.ventas_listas_precios%rowtype; v_cost numeric; v_price numeric;
begin
  perform private.price_require_admin(p_company, p_method in ('margen', 'recargo'));
  select * into v_list from public.ventas_listas_precios
  where empresa_id = p_company and id = p_list for share;
  if not found or v_list.archivado then raise exception 'Lista inexistente o archivada'; end if;
  if not exists (select 1 from public.stock_items where empresa_id = p_company and id = p_item
                 and activo and tipo_item = 'producto_terminado') then
    raise exception 'Producto terminado inexistente o inactivo';
  end if;
  if p_method in ('margen', 'recargo') then v_cost := private.price_item_cost(p_company, p_item); end if;
  v_price := private.price_compute(p_method, p_value, v_cost, v_list.redondeo);
  perform private.price_write(p_company, p_list, p_item, v_price, p_method, p_value, v_cost, false, 'manual', p_reason);
  return v_price;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_quote_status(p_company uuid, p_quote uuid, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row public.ventas_presupuestos%rowtype;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'ventas', 'editar') then
    raise exception 'Sin permiso para cambiar presupuestos' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('abierto', 'aceptado', 'rechazado', 'cancelado') then
    raise exception 'Estado inválido';
  end if;
  select * into v_row from public.ventas_presupuestos where empresa_id = p_company and id = p_quote for update;
  if not found then raise exception 'Presupuesto inexistente'; end if;
  if v_row.estado = p_status then return; end if;
  if p_status = 'aceptado' and v_row.vigente_hasta < (now() at time zone 'America/Argentina/Buenos_Aires')::date
     and private.get_user_role(p_company) is distinct from 'administrador' then
    raise exception 'El presupuesto está vencido: solo un administrador puede aceptarlo';
  end if;
  if v_row.estado <> 'abierto' and (p_status <> 'abierto'
     or private.get_user_role(p_company) is distinct from 'administrador') then
    raise exception 'Ese presupuesto ya está resuelto; solo un administrador puede reabrirlo';
  end if;
  update public.ventas_presupuestos set estado = p_status, estado_cambiado_en = clock_timestamp(), estado_cambiado_por = auth.uid()
  where empresa_id = p_company and id = p_quote;
  insert into public.ventas_presupuestos_estados(empresa_id, presupuesto_id, estado_anterior, estado_nuevo, cambiado_por)
  values (p_company, p_quote, v_row.estado, p_status, auth.uid());
end;
$function$;

CREATE OR REPLACE FUNCTION public.start_production_job(p_company uuid, p_job uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_ordenes','editar') then
    raise exception 'Sin permiso para iniciar fabricación' using errcode='42501'; end if;
  update public.produccion_ordenes set estado='en_proceso',iniciado_en=clock_timestamp()
    where empresa_id=p_company and id=p_job and estado='pendiente';
  if not found and not exists(select 1 from public.produccion_ordenes
    where empresa_id=p_company and id=p_job and estado='en_proceso') then
    raise exception 'La orden no está pendiente'; end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.stock_item_options(p_company uuid, p_search text DEFAULT ''::text)
 RETURNS TABLE(id uuid, code text, name text, unit_symbol text, barcode text, track_lots boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not (private.has_permission(p_company,'stock_saldos','ver') or private.has_permission(p_company,'stock_remitos','ver') or private.has_permission(p_company,'stock_movimientos','ver') or private.has_permission(p_company,'inventario','ver')) then
    raise exception 'Sin permiso para ver ítems de stock' using errcode = '42501';
  end if;
  if length(coalesce(p_search, '')) > 100 then
    raise exception 'Búsqueda demasiado larga';
  end if;
  return query
    select i.id, i.codigo, i.nombre, u.simbolo, i.codigo_barras, i.usa_lotes
    from public.stock_items i
    join public.stock_unidades u on u.id = i.unidad_id and u.empresa_id = i.empresa_id
    where i.empresa_id = p_company and i.activo
      and (coalesce(p_search, '') = ''
        or i.nombre ilike '%' || p_search || '%'
        or i.codigo ilike '%' || p_search || '%'
        or i.codigo_barras ilike '%' || p_search || '%')
    order by i.nombre, i.id
    limit 30;
end;
$function$;

CREATE OR REPLACE FUNCTION public.stock_lot_breakdown(p_company uuid, p_item uuid)
 RETURNS TABLE(warehouse_id uuid, warehouse_name text, lot_code text, expires_on date, quantity numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not (private.has_permission(p_company,'stock_saldos','ver') or private.has_permission(p_company,'stock_remitos','ver') or private.has_permission(p_company,'inventario','ver')) then
    raise exception 'Sin permiso para consultar lotes' using errcode = '42501';
  end if;
  return query
    select b.deposito_id, w.nombre, l.codigo, l.vencimiento, b.cantidad
    from public.stock_lotes_saldos b
    join public.stock_lotes l on l.id = b.lote_id
      and l.empresa_id = b.empresa_id and l.item_id = b.item_id
    join public.stock_depositos w on w.id = b.deposito_id
      and w.empresa_id = b.empresa_id
    where b.empresa_id = p_company and b.item_id = p_item and b.cantidad > 0
    order by w.nombre, l.vencimiento nulls last, l.codigo
    limit 500;
end;
$function$;

CREATE OR REPLACE FUNCTION public.stock_lot_options(p_company uuid, p_item uuid, p_warehouse uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, code text, expires_on date, available numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not (private.has_permission(p_company,'stock_saldos','ver') or private.has_permission(p_company,'stock_remitos','ver') or private.has_permission(p_company,'inventario','ver')) then
    raise exception 'Sin permiso para consultar lotes' using errcode = '42501';
  end if;
  return query
    select l.id, l.codigo, l.vencimiento,
      coalesce(sum(b.cantidad), 0)::numeric
    from public.stock_lotes l
    left join public.stock_lotes_saldos b
      on b.empresa_id = l.empresa_id and b.item_id = l.item_id
      and b.lote_id = l.id
      and (p_warehouse is null or b.deposito_id = p_warehouse)
    where l.empresa_id = p_company and l.item_id = p_item
    group by l.id
    order by l.vencimiento nulls last, l.codigo
    limit 200;
end;
$function$;

CREATE OR REPLACE FUNCTION public.stock_summary(p_company uuid, p_page integer DEFAULT 0, p_search text DEFAULT ''::text)
 RETURNS TABLE(item_id uuid, item_code text, item_name text, unit_symbol text, track_lots boolean, minimum_stock numeric, total_quantity numeric, warehouse_count bigint, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not (private.has_permission(p_company,'stock_saldos','ver') or private.has_permission(p_company,'inventario','ver')) then
    raise exception 'Sin permiso para consultar stock' using errcode = '42501';
  end if;
  if p_page is null or p_page < 0 or p_page > 100000
     or length(coalesce(p_search, '')) > 100 then
    raise exception 'Búsqueda inválida';
  end if;
  return query
    select i.id, i.codigo, i.nombre, u.simbolo, i.usa_lotes, i.stock_minimo,
           coalesce(sum(b.cantidad), 0)::numeric,
           count(b.deposito_id) filter (where b.cantidad > 0),
           count(*) over ()
    from public.stock_items i
    join public.stock_unidades u on u.id = i.unidad_id and u.empresa_id = i.empresa_id
    left join public.stock_saldos b
      on b.empresa_id = i.empresa_id and b.item_id = i.id
    where i.empresa_id = p_company and i.activo
      and (coalesce(p_search, '') = ''
        or i.nombre ilike '%' || p_search || '%'
        or i.codigo ilike '%' || p_search || '%')
    group by i.id, u.simbolo
    order by i.nombre, i.id
    limit 25 offset p_page * 25;
end;
$function$;

CREATE OR REPLACE FUNCTION public.stock_warehouse_options(p_company uuid, p_search text DEFAULT ''::text)
 RETURNS TABLE(id uuid, code text, name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not (private.has_permission(p_company,'stock_saldos','ver') or private.has_permission(p_company,'stock_remitos','ver') or private.has_permission(p_company,'stock_movimientos','ver') or private.has_permission(p_company,'inventario','ver')) then
    raise exception 'Sin permiso para ver depósitos' using errcode = '42501';
  end if;
  if length(coalesce(p_search, '')) > 100 then
    raise exception 'Búsqueda demasiado larga';
  end if;
  return query
    select w.id, w.codigo, w.nombre
    from public.stock_depositos w
    where w.empresa_id = p_company and w.activo
      and (coalesce(p_search, '') = ''
        or w.nombre ilike '%' || p_search || '%'
        or w.codigo ilike '%' || p_search || '%')
    order by w.nombre, w.id
    limit 30;
end;
$function$;

CREATE OR REPLACE FUNCTION public.supplier_account(p_company uuid, p_supplier uuid, p_from date, p_to date, p_page integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'compras_cuentas','ver')
    or not private.has_permission(p_company,'finanzas','ver') then
    raise exception 'Necesitás leer Compras y Finanzas' using errcode='42501'; end if;
  if p_from is null or p_to is null or p_from>p_to or p_page is null or p_page<0 or p_page>100000 then
    raise exception 'Rango o página inválidos'; end if;
  return (with ledger as (
    select r.id as id,r.creado_en as created_at,(r.creado_en at time zone 'America/Argentina/Buenos_Aires')::date as ledger_date,
      'Recepción · OC '||o.numero::text title,round(sum(l.cantidad*l.precio_unitario),2) debit,0::numeric credit
    from public.compras_recepciones r join public.compras_recepciones_lineas l on l.empresa_id=r.empresa_id and l.recepcion_id=r.id
    join public.compras_ordenes o on o.empresa_id=r.empresa_id and o.id=r.orden_compra_id
    where r.empresa_id=p_company and o.proveedor_id=p_supplier group by r.id,o.numero
    union all
    select t.id,t.creado_en,t.fecha,'Pago · OC '||o.numero::text||' · '||t.nota,0,t.importe
    from public.finanzas_movimientos t join public.compras_ordenes o on o.empresa_id=t.empresa_id and o.id=t.orden_compra_id
    where t.empresa_id=p_company and o.proveedor_id=p_supplier and t.tipo='pago_proveedor'
  ), running as (
    select *,sum(debit-credit) over(order by ledger_date,created_at,id rows unbounded preceding) balance from ledger
  ) select jsonb_build_object(
    'opening',coalesce((select sum(debit-credit) from ledger where ledger_date<p_from),0),
    'debit',coalesce((select sum(debit) from ledger where ledger_date between p_from and p_to),0),
    'credit',coalesce((select sum(credit) from ledger where ledger_date between p_from and p_to),0),
    'balance',coalesce((select sum(debit-credit) from ledger where ledger_date<=p_to),0),
    'total_count',(select count(*) from ledger where ledger_date between p_from and p_to),
    'rows',coalesce((select jsonb_agg(x order by x.ledger_date,x.created_at,x.id) from (
      select * from running where ledger_date between p_from and p_to order by ledger_date,created_at,id
        limit 25 offset p_page*25) x),'[]'::jsonb)));
end; $function$;

CREATE OR REPLACE FUNCTION public.supplier_adjustment_preview(p_company uuid, p_supplier uuid, p_item uuid, p_percent numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not (private.has_permission(p_company,'compras_proveedores','editar') and private.has_permission(p_company,'costos_materiales','ver')) then
    raise exception 'Sin permiso para ajustar precios' using errcode='42501'; end if;
  if p_supplier is null or p_percent is null or p_percent not between -99.99 and 1000
    or p_percent=0 or p_percent<>round(p_percent,2) then
    raise exception 'Elegí proveedor y porcentaje válido'; end if;
  return jsonb_build_object('count',(select count(*) from public.compras_proveedores_items q
    join public.stock_items i on i.empresa_id=q.empresa_id and i.id=q.item_id and i.activo
    join public.compras_proveedores s on s.empresa_id=q.empresa_id and s.id=q.proveedor_id and s.activo
    where q.empresa_id=p_company and q.proveedor_id=p_supplier and (p_item is null or q.item_id=p_item)),
    'examples',coalesce((select jsonb_agg(x) from (
      select i.nombre as name,q.precio_unitario as unit_price,q.moneda as currency_code,
        round(q.precio_unitario*(1+p_percent/100),2) next_price
      from public.compras_proveedores_items q
      join public.stock_items i on i.empresa_id=q.empresa_id and i.id=q.item_id and i.activo
      join public.compras_proveedores s on s.empresa_id=q.empresa_id and s.id=q.proveedor_id and s.activo
      where q.empresa_id=p_company and q.proveedor_id=p_supplier and (p_item is null or q.item_id=p_item)
      order by i.nombre limit 5) x),'[]'::jsonb));
end; $function$;

CREATE OR REPLACE FUNCTION public.supplier_cost_comparison(p_company uuid, p_supplier uuid DEFAULT NULL::uuid, p_item uuid DEFAULT NULL::uuid)
 RETURNS TABLE(supplier_id uuid, supplier_name text, supplier_active boolean, item_id uuid, item_code text, item_name text, unit_symbol text, unit_price numeric, currency_code text, exchange_rate_type_id uuid, exchange_rate_type text, exchange_rate numeric, adjustment_percent numeric, unit_cost_ars numeric, preferred boolean, supplier_sku text, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not ((private.has_permission(p_company,'compras_ordenes','ver') or private.has_permission(p_company,'compras_proveedores','ver')) and private.has_permission(p_company,'costos_materiales','ver')) then
    raise exception 'Sin permiso para comparar costos' using errcode='42501'; end if;
  return query select si.proveedor_id,s.nombre,s.activo,si.item_id,i.codigo,i.nombre,u.simbolo,
    si.precio_unitario,si.moneda,si.tipo_cambio_id,fx.nombre,
    case when si.moneda='USD' then private.current_fx_rate(p_company,si.tipo_cambio_id)
      else 1::numeric end,
    si.ajuste_porcentaje,
    case when si.moneda='USD' then
      round(si.precio_unitario*private.current_fx_rate(p_company,si.tipo_cambio_id)
        *(1+si.ajuste_porcentaje/100),2)
    else round(si.precio_unitario*(1+si.ajuste_porcentaje/100),2) end,
    si.preferido,si.proveedor_codigo,si.actualizado_en
  from public.compras_proveedores_items si
  join public.compras_proveedores s on s.empresa_id=si.empresa_id and s.id=si.proveedor_id
  join public.stock_items i on i.empresa_id=si.empresa_id and i.id=si.item_id
  join public.stock_unidades u on u.empresa_id=i.empresa_id and u.id=i.unidad_id
  left join public.finanzas_tipos_cambio fx on fx.empresa_id=si.empresa_id
    and fx.id=si.tipo_cambio_id
  where si.empresa_id=p_company and (p_supplier is null or si.proveedor_id=p_supplier)
    and (p_item is null or si.item_id=p_item)
  order by i.nombre,si.preferido desc,si.precio_unitario,s.nombre limit 500;
end;
$function$;

CREATE OR REPLACE FUNCTION public.supplier_directory(p_company uuid, p_search text DEFAULT ''::text, p_page integer DEFAULT 0)
 RETURNS TABLE(id uuid, name text, tax_id text, email text, phone text, notes text, active boolean, lead_time_days integer, supplies_description text, item_count bigint, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'compras_proveedores','ver') then
    raise exception 'Sin acceso a proveedores' using errcode='42501'; end if;
  if p_page is null or p_page<0 or p_page>100000 or length(coalesce(p_search,''))>100 then
    raise exception 'Búsqueda inválida'; end if;
  return query select s.id,s.nombre,s.identificacion_fiscal,s.email,s.telefono,s.nota,s.activo,
    s.demora_dias::integer,s.provee_descripcion,
    (select count(*) from public.compras_proveedores_items q where q.empresa_id=s.empresa_id and q.proveedor_id=s.id),
    count(*) over()
    from public.compras_proveedores s where s.empresa_id=p_company
      and (coalesce(p_search,'')='' or s.nombre ilike '%'||p_search||'%'
        or s.provee_descripcion ilike '%'||p_search||'%' or s.identificacion_fiscal ilike '%'||p_search||'%')
    order by s.activo desc,s.nombre,s.id limit 25 offset p_page*25;
end; $function$;

CREATE OR REPLACE FUNCTION public.supplier_payable_orders(p_company uuid, p_supplier uuid, p_page integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'compras_cuentas','ver')
    or not private.has_permission(p_company,'finanzas','ver') then raise exception 'Sin acceso a cuentas' using errcode='42501'; end if;
  if p_page is null or p_page<0 or p_page>100000 then raise exception 'Página inválida'; end if;
  return (with orders as (
    select o.id as id,o.numero as number,o.estado as status,round(sum(l.cantidad*l.precio_unitario),2) as total,
      round(sum(l.cantidad_recibida*l.precio_unitario),2) received,
      coalesce((select sum(t.importe) from public.finanzas_movimientos t
        where t.empresa_id=o.empresa_id and t.orden_compra_id=o.id and t.tipo='pago_proveedor'),0) paid
    from public.compras_ordenes o join public.compras_ordenes_lineas l on l.empresa_id=o.empresa_id and l.orden_compra_id=o.id
    where o.empresa_id=p_company and o.proveedor_id=p_supplier and o.estado in ('abierta','parcial','recibida')
    group by o.id
  ), pending as (select *,total-paid remaining from orders where total>paid)
  select jsonb_build_object('count',(select count(*) from pending),'rows',coalesce((select jsonb_agg(x) from (
    select * from pending order by number limit 25 offset p_page*25) x),'[]'::jsonb)));
end; $function$;

CREATE OR REPLACE FUNCTION public.supplier_purchase_statistics(p_company uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_result jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'compras_cuentas','ver') then
    raise exception 'Sin acceso a compras' using errcode='42501'; end if;
  if p_from is null or p_to is null or p_from>p_to then raise exception 'Rango de fechas inválido'; end if;
  with received as (
    select o.proveedor_id as supplier_id,o.proveedor_nombre as supplier_name,l.item_id as item_id,pl.item_codigo as item_code,pl.item_nombre as item_name,pl.unidad_simbolo as unit_symbol,
      l.cantidad as quantity,l.cantidad*l.precio_unitario as amount,r.id as receipt_id
    from public.compras_recepciones r join public.compras_recepciones_lineas l on l.empresa_id=r.empresa_id and l.recepcion_id=r.id
    join public.compras_ordenes o on o.empresa_id=r.empresa_id and o.id=r.orden_compra_id
    join public.compras_ordenes_lineas pl on pl.empresa_id=l.empresa_id and pl.orden_compra_id=l.orden_compra_id and pl.linea=l.linea
    where r.empresa_id=p_company and r.creado_en >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
      and r.creado_en < ((p_to+1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
  ) select jsonb_build_object('total',coalesce((select sum(amount) from received),0),
    'receipts',(select count(distinct receipt_id) from received),
    'suppliers',coalesce((select jsonb_agg(x) from (
      select supplier_id as supplier_id,max(supplier_name) as name,sum(amount) as amount,count(distinct receipt_id) receipts
      from received group by supplier_id order by sum(amount) desc,supplier_id limit 10) x),'[]'::jsonb),
    'products_frequency',coalesce((select jsonb_agg(x) from (
      select item_id as item_id,max(item_code) as code,max(item_name) as name,unit_symbol as unit_symbol,sum(quantity) as quantity,sum(amount) as amount,
        count(distinct receipt_id) frequency
      from received group by item_id,unit_symbol order by count(distinct receipt_id) desc,sum(amount) desc,item_id limit 10) x),'[]'::jsonb),
    'products',coalesce((select jsonb_agg(x) from (
      select item_id as item_id,max(item_code) as code,max(item_name) as name,unit_symbol as unit_symbol,sum(quantity) as quantity,sum(amount) as amount
      from received group by item_id,unit_symbol order by sum(amount) desc,item_id limit 10) x),'[]'::jsonb)) into v_result;
  return v_result;
end; $function$;

CREATE OR REPLACE FUNCTION public.supplier_quote_catalog(p_company uuid, p_supplier uuid DEFAULT NULL::uuid, p_item uuid DEFAULT NULL::uuid, p_search text DEFAULT ''::text, p_page integer DEFAULT 0)
 RETURNS TABLE(supplier_id uuid, supplier_name text, supplier_active boolean, item_id uuid, item_code text, item_name text, item_type text, item_active boolean, unit_symbol text, unit_price numeric, currency_code text, exchange_rate_type_id uuid, exchange_rate_type text, exchange_rate numeric, adjustment_percent numeric, unit_cost_ars numeric, preferred boolean, supplier_sku text, updated_at timestamp with time zone, is_best_price boolean, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not (private.has_permission(p_company,'compras_proveedores','ver') and private.has_permission(p_company,'costos_materiales','ver')) then
    raise exception 'Sin acceso a precios de proveedores' using errcode='42501'; end if;
  if p_page is null or p_page<0 or p_page>100000 or length(coalesce(p_search,''))>100 then
    raise exception 'Búsqueda inválida'; end if;
  return query with costs as (
    select q.proveedor_id,s.nombre supplier_name,s.activo supplier_active,
      q.item_id,i.codigo item_code,i.nombre item_name,i.tipo_item,i.activo item_active,u.simbolo unit_symbol,
      q.precio_unitario,q.moneda,q.tipo_cambio_id,t.nombre exchange_rate_type,
      case when q.moneda='USD' then private.current_fx_rate(p_company,q.tipo_cambio_id)
        else 1::numeric end exchange_rate,q.ajuste_porcentaje,q.preferido,q.proveedor_codigo,q.actualizado_en
    from public.compras_proveedores_items q
    join public.compras_proveedores s on s.empresa_id=q.empresa_id and s.id=q.proveedor_id
    join public.stock_items i on i.empresa_id=q.empresa_id and i.id=q.item_id
    join public.stock_unidades u on u.empresa_id=i.empresa_id and u.id=i.unidad_id
    left join public.finanzas_tipos_cambio t on t.empresa_id=q.empresa_id and t.id=q.tipo_cambio_id
    where q.empresa_id=p_company
  ), priced as (
    select c.*,round(c.precio_unitario*c.exchange_rate*(1+c.ajuste_porcentaje/100),2) unit_cost_ars
    from costs c
  ), ranked as (
    select c.*,min(c.unit_cost_ars) filter(where c.supplier_active and c.item_active)
      over(partition by c.item_id) best_price,
      count(*) filter(where c.supplier_active and c.item_active and c.unit_cost_ars is not null)
      over(partition by c.item_id) comparable_count from priced c
  ) select c.proveedor_id,c.supplier_name,c.supplier_active,c.item_id,c.item_code,c.item_name,
    c.tipo_item,c.item_active,c.unit_symbol,c.precio_unitario,c.moneda,c.tipo_cambio_id,
    c.exchange_rate_type,c.exchange_rate,c.ajuste_porcentaje,c.unit_cost_ars,c.preferido,
    c.proveedor_codigo,c.actualizado_en,
    (c.supplier_active and c.item_active and c.comparable_count>1 and c.unit_cost_ars=c.best_price),
    count(*) over()
    from ranked c where (p_supplier is null or c.proveedor_id=p_supplier)
      and (p_item is null or c.item_id=p_item)
      and (coalesce(p_search,'')='' or c.item_name ilike '%'||p_search||'%'
        or c.item_code ilike '%'||p_search||'%' or c.proveedor_codigo ilike '%'||p_search||'%')
    order by c.supplier_active desc,c.item_active desc,
      case when p_supplier is null then c.unit_cost_ars end asc nulls last,
      c.item_name,c.supplier_name,c.item_id,c.proveedor_id
    limit 25 offset p_page*25;
end; $function$;

CREATE OR REPLACE FUNCTION public.treasury_activity(p_company uuid)
 RETURNS TABLE(id uuid, account_id uuid, kind text, amount numeric, note text, occurred_on date, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'finanzas','ver') then
    raise exception 'Sin permiso para consultar tesorería' using errcode='42501'; end if;
  return query select x.id,x.cuenta_id,x.tipo,x.importe,x.nota,x.fecha,x.creado_en
  from (
    select t.id,t.cuenta_id,t.tipo,t.importe,t.nota,t.fecha,t.creado_en
      from public.finanzas_movimientos t where t.empresa_id=p_company
    union all
    select sp.id,psa.cuenta_id,
      case when r.cobro_id is null then 'customer_payment' else 'annulled_payment' end,
      case when r.cobro_id is null then sp.importe else 0::numeric end,
      'Venta Nº '||s.numero::text||' · '||s.cliente_nombre,
      sp.fecha_pago,sp.creado_en
    from public.finanzas_cobros_cuentas psa
    join public.ventas_cobros sp on sp.empresa_id=psa.empresa_id and sp.id=psa.cobro_id
    join public.ventas s on s.empresa_id=sp.empresa_id and s.id=sp.venta_id
    left join public.ventas_cobros_reversiones r on r.empresa_id=sp.empresa_id
      and r.cobro_id=sp.id
    where psa.empresa_id=p_company
  ) x order by x.creado_en desc limit 100;
end;
$function$;

CREATE OR REPLACE FUNCTION public.treasury_balances(p_company uuid)
 RETURNS TABLE(account_id uuid, name text, kind text, active boolean, opening_balance numeric, income numeric, expense numeric, balance numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'finanzas','ver') then
    raise exception 'Sin permiso para consultar tesorería' using errcode='42501'; end if;
  return query select a.id,a.nombre,a.tipo,a.activo,a.saldo_inicial,
    coalesce(e.credits,0)+coalesce(p.credits,0),coalesce(e.debits,0),
    a.saldo_inicial+coalesce(e.credits,0)+coalesce(p.credits,0)-coalesce(e.debits,0)
  from public.finanzas_cuentas a
  left join lateral (select
    coalesce(sum(t.importe) filter(where t.tipo in ('ingreso','transferencia_entrada')),0) credits,
    coalesce(sum(t.importe) filter(where t.tipo in ('egreso','pago_proveedor','transferencia_salida')),0) debits
    from public.finanzas_movimientos t where t.empresa_id=a.empresa_id and t.cuenta_id=a.id) e on true
  left join lateral (select coalesce(sum(sp.importe),0) credits
    from public.finanzas_cobros_cuentas psa join public.ventas_cobros sp
      on sp.empresa_id=psa.empresa_id and sp.id=psa.cobro_id
    where psa.empresa_id=a.empresa_id and psa.cuenta_id=a.id and not exists(
      select 1 from public.ventas_cobros_reversiones spr
      where spr.empresa_id=sp.empresa_id and spr.cobro_id=sp.id)) p on true
  where a.empresa_id=p_company order by a.nombre;
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_company_role(p_company uuid, p_role uuid, p_name text, p_permissions jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_code text;
  v_old_name text;
  v_name text := btrim(p_name);
  v_before text[];
  v_after text[];
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'administrador' then
    raise exception 'Solo el administrador puede editar roles' using errcode = '42501';
  end if;
  select codigo, nombre into v_code, v_old_name from public.ajustes_roles where id = p_role and empresa_id = p_company for update;
  if v_code is null then raise exception 'Rol inexistente'; end if;
  if v_code = 'administrador' then raise exception 'El rol administrador está protegido'; end if;
  if v_code = 'soporte' then raise exception 'El rol de soporte no se edita desde acá'; end if;
  if v_name is null or length(v_name) not between 2 and 60 then
    raise exception 'Datos del rol inválidos';
  end if;
  select coalesce(array_agg(rp.recurso || ':' || rp.accion order by rp.recurso, rp.accion), '{}')
    into v_before from public.ajustes_roles_permisos rp where rp.rol_id = p_role;
  update public.ajustes_roles set nombre = v_name where id = p_role;
  delete from public.ajustes_roles_permisos where rol_id = p_role;
  perform private.save_role_permissions(p_company, p_role, p_permissions);
  select coalesce(array_agg(rp.recurso || ':' || rp.accion order by rp.recurso, rp.accion), '{}')
    into v_after from public.ajustes_roles_permisos rp where rp.rol_id = p_role;
  perform private.log_access_event(p_company, 'rol_editado', null, p_role, jsonb_build_object(
    'name_before', v_old_name, 'name_after', v_name,
    'added', coalesce((select jsonb_agg(x order by x) from unnest(v_after) x where x <> all (v_before)), '[]'::jsonb),
    'removed', coalesce((select jsonb_agg(x order by x) from unnest(v_before) x where x <> all (v_after)), '[]'::jsonb)));
end;
$function$;

CREATE OR REPLACE FUNCTION public.void_delivery_note(p_company uuid, p_note uuid, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_note public.stock_remitos%rowtype;
  v_line public.stock_remitos_lineas%rowtype;
  v_operation uuid;
  v_event uuid;
  v_expiry date;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'stock', 'crear')
    or not private.has_permission(p_company, 'stock', 'eliminar') then
    raise exception 'Necesitás permiso para anular entregas y reingresar stock'
      using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_reason, ''))) not between 5 and 300 then
    raise exception 'Escribí un motivo de al menos cinco caracteres'; end if;
  select * into v_note from public.stock_remitos
    where empresa_id = p_company and id = p_note for update;
  if not found then raise exception 'Remito inexistente'; end if;
  if v_note.estado = 'anulado' then
    if v_note.motivo_anulacion <> btrim(p_reason) then
      raise exception 'El remito ya fue anulado con otro motivo'; end if;
    return v_note.id;
  end if;
  if v_note.tipo = 'venta' then
    if not private.has_permission(p_company, 'ventas', 'ver') then
      raise exception 'Necesitás acceso a ventas' using errcode = '42501'; end if;
    update public.stock_remitos set estado = 'anulado',
      motivo_anulacion = btrim(p_reason), anulado_en = clock_timestamp()
      where empresa_id = p_company and id = p_note;
    return p_note;
  end if;
  if v_note.tipo = 'produccion' then
    if not private.has_permission(p_company,'produccion_ordenes','editar') then
      raise exception 'Necesitás permiso para devolver insumos de producción'
        using errcode = '42501'; end if;
    perform 1 from public.produccion_ordenes
      where empresa_id = p_company and id = v_note.orden_id
        and estado = 'en_proceso' for update;
    if not found then
      raise exception 'La fabricación ya fue cerrada. No se puede anular esta entrega'; end if;
  end if;
  for v_line in select * from public.stock_remitos_lineas
    where empresa_id = p_company and remito_id = p_note order by linea loop
    if v_note.tipo = 'produccion' then
      if exists(select 1 from public.produccion_ordenes_eventos e
        where e.empresa_id = p_company and e.entrega_id = v_line.evento_produccion_id) then
        raise exception 'Ya se devolvió parte de esta entrega. Ajustá la orden manualmente';
      end if;
      v_event := public.return_production_material(p_company, v_note.orden_id,
        v_line.evento_produccion_id, v_line.cantidad,
        'Anulación remito Nº ' || v_note.numero || ' · ' || left(btrim(p_reason), 245),
        gen_random_uuid());
      select operacion_stock_id into v_operation from public.produccion_ordenes_eventos
        where empresa_id = p_company and id = v_event;
    else
      v_event := null;
      v_expiry := null;
      if v_line.lote_codigo is not null then
        select l.vencimiento into v_expiry from public.stock_lotes l
          where l.empresa_id = p_company and l.item_id = v_line.item_id
            and lower(l.codigo) = lower(v_line.lote_codigo);
        if not found then raise exception 'No se encuentra el lote de origen'; end if;
      end if;
      v_operation := public.post_stock_operation(p_company, v_line.item_id,
        v_line.deposito_id, null, 'ingreso', v_line.cantidad,
        'Anulación remito Nº ' || v_note.numero || ' · ' || left(btrim(p_reason), 245),
        gen_random_uuid(), v_line.lote_codigo, v_expiry);
    end if;
    insert into public.stock_remitos_reversiones(empresa_id, remito_id, linea,
      operacion_stock_id, evento_produccion_id)
    values (p_company, p_note, v_line.linea, v_operation, v_event);
  end loop;
  update public.stock_remitos set estado = 'anulado',
    motivo_anulacion = btrim(p_reason), anulado_en = clock_timestamp()
    where empresa_id = p_company and id = p_note;
  return p_note;
end;
$function$;

-- Un módulo apagado en empresas.modulos bloquea sus permisos.
-- Inicio, Ajustes, permisos de costos y los datos base (ítems, unidades,
-- categorías y depósitos) no dependen de ningún módulo.
create or replace function private.module_enabled(p_company uuid, p_resource text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  with pedido as (
    select case
      when p_resource in ('items', 'unidades', 'categorias', 'depositos') then null
      else coalesce(
        (select c.modulo from public.ajustes_permisos_catalogo c where c.recurso = p_resource),
        case p_resource
          when 'inventario' then 'stock'
          else p_resource
        end
      )
    end as modulo
  )
  select case
    when p.modulo is null or p.modulo not in ('stock', 'produccion', 'compras', 'ventas', 'finanzas', 'reportes') then true
    else coalesce((select (e.modulos ->> p.modulo)::boolean from public.empresas e where e.id = p_company), false)
  end
  from pedido p
$function$;

commit;

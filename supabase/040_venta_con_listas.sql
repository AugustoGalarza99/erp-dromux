-- Dromux ERP · 040 · La venta toma el precio de la lista del cliente, con descuento por línea.
-- ESTADO: PREPARADA, NO APLICADA. Toca el camino del dinero (post_sale): aplicar solo con autorización del
-- propietario, respaldo y después de la revisión crítica. Requiere 039 aplicada.
-- Comprobaciones: supabase/verificaciones/040_comprobaciones.sql. Deshacer: supabase/reparacion/0_deshacer_040.sql.
--
-- Decisiones del propietario (24/11/2026):
--   * IVA en la venta: el total y los cobros NO cambian (siguen siendo el neto). Cada línea guarda su alícuota
--     solo como dato informativo.
--   * Descuentos: tope general por empresa (price_settings.max_discount_percent, 0 por defecto = sin descuentos).
--     Quien registra ventas puede descontar hasta el tope; el administrador puede pasarlo con motivo obligatorio.
--     Descuento por línea (el descuento de documento queda para más adelante).
--   * Listas en USD: se ignoran al vender (solo sirven de referencia).
--
-- Precio de una línea = precio de la lista del cliente (vigente hoy, en pesos, no archivada) → lista
-- predeterminada → precio actual del producto (items.sale_unit_price), con el descuento aplicado y redondeado a
-- 2 decimales. El cliente envía el precio final que vio (expected_unit_price) y el servidor lo recalcula: si no
-- coincide, rechaza (igual que hoy). Cada línea guarda lista, precio de lista, descuento, motivo y alícuota.
--
-- post_sale se modifica SOLO por reemplazo de 6 fragmentos exactos sobre la definición vigente (H-002):
-- si alguno no aparece exactamente una vez, aborta sin cambiar nada. No toca stock, cobros ni numeración.

begin;

-- 1) Columnas nuevas (aditivas) --------------------------------------------------------------------------
alter table public.price_settings
  add column max_discount_percent numeric(5,2) not null default 0
  check (max_discount_percent >= 0 and max_discount_percent < 100);

alter table public.sale_lines
  add column price_list_id uuid,
  add column list_unit_price numeric(18,2) check (list_unit_price is null or list_unit_price >= 0),
  add column discount_percent numeric(5,2) not null default 0
    check (discount_percent >= 0 and discount_percent < 100),
  add column discount_reason text check (discount_reason is null or length(discount_reason) <= 200),
  add column tax_percent numeric(5,2) check (tax_percent is null or tax_percent between 0 and 100),
  add constraint sale_lines_price_list_fkey
    foreign key (company_id, price_list_id) references public.price_lists(company_id, id);

-- 2) Configuración: el tope de descuento (p_max_discount es opcional: un frontend anterior que llama con 5 parámetros sigue funcionando y no cambia el tope) ----------------------------------------------------------------
drop function public.save_price_settings(uuid, numeric, numeric, numeric, numeric);
create function public.save_price_settings(
  p_company uuid, p_default_tax numeric, p_min_margin numeric, p_commission numeric, p_structure numeric,
  p_max_discount numeric default null
) returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.price_require_admin(p_company, true);
  if p_default_tax is null or p_default_tax not between 0 and 100
     or p_min_margin is null or p_min_margin < 0 or p_min_margin >= 100
     or p_commission is null or p_commission not between 0 and 100
     or p_structure is null or p_structure not between 0 and 100
     or (p_max_discount is not null and (p_max_discount < 0 or p_max_discount >= 100)) then
    raise exception 'Revisá los porcentajes (IVA 0–100, margen mínimo y descuento máximo menores a 100)';
  end if;
  insert into public.price_settings(company_id, default_tax_percent, min_margin_percent,
    commission_percent, structure_percent, max_discount_percent, updated_by)
  values (p_company, p_default_tax, p_min_margin, p_commission, p_structure, coalesce(p_max_discount, 0), auth.uid())
  on conflict (company_id) do update set default_tax_percent = excluded.default_tax_percent,
    min_margin_percent = excluded.min_margin_percent, commission_percent = excluded.commission_percent,
    structure_percent = excluded.structure_percent,
    max_discount_percent = coalesce(p_max_discount, public.price_settings.max_discount_percent),
    updated_at = clock_timestamp(), updated_by = auth.uid();
end;
$$;

drop function public.erp_price_settings(uuid);
create function public.erp_price_settings(p_company uuid)
returns table(default_tax_percent numeric, min_margin_percent numeric, commission_percent numeric,
  structure_percent numeric, max_discount_percent numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.price_require_cost_view(p_company);
  return query select coalesce(s.default_tax_percent, 21::numeric), coalesce(s.min_margin_percent, 0::numeric),
    coalesce(s.commission_percent, 0::numeric), coalesce(s.structure_percent, 0::numeric),
    coalesce(s.max_discount_percent, 0::numeric)
  from (select 1) x left join public.price_settings s on s.company_id = p_company;
end;
$$;

-- sale_lines tiene lectura por columna (036): se habilitan las columnas nuevas no sensibles.
grant select (price_list_id, list_unit_price, discount_percent, discount_reason, tax_percent)
  on public.sale_lines to authenticated;

-- 3) Precio de venta: una sola regla, compartida por la pantalla y por post_sale ------------------------
create function private.sale_resolve_price(p_company uuid, p_customer uuid, p_item uuid)
returns table(price numeric, list_id uuid, tax_percent numeric, source text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_tax numeric; v_price numeric; v_list public.price_lists%rowtype; r record;
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  select coalesce(s.tax_percent, (select ps.default_tax_percent from public.price_settings ps
    where ps.company_id = p_company), 21)
    into v_tax from (select 1) x
    left join public.item_sale_settings s on s.company_id = p_company and s.item_id = p_item;
  for r in
    select l.price_list_id as id, 1 as ord from public.customer_price_lists l
      where l.company_id = p_company and l.customer_id = p_customer
    union all
    select d.id, 2 from public.price_lists d where d.company_id = p_company and d.is_default
    order by 2
  loop
    select * into v_list from public.price_lists pl
    where pl.company_id = p_company and pl.id = r.id and not pl.archived and pl.currency = 'ARS'
      and (pl.valid_from is null or pl.valid_from <= v_today) and (pl.valid_to is null or pl.valid_to >= v_today);
    if not found then continue; end if;
    select coalesce(own.net_price,
        private.price_round(b.net_price * (1 - v_list.base_discount_percent / 100), v_list.rounding_step))
      into v_price
    from (select 1) x
    left join public.price_list_items own
      on own.company_id = p_company and own.price_list_id = v_list.id and own.item_id = p_item
    left join public.price_list_items b
      on b.company_id = p_company and b.price_list_id = v_list.base_list_id and b.item_id = p_item;
    if v_price is not null then
      price := v_price; list_id := v_list.id; tax_percent := v_tax;
      source := case when r.ord = 1 then 'customer' else 'default' end;
      return next; return;
    end if;
  end loop;
  select i.sale_unit_price into v_price from public.items i where i.company_id = p_company and i.id = p_item;
  price := v_price; list_id := null; tax_percent := v_tax; source := 'item';
  return next;
end;
$$;
revoke all on function private.sale_resolve_price(uuid, uuid, uuid) from public, anon, authenticated;

-- La consulta pública pasa a usar la misma regla (misma firma y columnas que en 039).
create or replace function public.erp_resolve_sale_price(p_company uuid, p_customer uuid, p_item uuid)
returns table(net_price numeric, currency text, tax_percent numeric, gross_price numeric, price_list_id uuid, source text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  if auth.uid() is null or not private.has_permission(p_company, 'sales', 'read') then
    raise exception 'Sin acceso a ventas' using errcode = '42501';
  end if;
  return query select r.price, 'ARS'::text, r.tax_percent,
    case when r.price is not null then round(r.price * (1 + r.tax_percent / 100), 2) end, r.list_id, r.source
  from private.sale_resolve_price(p_company, p_customer, p_item) r;
end;
$$;

-- Precios de varios productos para un cliente (pantalla de venta). Sin costos ni márgenes.
create function public.erp_sale_prices(p_company uuid, p_customer uuid, p_items uuid[])
returns table(item_id uuid, net_price numeric, price_list_id uuid, list_name text, source text, tax_percent numeric)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  if auth.uid() is null or not private.has_permission(p_company, 'sales', 'read') then
    raise exception 'Sin acceso a ventas' using errcode = '42501';
  end if;
  if p_items is null or cardinality(p_items) > 200 then
    raise exception 'Consultá hasta 200 productos por vez';
  end if;
  return query
  select i.id, r.price, r.list_id, l.name, r.source, r.tax_percent
  from public.items i
  cross join lateral private.sale_resolve_price(p_company, p_customer, i.id) r
  left join public.price_lists l on l.company_id = p_company and l.id = r.list_id
  where i.company_id = p_company and i.id = any (p_items);
end;
$$;

-- Política de descuento para la pantalla: tope general y si quien consulta puede superarlo.
create function public.erp_sale_discount_policy(p_company uuid)
returns table(max_discount_percent numeric, can_exceed boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  if auth.uid() is null or not private.has_permission(p_company, 'sales', 'read') then
    raise exception 'Sin acceso a ventas' using errcode = '42501';
  end if;
  return query select coalesce((select s.max_discount_percent from public.price_settings s
      where s.company_id = p_company), 0::numeric),
    (private.get_user_role(p_company) is not distinct from 'admin'
      and private.has_permission(p_company, 'sales', 'insert'));
end;
$$;

revoke all on function
  public.save_price_settings(uuid, numeric, numeric, numeric, numeric, numeric),
  public.erp_price_settings(uuid),
  public.erp_resolve_sale_price(uuid, uuid, uuid),
  public.erp_sale_prices(uuid, uuid, uuid[]),
  public.erp_sale_discount_policy(uuid)
  from public, anon;
grant execute on function
  public.save_price_settings(uuid, numeric, numeric, numeric, numeric, numeric),
  public.erp_price_settings(uuid),
  public.erp_resolve_sale_price(uuid, uuid, uuid),
  public.erp_sale_prices(uuid, uuid, uuid[]),
  public.erp_sale_discount_policy(uuid)
  to authenticated;

-- 4) post_sale: 6 reemplazos exactos sobre la definición vigente ---------------------------------------------
do $do$
declare
  v_def text;
  v_count integer;
  r record;
begin
  v_def := replace(pg_get_functiondef('public.post_sale(uuid,uuid,text,jsonb,uuid)'::regprocedure), E'\r\n', E'\n');
  for r in select n, replace(old_text, chr(13), '') as old_text, replace(new_text, chr(13), '') as new_text from (values
    (1, $a$  v_post jsonb;
begin
$a$, $b$  v_post jsonb;
  v_res record;
  v_disc numeric;
  v_reason text;
  v_base numeric;
  v_cap numeric;
begin
$b$),
    (2, $a$    if v_item.sale_unit_price is null then
      raise exception 'Definí el precio de venta de %',v_item.name;
    end if;
    if (v_line->>'expected_unit_price') is null
      or (v_line->>'expected_unit_price')::numeric <> v_item.sale_unit_price then
      raise exception 'El precio de % cambió. Actualizá la pantalla y revisá la venta',v_item.name;
    end if;
$a$, $b$    select * into v_res from private.sale_resolve_price(p_company,p_customer,v_item_id);
    if v_res.price is null then
      raise exception 'Definí el precio de venta de %',v_item.name;
    end if;
    select s.max_discount_percent into v_cap from public.price_settings s where s.company_id=p_company;
    v_cap := coalesce(v_cap,0);
    v_disc := coalesce(nullif(btrim(v_line->>'discount_percent'),'')::numeric,0);
    v_reason := nullif(btrim(v_line->>'discount_reason'),'');
    if v_disc = 0 then v_reason := null; end if;
    if v_disc < 0 or v_disc >= 100 or v_disc <> round(v_disc,2) then
      raise exception 'El descuento de % es inválido',v_item.name;
    end if;
    if length(coalesce(v_reason,'')) > 200 then
      raise exception 'El motivo del descuento es demasiado largo';
    end if;
    if v_disc > v_cap then
      if private.get_user_role(p_company) is distinct from 'admin' then
        raise exception 'El descuento de % supera el máximo permitido (% %%)',v_item.name,v_cap;
      end if;
      if length(regexp_replace(coalesce(v_reason,''),'[^[:alnum:]]','','g')) < 3 then
        raise exception 'Indicá el motivo del descuento de %',v_item.name;
      end if;
    end if;
    v_base := v_res.price;
    if v_disc > 0 and round(v_base*(1-v_disc/100),2) <= 0 then
      raise exception 'El descuento de % deja el precio en cero',v_item.name;
    end if;
    if (v_line->>'expected_unit_price') is null
      or (v_line->>'expected_unit_price')::numeric <> round(v_base*(1-v_disc/100),2) then
      raise exception 'El precio de % cambió. Actualizá la pantalla y revisá la venta',v_item.name;
    end if;
$b$),
    (3, $a$    v_unit_price := v_item.sale_unit_price;
$a$, $b$    v_unit_price := round(v_base*(1-v_disc/100),2);
$b$),
    (4, $a$'line_total',v_line_total,'estimated_unit_cost',v_cost,'operation',v_operation));$a$,
        $b$'line_total',v_line_total,'estimated_unit_cost',v_cost,'operation',v_operation,
      'price_list_id',v_res.list_id,'list_unit_price',v_base,'discount_percent',v_disc,
      'discount_reason',v_reason,'tax_percent',v_res.tax_percent));$b$),
    (5, $a$      line_total,estimated_unit_cost,stock_operation_id)
$a$, $b$      line_total,estimated_unit_cost,stock_operation_id,
      price_list_id,list_unit_price,discount_percent,discount_reason,tax_percent)
$b$),
    (6, $a$      (v_post->>'operation')::uuid);
$a$, $b$      (v_post->>'operation')::uuid,
      (v_post->>'price_list_id')::uuid,(v_post->>'list_unit_price')::numeric,
      (v_post->>'discount_percent')::numeric,v_post->>'discount_reason',
      (v_post->>'tax_percent')::numeric);
$b$)
  ) as t(n, old_text, new_text) loop
    v_count := (length(v_def) - length(replace(v_def, r.old_text, ''))) / length(r.old_text);
    if v_count <> 1 then
      raise exception 'post_sale: el fragmento % aparece % veces (se esperaba 1). No se cambió nada.', r.n, v_count;
    end if;
    v_def := replace(v_def, r.old_text, r.new_text);
  end loop;
  execute v_def;
end
$do$;

commit;

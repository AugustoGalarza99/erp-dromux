-- Deshace 040 (venta con listas y descuentos). Deja post_sale como estaba antes de la 040.
-- ATENCIÓN: borra las columnas de lista/descuento de sale_lines. Aborta si ya hay ventas con lista o
-- descuento registrados (perderías esa trazabilidad): en ese caso no deshacer; corregir hacia adelante.
-- No toca las listas de la 039 ni ventas, cobros o stock.
begin;

do $$
begin
  if exists (select 1 from public.sale_lines where price_list_id is not null or discount_percent > 0
             or discount_reason is not null or list_unit_price is not null or tax_percent is not null) then
    raise exception 'Hay ventas registradas con la 040 (lista, precio de lista, descuento o alícuota). No se puede deshacer sin perder esa información: corregí hacia adelante.';
  end if;
  if exists (select 1 from public.price_settings where max_discount_percent > 0) then
    raise exception 'Hay un tope de descuento configurado. Anotalo y poné 0 antes de deshacer la 040.';
  end if;
end
$$;

-- 1) post_sale: revertir los 6 fragmentos (cada uno debe aparecer exactamente una vez).
do $do$
declare
  v_def text; v_count integer; r record;
begin
  v_def := replace(pg_get_functiondef('public.post_sale(uuid,uuid,text,jsonb,uuid)'::regprocedure), E'\r\n', E'\n');
  for r in select n, replace(old_text, chr(13), '') as old_text, replace(new_text, chr(13), '') as new_text from (values
    (1, $b$  v_post jsonb;
  v_res record;
  v_disc numeric;
  v_reason text;
  v_base numeric;
  v_cap numeric;
begin
$b$, $a$  v_post jsonb;
begin
$a$),
    (2, $b$    select * into v_res from private.sale_resolve_price(p_company,p_customer,v_item_id);
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
$b$, $a$    if v_item.sale_unit_price is null then
      raise exception 'Definí el precio de venta de %',v_item.name;
    end if;
    if (v_line->>'expected_unit_price') is null
      or (v_line->>'expected_unit_price')::numeric <> v_item.sale_unit_price then
      raise exception 'El precio de % cambió. Actualizá la pantalla y revisá la venta',v_item.name;
    end if;
$a$),
    (3, $b$    v_unit_price := round(v_base*(1-v_disc/100),2);
$b$, $a$    v_unit_price := v_item.sale_unit_price;
$a$),
    (4, $b$'line_total',v_line_total,'estimated_unit_cost',v_cost,'operation',v_operation,
      'price_list_id',v_res.list_id,'list_unit_price',v_base,'discount_percent',v_disc,
      'discount_reason',v_reason,'tax_percent',v_res.tax_percent));$b$,
        $a$'line_total',v_line_total,'estimated_unit_cost',v_cost,'operation',v_operation));$a$),
    (5, $b$      line_total,estimated_unit_cost,stock_operation_id,
      price_list_id,list_unit_price,discount_percent,discount_reason,tax_percent)
$b$, $a$      line_total,estimated_unit_cost,stock_operation_id)
$a$),
    (6, $b$      (v_post->>'operation')::uuid,
      (v_post->>'price_list_id')::uuid,(v_post->>'list_unit_price')::numeric,
      (v_post->>'discount_percent')::numeric,v_post->>'discount_reason',
      (v_post->>'tax_percent')::numeric);
$b$, $a$      (v_post->>'operation')::uuid);
$a$)
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

-- 2) Funciones nuevas y vuelta a las de la 039.
drop function if exists public.erp_sale_discount_policy(uuid);
drop function if exists public.erp_sale_prices(uuid, uuid, uuid[]);
drop function if exists private.sale_resolve_price(uuid, uuid, uuid);
-- erp_resolve_sale_price queda con la regla de la 040 hasta reaplicar la 039: se vuelve a su cuerpo anterior.
drop function if exists public.erp_resolve_sale_price(uuid, uuid, uuid);

drop function if exists public.erp_price_settings(uuid);
create function public.erp_price_settings(p_company uuid)
returns table(default_tax_percent numeric, min_margin_percent numeric,
  commission_percent numeric, structure_percent numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.price_require_cost_view(p_company);
  return query select coalesce(s.default_tax_percent, 21::numeric), coalesce(s.min_margin_percent, 0::numeric),
    coalesce(s.commission_percent, 0::numeric), coalesce(s.structure_percent, 0::numeric)
  from (select 1) x left join public.price_settings s on s.company_id = p_company;
end;
$$;

drop function if exists public.save_price_settings(uuid, numeric, numeric, numeric, numeric, numeric);
create function public.save_price_settings(
  p_company uuid, p_default_tax numeric, p_min_margin numeric, p_commission numeric, p_structure numeric
) returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.price_require_admin(p_company, true);
  if p_default_tax is null or p_default_tax not between 0 and 100
     or p_min_margin is null or p_min_margin < 0 or p_min_margin >= 100
     or p_commission is null or p_commission not between 0 and 100
     or p_structure is null or p_structure not between 0 and 100 then
    raise exception 'Revisá los porcentajes (IVA 0–100, margen mínimo menor a 100)';
  end if;
  insert into public.price_settings(company_id, default_tax_percent, min_margin_percent,
    commission_percent, structure_percent, updated_by)
  values (p_company, p_default_tax, p_min_margin, p_commission, p_structure, auth.uid())
  on conflict (company_id) do update set default_tax_percent = excluded.default_tax_percent,
    min_margin_percent = excluded.min_margin_percent, commission_percent = excluded.commission_percent,
    structure_percent = excluded.structure_percent, updated_at = clock_timestamp(), updated_by = auth.uid();
end;
$$;
revoke all on function public.erp_price_settings(uuid),
  public.save_price_settings(uuid, numeric, numeric, numeric, numeric) from public, anon;
grant execute on function public.erp_price_settings(uuid),
  public.save_price_settings(uuid, numeric, numeric, numeric, numeric) to authenticated;

-- 3) Columnas.
alter table public.sale_lines
  drop constraint sale_lines_price_list_fkey,
  drop column price_list_id, drop column list_unit_price, drop column discount_percent,
  drop column discount_reason, drop column tax_percent;
alter table public.price_settings drop column max_discount_percent;

commit;
-- NOTA: erp_resolve_sale_price (consulta de la 039) se elimina aquí. Si la querés de vuelta, ejecutá solo ese
-- bloque de 039_listas_precios.sql (create function public.erp_resolve_sale_price ... y su grant).

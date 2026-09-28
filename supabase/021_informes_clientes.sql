-- Versión 021 · detalle administrativo de rentabilidad e informes operativos.
-- Aplicar una vez después de 020. No cambia ventas ni costos ya registrados.

create function public.erp_admin_sales_profit_detail(
  p_company uuid,
  p_from date,
  p_to date,
  p_search text default '',
  p_page integer default 0
)
returns table (
  sale_id uuid,
  sale_number bigint,
  customer_name text,
  sold_at timestamptz,
  product_summary text,
  net_revenue numeric,
  known_cost numeric,
  gross_profit numeric,
  missing_lines bigint,
  cancelled boolean,
  total_rows bigint
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or private.get_user_role(p_company) <> 'admin'
    or not private.has_permission(p_company, 'finance', 'read')
    or not private.has_permission(p_company, 'sales', 'read') then
    raise exception 'Solo el administrador puede consultar la rentabilidad por venta'
      using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_to < p_from
    or p_to - p_from > 366 or p_page is null or p_page < 0 or p_page > 10000
    or length(coalesce(p_search, '')) > 100 then
    raise exception 'Revisá el período y la búsqueda';
  end if;

  return query
  with selected_sales as (
    select s.id, s.number, s.customer_name, s.created_at
    from public.sales s
    where s.company_id = p_company
      and s.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
      and s.created_at < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
      and (btrim(coalesce(p_search, '')) = ''
        or s.customer_name ilike '%' || btrim(p_search) || '%'
        or s.number::text ilike '%' || btrim(p_search) || '%'
        or exists (
          select 1 from public.sale_lines sl
          where sl.company_id = p_company and sl.sale_id = s.id
            and (sl.item_name ilike '%' || btrim(p_search) || '%'
              or sl.item_code ilike '%' || btrim(p_search) || '%')
        ))
  ), line_values as (
    select sl.sale_id, sl.item_name, sl.line_no,
      sl.line_total - coalesce(adj.credit_amount, 0) as revenue,
      sl.quantity - coalesce(adj.restocked_quantity, 0) as retained_quantity,
      sl.estimated_unit_cost
    from public.sale_lines sl
    join selected_sales ss on ss.id = sl.sale_id
    left join lateral (
      select sum(al.credit_amount) as credit_amount,
        sum(al.quantity) filter (where al.restocked) as restocked_quantity
      from public.sale_adjustment_lines al
      where al.company_id = sl.company_id
        and al.sale_id = sl.sale_id and al.sale_line_no = sl.line_no
    ) adj on true
    where sl.company_id = p_company
  ), amounts as (
    select lv.sale_id,
      string_agg(lv.item_name, ', ' order by lv.line_no) as products,
      sum(lv.revenue) as revenue,
      sum(lv.retained_quantity * lv.estimated_unit_cost)
        filter (where lv.estimated_unit_cost is not null) as cost,
      count(*) filter (where lv.estimated_unit_cost is null
        and lv.retained_quantity > 0) as missing
    from line_values lv group by lv.sale_id
  ), details as (
    select ss.id, ss.number, ss.customer_name, ss.created_at,
      a.products, a.revenue, a.cost, a.missing,
      exists (select 1 from public.sale_adjustments sa
        where sa.company_id = p_company and sa.sale_id = ss.id
          and sa.kind = 'cancel') as is_cancelled
    from selected_sales ss join amounts a on a.sale_id = ss.id
  )
  select d.id, d.number, d.customer_name, d.created_at, d.products,
    d.revenue, d.cost,
    case when d.missing = 0 then d.revenue - coalesce(d.cost, 0)
      else null end,
    d.missing, d.is_cancelled, count(*) over()
  from details d
  order by d.created_at desc, d.id desc
  limit 25 offset p_page * 25;
end;
$$;

create function public.erp_operational_report(
  p_company uuid,
  p_from date,
  p_to date
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_result jsonb := '{}'::jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'reports', 'read') then
    raise exception 'Sin acceso a informes' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then
    raise exception 'Elegí un período de hasta un año';
  end if;
  if private.has_permission(p_company, 'sales', 'read') then
    v_result := v_result || jsonb_build_object(
      'sales', (select count(*) from public.sales s
        where s.company_id = p_company
          and s.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
          and s.created_at < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')),
      'revenue', (select coalesce(sum(s.total - coalesce(a.credits, 0)), 0)
        from public.sales s
        left join lateral (select sum(sa.credit_total) as credits
          from public.sale_adjustments sa
          where sa.company_id = s.company_id and sa.sale_id = s.id) a on true
        where s.company_id = p_company
          and s.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
          and s.created_at < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')),
      'top_products', (select coalesce(jsonb_agg(t.entry order by t.qty desc), '[]'::jsonb)
        from (select jsonb_build_object('name', l.item_name,
            'quantity', sum(l.quantity - coalesce(a.returned, 0))) as entry,
            sum(l.quantity - coalesce(a.returned, 0)) as qty
          from public.sale_lines l
          join public.sales s on s.company_id = l.company_id and s.id = l.sale_id
          left join lateral (select sum(al.quantity) as returned
            from public.sale_adjustment_lines al
            where al.company_id = l.company_id and al.sale_id = l.sale_id
              and al.sale_line_no = l.line_no) a on true
          where s.company_id = p_company
            and s.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
            and s.created_at < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
          group by l.item_id, l.item_name
          order by qty desc limit 5) t)
    );
  end if;
  if private.has_permission(p_company, 'production', 'read') then
    v_result := v_result || jsonb_build_object(
      'finished_jobs', (select count(*) from public.production_runs r
        where r.company_id = p_company
          and r.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
          and r.created_at < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')),
      'jobs_in_progress', (select count(*) from public.production_jobs j
        where j.company_id = p_company
          and j.status in ('queued', 'in_progress'))
    );
  end if;
  if private.has_permission(p_company, 'purchases', 'read') then
    v_result := v_result || jsonb_build_object(
      'purchase_orders', (select count(*) from public.purchase_orders o
        where o.company_id = p_company
          and o.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
          and o.created_at < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires'))
    );
  end if;
  return v_result;
end;
$$;

revoke execute on function public.erp_admin_sales_profit_detail(uuid,date,date,text,integer),
  public.erp_operational_report(uuid,date,date) from public, anon;
grant execute on function public.erp_admin_sales_profit_detail(uuid,date,date,text,integer),
  public.erp_operational_report(uuid,date,date) to authenticated;

-- Resumen coherente con el detalle: ventas sin algún costo quedan excluidas
-- de la ganancia global para evitar mostrar un beneficio incompleto.
create or replace function public.erp_admin_sales_profit_summary(p_company uuid)
returns table(sales_total numeric, covered_revenue numeric, covered_cost numeric,
  estimated_profit numeric, missing_lines bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or private.get_user_role(p_company) <> 'admin'
    or not private.has_permission(p_company, 'finance', 'read')
    or not private.has_permission(p_company, 'sales', 'read') then
    raise exception 'Solo el administrador puede consultar ganancias'
      using errcode = '42501';
  end if;
  return query
  with line_values as (
    select l.sale_id,
      l.line_total - coalesce(a.credit_amount, 0) as revenue,
      l.quantity - coalesce(a.restocked_quantity, 0) as retained_quantity,
      l.estimated_unit_cost
    from public.sale_lines l
    left join lateral (
      select sum(al.credit_amount) credit_amount,
        sum(al.quantity) filter (where al.restocked) restocked_quantity
      from public.sale_adjustment_lines al
      where al.company_id = l.company_id and al.sale_id = l.sale_id
        and al.sale_line_no = l.line_no
    ) a on true
    where l.company_id = p_company
  ), sale_totals as (
    select lv.sale_id, sum(lv.revenue) revenue,
      sum(lv.retained_quantity * lv.estimated_unit_cost)
        filter (where lv.estimated_unit_cost is not null) cost,
      count(*) filter (where lv.estimated_unit_cost is null
        and lv.retained_quantity > 0) missing
    from line_values lv group by lv.sale_id
  )
  select coalesce(sum(st.revenue), 0),
    coalesce(sum(st.revenue) filter (where st.missing = 0), 0),
    coalesce(sum(st.cost) filter (where st.missing = 0), 0),
    coalesce(sum(st.revenue - coalesce(st.cost, 0)) filter (where st.missing = 0), 0),
    coalesce(sum(st.missing), 0)::bigint
  from sale_totals st;
end;
$$;

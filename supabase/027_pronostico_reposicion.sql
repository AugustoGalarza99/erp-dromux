-- Dromux Producción · pronóstico y reposición, versión 027.
-- Requiere 026. Ejecutar una vez en la base de pruebas antes de producción.

alter table public.suppliers add column lead_time_days integer not null default 7
  check (lead_time_days between 0 and 365);
grant update (lead_time_days) on public.suppliers to authenticated;
grant insert (lead_time_days) on public.suppliers to authenticated;

create function public.erp_replenishment_forecast(p_company uuid)
returns table (
  item_id uuid, item_code text, item_name text, unit_symbol text,
  physical numeric, usable numeric, reserved numeric, free numeric,
  pending_purchase numeric, minimum_stock numeric,
  consumed_60d numeric, history_days integer, daily_use numeric,
  days_left numeric, supplier_id uuid, supplier_name text,
  lead_time_days integer, suggested_quantity numeric, alert_level text
) language sql stable security definer set search_path = '' as $$
  with scope as (
    select i.id, i.code, i.name, i.minimum_stock, i.track_lots, u.symbol
    from public.items i
    join public.units u on u.company_id=i.company_id and u.id=i.unit_id
    where i.company_id=p_company and i.active
      and i.item_type in ('raw_material','semi_finished','consumable')
      and auth.uid() is not null
      and private.has_permission(p_company,'stock','read')
      and private.has_permission(p_company,'purchases','read')
      and private.has_permission(p_company,'production','read')
  ), snapshot as (
    select i.*,
      coalesce(b.physical,0) as physical,
      coalesce(us.usable,0) as usable,
      coalesce(r.reserved,0) as reserved,
      coalesce(po.pending,0) as pending_purchase,
      coalesce(m.consumed,0) as consumed_60d,
      m.first_issue,
      s.supplier_id,s.supplier_name,coalesce(s.lead_days,7) as lead_days
    from scope i
    left join lateral (
      select sum(b.quantity) physical from public.stock_balances b
      where b.company_id=p_company and b.item_id=i.id
    ) b on true
    left join lateral (
      select sum(q.quantity) usable from (
        select b.quantity from public.stock_balances b
        join public.warehouses w on w.company_id=b.company_id
          and w.id=b.warehouse_id and w.active
        where b.company_id=p_company and b.item_id=i.id and not i.track_lots
        union all
        select lb.quantity from public.stock_lot_balances lb
        join public.warehouses w on w.company_id=lb.company_id
          and w.id=lb.warehouse_id and w.active
        join public.stock_lots l on l.company_id=lb.company_id
          and l.item_id=lb.item_id and l.id=lb.lot_id
        where lb.company_id=p_company and lb.item_id=i.id and i.track_lots
          and (l.expires_on is null or l.expires_on >=
            (now() at time zone 'America/Argentina/Buenos_Aires')::date)
      ) q
    ) us on true
    left join lateral (
      select sum(a.quantity) reserved from public.production_reservation_locations a
      join public.production_jobs j on j.company_id=a.company_id and j.id=a.job_id
      where a.company_id=p_company and a.component_id=i.id
        and j.status in ('queued','in_progress')
    ) r on true
    left join lateral (
      select sum(l.quantity-l.received_quantity) pending
      from public.purchase_order_lines l
      join public.purchase_orders o on o.company_id=l.company_id and o.id=l.order_id
      where l.company_id=p_company and l.item_id=i.id
        and o.status in ('open','partial')
    ) po on true
    left join lateral (
      select sum(-m.delta) consumed, min(m.created_at) first_issue
      from public.stock_movements m
      where m.company_id=p_company and m.item_id=i.id and m.kind='issue'
        and m.created_at >= now()-interval '60 days'
    ) m on true
    left join lateral (
      select si.supplier_id,s.name supplier_name,s.lead_time_days lead_days
      from public.supplier_items si
      join public.suppliers s on s.company_id=si.company_id
        and s.id=si.supplier_id and s.active
      where si.company_id=p_company and si.item_id=i.id
      order by si.preferred desc,s.name,s.id limit 1
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
  select d.id,d.code,d.name,d.symbol,d.physical,d.usable,d.reserved,d.free_stock,
    d.pending_purchase,d.minimum_stock,d.consumed_60d,d.observation_days,d.rate,
    case when d.rate>0 then round(d.free_stock/d.rate,1) else null end,
    d.supplier_id,d.supplier_name,d.lead_days,
    greatest(0,ceil(greatest(d.minimum_stock,
      d.rate*(d.lead_days+7)) - d.free_stock-d.pending_purchase)),
    case
      when d.free_stock<=0 and d.pending_purchase<=0 then 'critical'
      when d.rate>0 and d.free_stock/d.rate<=d.lead_days then 'critical'
      when d.free_stock<d.minimum_stock then 'warning'
      when d.rate>0 and d.free_stock/d.rate<=d.lead_days+7 then 'warning'
      else 'ok'
    end
  from demand d
  order by case
    when d.free_stock<=0 and d.pending_purchase<=0 then 0
    when d.rate>0 and d.free_stock/d.rate<=d.lead_days then 0
    when d.free_stock<d.minimum_stock then 1
    when d.rate>0 and d.free_stock/d.rate<=d.lead_days+7 then 1
    else 2 end,d.name;
$$;
revoke execute on function public.erp_replenishment_forecast(uuid) from public,anon;
grant execute on function public.erp_replenishment_forecast(uuid) to authenticated;

-- Dromux Producción · Centro operativo y avisos, versión 023.
-- Requiere 022. Ejecutar una vez en la base de prueba.

create table public.operational_alert_reads (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  alert_key text not null check (length(alert_key) between 5 and 120),
  fingerprint text not null check (length(fingerprint) between 1 and 150),
  read_at timestamptz not null default now(),
  primary key (company_id, user_id, alert_key)
);

alter table public.operational_alert_reads enable row level security;
create policy operational_alert_reads_select on public.operational_alert_reads
  for select to authenticated using (
    user_id = (select auth.uid())
    and (select private.has_permission(company_id, 'dashboard', 'read'))
  );
create policy operational_alert_reads_insert on public.operational_alert_reads
  for insert to authenticated with check (
    user_id = (select auth.uid())
    and (select private.has_permission(company_id, 'dashboard', 'read'))
  );
create policy operational_alert_reads_update on public.operational_alert_reads
  for update to authenticated using (
    user_id = (select auth.uid())
    and (select private.has_permission(company_id, 'dashboard', 'read'))
  ) with check (
    user_id = (select auth.uid())
    and (select private.has_permission(company_id, 'dashboard', 'read'))
  );
revoke all on public.operational_alert_reads from public, anon, authenticated;
grant select, insert, update on public.operational_alert_reads to authenticated;

create function public.erp_production_alerts(p_company uuid)
returns table (
  alert_key text, fingerprint text, severity text, title text,
  detail text, destination text, occurred_on date
)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'dashboard', 'read') then
    raise exception 'Sin acceso al centro operativo' using errcode = '42501';
  end if;

  if private.has_permission(p_company, 'production', 'read') then
    return query
    select 'job:' || j.id::text,
      j.status || ':' || coalesce(j.due_on::text, ''),
      case when j.due_on < v_today then 'critical' else 'warning' end,
      case when j.due_on < v_today then 'Fabricación fuera de plazo'
        else 'Fabricación próxima a vencer' end,
      i.name || ' · ' || j.planned_quantity::text || ' ' || u.symbol ||
        ' · Fecha prevista: ' || to_char(j.due_on, 'DD/MM/YYYY'),
      '/production/orders?job=' || j.id::text, j.due_on
    from public.production_jobs j
    join public.items i on i.company_id = j.company_id and i.id = j.product_id
    join public.units u on u.company_id = i.company_id and u.id = i.unit_id
    where j.company_id = p_company and j.status in ('queued', 'in_progress')
      and j.due_on <= v_today + 3;
  end if;

  if private.has_permission(p_company, 'stock', 'read')
    and private.has_permission(p_company, 'items', 'read') then
    return query
    select 'stock:' || i.id::text,
      i.minimum_stock::text || ':' || coalesce(b.total, 0)::text,
      case when coalesce(b.total, 0) <= 0 then 'critical' else 'warning' end,
      case when coalesce(b.total, 0) <= 0 then 'Ítem sin existencias'
        else 'Stock bajo el mínimo' end,
      i.name || ' · Disponible físico: ' || coalesce(b.total, 0)::text ||
        ' ' || u.symbol || ' · Mínimo: ' || i.minimum_stock::text || ' ' || u.symbol,
      '/inventory/stock', v_today
    from public.items i
    join public.units u on u.company_id = i.company_id and u.id = i.unit_id
    left join lateral (
      select sum(sb.quantity) as total from public.stock_balances sb
      where sb.company_id = i.company_id and sb.item_id = i.id
    ) b on true
    where i.company_id = p_company and i.active
      and i.item_type in ('raw_material', 'semi_finished', 'consumable', 'finished_product')
      and i.minimum_stock > 0 and coalesce(b.total, 0) < i.minimum_stock;
  end if;
end;
$$;

revoke execute on function public.erp_production_alerts(uuid) from public, anon;
grant execute on function public.erp_production_alerts(uuid) to authenticated;

-- Recuento total y próximas cinco órdenes sin cargar todos los consumos al inicio.
create function public.erp_production_dashboard(p_company uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null
    or not private.has_permission(p_company, 'production', 'read') then
    raise exception 'Sin acceso a producción' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'queued', (select count(*) from public.production_jobs
      where company_id = p_company and status = 'queued'),
    'in_progress', (select count(*) from public.production_jobs
      where company_id = p_company and status = 'in_progress'),
    'overdue', (select count(*) from public.production_jobs
      where company_id = p_company and status in ('queued', 'in_progress')
        and due_on < v_today),
    'next', (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb)
      from (select j.id, j.status, j.due_on, j.note,
        j.planned_quantity, i.name as product_name
        from public.production_jobs j
        join public.items i on i.company_id = j.company_id and i.id = j.product_id
        where j.company_id = p_company and j.status in ('queued', 'in_progress')
        order by j.due_on asc nulls last, j.created_at asc
        limit 5) p)
  );
end;
$$;
revoke execute on function public.erp_production_dashboard(uuid) from public, anon;
grant execute on function public.erp_production_dashboard(uuid) to authenticated;

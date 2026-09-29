-- Dromux Producción · ubicación de reservas, versión 026.
-- Requiere 025. Las ubicaciones se recalculan dentro de la transacción.

create table public.production_reservation_locations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  job_id uuid not null,
  component_id uuid not null,
  warehouse_id uuid not null,
  lot_id uuid,
  lot_code text,
  quantity numeric(18,6) not null check(quantity > 0),
  foreign key(company_id,job_id,component_id)
    references public.production_job_reservations(company_id,job_id,component_id),
  foreign key(company_id,warehouse_id)
    references public.warehouses(company_id,id),
  foreign key(lot_id) references public.stock_lots(id),
  check((lot_id is null) = (lot_code is null))
);
create index production_reservation_location_slot
  on public.production_reservation_locations(company_id,component_id,warehouse_id,lot_id);
create index production_reservation_location_job
  on public.production_reservation_locations(company_id,job_id);
alter table public.production_reservation_locations enable row level security;
create policy reservation_locations_read on public.production_reservation_locations
  for select to authenticated using (
    (select private.has_permission(company_id,'production','read'))
    and (select private.has_permission(company_id,'stock','read'))
  );
revoke all on public.production_reservation_locations from public,anon,authenticated;
grant select on public.production_reservation_locations to authenticated;

create or replace function private.rebalance_production_reservations(p_company uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_row record; v_slot record;
  v_needed numeric; v_remaining numeric; v_reserved numeric;
  v_taken numeric; v_assign numeric;
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('production-reservations:'||p_company::text,0));
  delete from public.production_reservation_locations where company_id=p_company;
  for v_row in
    select r.company_id,r.job_id,r.component_id,r.required_quantity,j.status
    from public.production_job_reservations r
    join public.production_jobs j on j.company_id=r.company_id and j.id=r.job_id
    where r.company_id=p_company
    order by r.component_id,j.due_on asc nulls last,j.created_at,j.id
  loop
    v_reserved:=0;
    if v_row.status in ('queued','in_progress') then
      select coalesce(sum(case when e.kind='issue' then e.quantity else -e.quantity end),0)
        into v_needed from public.production_job_events e
        where e.company_id=p_company and e.job_id=v_row.job_id
          and e.component_id=v_row.component_id;
      v_remaining:=greatest(0,v_row.required_quantity-v_needed);
      for v_slot in
        select slots.warehouse_id,slots.lot_id,slots.lot_code,slots.quantity
        from (
          select b.warehouse_id,null::uuid lot_id,null::text lot_code,
            null::date expires_on,b.quantity,w.name warehouse_name
          from public.stock_balances b
          join public.items i on i.company_id=b.company_id and i.id=b.item_id
          join public.warehouses w on w.company_id=b.company_id
            and w.id=b.warehouse_id and w.active
          where b.company_id=p_company and b.item_id=v_row.component_id
            and not i.track_lots and b.quantity>0
          union all
          select lb.warehouse_id,lb.lot_id,l.code,l.expires_on,
            lb.quantity,w.name
          from public.stock_lot_balances lb
          join public.items i on i.company_id=lb.company_id and i.id=lb.item_id
          join public.stock_lots l on l.company_id=lb.company_id
            and l.item_id=lb.item_id and l.id=lb.lot_id
          join public.warehouses w on w.company_id=lb.company_id
            and w.id=lb.warehouse_id and w.active
          where lb.company_id=p_company and lb.item_id=v_row.component_id
            and i.track_lots and lb.quantity>0
            and (l.expires_on is null or l.expires_on>=v_today)
        ) slots
        order by slots.expires_on asc nulls last,slots.warehouse_name,
          slots.warehouse_id,slots.lot_code nulls last
      loop
        exit when v_remaining<=0;
        select coalesce(sum(a.quantity),0) into v_taken
          from public.production_reservation_locations a
          where a.company_id=p_company and a.component_id=v_row.component_id
            and a.warehouse_id=v_slot.warehouse_id
            and a.lot_id is not distinct from v_slot.lot_id;
        v_assign:=least(v_remaining,greatest(0,v_slot.quantity-v_taken));
        if v_assign>0 then
          insert into public.production_reservation_locations(
            company_id,job_id,component_id,warehouse_id,lot_id,lot_code,quantity)
          values(p_company,v_row.job_id,v_row.component_id,v_slot.warehouse_id,
            v_slot.lot_id,v_slot.lot_code,v_assign);
          v_reserved:=v_reserved+v_assign;
          v_remaining:=v_remaining-v_assign;
        end if;
      end loop;
    end if;
    update public.production_job_reservations
      set reserved_quantity=v_reserved,updated_at=clock_timestamp()
      where company_id=p_company and job_id=v_row.job_id
        and component_id=v_row.component_id
        and reserved_quantity is distinct from v_reserved;
  end loop;
end;
$$;

-- Backfill de ubicaciones para todas las órdenes ya abiertas.
do $$ declare v_company record; begin
  for v_company in select distinct company_id from public.production_job_reservations loop
    perform private.rebalance_production_reservations(v_company.company_id);
  end loop;
end $$;

-- Misma función pública; añade control del depósito y lote de origen.
create or replace function public.post_stock_operation(
  p_company uuid,p_item uuid,p_warehouse uuid,p_to_warehouse uuid,
  p_kind text,p_quantity numeric,p_note text,p_request_id uuid,
  p_lot_code text,p_expires_on date
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_reserved numeric; v_own numeric; v_usable numeric;
  v_slot_reserved numeric; v_slot_own numeric; v_slot_physical numeric;
  v_track boolean; v_lot uuid; v_expiry date;
  v_job uuid; v_operation uuid;
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Sin permiso para registrar movimientos' using errcode='42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('production-reservations:'||p_company::text,0));
  if p_request_id is not null and exists (
    select 1 from public.stock_operations o
    where o.company_id=p_company and o.request_id=p_request_id
  ) then
    return private.post_stock_operation(p_company,p_item,p_warehouse,
      p_to_warehouse,p_kind,p_quantity,p_note,p_request_id,p_lot_code,p_expires_on);
  end if;
  perform private.rebalance_production_reservations(p_company);
  if p_kind in ('issue','transfer') and p_item is not null
    and p_warehouse is not null and p_quantity>0 then
    v_job:=nullif(pg_catalog.current_setting('dromux.production_job',true),'')::uuid;
    if v_job is not null and p_kind='issue' then
      perform 1 from public.production_jobs j where j.company_id=p_company
        and j.id=v_job and j.status in ('queued','in_progress');
      if not found then raise exception 'Orden de fabricación no activa'; end if;
    end if;
    select i.track_lots into v_track from public.items i
      where i.company_id=p_company and i.id=p_item;
    if v_track then
      select l.id,l.expires_on into v_lot,v_expiry from public.stock_lots l
        where l.company_id=p_company and l.item_id=p_item
          and lower(l.code)=lower(btrim(p_lot_code));
      if v_lot is null then raise exception 'Elegí un lote existente'; end if;
      if p_kind='issue' and v_expiry<v_today then
        raise exception 'El lote está vencido. Elegí uno vigente'; end if;
      select coalesce(b.quantity,0) into v_slot_physical
        from public.stock_lot_balances b where b.company_id=p_company
          and b.item_id=p_item and b.warehouse_id=p_warehouse and b.lot_id=v_lot;
    else
      select coalesce(b.quantity,0) into v_slot_physical
        from public.stock_balances b where b.company_id=p_company
          and b.item_id=p_item and b.warehouse_id=p_warehouse;
    end if;
    v_slot_physical:=coalesce(v_slot_physical,0);
    select coalesce(sum(a.quantity),0),
      coalesce(sum(a.quantity) filter(where a.job_id=v_job),0)
      into v_slot_reserved,v_slot_own
      from public.production_reservation_locations a
      join public.production_jobs j on j.company_id=a.company_id and j.id=a.job_id
      where a.company_id=p_company and a.component_id=p_item
        and a.warehouse_id=p_warehouse
        and a.lot_id is not distinct from v_lot
        and j.status in ('queued','in_progress');
    if p_quantity>greatest(0,v_slot_physical-v_slot_reserved
      +case when p_kind='issue' then v_slot_own else 0 end) then
      raise exception 'Stock libre insuficiente en el depósito y lote elegidos';
    end if;
    if p_kind='issue' then
      select coalesce(sum(a.quantity),0),
        coalesce(sum(a.quantity) filter(where a.job_id=v_job),0)
        into v_reserved,v_own from public.production_reservation_locations a
        join public.production_jobs j on j.company_id=a.company_id and j.id=a.job_id
        where a.company_id=p_company and a.component_id=p_item
          and j.status in ('queued','in_progress');
      if v_track then
        select coalesce(sum(lb.quantity),0) into v_usable
          from public.stock_lot_balances lb
          join public.warehouses w on w.company_id=lb.company_id
            and w.id=lb.warehouse_id and w.active
          join public.stock_lots l on l.company_id=lb.company_id
            and l.item_id=lb.item_id and l.id=lb.lot_id
          where lb.company_id=p_company and lb.item_id=p_item
            and (l.expires_on is null or l.expires_on>=v_today);
      else
        select coalesce(sum(b.quantity),0) into v_usable
          from public.stock_balances b
          join public.warehouses w on w.company_id=b.company_id
            and w.id=b.warehouse_id and w.active
          where b.company_id=p_company and b.item_id=p_item;
      end if;
      if p_quantity>greatest(0,v_usable-v_reserved+v_own) then
        raise exception 'Stock comprometido para fabricación: saldo libre insuficiente';
      end if;
    end if;
  end if;
  v_operation:=private.post_stock_operation(p_company,p_item,p_warehouse,
    p_to_warehouse,p_kind,p_quantity,p_note,p_request_id,p_lot_code,p_expires_on);
  if p_kind in ('receipt','issue','transfer') then
    perform private.rebalance_production_reservations(p_company);
  end if;
  return v_operation;
end;
$$;

-- Detalle de ubicaciones y stock utilizable (excluye lotes vencidos).
create or replace function public.erp_can_manufacture(
  p_company uuid,p_product uuid,p_quantity numeric
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_formula public.production_formulas%rowtype; v_lines jsonb;
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null
    or not private.has_permission(p_company,'production','read')
    or not private.has_permission(p_company,'stock','read') then
    raise exception 'Necesitás acceso a producción y stock' using errcode='42501';
  end if;
  if p_product is null or p_quantity is null or p_quantity<=0
    or p_quantity>=1000000000000 or p_quantity<>round(p_quantity,6) then
    raise exception 'Indicá una cantidad válida con hasta seis decimales';
  end if;
  select * into v_formula from public.production_formulas
    where company_id=p_company and product_id=p_product;
  if not found then raise exception 'El producto no tiene fórmula'; end if;
  select jsonb_agg(jsonb_build_object(
    'item_id',n.item_id,'item_code',n.item_code,'item_name',n.item_name,
    'item_type',n.item_type,'unit_symbol',n.unit_symbol,
    'required',n.required,'physical',coalesce(b.physical,0),
    'usable',coalesce(sl.usable,0),'reserved',coalesce(r.reserved,0),
    'free',greatest(0,coalesce(sl.usable,0)-coalesce(r.reserved,0)),
    'locations',coalesce(sl.locations,'[]'::jsonb)) order by n.item_name)
    into v_lines
  from (
    select i.company_id,i.id item_id,i.code item_code,i.name item_name,
      i.item_type,i.track_lots,u.symbol unit_symbol,
      round(sum(l.quantity)*p_quantity/v_formula.batch_quantity,6) required
    from public.production_formula_lines l
    join public.items i on i.company_id=l.company_id and i.id=l.component_id
    join public.units u on u.company_id=i.company_id and u.id=i.unit_id
    where l.company_id=p_company and l.product_id=p_product
    group by i.company_id,i.id,u.symbol
  ) n
  left join lateral (
    select sum(b.quantity) physical from public.stock_balances b
    where b.company_id=p_company and b.item_id=n.item_id
  ) b on true
  left join lateral (
    select sum(a.quantity) reserved from public.production_reservation_locations a
    join public.production_jobs j on j.company_id=a.company_id and j.id=a.job_id
    where a.company_id=p_company and a.component_id=n.item_id
      and j.status in ('queued','in_progress')
  ) r on true
  left join lateral (
    select sum(s.quantity) usable,
      jsonb_agg(jsonb_build_object(
        'warehouse_id',s.warehouse_id,'warehouse_name',s.warehouse_name,
        'lot_code',s.lot_code,'expires_on',s.expires_on,
        'physical',s.quantity,'reserved',coalesce(ar.reserved,0),
        'free',greatest(0,s.quantity-coalesce(ar.reserved,0)))
        order by s.expires_on asc nulls last,s.warehouse_name,s.lot_code) locations
    from (
      select sb.warehouse_id,w.name warehouse_name,
        null::uuid lot_id,null::text lot_code,null::date expires_on,sb.quantity
      from public.stock_balances sb
      join public.warehouses w on w.company_id=sb.company_id
        and w.id=sb.warehouse_id and w.active
      where sb.company_id=p_company and sb.item_id=n.item_id
        and not n.track_lots and sb.quantity>0
      union all
      select lb.warehouse_id,w.name,lb.lot_id,l.code,l.expires_on,lb.quantity
      from public.stock_lot_balances lb
      join public.stock_lots l on l.company_id=lb.company_id
        and l.item_id=lb.item_id and l.id=lb.lot_id
      join public.warehouses w on w.company_id=lb.company_id
        and w.id=lb.warehouse_id and w.active
      where lb.company_id=p_company and lb.item_id=n.item_id
        and n.track_lots and lb.quantity>0
        and (l.expires_on is null or l.expires_on>=v_today)
    ) s
    left join lateral (
      select sum(a.quantity) reserved from public.production_reservation_locations a
      join public.production_jobs j on j.company_id=a.company_id and j.id=a.job_id
      where a.company_id=p_company and a.component_id=n.item_id
        and a.warehouse_id=s.warehouse_id
        and a.lot_id is not distinct from s.lot_id
        and j.status in ('queued','in_progress')
    ) ar on true
  ) sl on true;
  return jsonb_build_object('product_id',p_product,'quantity',p_quantity,
    'formula_version',v_formula.version,'lines',coalesce(v_lines,'[]'::jsonb));
end;
$$;

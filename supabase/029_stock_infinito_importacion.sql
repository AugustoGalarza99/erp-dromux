-- Dromux 029 · stock infinito e importación por lote.
-- Ejecutar después de 028. Cada lote de importación es una transacción.

alter table public.items add column infinite_stock boolean not null default false;
alter table public.items add constraint items_infinite_rules
  check (not infinite_stock or (not track_lots and minimum_stock=0));
grant insert (infinite_stock), update (infinite_stock) on public.items to authenticated;

create function private.check_infinite_stock_change() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.infinite_stock and (tg_op='INSERT' or not old.infinite_stock) then
    if exists (select 1 from public.stock_balances b where b.company_id=new.company_id
      and b.item_id=new.id and b.quantity<>0) then
      raise exception 'Dejá el saldo físico en cero antes de activar stock infinito';
    end if;
    if exists (select 1 from public.production_job_reservations r
      join public.production_jobs j on j.company_id=r.company_id and j.id=r.job_id
      where r.company_id=new.company_id and r.component_id=new.id
        and j.status in ('queued','in_progress')) then
      raise exception 'Terminá las órdenes pendientes antes de activar stock infinito';
    end if;
  end if;
  if tg_op='UPDATE' and old.infinite_stock and not new.infinite_stock then
    if exists (select 1 from public.production_job_reservations r
      join public.production_jobs j on j.company_id=r.company_id and j.id=r.job_id
      where r.company_id=new.company_id and r.component_id=new.id
        and j.status in ('queued','in_progress')) then
      raise exception 'Terminá las órdenes pendientes antes de cambiar el modo de stock';
    end if;
  end if;
  return new;
end; $$;
create trigger items_infinite_transition before insert or update of infinite_stock
  on public.items for each row execute function private.check_infinite_stock_change();
revoke execute on function private.check_infinite_stock_change() from public,anon,authenticated;

create function private.prevent_infinite_physical_movement() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_infinite boolean;
begin
  select i.infinite_stock into v_infinite from public.items i
    where i.company_id=new.company_id and i.id=new.item_id for share;
  if coalesce(v_infinite,false) then
    raise exception 'El ítem tiene stock infinito; no registra movimientos físicos';
  end if;
  return new;
end; $$;
create trigger stock_movements_infinite_guard before insert on public.stock_movements
  for each row execute function private.prevent_infinite_physical_movement();
revoke execute on function private.prevent_infinite_physical_movement() from public,anon,authenticated;

-- Una operación virtual conserva trazabilidad y no crea saldos ni movimientos físicos.
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
    if v_row.status in ('queued','in_progress') and not exists (
      select 1 from public.items i where i.company_id=p_company
        and i.id=v_row.component_id and i.infinite_stock) then
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


create or replace function public.post_stock_operation(
  p_company uuid,p_item uuid,p_warehouse uuid,p_to_warehouse uuid,
  p_kind text,p_quantity numeric,p_note text,p_request_id uuid,
  p_lot_code text,p_expires_on date
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_reserved numeric; v_own numeric; v_usable numeric;
  v_slot_reserved numeric; v_slot_own numeric; v_slot_physical numeric;
  v_track boolean; v_lot uuid; v_expiry date;
  v_job uuid; v_operation uuid; v_infinite boolean; v_existing public.stock_operations%rowtype;
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
  select i.infinite_stock into v_infinite from public.items i
    where i.company_id=p_company and i.id=p_item and i.active for share;
  if coalesce(v_infinite,false) then
    if p_request_id is null or p_warehouse is null or p_kind not in ('receipt','issue')
      or p_to_warehouse is not null or p_quantity is null or p_quantity<=0
      or p_quantity>=1000000000000 or p_quantity<>round(p_quantity,6)
      or length(btrim(coalesce(p_note,''))) not between 3 and 500
      or nullif(btrim(coalesce(p_lot_code,'')),'') is not null
      or p_expires_on is not null then
      raise exception 'Movimiento inválido para un ítem de stock infinito';
    end if;
    perform 1 from public.companies c where c.id=p_company and c.active for share;
    if not found then raise exception 'La empresa está suspendida'; end if;
    perform 1 from public.warehouses w where w.company_id=p_company
      and w.id=p_warehouse and w.active for share;
    if not found then raise exception 'Elegí un depósito activo'; end if;
    v_job:=nullif(pg_catalog.current_setting('dromux.production_job',true),'')::uuid;
    if v_job is not null and p_kind='issue' and not exists (
      select 1 from public.production_jobs j where j.company_id=p_company
        and j.id=v_job and j.status in ('queued','in_progress')) then
      raise exception 'Orden de fabricación no activa';
    end if;
    insert into public.stock_operations(company_id,request_id,item_id,warehouse_id,
      kind,quantity,note,actor_id)
    values(p_company,p_request_id,p_item,p_warehouse,p_kind,p_quantity,btrim(p_note),auth.uid())
    on conflict(company_id,request_id) do nothing returning id into v_operation;
    if v_operation is null then
      select * into v_existing from public.stock_operations o
        where o.company_id=p_company and o.request_id=p_request_id;
      if v_existing.item_id is distinct from p_item
        or v_existing.warehouse_id is distinct from p_warehouse
        or v_existing.to_warehouse_id is not null or v_existing.kind<>p_kind
        or v_existing.quantity<>p_quantity or v_existing.note<>btrim(p_note)
        or v_existing.actor_id<>auth.uid() then
        raise exception 'Esta solicitud ya se usó con otros datos';
      end if;
      return v_existing.id;
    end if;
    return v_operation;
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
    'required',n.required,'infinite_stock',n.infinite_stock,'physical',coalesce(b.physical,0),
    'usable',coalesce(sl.usable,0),'reserved',coalesce(r.reserved,0),
    'free',case when n.infinite_stock then n.required else greatest(0,coalesce(sl.usable,0)-coalesce(r.reserved,0)) end,
    'locations',coalesce(sl.locations,'[]'::jsonb)) order by n.item_name)
    into v_lines
  from (
    select i.company_id,i.id item_id,i.code item_code,i.name item_name,
      i.item_type,i.track_lots,i.infinite_stock,u.symbol unit_symbol,
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
create or replace function public.erp_replenishment_forecast(p_company uuid)
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
    where i.company_id=p_company and i.active and not i.infinite_stock
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

-- Importa sólo ítems nuevos; cualquier error revierte el lote completo.
create function public.import_items(p_company uuid,p_rows jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare v_row jsonb; v_index integer:=0; v_unit uuid; v_category uuid;
  v_code text; v_name text; v_type text; v_barcode text;
  v_cost numeric; v_price numeric; v_min numeric; v_lots boolean;
  v_infinite boolean; v_active boolean; v_description text;
begin
  if auth.uid() is null or not private.has_permission(p_company,'items','insert') then
    raise exception 'No tenés permiso para importar ítems' using errcode='42501';
  end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa no está activa'; end if;
  if p_rows is null or jsonb_typeof(p_rows)<>'array'
    or jsonb_array_length(p_rows) not between 1 and 200 then
    raise exception 'Importá entre 1 y 200 ítems por archivo';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('import-items:'||p_company::text,0));
  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_index:=v_index+1;
    if jsonb_typeof(v_row)<>'object' then
      raise exception 'Fila %: formato inválido',v_index+1;
    end if;
    v_code:=btrim(coalesce(v_row->>'codigo',''));
    v_name:=btrim(coalesce(v_row->>'nombre',''));
    v_type:=btrim(coalesce(v_row->>'tipo',''));
    v_barcode:=nullif(btrim(coalesce(v_row->>'codigo_barras','')),'');
    v_description:=btrim(coalesce(v_row->>'descripcion',''));
    if v_code !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$'
      or length(v_name) not between 2 and 160
      or v_type not in ('raw_material','semi_finished','finished_product','consumable')
      or length(v_description)>1500
      or (v_barcode is not null and length(v_barcode) not between 4 and 80) then
      raise exception 'Fila %: revisá código, nombre, tipo, descripción y código de barras',v_index+1;
    end if;
    if coalesce(v_row->>'stock_minimo','') !~ '^\d+(\.\d{1,6})?$'
      or coalesce(v_row->>'costo_referencia_ars','') !~ '^\d+(\.\d{1,2})?$'
      and nullif(v_row->>'costo_referencia_ars','') is not null
      or coalesce(v_row->>'precio_venta_ars','') !~ '^\d+(\.\d{1,2})?$'
      and nullif(v_row->>'precio_venta_ars','') is not null then
      raise exception 'Fila %: números inválidos (usá punto decimal)',v_index+1;
    end if;
    v_min:=(v_row->>'stock_minimo')::numeric;
    v_cost:=nullif(v_row->>'costo_referencia_ars','')::numeric;
    v_price:=nullif(v_row->>'precio_venta_ars','')::numeric;
    if v_min>=1000000000000 or coalesce(v_cost,0)>=1000000000000
      or coalesce(v_price,0)>=1000000000000 then
      raise exception 'Fila %: importe o cantidad fuera de rango',v_index+1;
    end if;
    if coalesce(v_row->>'seguir_lotes','') not in ('true','false')
      or coalesce(v_row->>'stock_infinito','') not in ('true','false')
      or coalesce(v_row->>'activo','') not in ('true','false') then
      raise exception 'Fila %: usá SI o NO en las columnas de opciones',v_index+1;
    end if;
    v_lots:=(v_row->>'seguir_lotes')::boolean;
    v_infinite:=(v_row->>'stock_infinito')::boolean;
    v_active:=(v_row->>'activo')::boolean;
    if v_infinite and (v_lots or v_min<>0) then
      raise exception 'Fila %: stock infinito requiere sin lotes y stock mínimo cero',v_index+1;
    end if;
    if v_price is not null and (v_type<>'finished_product'
      or private.get_user_role(p_company)<>'admin'
      or not private.has_permission(p_company,'sales','update')) then
      raise exception 'Fila %: solo un administrador puede cargar precios de productos terminados',v_index+1;
    end if;
    if v_type='raw_material' and v_cost is null then
      raise exception 'Fila %: la materia prima necesita costo de referencia',v_index+1;
    end if;
    select u.id into v_unit from public.units u
      where u.company_id=p_company and u.active
        and lower(u.code)=lower(btrim(coalesce(v_row->>'unidad_codigo','')));
    if v_unit is null then
      raise exception 'Fila %: la unidad no existe o está inactiva',v_index+1;
    end if;
    v_category:=null;
    if nullif(btrim(coalesce(v_row->>'categoria_codigo','')),'') is not null then
      select c.id into v_category from public.item_categories c
        where c.company_id=p_company and c.active
          and lower(c.code)=lower(btrim(v_row->>'categoria_codigo'));
      if v_category is null then
        raise exception 'Fila %: la categoría no existe o está inactiva',v_index+1;
      end if;
    end if;
    if exists (select 1 from public.items i where i.company_id=p_company
      and lower(i.code)=lower(v_code)) then
      raise exception 'Fila %: el código % ya existe o está repetido',v_index+1,v_code;
    end if;
    if v_barcode is not null and exists (select 1 from public.items i
      where i.company_id=p_company and i.barcode=v_barcode) then
      raise exception 'Fila %: el código de barras % ya existe o está repetido',v_index+1,v_barcode;
    end if;
    insert into public.items(company_id,code,name,item_type,category_id,unit_id,
      barcode,description,minimum_stock,track_lots,infinite_stock,
      reference_unit_cost,sale_unit_price,active)
    values(p_company,v_code,v_name,v_type,v_category,v_unit,v_barcode,
      v_description,v_min,v_lots,v_infinite,v_cost,v_price,v_active);
  end loop;
  return v_index;
end; $$;
revoke all on function public.import_items(uuid,jsonb) from public,anon;
grant execute on function public.import_items(uuid,jsonb) to authenticated;

create or replace function public.erp_production_alerts(p_company uuid)
returns table (
  alert_key text,fingerprint text,severity text,title text,
  detail text,destination text,occurred_on date
) language plpgsql stable security definer set search_path = '' as $$
declare v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null or not private.has_permission(p_company,'dashboard','read') then
    raise exception 'Sin acceso al centro operativo' using errcode='42501';
  end if;
  return query select base.alert_key,base.fingerprint,base.severity,
    base.title,base.detail,base.destination,base.occurred_on
    from private.erp_production_alerts(p_company) base;
  if private.has_permission(p_company,'production','read')
    and private.has_permission(p_company,'stock','read') then
    return query
    select 'reservation:'||j.id::text||':'||r.component_id::text,
      greatest(0,r.required_quantity-coalesce(e.consumed,0)-r.reserved_quantity)::text
        ||':'||coalesce(j.due_on::text,''),
      case when j.due_on <= v_today+3 then 'critical' else 'warning' end,
      'Faltan insumos para una orden',
      i.name||' · Faltan '||
        greatest(0,r.required_quantity-coalesce(e.consumed,0)-r.reserved_quantity)::text
        ||' '||u.symbol||' para '||p.name,
      '/production/orders?job='||j.id::text,
      coalesce(j.due_on,v_today)
    from public.production_job_reservations r
    join public.production_jobs j on j.company_id=r.company_id and j.id=r.job_id
    join public.items i on i.company_id=r.company_id and i.id=r.component_id
    join public.items p on p.company_id=j.company_id and p.id=j.product_id
    join public.units u on u.company_id=i.company_id and u.id=i.unit_id
    left join lateral (
      select sum(case when ev.kind='issue' then ev.quantity else -ev.quantity end) consumed
      from public.production_job_events ev
      where ev.company_id=r.company_id and ev.job_id=r.job_id
        and ev.component_id=r.component_id
    ) e on true
    where r.company_id=p_company and not i.infinite_stock
      and j.status in ('queued','in_progress')
      and r.required_quantity-coalesce(e.consumed,0)>r.reserved_quantity;
  end if;
end;
$$;

-- Permite comenzar a seguir lotes con o sin stock actual.
-- Si ya hay stock, crea un lote inicial por depósito y audita la apertura.
-- Ejecutar una vez después de 006.

create table public.stock_lot_openings (
  company_id uuid not null,
  item_id uuid not null,
  warehouse_id uuid not null,
  lot_id uuid not null,
  quantity numeric(18, 6) not null check (quantity > 0),
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  primary key (company_id, item_id, warehouse_id),
  constraint stock_lot_openings_lot_fk foreign key (company_id, item_id, lot_id)
    references public.stock_lots(company_id, item_id, id),
  constraint stock_lot_openings_warehouse_fk foreign key (company_id, warehouse_id)
    references public.warehouses(company_id, id)
);

alter table public.stock_lot_openings enable row level security;
create policy stock_lot_openings_read on public.stock_lot_openings
  for select to authenticated
  using ((select private.has_permission(company_id, 'stock', 'read')));
revoke all on public.stock_lot_openings from anon, authenticated;
grant select on public.stock_lot_openings to authenticated;
create trigger stock_lot_openings_immutable
before update or delete on public.stock_lot_openings for each row
execute function private.reject_stock_history_mutation();

create or replace function private.prevent_late_lot_tracking()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.track_lots and not old.track_lots and exists (
    select 1 from public.stock_balances b
    where b.company_id = old.company_id and b.item_id = old.id
      and b.quantity <> coalesce((
        select sum(lb.quantity) from public.stock_lot_balances lb
        where lb.company_id = b.company_id and lb.item_id = b.item_id
          and lb.warehouse_id = b.warehouse_id
      ), 0)
  ) then
    raise exception 'El ítem tiene stock sin lotes: activá la trazabilidad desde la ficha';
  end if;

  if old.track_lots and not new.track_lots and exists (
    select 1 from public.stock_lots l
    where l.company_id = old.company_id and l.item_id = old.id
  ) then
    raise exception 'No se puede desactivar lotes en un ítem que ya tiene lotes';
  end if;

  return new;
end;
$$;

revoke execute on function private.prevent_late_lot_tracking()
  from public, anon, authenticated;

create function public.activate_item_lots(p_company uuid, p_item uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_item public.items%rowtype;
  v_balance record;
  v_lot_id uuid;
begin
  if v_actor is null
     or not private.has_permission(p_company, 'items', 'update')
     or not private.has_permission(p_company, 'stock', 'insert') then
    raise exception 'Sin permiso para activar lotes' using errcode = '42501';
  end if;

  perform 1 from public.companies c
  where c.id = p_company and c.active for share;
  if not found then
    raise exception 'La empresa no está activa' using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_company::text || ':' || p_item::text, 0)
  );

  select * into v_item from public.items i
  where i.company_id = p_company and i.id = p_item and i.active for update;
  if not found then raise exception 'Ítem inexistente o inactivo'; end if;
  if v_item.track_lots then return; end if;

  if exists (
    select 1 from public.stock_lots l
    where l.company_id = p_company and l.item_id = p_item
  ) then
    raise exception 'El ítem ya tiene lotes registrados';
  end if;

  for v_balance in
    select b.warehouse_id, b.quantity, w.code as warehouse_code
    from public.stock_balances b
    join public.warehouses w
      on w.company_id = b.company_id and w.id = b.warehouse_id
    where b.company_id = p_company and b.item_id = p_item
      and b.quantity > 0
    order by b.warehouse_id
  loop
    insert into public.stock_lots(company_id, item_id, code)
    values (
      p_company, p_item,
      'Inicial ' || left(v_balance.warehouse_code, 24)
        || ' ' || v_balance.warehouse_id::text
    ) returning id into v_lot_id;

    insert into public.stock_lot_balances(
      company_id, item_id, warehouse_id, lot_id, quantity
    ) values (p_company, p_item, v_balance.warehouse_id, v_lot_id,
      v_balance.quantity);

    insert into public.stock_lot_openings(
      company_id, item_id, warehouse_id, lot_id, quantity, actor_id
    ) values (p_company, p_item, v_balance.warehouse_id, v_lot_id,
      v_balance.quantity, v_actor);
  end loop;

  update public.items i set track_lots = true
  where i.company_id = p_company and i.id = p_item;
end;
$$;

revoke execute on function public.activate_item_lots(uuid, uuid) from public, anon;
grant execute on function public.activate_item_lots(uuid, uuid) to authenticated;

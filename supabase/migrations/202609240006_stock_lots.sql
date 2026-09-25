-- ERP Dromux: lotes y existencias por lote.
-- Ejecutar DESPUÉS de 202609240005_stock_movements.sql.

create table public.stock_lots (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  item_id uuid not null,
  code text not null check (length(btrim(code)) between 1 and 80 and code = btrim(code)),
  expires_on date,
  created_at timestamptz not null default now(),
  constraint stock_lots_company_item_id_unique unique (company_id, item_id, id),
  constraint stock_lots_item_fk foreign key (company_id, item_id)
    references public.items(company_id, id)
);

create unique index stock_lots_code_unique
  on public.stock_lots(company_id, item_id, lower(code));

create table public.stock_lot_balances (
  company_id uuid not null,
  item_id uuid not null,
  warehouse_id uuid not null,
  lot_id uuid not null,
  quantity numeric(18, 6) not null default 0 check (quantity >= 0),
  primary key (company_id, item_id, warehouse_id, lot_id),
  constraint stock_lot_balances_lot_fk foreign key (company_id, item_id, lot_id)
    references public.stock_lots(company_id, item_id, id),
  constraint stock_lot_balances_warehouse_fk foreign key (company_id, warehouse_id)
    references public.warehouses(company_id, id)
);

create index stock_lot_balances_available_idx
  on public.stock_lot_balances(company_id, item_id, warehouse_id)
  where quantity > 0;

alter table public.stock_operations
  add column lot_id uuid,
  add column lot_code text,
  add column lot_expires_on date,
  add constraint stock_operations_lot_fk foreign key (company_id, item_id, lot_id)
    references public.stock_lots(company_id, item_id, id);

alter table public.stock_movements
  add column lot_id uuid,
  add column lot_code text,
  add column lot_expires_on date,
  add constraint stock_movements_lot_fk foreign key (company_id, item_id, lot_id)
    references public.stock_lots(company_id, item_id, id);

alter table public.stock_lots enable row level security;
alter table public.stock_lot_balances enable row level security;

create policy stock_lots_read on public.stock_lots
  for select to authenticated
  using ((select private.has_permission(company_id, 'stock', 'read')));
create policy stock_lot_balances_read on public.stock_lot_balances
  for select to authenticated
  using ((select private.has_permission(company_id, 'stock', 'read')));

revoke all on public.stock_lots, public.stock_lot_balances from anon, authenticated;
grant select on public.stock_lots, public.stock_lot_balances to authenticated;

create trigger stock_lots_immutable
before update or delete on public.stock_lots for each row
execute function private.reject_stock_history_mutation();

-- Una vez usado un lote, no se puede abandonar su trazabilidad.
create or replace function private.prevent_late_lot_tracking()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.track_lots and not old.track_lots and exists (
    select 1 from public.stock_movements m
    where m.company_id = old.company_id and m.item_id = old.id
  ) then
    raise exception 'No se puede activar lotes en un ítem con historial de stock';
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

drop function public.post_stock_operation(
  uuid, uuid, uuid, uuid, text, numeric, text, uuid
);

create function public.post_stock_operation(
  p_company uuid,
  p_item uuid,
  p_warehouse uuid,
  p_to_warehouse uuid,
  p_kind text,
  p_quantity numeric,
  p_note text,
  p_request_id uuid,
  p_lot_code text,
  p_expires_on date
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_note text := btrim(p_note);
  v_code text := nullif(btrim(p_lot_code), '');
  v_operation uuid;
  v_existing public.stock_operations%rowtype;
  v_item_code text;
  v_unit_symbol text;
  v_track_lots boolean;
  v_warehouse_code text;
  v_target_code text;
  v_source_balance numeric(18, 6);
  v_target_balance numeric(18, 6);
  v_source_version bigint;
  v_target_version bigint;
  v_lot_id uuid;
  v_lot_code text;
  v_lot_expiry date;
  v_lot_balance numeric(18, 6);
begin
  if v_actor is null or not private.has_permission(p_company, 'stock', 'insert') then
    raise exception 'Sin permiso para registrar movimientos' using errcode = '42501';
  end if;
  if p_request_id is null or p_item is null or p_warehouse is null
     or p_kind is null or p_kind not in ('receipt', 'issue', 'transfer')
     or p_quantity is null or p_quantity <= 0 or p_quantity >= 1000000000000
     or round(p_quantity, 6) <> p_quantity
     or v_note is null or length(v_note) not between 3 and 500
     or (p_kind = 'transfer' and (p_to_warehouse is null
       or p_to_warehouse = p_warehouse))
     or (p_kind <> 'transfer' and p_to_warehouse is not null)
     or length(coalesce(p_lot_code, '')) > 80
     or (p_kind <> 'receipt' and p_expires_on is not null) then
    raise exception 'Datos de movimiento inválidos';
  end if;

  perform 1 from public.companies c
  where c.id = p_company and c.active for share;
  if not found or not private.has_permission(p_company, 'stock', 'insert') then
    raise exception 'La empresa no está activa o no tenés permiso' using errcode = '42501';
  end if;

  -- Serializa todos los movimientos del mismo ítem y sus cambios de saldo.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_company::text || ':' || p_item::text, 0)
  );

  insert into public.stock_operations (
    company_id, request_id, item_id, warehouse_id, to_warehouse_id,
    kind, quantity, note, actor_id, lot_code, lot_expires_on
  ) values (
    p_company, p_request_id, p_item, p_warehouse, p_to_warehouse,
    p_kind, p_quantity, v_note, v_actor, v_code, p_expires_on
  ) on conflict (company_id, request_id) do nothing
  returning id into v_operation;

  if v_operation is null then
    select * into v_existing from public.stock_operations
    where company_id = p_company and request_id = p_request_id;
    if v_existing.item_id is distinct from p_item
       or v_existing.warehouse_id is distinct from p_warehouse
       or v_existing.to_warehouse_id is distinct from p_to_warehouse
       or v_existing.kind is distinct from p_kind
       or v_existing.quantity is distinct from p_quantity
       or v_existing.note is distinct from v_note
       or v_existing.actor_id is distinct from v_actor
       or v_existing.lot_code is distinct from v_code
       or v_existing.lot_expires_on is distinct from p_expires_on then
      raise exception 'La solicitud ya se usó con otros datos';
    end if;
    return v_existing.id;
  end if;

  select i.code, u.symbol, i.track_lots
  into v_item_code, v_unit_symbol, v_track_lots
  from public.items i
  join public.units u on u.id = i.unit_id and u.company_id = i.company_id
  where i.id = p_item and i.company_id = p_company and i.active
  for share of i;
  if not found then raise exception 'Ítem inactivo o inexistente'; end if;

  if v_track_lots then
    if v_code is null then raise exception 'Indicá el lote del ítem'; end if;
    if p_kind = 'receipt' then
      insert into public.stock_lots(company_id, item_id, code, expires_on)
      values (p_company, p_item, v_code, p_expires_on)
      on conflict do nothing;
    end if;
    select l.id, l.code, l.expires_on
    into v_lot_id, v_lot_code, v_lot_expiry
    from public.stock_lots l
    where l.company_id = p_company and l.item_id = p_item
      and lower(l.code) = lower(v_code);
    if v_lot_id is null then raise exception 'Lote inexistente para este ítem'; end if;
    if p_kind = 'receipt' and v_lot_expiry is distinct from p_expires_on then
      raise exception 'La fecha de vencimiento no coincide con la del lote existente';
    end if;
  elsif v_code is not null or p_expires_on is not null then
    raise exception 'El ítem no utiliza lotes';
  end if;

  select w.code into v_warehouse_code from public.warehouses w
  where w.id = p_warehouse and w.company_id = p_company and w.active
  for share of w;
  if not found then raise exception 'Depósito inactivo o inexistente'; end if;
  if p_kind = 'transfer' then
    select w.code into v_target_code from public.warehouses w
    where w.id = p_to_warehouse and w.company_id = p_company and w.active
    for share of w;
    if not found then raise exception 'Depósito destino inactivo o inexistente'; end if;
  end if;

  insert into public.stock_balances(company_id, item_id, warehouse_id)
  values (p_company, p_item, p_warehouse)
  on conflict (company_id, item_id, warehouse_id) do nothing;
  select b.quantity into v_source_balance from public.stock_balances b
  where b.company_id = p_company and b.item_id = p_item
    and b.warehouse_id = p_warehouse for update;
  if p_kind in ('issue', 'transfer') and v_source_balance < p_quantity then
    raise exception 'Stock insuficiente en el depósito de origen';
  end if;

  if v_track_lots then
    insert into public.stock_lot_balances(company_id, item_id, warehouse_id, lot_id)
    values (p_company, p_item, p_warehouse, v_lot_id)
    on conflict (company_id, item_id, warehouse_id, lot_id) do nothing;
    select b.quantity into v_lot_balance from public.stock_lot_balances b
    where b.company_id = p_company and b.item_id = p_item
      and b.warehouse_id = p_warehouse and b.lot_id = v_lot_id for update;
    if p_kind in ('issue', 'transfer') and v_lot_balance < p_quantity then
      raise exception 'Stock insuficiente para el lote en el depósito de origen';
    end if;
    update public.stock_lot_balances b
    set quantity = b.quantity + case when p_kind = 'receipt'
      then p_quantity else -p_quantity end
    where b.company_id = p_company and b.item_id = p_item
      and b.warehouse_id = p_warehouse and b.lot_id = v_lot_id;
  end if;

  update public.stock_balances b
  set quantity = b.quantity + case when p_kind = 'receipt'
      then p_quantity else -p_quantity end,
      version = b.version + 1, updated_at = clock_timestamp()
  where b.company_id = p_company and b.item_id = p_item
    and b.warehouse_id = p_warehouse
  returning b.quantity, b.version into v_source_balance, v_source_version;

  insert into public.stock_movements (
    company_id, operation_id, line_no, item_id, warehouse_id, kind,
    delta, balance_after, balance_version, item_code, warehouse_code,
    unit_symbol, note, actor_id, lot_id, lot_code, lot_expires_on
  ) values (
    p_company, v_operation, 1, p_item, p_warehouse,
    case p_kind when 'receipt' then 'receipt'
      when 'issue' then 'issue' else 'transfer_out' end,
    case when p_kind = 'receipt' then p_quantity else -p_quantity end,
    v_source_balance, v_source_version, v_item_code, v_warehouse_code,
    v_unit_symbol, v_note, v_actor, v_lot_id, v_lot_code, v_lot_expiry
  );

  if p_kind = 'transfer' then
    insert into public.stock_balances(company_id, item_id, warehouse_id)
    values (p_company, p_item, p_to_warehouse)
    on conflict (company_id, item_id, warehouse_id) do nothing;
    update public.stock_balances b
    set quantity = b.quantity + p_quantity, version = b.version + 1,
        updated_at = clock_timestamp()
    where b.company_id = p_company and b.item_id = p_item
      and b.warehouse_id = p_to_warehouse
    returning b.quantity, b.version into v_target_balance, v_target_version;

    if v_track_lots then
      insert into public.stock_lot_balances(company_id, item_id, warehouse_id, lot_id)
      values (p_company, p_item, p_to_warehouse, v_lot_id)
      on conflict (company_id, item_id, warehouse_id, lot_id) do nothing;
      update public.stock_lot_balances b
      set quantity = b.quantity + p_quantity
      where b.company_id = p_company and b.item_id = p_item
        and b.warehouse_id = p_to_warehouse and b.lot_id = v_lot_id;
    end if;

    insert into public.stock_movements (
      company_id, operation_id, line_no, item_id, warehouse_id, kind,
      delta, balance_after, balance_version, item_code, warehouse_code,
      unit_symbol, note, actor_id, lot_id, lot_code, lot_expires_on
    ) values (
      p_company, v_operation, 2, p_item, p_to_warehouse, 'transfer_in',
      p_quantity, v_target_balance, v_target_version, v_item_code, v_target_code,
      v_unit_symbol, v_note, v_actor, v_lot_id, v_lot_code, v_lot_expiry
    );
  end if;

  if v_lot_id is not null then
    update public.stock_operations o set lot_id = v_lot_id
    where o.id = v_operation;
  end if;

  return v_operation;
end;
$$;

-- La función debe completar lot_id sin permitir modificaciones posteriores.
-- Reemplazamos el disparador por uno que sólo acepta este primer enlace.
create or replace function private.reject_stock_operation_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE'
     and old.lot_id is null and new.lot_id is not null
     and (to_jsonb(new) - 'lot_id') = (to_jsonb(old) - 'lot_id') then
    return new;
  end if;
  raise exception 'El historial de stock es inmutable; registrá una operación compensatoria';
end;
$$;

drop trigger stock_operations_immutable on public.stock_operations;
create trigger stock_operations_immutable
before update or delete on public.stock_operations for each row
execute function private.reject_stock_operation_mutation();
revoke execute on function private.reject_stock_operation_mutation()
  from public, anon, authenticated;

revoke execute on function public.post_stock_operation(
  uuid, uuid, uuid, uuid, text, numeric, text, uuid, text, date
) from public, anon;
grant execute on function public.post_stock_operation(
  uuid, uuid, uuid, uuid, text, numeric, text, uuid, text, date
) to authenticated;

create function public.stock_lot_options(
  p_company uuid, p_item uuid, p_warehouse uuid default null
) returns table (id uuid, code text, expires_on date, available numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.has_permission(p_company, 'stock', 'read') then
    raise exception 'Sin permiso para consultar lotes' using errcode = '42501';
  end if;
  return query
    select l.id, l.code, l.expires_on,
      coalesce(sum(b.quantity), 0)::numeric
    from public.stock_lots l
    left join public.stock_lot_balances b
      on b.company_id = l.company_id and b.item_id = l.item_id
      and b.lot_id = l.id
      and (p_warehouse is null or b.warehouse_id = p_warehouse)
    where l.company_id = p_company and l.item_id = p_item
    group by l.id
    order by l.expires_on nulls last, l.code
    limit 200;
end;
$$;

create function public.stock_lot_breakdown(
  p_company uuid, p_item uuid
) returns table (
  warehouse_id uuid, warehouse_name text, lot_code text,
  expires_on date, quantity numeric
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.has_permission(p_company, 'stock', 'read') then
    raise exception 'Sin permiso para consultar lotes' using errcode = '42501';
  end if;
  return query
    select b.warehouse_id, w.name, l.code, l.expires_on, b.quantity
    from public.stock_lot_balances b
    join public.stock_lots l on l.id = b.lot_id
      and l.company_id = b.company_id and l.item_id = b.item_id
    join public.warehouses w on w.id = b.warehouse_id
      and w.company_id = b.company_id
    where b.company_id = p_company and b.item_id = p_item and b.quantity > 0
    order by w.name, l.expires_on nulls last, l.code
    limit 500;
end;
$$;

revoke execute on function public.stock_lot_options(uuid, uuid, uuid),
  public.stock_lot_breakdown(uuid, uuid) from public, anon;
grant execute on function public.stock_lot_options(uuid, uuid, uuid),
  public.stock_lot_breakdown(uuid, uuid) to authenticated;

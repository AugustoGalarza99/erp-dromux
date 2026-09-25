-- ERP Dromux · recepción parcial de órdenes y entrada atómica en stock.
-- Ejecutar una vez después de 009.

alter table public.purchase_order_lines
  add column received_quantity numeric(18, 6) not null default 0
    check (received_quantity >= 0 and received_quantity <= quantity);

alter table public.purchase_orders
  drop constraint purchase_orders_status_check;
alter table public.purchase_orders
  add constraint purchase_orders_status_check
    check (status in ('open', 'partial', 'received', 'cancelled'));

create table public.purchase_receipts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  order_id uuid not null,
  request_id uuid not null,
  request_payload jsonb not null,
  note text not null check (length(btrim(note)) between 3 and 430),
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  constraint purchase_receipts_company_id_unique unique (company_id, id),
  constraint purchase_receipts_request_unique unique (company_id, request_id),
  constraint purchase_receipts_order_fk foreign key (company_id, order_id)
    references public.purchase_orders(company_id, id)
);

create index purchase_receipts_order_date_idx
  on public.purchase_receipts(company_id, order_id, created_at desc);

create table public.purchase_receipt_lines (
  company_id uuid not null,
  receipt_id uuid not null,
  order_id uuid not null,
  line_no smallint not null,
  item_id uuid not null,
  warehouse_id uuid not null,
  warehouse_code text not null,
  quantity numeric(18, 6) not null check (quantity > 0),
  unit_price numeric(18, 2) not null check (unit_price >= 0),
  lot_code text,
  expires_on date,
  stock_operation_id uuid not null,
  primary key (company_id, receipt_id, line_no),
  constraint receipt_lines_receipt_fk foreign key (company_id, receipt_id)
    references public.purchase_receipts(company_id, id),
  constraint receipt_lines_order_fk foreign key (company_id, order_id, line_no)
    references public.purchase_order_lines(company_id, order_id, line_no),
  constraint receipt_lines_item_fk foreign key (company_id, item_id)
    references public.items(company_id, id),
  constraint receipt_lines_warehouse_fk foreign key (company_id, warehouse_id)
    references public.warehouses(company_id, id),
  constraint receipt_lines_stock_fk foreign key (company_id, stock_operation_id)
    references public.stock_operations(company_id, id)
);

alter table public.purchase_receipts enable row level security;
alter table public.purchase_receipt_lines enable row level security;
create policy purchase_receipts_read on public.purchase_receipts
  for select to authenticated
  using ((select private.has_permission(company_id, 'purchases', 'read')));
create policy purchase_receipt_lines_read on public.purchase_receipt_lines
  for select to authenticated
  using ((select private.has_permission(company_id, 'purchases', 'read')));
revoke all on public.purchase_receipts, public.purchase_receipt_lines
  from anon, authenticated;
grant select on public.purchase_receipts, public.purchase_receipt_lines
  to authenticated;

create trigger purchase_receipts_immutable
before update or delete on public.purchase_receipts for each row
execute function private.reject_stock_history_mutation();
create trigger purchase_receipt_lines_immutable
before update or delete on public.purchase_receipt_lines for each row
execute function private.reject_stock_history_mutation();

create function public.receive_purchase_order(
  p_company uuid,
  p_order uuid,
  p_request_id uuid,
  p_note text,
  p_lines jsonb
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_note text := btrim(p_note);
  v_order public.purchase_orders%rowtype;
  v_existing public.purchase_receipts%rowtype;
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
     or not private.has_permission(p_company, 'purchases', 'insert')
     or not private.has_permission(p_company, 'stock', 'insert') then
    raise exception 'Sin permiso para recibir compras y registrar stock'
      using errcode = '42501';
  end if;

  if p_request_id is null or p_order is null or v_note is null
     or length(v_note) not between 3 and 430
     or jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) not between 1 and 40 then
    raise exception 'Datos de recepción inválidos';
  end if;

  perform 1 from public.companies c
  where c.id = p_company and c.active for share;
  if not found then raise exception 'La empresa no está activa'; end if;

  -- Todas las recepciones de una orden compiten por la misma fila.
  select * into v_order from public.purchase_orders o
  where o.company_id = p_company and o.id = p_order for update;
  if not found then raise exception 'Orden inexistente'; end if;

  select * into v_existing from public.purchase_receipts r
  where r.company_id = p_company and r.request_id = p_request_id;
  if found then
    if v_existing.order_id is distinct from p_order
       or v_existing.actor_id is distinct from auth.uid()
       or v_existing.note is distinct from v_note
       or v_existing.request_payload is distinct from p_lines then
      raise exception 'Esta solicitud ya se usó con otros datos';
    end if;
    return v_existing.id;
  end if;

  if v_order.status not in ('open', 'partial') then
    raise exception 'La orden ya no admite recepciones';
  end if;

  insert into public.purchase_receipts(
    company_id, order_id, request_id, request_payload, note, actor_id
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

    select l.item_id, l.quantity, l.received_quantity, l.unit_price
    into v_item, v_order_quantity, v_received, v_price
    from public.purchase_order_lines l
    where l.company_id = p_company and l.order_id = p_order
      and l.line_no = v_line_no for update;
    if not found then raise exception 'Línea inexistente en la orden'; end if;
    if v_received + v_quantity > v_order_quantity then
      raise exception 'La cantidad supera lo pendiente en la línea %', v_line_no;
    end if;

    -- Reutiliza la operación transaccional y las reglas de depósito/lote.
    v_operation := public.post_stock_operation(
      p_company, v_item, v_warehouse, null, 'receipt', v_quantity,
      'Recepción OC #' || v_order.number::text || ' · ' || v_note,
      gen_random_uuid(), v_lot_code, v_expires
    );

    select op.lot_code, op.lot_expires_on
    into v_lot_code, v_expires
    from public.stock_operations op
    where op.company_id = p_company and op.id = v_operation;

    select w.code into v_warehouse_code from public.warehouses w
    where w.company_id = p_company and w.id = v_warehouse;

    insert into public.purchase_receipt_lines(
      company_id, receipt_id, order_id, line_no, item_id,
      warehouse_id, warehouse_code, quantity, unit_price, lot_code, expires_on,
      stock_operation_id
    ) values (
      p_company, v_receipt, p_order, v_line_no, v_item,
      v_warehouse, v_warehouse_code, v_quantity, v_price, v_lot_code, v_expires,
      v_operation
    );

    update public.purchase_order_lines l
    set received_quantity = l.received_quantity + v_quantity
    where l.company_id = p_company and l.order_id = p_order
      and l.line_no = v_line_no;

    v_count := v_count + 1;
  end loop;

  update public.purchase_orders o
  set status = case
    when not exists (
      select 1 from public.purchase_order_lines l
      where l.company_id = p_company and l.order_id = p_order
        and l.received_quantity < l.quantity
    ) then 'received' else 'partial' end
  where o.company_id = p_company and o.id = p_order;

  return v_receipt;
end;
$$;

revoke execute on function public.receive_purchase_order(
  uuid, uuid, uuid, text, jsonb
) from public, anon;
grant execute on function public.receive_purchase_order(
  uuid, uuid, uuid, text, jsonb
) to authenticated;

create function public.purchase_receivable_lines(
  p_company uuid, p_order uuid
) returns table (
  line_no smallint, item_id uuid, item_code text, item_name text,
  unit_symbol text, quantity numeric, received_quantity numeric,
  unit_price numeric, track_lots boolean
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.has_permission(p_company, 'purchases', 'read') then
    raise exception 'Sin permiso para consultar órdenes' using errcode = '42501';
  end if;
  return query
    select l.line_no, l.item_id, l.item_code, l.item_name,
      l.unit_symbol, l.quantity, l.received_quantity, l.unit_price,
      i.track_lots
    from public.purchase_order_lines l
    join public.items i on i.company_id = l.company_id and i.id = l.item_id
    where l.company_id = p_company and l.order_id = p_order
    order by l.line_no;
end;
$$;

revoke execute on function public.purchase_receivable_lines(uuid, uuid)
  from public, anon;
grant execute on function public.purchase_receivable_lines(uuid, uuid)
  to authenticated;

-- Cancelar el saldo pendiente conserva íntegro el historial recibido.
create or replace function public.cancel_purchase_order(p_company uuid, p_order uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.has_permission(p_company, 'purchases', 'update') then
    raise exception 'Sin permiso para cancelar órdenes' using errcode = '42501';
  end if;
  perform 1 from public.companies c
  where c.id = p_company and c.active for share;
  if not found then raise exception 'Empresa inactiva'; end if;
  update public.purchase_orders o
  set status = 'cancelled', cancelled_at = clock_timestamp()
  where o.company_id = p_company and o.id = p_order
    and o.status in ('open', 'partial');
  if not found then raise exception 'Orden inexistente o cerrada'; end if;
end;
$$;

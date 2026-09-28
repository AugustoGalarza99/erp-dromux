-- Dromux ERP · Remitos de salida y fabricación, versión 022.
-- Ejecutar una vez después de 021. Cada remito confirmado descuenta stock
-- en la misma transacción. Los vinculados a producción reutilizan el consumo.

create table public.delivery_note_counters (
  company_id uuid primary key references public.companies(id) on delete cascade,
  next_number bigint not null default 1 check (next_number > 0)
);

create table public.delivery_notes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  number bigint not null check (number > 0),
  request_id uuid not null,
  request_payload jsonb not null,
  kind text not null check (kind in ('production', 'materials', 'products', 'sale')),
  job_id uuid,
  sale_id uuid,
  recipient text not null check (length(btrim(recipient)) between 3 and 120),
  note text not null check (length(btrim(note)) between 3 and 300),
  status text not null default 'issued' check (status in ('issued','voided')),
  void_reason text,
  voided_at timestamptz,
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  unique (company_id, id),
  unique (company_id, number),
  unique (company_id, request_id),
  foreign key (company_id, job_id) references public.production_jobs(company_id, id),
  foreign key (company_id, sale_id) references public.sales(company_id, id),
  check ((kind = 'production') = (job_id is not null)),
  check ((kind = 'sale') = (sale_id is not null)),
  check ((status = 'voided') = (voided_at is not null and void_reason is not null))
);
create index delivery_notes_recent on public.delivery_notes(company_id, created_at desc);
create index delivery_notes_job on public.delivery_notes(company_id, job_id, created_at)
  where job_id is not null;

create table public.delivery_note_lines (
  company_id uuid not null,
  note_id uuid not null,
  line_no smallint not null check (line_no between 1 and 40),
  item_id uuid not null,
  item_code text not null,
  item_name text not null,
  unit_symbol text not null,
  warehouse_id uuid not null,
  warehouse_name text not null,
  lot_code text,
  quantity numeric(18, 6) not null check (quantity > 0),
  stock_operation_id uuid not null,
  production_event_id uuid,
  sale_id uuid,
  sale_line_no smallint,
  primary key (company_id, note_id, line_no),
  unique (company_id, production_event_id),
  foreign key (company_id, note_id) references public.delivery_notes(company_id, id),
  foreign key (company_id, item_id) references public.items(company_id, id),
  foreign key (company_id, warehouse_id) references public.warehouses(company_id, id),
  foreign key (company_id, stock_operation_id)
    references public.stock_operations(company_id, id),
  foreign key (company_id, production_event_id)
    references public.production_job_events(company_id, id),
  foreign key (company_id, sale_id, sale_line_no)
    references public.sale_lines(company_id, sale_id, line_no),
  check ((sale_id is null) = (sale_line_no is null))
);

create table public.delivery_note_reversals (
  company_id uuid not null,
  note_id uuid not null,
  line_no smallint not null,
  stock_operation_id uuid not null,
  production_event_id uuid,
  sale_id uuid,
  sale_line_no smallint,
  primary key (company_id, note_id, line_no),
  foreign key (company_id, note_id, line_no)
    references public.delivery_note_lines(company_id, note_id, line_no),
  foreign key (company_id, stock_operation_id)
    references public.stock_operations(company_id, id),
  foreign key (company_id, production_event_id)
    references public.production_job_events(company_id, id),
  foreign key (company_id, sale_id, sale_line_no)
    references public.sale_lines(company_id, sale_id, line_no),
  check ((sale_id is null) = (sale_line_no is null))
);

alter table public.delivery_notes enable row level security;
alter table public.delivery_note_lines enable row level security;
alter table public.delivery_note_reversals enable row level security;
create policy delivery_notes_read on public.delivery_notes for select to authenticated
  using ((select private.has_permission(company_id, 'stock', 'read'))
    or (kind = 'production' and
      (select private.has_permission(company_id, 'production', 'read'))));
create policy delivery_lines_read on public.delivery_note_lines for select to authenticated
  using (exists (select 1 from public.delivery_notes d
    where d.company_id = delivery_note_lines.company_id
      and d.id = delivery_note_lines.note_id
      and (private.has_permission(d.company_id, 'stock', 'read')
        or (d.kind = 'production' and
          private.has_permission(d.company_id, 'production', 'read')))));
create policy delivery_reversals_read on public.delivery_note_reversals for select to authenticated
  using (exists (select 1 from public.delivery_notes d
    where d.company_id = delivery_note_reversals.company_id
      and d.id = delivery_note_reversals.note_id
      and (private.has_permission(d.company_id, 'stock', 'read')
        or (d.kind = 'production' and
          private.has_permission(d.company_id, 'production', 'read')))));
revoke all on public.delivery_note_counters, public.delivery_notes,
  public.delivery_note_lines, public.delivery_note_reversals from public, anon, authenticated;
grant select on public.delivery_notes, public.delivery_note_lines,
  public.delivery_note_reversals to authenticated;
create trigger delivery_note_lines_immutable before update or delete
  on public.delivery_note_lines for each row
  execute function private.reject_stock_history_mutation();
create trigger delivery_note_reversals_immutable before update or delete
  on public.delivery_note_reversals for each row
  execute function private.reject_stock_history_mutation();

create function public.issue_delivery_note(
  p_company uuid, p_kind text, p_job uuid, p_recipient text,
  p_note text, p_lines jsonb, p_request uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_payload jsonb;
  v_existing public.delivery_notes%rowtype;
  v_job public.production_jobs%rowtype;
  v_line jsonb;
  v_item public.items%rowtype;
  v_warehouse text;
  v_symbol text;
  v_id uuid;
  v_number bigint;
  v_line_no integer := 0;
  v_quantity numeric;
  v_warehouse_id uuid;
  v_lot text;
  v_operation uuid;
  v_event uuid;
begin
  if auth.uid() is null
    or not private.has_permission(p_company, 'stock', 'insert')
    or (p_kind = 'production' and
      not private.has_permission(p_company, 'production', 'insert')) then
    raise exception 'Necesitás permiso para entregar stock y registrar fabricación'
      using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('production','materials','products')
    or (p_kind = 'production') is distinct from (p_job is not null)
    or p_request is null
    or length(btrim(coalesce(p_recipient, ''))) not between 3 and 120
    or length(btrim(coalesce(p_note, ''))) not between 3 and 300
    or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) not between 1 and 40 then
    raise exception 'Revisá tipo de remito, destinatario e insumos';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('delivery:' || p_company::text || ':' || p_request::text, 0));
  v_payload := jsonb_build_object('kind', p_kind, 'job', p_job,
    'recipient', btrim(p_recipient), 'note', btrim(p_note), 'lines', p_lines);
  select * into v_existing from public.delivery_notes
    where company_id = p_company and request_id = p_request;
  if found then
    if v_existing.actor_id <> auth.uid() or v_existing.request_payload <> v_payload then
      raise exception 'Esta solicitud ya se usó con otros datos';
    end if;
    return v_existing.id;
  end if;
  if p_job is not null then
    select * into v_job from public.production_jobs
      where company_id = p_company and id = p_job for update;
    if not found or v_job.status not in ('queued', 'in_progress') then
      raise exception 'La orden de fabricación no admite más entregas';
    end if;
  end if;
  perform 1 from public.companies where id = p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  insert into public.delivery_note_counters(company_id) values (p_company)
    on conflict do nothing;
  update public.delivery_note_counters set next_number = next_number + 1
    where company_id = p_company returning next_number - 1 into v_number;
  insert into public.delivery_notes(company_id, number, request_id,
    request_payload, kind, job_id, recipient, note, actor_id)
  values (p_company, v_number, p_request, v_payload,
    p_kind, p_job, btrim(p_recipient), btrim(p_note), auth.uid())
  returning id into v_id;

  for v_line in select value from jsonb_array_elements(p_lines) x(value) loop
    v_line_no := v_line_no + 1;
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'Cada renglón debe contener un ítem'; end if;
    v_quantity := (v_line ->> 'quantity')::numeric;
    v_warehouse_id := (v_line ->> 'warehouse_id')::uuid;
    v_lot := nullif(btrim(v_line ->> 'lot_code'), '');
    if (v_line ->> 'item_id') is null or v_warehouse_id is null
      or v_quantity is null or v_quantity <= 0 or v_quantity >= 1000000000000
      or v_quantity <> round(v_quantity, 6) or length(coalesce(v_lot, '')) > 80 then
      raise exception 'Revisá ítem, cantidad, depósito y lote de cada renglón';
    end if;
    select * into v_item from public.items
      where company_id = p_company and id = (v_line ->> 'item_id')::uuid
        and active for share;
    if not found then raise exception 'El ítem está inactivo o no existe'; end if;
    if (p_kind = 'production'
        and v_item.item_type not in ('raw_material', 'semi_finished'))
      or (p_kind = 'materials'
        and v_item.item_type not in ('raw_material', 'semi_finished', 'consumable'))
      or (p_kind = 'products'
        and v_item.item_type not in ('semi_finished', 'finished_product')) then
      raise exception 'El tipo de ítem no corresponde a este remito';
    end if;
    select w.name into v_warehouse from public.warehouses w
      where w.company_id = p_company and w.id = v_warehouse_id and w.active for share;
    if not found then raise exception 'Elegí un depósito de origen activo'; end if;
    select u.symbol into v_symbol from public.units u
      where u.company_id = p_company and u.id = v_item.unit_id;
    if p_kind = 'production' then
      v_event := public.issue_production_material(p_company, p_job,
        v_item.id, v_warehouse_id, v_lot, v_quantity,
        'Remito Nº ' || v_number || ' · ' || left(btrim(p_note), 250),
        gen_random_uuid());
      select stock_operation_id into v_operation from public.production_job_events
        where company_id = p_company and id = v_event;
    else
      v_event := null;
      v_operation := public.post_stock_operation(p_company, v_item.id,
        v_warehouse_id, null, 'issue', v_quantity,
        'Remito Nº ' || v_number || ' · ' || left(btrim(p_note), 250),
        gen_random_uuid(), v_lot, null);
    end if;
    insert into public.delivery_note_lines(company_id, note_id, line_no,
      item_id, item_code, item_name, unit_symbol, warehouse_id,
      warehouse_name, lot_code, quantity, stock_operation_id, production_event_id)
    values (p_company, v_id, v_line_no, v_item.id, v_item.code, v_item.name,
      coalesce(v_symbol, ''), v_warehouse_id, v_warehouse, v_lot,
      v_quantity, v_operation, v_event);
  end loop;
  return v_id;
end;
$$;

create function public.void_delivery_note(
  p_company uuid, p_note uuid, p_reason text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_note public.delivery_notes%rowtype;
  v_line public.delivery_note_lines%rowtype;
  v_operation uuid;
  v_event uuid;
  v_expiry date;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'stock', 'insert')
    or not private.has_permission(p_company, 'stock', 'delete') then
    raise exception 'Necesitás permiso para anular entregas y reingresar stock'
      using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_reason, ''))) not between 5 and 300 then
    raise exception 'Escribí un motivo de al menos cinco caracteres'; end if;
  select * into v_note from public.delivery_notes
    where company_id = p_company and id = p_note for update;
  if not found then raise exception 'Remito inexistente'; end if;
  if v_note.status = 'voided' then
    if v_note.void_reason <> btrim(p_reason) then
      raise exception 'El remito ya fue anulado con otro motivo'; end if;
    return v_note.id;
  end if;
  if v_note.kind = 'sale' then
    if not private.has_permission(p_company, 'sales', 'read') then
      raise exception 'Necesitás acceso a ventas' using errcode = '42501'; end if;
    update public.delivery_notes set status = 'voided',
      void_reason = btrim(p_reason), voided_at = clock_timestamp()
      where company_id = p_company and id = p_note;
    return p_note;
  end if;
  if v_note.kind = 'production' then
    if not private.has_permission(p_company, 'production', 'update') then
      raise exception 'Necesitás permiso para devolver insumos de producción'
        using errcode = '42501'; end if;
    perform 1 from public.production_jobs
      where company_id = p_company and id = v_note.job_id
        and status = 'in_progress' for update;
    if not found then
      raise exception 'La fabricación ya fue cerrada. No se puede anular esta entrega'; end if;
  end if;
  for v_line in select * from public.delivery_note_lines
    where company_id = p_company and note_id = p_note order by line_no loop
    if v_note.kind = 'production' then
      if exists(select 1 from public.production_job_events e
        where e.company_id = p_company and e.issue_id = v_line.production_event_id) then
        raise exception 'Ya se devolvió parte de esta entrega. Ajustá la orden manualmente';
      end if;
      v_event := public.return_production_material(p_company, v_note.job_id,
        v_line.production_event_id, v_line.quantity,
        'Anulación remito Nº ' || v_note.number || ' · ' || left(btrim(p_reason), 245),
        gen_random_uuid());
      select stock_operation_id into v_operation from public.production_job_events
        where company_id = p_company and id = v_event;
    else
      v_event := null;
      v_expiry := null;
      if v_line.lot_code is not null then
        select l.expires_on into v_expiry from public.stock_lots l
          where l.company_id = p_company and l.item_id = v_line.item_id
            and lower(l.code) = lower(v_line.lot_code);
        if not found then raise exception 'No se encuentra el lote de origen'; end if;
      end if;
      v_operation := public.post_stock_operation(p_company, v_line.item_id,
        v_line.warehouse_id, null, 'receipt', v_line.quantity,
        'Anulación remito Nº ' || v_note.number || ' · ' || left(btrim(p_reason), 245),
        gen_random_uuid(), v_line.lot_code, v_expiry);
    end if;
    insert into public.delivery_note_reversals(company_id, note_id, line_no,
      stock_operation_id, production_event_id)
    values (p_company, p_note, v_line.line_no, v_operation, v_event);
  end loop;
  update public.delivery_notes set status = 'voided',
    void_reason = btrim(p_reason), voided_at = clock_timestamp()
    where company_id = p_company and id = p_note;
  return p_note;
end;
$$;

-- Un remito vinculado a venta documenta la entrega. La venta ya descontó stock:
-- aquí se reutiliza su operación y se controla la suma entregada por renglón.
create function public.issue_sale_delivery_note(
  p_company uuid, p_sale uuid, p_recipient text, p_note text,
  p_lines jsonb, p_request uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_sale public.sales%rowtype;
  v_previous public.delivery_notes%rowtype;
  v_line public.sale_lines%rowtype;
  v_entry jsonb;
  v_payload jsonb;
  v_id uuid;
  v_number bigint;
  v_line_no integer := 0;
  v_quantity numeric;
  v_already numeric;
  v_returned numeric;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'sales', 'read')
    or not private.has_permission(p_company, 'stock', 'read')
    or not private.has_permission(p_company, 'stock', 'insert') then
    raise exception 'Necesitás acceso a ventas y stock para emitir el remito'
      using errcode = '42501'; end if;
  if p_sale is null or p_request is null
    or length(btrim(coalesce(p_recipient, ''))) not between 3 and 120
    or length(btrim(coalesce(p_note, ''))) not between 3 and 300
    or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) not between 1 and 40 then
    raise exception 'Revisá la venta, el destinatario y los renglones'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('delivery:' || p_company::text || ':' || p_request::text, 0));
  v_payload := jsonb_build_object('kind', 'sale', 'sale', p_sale,
    'recipient', btrim(p_recipient), 'note', btrim(p_note), 'lines', p_lines);
  select * into v_previous from public.delivery_notes
    where company_id = p_company and request_id = p_request;
  if found then
    if v_previous.actor_id <> auth.uid() or v_previous.request_payload <> v_payload then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_previous.id;
  end if;
  select * into v_sale from public.sales
    where company_id = p_company and id = p_sale for update;
  if not found then raise exception 'Venta inexistente'; end if;
  if exists (select 1 from public.sale_adjustments a
    where a.company_id = p_company and a.sale_id = p_sale and a.kind = 'cancel') then
    raise exception 'Una venta anulada no puede generar nuevos remitos'; end if;
  perform 1 from public.companies where id = p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  insert into public.delivery_note_counters(company_id) values (p_company)
    on conflict do nothing;
  update public.delivery_note_counters set next_number = next_number + 1
    where company_id = p_company returning next_number - 1 into v_number;
  insert into public.delivery_notes(company_id, number, request_id,
    request_payload, kind, sale_id, recipient, note, actor_id)
  values (p_company, v_number, p_request, v_payload, 'sale', p_sale,
    btrim(p_recipient), btrim(p_note), auth.uid()) returning id into v_id;
  for v_entry in select value from jsonb_array_elements(p_lines) x(value) loop
    v_line_no := v_line_no + 1;
    if jsonb_typeof(v_entry) <> 'object' then
      raise exception 'Renglón de venta inválido'; end if;
    v_quantity := (v_entry ->> 'quantity')::numeric;
    if (v_entry ->> 'line_no') is null or v_quantity is null
      or v_quantity <= 0 or v_quantity >= 1000000000000
      or v_quantity <> round(v_quantity, 6) then
      raise exception 'Revisá las cantidades entregadas'; end if;
    select * into v_line from public.sale_lines
      where company_id = p_company and sale_id = p_sale
        and line_no = (v_entry ->> 'line_no')::smallint;
    if not found then raise exception 'Producto no incluido en la venta'; end if;
    if exists (select 1 from public.delivery_note_lines l
      where l.company_id = p_company and l.note_id = v_id
        and l.sale_line_no = v_line.line_no) then
      raise exception 'Cada producto de la venta puede figurar una vez por remito'; end if;
    select coalesce(sum(l.quantity), 0) into v_already
      from public.delivery_note_lines l
      join public.delivery_notes d on d.company_id = l.company_id and d.id = l.note_id
      where d.company_id = p_company and d.sale_id = p_sale
        and d.status = 'issued' and l.sale_line_no = v_line.line_no;
    select coalesce(sum(a.quantity), 0) into v_returned
      from public.sale_adjustment_lines a
      where a.company_id = p_company and a.sale_id = p_sale
        and a.sale_line_no = v_line.line_no;
    if v_quantity > v_line.quantity - v_returned - v_already then
      raise exception 'Esta entrega supera el saldo disponible del producto vendido'; end if;
    insert into public.delivery_note_lines(company_id, note_id, line_no,
      item_id, item_code, item_name, unit_symbol, warehouse_id, warehouse_name,
      lot_code, quantity, stock_operation_id, sale_id, sale_line_no)
    values (p_company, v_id, v_line_no, v_line.item_id, v_line.item_code,
      v_line.item_name, v_line.unit_symbol, v_line.warehouse_id,
      v_line.warehouse_code, v_line.lot_code, v_quantity,
      v_line.stock_operation_id, p_sale, v_line.line_no);
  end loop;
  return v_id;
end;
$$;
revoke execute on function public.issue_sale_delivery_note(uuid,uuid,text,text,jsonb,uuid)
  from public, anon;
grant execute on function public.issue_sale_delivery_note(uuid,uuid,text,text,jsonb,uuid)
  to authenticated;

revoke execute on function public.issue_delivery_note(uuid,text,uuid,text,text,jsonb,uuid),
  public.void_delivery_note(uuid,uuid,text) from public, anon;
grant execute on function public.issue_delivery_note(uuid,text,uuid,text,text,jsonb,uuid),
  public.void_delivery_note(uuid,uuid,text) to authenticated;

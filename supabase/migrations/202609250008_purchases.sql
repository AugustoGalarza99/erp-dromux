-- ERP Dromux · proveedores y órdenes de compra.
-- Ejecutar una vez después de 007.

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null check (length(btrim(name)) between 2 and 160),
  tax_id text not null default '' check (length(tax_id) <= 30),
  email text not null default '' check (length(email) <= 160),
  phone text not null default '' check (length(phone) <= 40),
  notes text not null default '' check (length(notes) <= 500),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint suppliers_company_id_unique unique (company_id, id)
);

create index suppliers_company_active_idx
  on public.suppliers(company_id, active, name);
create unique index suppliers_company_name_unique
  on public.suppliers(company_id, lower(name));

alter table public.suppliers enable row level security;
create policy suppliers_read on public.suppliers for select to authenticated
  using ((select private.has_permission(company_id, 'purchases', 'read')));
create policy suppliers_insert on public.suppliers for insert to authenticated
  with check ((select private.has_permission(company_id, 'purchases', 'insert')));
create policy suppliers_update on public.suppliers for update to authenticated
  using ((select private.has_permission(company_id, 'purchases', 'update')))
  with check ((select private.has_permission(company_id, 'purchases', 'update')));
revoke all on public.suppliers from anon, authenticated;
grant select on public.suppliers to authenticated;
grant insert (company_id, name, tax_id, email, phone, notes, active)
  on public.suppliers to authenticated;
grant update (name, tax_id, email, phone, notes, active)
  on public.suppliers to authenticated;

create table public.purchase_counters (
  company_id uuid primary key references public.companies(id) on delete cascade,
  next_number bigint not null default 1 check (next_number > 0)
);
revoke all on public.purchase_counters from anon, authenticated;

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  number bigint not null check (number > 0),
  supplier_id uuid not null,
  supplier_name text not null,
  status text not null default 'open' check (status in ('open', 'cancelled')),
  note text not null default '' check (length(note) <= 500),
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  cancelled_at timestamptz,
  constraint purchase_orders_company_id_unique unique (company_id, id),
  constraint purchase_orders_company_number_unique unique (company_id, number),
  constraint purchase_orders_supplier_fk foreign key (company_id, supplier_id)
    references public.suppliers(company_id, id)
);
create index purchase_orders_company_date_idx
  on public.purchase_orders(company_id, created_at desc);

create table public.purchase_order_lines (
  company_id uuid not null,
  order_id uuid not null,
  line_no smallint not null check (line_no between 1 and 40),
  item_id uuid not null,
  item_code text not null,
  unit_symbol text not null,
  quantity numeric(18, 6) not null check (quantity > 0),
  unit_price numeric(18, 2) not null check (unit_price >= 0),
  primary key (company_id, order_id, line_no),
  constraint purchase_lines_order_fk foreign key (company_id, order_id)
    references public.purchase_orders(company_id, id),
  constraint purchase_lines_item_fk foreign key (company_id, item_id)
    references public.items(company_id, id),
  constraint purchase_lines_item_unique unique (company_id, order_id, item_id)
);

alter table public.purchase_orders enable row level security;
alter table public.purchase_order_lines enable row level security;
create policy purchase_orders_read on public.purchase_orders for select to authenticated
  using ((select private.has_permission(company_id, 'purchases', 'read')));
create policy purchase_lines_read on public.purchase_order_lines for select to authenticated
  using ((select private.has_permission(company_id, 'purchases', 'read')));
revoke all on public.purchase_orders, public.purchase_order_lines from anon, authenticated;
grant select on public.purchase_orders, public.purchase_order_lines to authenticated;

create function public.create_purchase_order(
  p_company uuid, p_supplier uuid, p_note text, p_lines jsonb
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_number bigint;
  v_order uuid;
  v_line jsonb;
  v_item uuid;
  v_quantity numeric;
  v_price numeric;
  v_code text;
  v_unit text;
  v_supplier_name text;
  v_index smallint := 0;
begin
  if not private.has_permission(p_company, 'purchases', 'insert') then
    raise exception 'Sin permiso para crear órdenes' using errcode = '42501';
  end if;
  if p_supplier is null or length(coalesce(p_note, '')) > 500
     or jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) not between 1 and 40 then
    raise exception 'Datos de orden inválidos';
  end if;

  perform 1 from public.companies c
  where c.id = p_company and c.active for share;
  if not found then raise exception 'Empresa inactiva'; end if;
  select s.name into v_supplier_name from public.suppliers s
  where s.id = p_supplier and s.company_id = p_company and s.active for share;
  if not found then raise exception 'Elegí un proveedor activo'; end if;

  insert into public.purchase_counters(company_id) values (p_company)
  on conflict (company_id) do nothing;
  update public.purchase_counters c
  set next_number = c.next_number + 1
  where c.company_id = p_company
  returning c.next_number - 1 into v_number;

  insert into public.purchase_orders(
    company_id, number, supplier_id, supplier_name, note, actor_id
  ) values (
    p_company, v_number, p_supplier, v_supplier_name,
    btrim(coalesce(p_note, '')), auth.uid()
  )
  returning id into v_order;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(v_line) is distinct from 'object'
       or coalesce(v_line->>'item_id', '') !~
         '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
       or coalesce(v_line->>'quantity', '') !~ '^[0-9]+(\.[0-9]{1,6})?$'
       or coalesce(v_line->>'unit_price', '') !~ '^[0-9]+(\.[0-9]{1,2})?$' then
      raise exception 'Línea de compra inválida';
    end if;
    v_item := (v_line->>'item_id')::uuid;
    v_quantity := (v_line->>'quantity')::numeric;
    v_price := (v_line->>'unit_price')::numeric;
    if v_quantity <= 0 or v_quantity >= 1000000000000
       or v_price >= 10000000000000000 then
      raise exception 'Cantidad o precio fuera de rango';
    end if;

    select i.code, u.symbol into v_code, v_unit
    from public.items i
    join public.units u on u.company_id = i.company_id and u.id = i.unit_id
    where i.company_id = p_company and i.id = v_item and i.active
    for share of i;
    if not found then raise exception 'La orden contiene un ítem inactivo'; end if;

    v_index := v_index + 1;
    insert into public.purchase_order_lines(
      company_id, order_id, line_no, item_id, item_code,
      unit_symbol, quantity, unit_price
    ) values (p_company, v_order, v_index, v_item, v_code,
      v_unit, v_quantity, v_price);
  end loop;

  return v_order;
end;
$$;

create function public.cancel_purchase_order(p_company uuid, p_order uuid)
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
  where o.company_id = p_company and o.id = p_order and o.status = 'open';
  if not found then raise exception 'Orden inexistente o ya cancelada'; end if;
end;
$$;

revoke execute on function public.create_purchase_order(uuid, uuid, text, jsonb),
  public.cancel_purchase_order(uuid, uuid) from public, anon;
grant execute on function public.create_purchase_order(uuid, uuid, text, jsonb),
  public.cancel_purchase_order(uuid, uuid) to authenticated;

create function public.purchase_item_options(
  p_company uuid, p_search text default ''
) returns table (
  id uuid, code text, name text, unit_symbol text
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.has_permission(p_company, 'purchases', 'read') then
    raise exception 'Sin permiso para consultar ítems de compra' using errcode = '42501';
  end if;
  if length(coalesce(p_search, '')) > 100 then
    raise exception 'Búsqueda demasiado larga';
  end if;
  return query
    select i.id, i.code, i.name, u.symbol
    from public.items i
    join public.units u on u.company_id = i.company_id and u.id = i.unit_id
    where i.company_id = p_company and i.active
      and (coalesce(p_search, '') = ''
        or i.name ilike '%' || p_search || '%'
        or i.code ilike '%' || p_search || '%'
        or i.barcode ilike '%' || p_search || '%')
    order by i.name, i.id
    limit 30;
end;
$$;

revoke execute on function public.purchase_item_options(uuid, text)
  from public, anon;
grant execute on function public.purchase_item_options(uuid, text)
  to authenticated;

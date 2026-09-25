-- ERP Dromux · stock por depósito y libro de movimientos.
-- Requiere 202609240004_items.sql. Aplicar una vez.

create table public.stock_balances (
  company_id uuid not null references public.companies(id) on delete cascade,
  item_id uuid not null,
  warehouse_id uuid not null,
  quantity numeric(18, 6) not null default 0 check (quantity >= 0),
  version bigint not null default 0 check (version >= 0),
  updated_at timestamptz not null default now(),
  primary key (company_id, item_id, warehouse_id),
  constraint stock_balances_item_company_fk
    foreign key (company_id, item_id) references public.items(company_id, id),
  constraint stock_balances_warehouse_company_fk
    foreign key (company_id, warehouse_id) references public.warehouses(company_id, id)
);

create index stock_balances_warehouse_idx
  on public.stock_balances(company_id, warehouse_id, item_id);

create table public.stock_operations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  request_id uuid not null,
  item_id uuid not null,
  warehouse_id uuid not null,
  to_warehouse_id uuid,
  kind text not null check (kind in ('receipt', 'issue', 'transfer')),
  quantity numeric(18, 6) not null check (quantity > 0),
  note text not null check (length(btrim(note)) between 3 and 500),
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  constraint stock_operations_request_unique unique (company_id, request_id),
  constraint stock_operations_company_id_unique unique (company_id, id),
  constraint stock_operations_item_company_fk
    foreign key (company_id, item_id) references public.items(company_id, id),
  constraint stock_operations_warehouse_company_fk
    foreign key (company_id, warehouse_id) references public.warehouses(company_id, id),
  constraint stock_operations_target_company_fk
    foreign key (company_id, to_warehouse_id) references public.warehouses(company_id, id),
  constraint stock_operations_destination_check check (
    (kind = 'transfer' and to_warehouse_id is not null
      and to_warehouse_id <> warehouse_id)
    or (kind <> 'transfer' and to_warehouse_id is null)
  )
);

create index stock_operations_company_date_idx
  on public.stock_operations(company_id, created_at desc);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  operation_id uuid not null,
  line_no smallint not null check (line_no in (1, 2)),
  item_id uuid not null,
  warehouse_id uuid not null,
  kind text not null check (
    kind in ('receipt', 'issue', 'transfer_out', 'transfer_in')
  ),
  delta numeric(18, 6) not null check (delta <> 0),
  balance_after numeric(18, 6) not null check (balance_after >= 0),
  balance_version bigint not null check (balance_version > 0),
  item_code text not null,
  warehouse_code text not null,
  unit_symbol text not null,
  note text not null,
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  unique (operation_id, line_no),
  constraint stock_movements_operation_company_fk
    foreign key (company_id, operation_id)
    references public.stock_operations(company_id, id),
  constraint stock_movements_item_company_fk
    foreign key (company_id, item_id) references public.items(company_id, id),
  constraint stock_movements_warehouse_company_fk
    foreign key (company_id, warehouse_id) references public.warehouses(company_id, id),
  constraint stock_movements_sign_check check (
    (kind in ('receipt', 'transfer_in') and delta > 0)
    or (kind in ('issue', 'transfer_out') and delta < 0)
  )
);

create index stock_movements_company_date_idx
  on public.stock_movements(company_id, created_at desc, id desc);
create index stock_movements_item_date_idx
  on public.stock_movements(company_id, item_id, created_at desc);
create index stock_movements_warehouse_date_idx
  on public.stock_movements(company_id, warehouse_id, created_at desc);
create unique index stock_movements_balance_version_unique
  on public.stock_movements(company_id, item_id, warehouse_id, balance_version);

alter table public.stock_balances enable row level security;
alter table public.stock_operations enable row level security;
alter table public.stock_movements enable row level security;

create policy stock_balances_read on public.stock_balances
  for select to authenticated
  using ((select private.has_permission(company_id, 'stock', 'read')));
create policy stock_operations_read on public.stock_operations
  for select to authenticated
  using ((select private.has_permission(company_id, 'stock', 'read')));
create policy stock_movements_read on public.stock_movements
  for select to authenticated
  using ((select private.has_permission(company_id, 'stock', 'read')));

-- El navegador sólo lee. Ningún INSERT/UPDATE/DELETE directo a estas tablas.
revoke all on public.stock_balances, public.stock_operations,
  public.stock_movements from anon, authenticated;
grant select on public.stock_balances, public.stock_operations,
  public.stock_movements to authenticated;

create function private.reject_stock_history_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'El historial de stock es inmutable; registrá una operación compensatoria';
end;
$$;
create trigger stock_movements_immutable
before update or delete on public.stock_movements for each row
execute function private.reject_stock_history_mutation();
create trigger stock_operations_immutable
before update or delete on public.stock_operations for each row
execute function private.reject_stock_history_mutation();
revoke execute on function private.reject_stock_history_mutation()
  from public, anon, authenticated;

-- Evita dejar unidades con stock atrapadas en un ítem o depósito desactivado.
create function private.check_stock_catalog_deactivation()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.active and not new.active then
    if tg_table_name = 'items' and exists (
      select 1 from public.stock_balances b
      where b.company_id = old.company_id
        and b.item_id = old.id and b.quantity > 0
    ) then
      raise exception 'Trasladá o consumí el stock antes de desactivar el ítem';
    end if;
    if tg_table_name = 'warehouses' and exists (
      select 1 from public.stock_balances b
      where b.company_id = old.company_id
        and b.warehouse_id = old.id and b.quantity > 0
    ) then
      raise exception 'Trasladá el stock antes de desactivar el depósito';
    end if;
  end if;
  return new;
end;
$$;
create trigger items_prevent_stock_stranding
before update of active on public.items for each row
execute function private.check_stock_catalog_deactivation();
create trigger warehouses_prevent_stock_stranding
before update of active on public.warehouses for each row
execute function private.check_stock_catalog_deactivation();
revoke execute on function private.check_stock_catalog_deactivation()
  from public, anon, authenticated;

-- Cambiar la unidad de un ítem con historial mezclaría kg con unidades, etc.
create function private.prevent_stock_unit_change()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.unit_id is distinct from old.unit_id and exists (
    select 1 from public.stock_movements m
    where m.company_id = old.company_id and m.item_id = old.id
  ) then
    raise exception 'La unidad no puede cambiarse si el ítem tiene movimientos';
  end if;
  return new;
end;
$$;
create trigger items_prevent_unit_change
before update of unit_id on public.items for each row
execute function private.prevent_stock_unit_change();
revoke execute on function private.prevent_stock_unit_change()
  from public, anon, authenticated;

create function public.post_stock_operation(
  p_company uuid,
  p_item uuid,
  p_warehouse uuid,
  p_to_warehouse uuid,
  p_kind text,
  p_quantity numeric,
  p_note text,
  p_request_id uuid
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_note text := btrim(p_note);
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
begin
  if v_actor is null or not private.has_permission(p_company, 'stock', 'insert') then
    raise exception 'Sin permiso para registrar movimientos' using errcode = '42501';
  end if;
  if p_request_id is null or p_item is null or p_warehouse is null
     or p_kind is null or p_kind not in ('receipt', 'issue', 'transfer')
     or p_quantity is null or p_quantity <= 0
     or p_quantity >= 1000000000000
     or round(p_quantity, 6) <> p_quantity
     or v_note is null or length(v_note) not between 3 and 500
     or (p_kind = 'transfer' and (p_to_warehouse is null
       or p_to_warehouse = p_warehouse))
     or (p_kind <> 'transfer' and p_to_warehouse is not null) then
    raise exception 'Datos de movimiento inválidos';
  end if;

  -- Una operación y una suspensión compiten por la misma fila de empresa.
  perform 1 from public.companies c
  where c.id = p_company and c.active for share;
  if not found or not private.has_permission(p_company, 'stock', 'insert') then
    raise exception 'La empresa no está activa o no tenés permiso' using errcode = '42501';
  end if;

  -- Serializa movimientos de un mismo ítem, incluso entre depósitos distintos.
  -- Las transacciones de ítems diferentes pueden continuar en paralelo.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_company::text || ':' || p_item::text, 0)
  );

  insert into public.stock_operations (
    company_id, request_id, item_id, warehouse_id, to_warehouse_id,
    kind, quantity, note, actor_id
  ) values (
    p_company, p_request_id, p_item, p_warehouse, p_to_warehouse,
    p_kind, p_quantity, v_note, v_actor
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
       or v_existing.actor_id is distinct from v_actor then
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
    raise exception 'El ítem requiere lotes; la gestión de lotes aún no está habilitada';
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

  if p_kind = 'receipt' then
    update public.stock_balances b
    set quantity = b.quantity + p_quantity, version = b.version + 1,
        updated_at = clock_timestamp()
    where b.company_id = p_company and b.item_id = p_item
      and b.warehouse_id = p_warehouse
    returning b.quantity, b.version into v_source_balance, v_source_version;
  else
    update public.stock_balances b
    set quantity = b.quantity - p_quantity, version = b.version + 1,
        updated_at = clock_timestamp()
    where b.company_id = p_company and b.item_id = p_item
      and b.warehouse_id = p_warehouse
    returning b.quantity, b.version into v_source_balance, v_source_version;
  end if;

  insert into public.stock_movements (
    company_id, operation_id, line_no, item_id, warehouse_id,
    kind, delta, balance_after, balance_version, item_code, warehouse_code,
    unit_symbol, note, actor_id
  ) values (
    p_company, v_operation, 1, p_item, p_warehouse,
    case p_kind when 'receipt' then 'receipt'
      when 'issue' then 'issue' else 'transfer_out' end,
    case when p_kind = 'receipt' then p_quantity else -p_quantity end,
    v_source_balance, v_source_version, v_item_code, v_warehouse_code,
    v_unit_symbol, v_note, v_actor
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

    insert into public.stock_movements (
      company_id, operation_id, line_no, item_id, warehouse_id,
      kind, delta, balance_after, balance_version, item_code, warehouse_code,
      unit_symbol, note, actor_id
    ) values (
      p_company, v_operation, 2, p_item, p_to_warehouse,
      'transfer_in', p_quantity, v_target_balance, v_target_version,
      v_item_code, v_target_code, v_unit_symbol, v_note, v_actor
    );
  end if;

  return v_operation;
end;
$$;
revoke execute on function public.post_stock_operation(
  uuid, uuid, uuid, uuid, text, numeric, text, uuid
) from public, anon;
grant execute on function public.post_stock_operation(
  uuid, uuid, uuid, uuid, text, numeric, text, uuid
) to authenticated;

-- Incluye ítems sin movimientos, que tienen stock 0.
create function public.stock_summary(
  p_company uuid,
  p_page integer default 0,
  p_search text default ''
) returns table (
  item_id uuid,
  item_code text,
  item_name text,
  unit_symbol text,
  track_lots boolean,
  minimum_stock numeric,
  total_quantity numeric,
  warehouse_count bigint,
  total_count bigint
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.has_permission(p_company, 'stock', 'read') then
    raise exception 'Sin permiso para consultar stock' using errcode = '42501';
  end if;
  if p_page is null or p_page < 0 or p_page > 100000
     or length(coalesce(p_search, '')) > 100 then
    raise exception 'Búsqueda inválida';
  end if;
  return query
    select i.id, i.code, i.name, u.symbol, i.track_lots, i.minimum_stock,
           coalesce(sum(b.quantity), 0)::numeric,
           count(b.warehouse_id) filter (where b.quantity > 0),
           count(*) over ()
    from public.items i
    join public.units u on u.id = i.unit_id and u.company_id = i.company_id
    left join public.stock_balances b
      on b.company_id = i.company_id and b.item_id = i.id
    where i.company_id = p_company and i.active
      and (coalesce(p_search, '') = ''
        or i.name ilike '%' || p_search || '%'
        or i.code ilike '%' || p_search || '%')
    group by i.id, u.symbol
    order by i.name, i.id
    limit 25 offset p_page * 25;
end;
$$;
revoke execute on function public.stock_summary(uuid, integer, text)
  from public, anon;
grant execute on function public.stock_summary(uuid, integer, text)
  to authenticated;

insert into public.role_permissions(company_id, role_id, resource, action)
select r.company_id, r.id, 'stock', a.action
from public.roles r
cross join (values ('read'), ('insert'), ('update'), ('delete'), ('manage')) as a(action)
where r.code = 'admin'
on conflict do nothing;

create or replace function public.create_company_role(
  p_company uuid, p_name text, p_code text, p_permissions jsonb
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_role uuid; v_name text := btrim(p_name); v_entry jsonb;
begin
  if not private.has_permission(p_company, 'roles', 'insert') then
    raise exception 'Sin permiso para crear roles' using errcode = '42501';
  end if;
  if v_name is null or length(v_name) not between 2 and 60
     or p_code is null or p_code !~ '^[a-z][a-z0-9_]{1,39}$' then
    raise exception 'Nombre o código inválido';
  end if;
  if jsonb_typeof(p_permissions) is distinct from 'array'
     or jsonb_array_length(p_permissions) > 100 then
    raise exception 'Lista de permisos inválida';
  end if;

  insert into public.roles(company_id, code, name)
  values (p_company, p_code, v_name) returning id into v_role;

  insert into public.role_permissions(company_id, role_id, resource, action)
  select p_company, v_role, p.resource, p.action
  from jsonb_to_recordset(p_permissions) as p(resource text, action text)
  where p.resource in ('dashboard', 'inventory', 'production', 'purchases',
                       'finance', 'reports', 'settings', 'users', 'roles',
                       'units', 'categories', 'warehouses', 'items', 'stock')
    and p.action in ('read', 'insert', 'update', 'delete', 'manage')
  on conflict do nothing;

  -- Rechazamos entradas desconocidas en vez de descartarlas silenciosamente.
  if (select count(*) from public.role_permissions where role_id = v_role)
     <> (select count(distinct (entry->>'resource', entry->>'action'))
         from jsonb_array_elements(p_permissions) as entry) then
    raise exception 'Permisos desconocidos o repetidos';
  end if;
  return v_role;
end;
$$;




create or replace function public.update_company_role(
  p_company uuid, p_role uuid, p_name text, p_permissions jsonb
) returns void
language plpgsql security definer set search_path = '' as $$
declare v_code text; v_name text := btrim(p_name);
begin
  if not private.has_permission(p_company, 'roles', 'update') then
    raise exception 'Sin permiso para editar roles' using errcode = '42501';
  end if;
  select code into v_code from public.roles
  where id = p_role and company_id = p_company for update;
  if v_code is null then raise exception 'Rol inexistente'; end if;
  if v_code = 'admin' then raise exception 'El rol administrador está protegido'; end if;
  if v_name is null or length(v_name) not between 2 and 60
     or jsonb_typeof(p_permissions) is distinct from 'array'
     or jsonb_array_length(p_permissions) > 100 then
    raise exception 'Datos del rol inválidos';
  end if;

  update public.roles set name = v_name where id = p_role;
  delete from public.role_permissions where role_id = p_role;
  insert into public.role_permissions(company_id, role_id, resource, action)
  select p_company, p_role, p.resource, p.action
  from jsonb_to_recordset(p_permissions) as p(resource text, action text)
  where p.resource in ('dashboard', 'inventory', 'production', 'purchases',
                       'finance', 'reports', 'settings', 'users', 'roles',
                       'units', 'categories', 'warehouses', 'items', 'stock')
    and p.action in ('read', 'insert', 'update', 'delete', 'manage')
  on conflict do nothing;

  if (select count(*) from public.role_permissions where role_id = p_role)
     <> (select count(distinct (entry->>'resource', entry->>'action'))
         from jsonb_array_elements(p_permissions) as entry) then
    raise exception 'Permisos desconocidos o repetidos';
  end if;
end;
$$;




create or replace function public.create_company(p_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_company uuid; v_role uuid; v_user uuid := auth.uid(); v_name text := btrim(p_name);
begin
 if v_user is null then raise exception 'Debes iniciar sesión' using errcode='28000'; end if;
 if v_name is null or length(v_name) not between 2 and 100 then raise exception 'El nombre debe tener entre 2 y 100 caracteres'; end if;
 insert into public.companies(name,slug) values(v_name,'empresa-'||replace(gen_random_uuid()::text,'-','')) returning id into v_company;
 insert into public.roles(company_id,code,name) values(v_company,'admin','Administrador') returning id into v_role;
 insert into public.company_users(company_id,user_id,role_id) values(v_company,v_user,v_role);
 insert into public.company_settings(company_id) values(v_company);
 insert into public.company_modules(company_id,module,enabled) values
 (v_company,'inventory',true),(v_company,'production',true),(v_company,'purchases',true),
 (v_company,'finance',true),(v_company,'reports',true);
 insert into public.role_permissions(company_id,role_id,resource,action)
 select v_company,v_role,resource,action from
 (values ('dashboard'),('inventory'),('production'),('purchases'),('finance'),('reports'),('settings'),('users'),('roles'),('units'),('categories'),('warehouses'),('items'),('stock')) as r(resource)
 cross join (values ('read'),('insert'),('update'),('delete'),('manage')) as a(action);
 insert into public.profiles(id,name) values(v_user,coalesce(nullif(v_user::text,''),'Usuario')) on conflict (id) do nothing;
 return v_company;
end $$;


-- Búsqueda acotada para el formulario; nunca descarga el catálogo entero.
create function public.stock_item_options(
  p_company uuid, p_search text default ''
) returns table (
  id uuid,
  code text,
  name text,
  unit_symbol text,
  barcode text,
  track_lots boolean
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.has_permission(p_company, 'stock', 'read') then
    raise exception 'Sin permiso para ver ítems de stock' using errcode = '42501';
  end if;
  if length(coalesce(p_search, '')) > 100 then
    raise exception 'Búsqueda demasiado larga';
  end if;
  return query
    select i.id, i.code, i.name, u.symbol, i.barcode, i.track_lots
    from public.items i
    join public.units u on u.id = i.unit_id and u.company_id = i.company_id
    where i.company_id = p_company and i.active
      and (coalesce(p_search, '') = ''
        or i.name ilike '%' || p_search || '%'
        or i.code ilike '%' || p_search || '%'
        or i.barcode ilike '%' || p_search || '%')
    order by i.name, i.id
    limit 30;
end;
$$;

create function public.stock_warehouse_options(
  p_company uuid, p_search text default ''
) returns table (
  id uuid,
  code text,
  name text
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.has_permission(p_company, 'stock', 'read') then
    raise exception 'Sin permiso para ver depósitos' using errcode = '42501';
  end if;
  if length(coalesce(p_search, '')) > 100 then
    raise exception 'Búsqueda demasiado larga';
  end if;
  return query
    select w.id, w.code, w.name
    from public.warehouses w
    where w.company_id = p_company and w.active
      and (coalesce(p_search, '') = ''
        or w.name ilike '%' || p_search || '%'
        or w.code ilike '%' || p_search || '%')
    order by w.name, w.id
    limit 30;
end;
$$;

revoke execute on function public.stock_item_options(uuid, text),
  public.stock_warehouse_options(uuid, text) from public, anon;
grant execute on function public.stock_item_options(uuid, text),
  public.stock_warehouse_options(uuid, text) to authenticated;

-- Una ficha con movimientos no puede activar el requisito de lotes a posteriori.
create function private.prevent_late_lot_tracking()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.track_lots and not old.track_lots and exists (
    select 1 from public.stock_movements m
    where m.company_id = old.company_id and m.item_id = old.id
  ) then
    raise exception 'No se puede activar lotes en un ítem con historial de stock';
  end if;
  return new;
end;
$$;
create trigger items_prevent_late_lot_tracking
before update of track_lots on public.items for each row
execute function private.prevent_late_lot_tracking();
revoke execute on function private.prevent_late_lot_tracking()
  from public, anon, authenticated;

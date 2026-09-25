-- ERP Dromux · suspensión central y catálogos base del inventario.
-- Aplicar una sola vez después de 202609240002_users_roles.sql.

alter table public.companies
  add column active boolean not null default true;

create index companies_active_idx on public.companies(id) where active;

-- Estas funciones sostienen las policies de las migraciones anteriores.
-- Al comprobar companies.active aquí, una suspensión bloquea todos los recursos
-- existentes y las tablas futuras que usen private.has_permission().
create or replace function private.is_company_member(p_company uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.company_users cu
    join public.companies c on c.id = cu.company_id
    where cu.company_id = p_company
      and cu.user_id = (select auth.uid())
      and cu.active and c.active
  );
$$;

create or replace function private.has_permission(
  p_company uuid, p_resource text, p_action text
) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.company_users cu
    join public.companies c on c.id = cu.company_id
    join public.role_permissions rp
      on rp.role_id = cu.role_id and rp.company_id = cu.company_id
    where cu.company_id = p_company
      and cu.user_id = (select auth.uid())
      and cu.active and c.active
      and rp.resource = p_resource and rp.action = p_action
  );
$$;

create or replace function private.get_user_role(p_company uuid)
returns text language sql stable security definer set search_path = '' as $$
  select r.code
  from public.company_users cu
  join public.companies c on c.id = cu.company_id
  join public.roles r on r.id = cu.role_id and r.company_id = cu.company_id
  where cu.company_id = p_company
    and cu.user_id = (select auth.uid())
    and cu.active and c.active
  limit 1;
$$;

-- Cierra la excepción de lectura propia de company_users de la V1.
drop policy company_users_self_or_admin_select on public.company_users;
create policy company_users_self_or_admin_select
  on public.company_users for select to authenticated
  using (
    (user_id = (select auth.uid()) and (select private.is_company_member(company_id)))
    or (select private.has_permission(company_id, 'users', 'read'))
  );

-- Un resumen mínimo permite mostrar el motivo del bloqueo sin exponer datos
-- operativos de empresas suspendidas. La función ignora las policies por diseño.
create function public.my_company_access()
returns table (
  company_id uuid,
  company_name text,
  company_slug text,
  company_active boolean,
  role_id uuid,
  role_name text,
  role_code text
)
language sql stable security definer set search_path = '' as $$
  select cu.company_id, c.name, c.slug, c.active,
         cu.role_id, r.name, r.code
  from public.company_users cu
  join public.companies c on c.id = cu.company_id
  join public.roles r on r.id = cu.role_id and r.company_id = cu.company_id
  where cu.user_id = (select auth.uid()) and cu.active
  order by cu.created_at;
$$;
revoke execute on function public.my_company_access() from public, anon;
grant execute on function public.my_company_access() to authenticated;

-- La invitación aún sin consumir también respeta el estado de la empresa.
create or replace function public.accept_company_invitation(p_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_invitation public.company_invitations%rowtype;
  v_user auth.users%rowtype;
begin
  if auth.uid() is null or p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Invitación inválida';
  end if;
  select * into v_user from auth.users where id = auth.uid();
  if v_user.email_confirmed_at is null then
    raise exception 'Confirmá tu correo electrónico antes de aceptar';
  end if;
  select * into v_invitation from public.company_invitations
  where token_hash = encode(digest(p_token, 'sha256'), 'hex') for update;
  if not found or v_invitation.revoked_at is not null
     or v_invitation.used_at is not null
     or v_invitation.expires_at <= now()
     or lower(v_user.email) <> v_invitation.email
     or not exists (
       select 1 from public.companies c
       where c.id = v_invitation.company_id and c.active
     ) then
    raise exception 'Invitación vencida o empresa no disponible';
  end if;
  insert into public.company_users(company_id, user_id, role_id)
  values (v_invitation.company_id, v_user.id, v_invitation.role_id);
  insert into public.profiles(id, name)
  values (v_user.id, split_part(v_user.email, '@', 1))
  on conflict (id) do nothing;
  update public.company_invitations set used_at = now()
  where id = v_invitation.id;
  return v_invitation.company_id;
end;
$$;

create table public.units (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null check (code ~ '^[a-z][a-z0-9_]{0,19}$'),
  name text not null check (length(btrim(name)) between 2 and 80),
  symbol text not null check (length(btrim(symbol)) between 1 and 12),
  dimension text not null check (
    dimension in ('count', 'mass', 'volume', 'length', 'area', 'time')
  ),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (company_id, code),
  unique (company_id, id)
);

create table public.item_categories (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null check (code ~ '^[a-z][a-z0-9_]{0,39}$'),
  name text not null check (length(btrim(name)) between 2 and 100),
  description text not null default '' check (length(description) <= 500),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (company_id, code),
  unique (company_id, id)
);

create table public.warehouses (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null check (code ~ '^[a-z][a-z0-9_]{0,39}$'),
  name text not null check (length(btrim(name)) between 2 and 100),
  location text not null default '' check (length(location) <= 250),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (company_id, code),
  unique (company_id, id)
);

create index units_listing_idx on public.units(company_id, active, name);
create index categories_listing_idx on public.item_categories(company_id, active, name);
create index warehouses_listing_idx on public.warehouses(company_id, active, name);

alter table public.units enable row level security;
alter table public.item_categories enable row level security;
alter table public.warehouses enable row level security;

create policy units_read on public.units for select to authenticated
  using ((select private.has_permission(company_id, 'units', 'read')));
create policy units_insert on public.units for insert to authenticated
  with check ((select private.has_permission(company_id, 'units', 'insert')));
create policy units_update on public.units for update to authenticated
  using ((select private.has_permission(company_id, 'units', 'update')))
  with check ((select private.has_permission(company_id, 'units', 'update')));

create policy categories_read on public.item_categories for select to authenticated
  using ((select private.has_permission(company_id, 'categories', 'read')));
create policy categories_insert on public.item_categories for insert to authenticated
  with check ((select private.has_permission(company_id, 'categories', 'insert')));
create policy categories_update on public.item_categories for update to authenticated
  using ((select private.has_permission(company_id, 'categories', 'update')))
  with check ((select private.has_permission(company_id, 'categories', 'update')));

create policy warehouses_read on public.warehouses for select to authenticated
  using ((select private.has_permission(company_id, 'warehouses', 'read')));
create policy warehouses_insert on public.warehouses for insert to authenticated
  with check ((select private.has_permission(company_id, 'warehouses', 'insert')));
create policy warehouses_update on public.warehouses for update to authenticated
  using ((select private.has_permission(company_id, 'warehouses', 'update')))
  with check ((select private.has_permission(company_id, 'warehouses', 'update')));

revoke all on public.units, public.item_categories, public.warehouses
  from anon, authenticated;
grant select on public.units, public.item_categories, public.warehouses
  to authenticated;
grant insert (company_id, code, name, symbol, dimension, active)
  on public.units to authenticated;
grant update (code, name, symbol, dimension, active)
  on public.units to authenticated;
grant insert (company_id, code, name, description, active)
  on public.item_categories to authenticated;
grant update (code, name, description, active)
  on public.item_categories to authenticated;
grant insert (company_id, code, name, location, active)
  on public.warehouses to authenticated;
grant update (code, name, location, active)
  on public.warehouses to authenticated;

-- Los administradores existentes reciben los catálogos nuevos.
insert into public.role_permissions(company_id, role_id, resource, action)
select r.company_id, r.id, resource, action
from public.roles r
cross join (values ('units'), ('categories'), ('warehouses')) as resources(resource)
cross join (values ('read'), ('insert'), ('update'), ('delete'), ('manage')) as actions(action)
where r.code = 'admin'
on conflict do nothing;

-- No concedemos UPDATE(active) en companies al cliente. Sólo un operador con
-- acceso administrativo a SQL Editor / credenciales de servidor puede cambiarlo.

-- Ampliar recursos admitidos por la administración de roles y empresas nuevas.
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
     or jsonb_array_length(p_permissions) > 50 then
    raise exception 'Lista de permisos inválida';
  end if;

  insert into public.roles(company_id, code, name)
  values (p_company, p_code, v_name) returning id into v_role;

  insert into public.role_permissions(company_id, role_id, resource, action)
  select p_company, v_role, p.resource, p.action
  from jsonb_to_recordset(p_permissions) as p(resource text, action text)
  where p.resource in ('dashboard', 'inventory', 'production', 'purchases',
                       'finance', 'reports', 'settings', 'users', 'roles',
                       'units', 'categories', 'warehouses')
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
     or jsonb_array_length(p_permissions) > 50 then
    raise exception 'Datos del rol inválidos';
  end if;

  update public.roles set name = v_name where id = p_role;
  delete from public.role_permissions where role_id = p_role;
  insert into public.role_permissions(company_id, role_id, resource, action)
  select p_company, p_role, p.resource, p.action
  from jsonb_to_recordset(p_permissions) as p(resource text, action text)
  where p.resource in ('dashboard', 'inventory', 'production', 'purchases',
                       'finance', 'reports', 'settings', 'users', 'roles',
                       'units', 'categories', 'warehouses')
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
 (values ('dashboard'),('inventory'),('production'),('purchases'),('finance'),('reports'),('settings'),('users'),('roles'),('units'),('categories'),('warehouses')) as r(resource)
 cross join (values ('read'),('insert'),('update'),('delete'),('manage')) as a(action);
 insert into public.profiles(id,name) values(v_user,coalesce(nullif(v_user::text,''),'Usuario')) on conflict (id) do nothing;
 return v_company;
end $$;

-- Endurecimiento de privilegios de tablas creadas en V1 y V2. Supabase puede
-- aplicar privilegios predeterminados sobre objetos nuevos; las escrituras
-- delicadas deben pasar por las RPC que comprueban permisos.
revoke all on public.profiles, public.companies, public.roles,
  public.company_users, public.role_permissions, public.company_settings,
  public.company_modules, public.company_invitations from authenticated;

grant select on public.profiles, public.companies, public.roles,
  public.company_users, public.role_permissions, public.company_settings,
  public.company_modules to authenticated;
grant update (name) on public.profiles to authenticated;
grant update (name) on public.companies to authenticated;
grant update (currency_code, timezone) on public.company_settings
  to authenticated;

-- El rol authenticated nunca recibe UPDATE(active) sobre companies. Las RPC
-- SECURITY DEFINER siguen funcionando con el propietario de las funciones.

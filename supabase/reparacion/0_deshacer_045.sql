-- Deshacer 045. Restaura create_company_role/update_company_role (versión 044), create_company y private.has_permission
-- originales y devuelve los permisos de los roles que existían al aplicar 045 a su estado de ANTES (copia en
-- private.role_permissions_pre045); los roles creados después de 045 conservan solo sus permisos de los 16 recursos
-- originales. Se PIERDE la configuración por pantalla hecha después de 045. Si 046 o posterior ya está aplicada, NO usar
-- este archivo: primero deshacer esas migraciones en orden inverso.
begin;

create or replace function public.create_company_role(p_company uuid, p_name text, p_code text, p_permissions jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_role uuid;
  v_name text := btrim(p_name);
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'admin' then
    raise exception 'Solo el administrador puede crear roles' using errcode = '42501';
  end if;
  if v_name is null or length(v_name) not between 2 and 60 or p_code is null or p_code !~ '^[a-z][a-z0-9_]{1,39}$' then
    raise exception 'Nombre o código inválido';
  end if;
  if p_code in ('admin', 'support') then
    raise exception 'Ese código de rol está reservado';
  end if;
  if jsonb_typeof(p_permissions) is distinct from 'array' or jsonb_array_length(p_permissions) > 100 then
    raise exception 'Lista de permisos inválida';
  end if;
  insert into public.roles(company_id, code, name) values (p_company, p_code, v_name) returning id into v_role;
  insert into public.role_permissions(company_id, role_id, resource, action)
  select p_company, v_role, p.resource, p.action
  from jsonb_to_recordset(p_permissions) as p(resource text, action text)
  where p.resource in ('dashboard', 'inventory', 'production', 'purchases', 'sales', 'finance', 'reports', 'settings',
      'users', 'roles', 'units', 'categories', 'warehouses', 'items', 'stock', 'purchase_requests')
    and p.action in ('read', 'insert', 'update', 'delete', 'manage')
  on conflict do nothing;
  if (select count(*) from public.role_permissions where role_id = v_role)
    <> (select count(distinct (entry->>'resource', entry->>'action')) from jsonb_array_elements(p_permissions) as entry) then
    raise exception 'Permisos desconocidos o repetidos';
  end if;
  perform private.log_access_event(p_company, 'role_created', null, v_role, jsonb_build_object(
    'name', v_name, 'code', p_code,
    'permissions', coalesce((select jsonb_agg(rp.resource || ':' || rp.action order by rp.resource, rp.action)
      from public.role_permissions rp where rp.role_id = v_role), '[]'::jsonb)));
  return v_role;
end;
$$;

create or replace function public.update_company_role(p_company uuid, p_role uuid, p_name text, p_permissions jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_code text;
  v_old_name text;
  v_name text := btrim(p_name);
  v_before text[];
  v_after text[];
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'admin' then
    raise exception 'Solo el administrador puede editar roles' using errcode = '42501';
  end if;
  select code, name into v_code, v_old_name from public.roles where id = p_role and company_id = p_company for update;
  if v_code is null then raise exception 'Rol inexistente'; end if;
  if v_code = 'admin' then raise exception 'El rol administrador está protegido'; end if;
  if v_code = 'support' then raise exception 'El rol de soporte no se edita desde acá'; end if;
  if v_name is null or length(v_name) not between 2 and 60
    or jsonb_typeof(p_permissions) is distinct from 'array' or jsonb_array_length(p_permissions) > 100 then
    raise exception 'Datos del rol inválidos';
  end if;
  select coalesce(array_agg(rp.resource || ':' || rp.action order by rp.resource, rp.action), '{}')
    into v_before from public.role_permissions rp where rp.role_id = p_role;
  update public.roles set name = v_name where id = p_role;
  delete from public.role_permissions where role_id = p_role;
  insert into public.role_permissions(company_id, role_id, resource, action)
  select p_company, p_role, p.resource, p.action
  from jsonb_to_recordset(p_permissions) as p(resource text, action text)
  where p.resource in ('dashboard', 'inventory', 'production', 'purchases', 'sales', 'finance', 'reports', 'settings',
      'users', 'roles', 'units', 'categories', 'warehouses', 'items', 'stock', 'purchase_requests')
    and p.action in ('read', 'insert', 'update', 'delete', 'manage')
  on conflict do nothing;
  if (select count(*) from public.role_permissions where role_id = p_role)
    <> (select count(distinct (entry->>'resource', entry->>'action')) from jsonb_array_elements(p_permissions) as entry) then
    raise exception 'Permisos desconocidos o repetidos';
  end if;
  select coalesce(array_agg(rp.resource || ':' || rp.action order by rp.resource, rp.action), '{}')
    into v_after from public.role_permissions rp where rp.role_id = p_role;
  perform private.log_access_event(p_company, 'role_updated', null, p_role, jsonb_build_object(
    'name_before', v_old_name, 'name_after', v_name,
    'added', coalesce((select jsonb_agg(x order by x) from unnest(v_after) x where x <> all (v_before)), '[]'::jsonb),
    'removed', coalesce((select jsonb_agg(x order by x) from unnest(v_before) x where x <> all (v_after)), '[]'::jsonb)));
end;
$$;

create or replace function public.create_company(p_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_company uuid; v_role uuid; v_user uuid := auth.uid(); v_name text := nullif(btrim(p_name),'');
begin
  if v_user is null then raise exception 'Iniciá sesión' using errcode='42501'; end if;
  if v_name is null or length(v_name) not between 2 and 100 then raise exception 'El nombre debe tener entre 2 y 100 caracteres'; end if;
  insert into public.companies(name,slug) values(v_name,'empresa-'||replace(gen_random_uuid()::text,'-','')) returning id into v_company;
  insert into public.roles(company_id,code,name) values(v_company,'admin','Administrador') returning id into v_role;
  insert into public.company_users(company_id,user_id,role_id) values(v_company,v_user,v_role);
  insert into public.company_settings(company_id) values(v_company);
  insert into public.company_modules(company_id,module,enabled) values (v_company,'inventory',true),(v_company,'production',true),(v_company,'purchases',true),(v_company,'sales',true),(v_company,'finance',true),(v_company,'reports',true);
  insert into public.role_permissions(company_id,role_id,resource,action) select v_company,v_role,resource,action from (values ('dashboard'),('inventory'),('production'),('purchases'),('sales'),('finance'),('reports'),('settings'),('users'),('roles'),('units'),('categories'),('warehouses'),('items'),('stock'),('purchase_requests')) as r(resource) cross join (values ('read'),('insert'),('update'),('delete'),('manage')) as a(action);
  insert into public.profiles(id,name) values(v_user,coalesce(nullif(v_user::text,''),'Usuario')) on conflict (id) do nothing;
  return v_company;
end;
$$;

create or replace function private.has_permission(p_company uuid, p_resource text, p_action text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.company_users cu join public.companies c on c.id=cu.company_id
    join public.role_permissions rp on rp.role_id=cu.role_id and rp.company_id=cu.company_id
    where cu.company_id=p_company and cu.user_id=(select auth.uid()) and cu.active and c.active
      and rp.resource=p_resource and rp.action=p_action
  ) or (
    p_action='read' and p_resource in ('dashboard','inventory','items','stock','warehouses','units','categories',
      'production','purchases','sales','finance','reports','settings','users','roles')
    and private.support_session_active(p_company)
  );
$$;

-- Roles que existían al aplicar 045: vuelven exactamente a su estado anterior.
delete from public.role_permissions where role_id in (select distinct role_id from private.role_permissions_pre045);
insert into public.role_permissions select * from private.role_permissions_pre045;
-- Roles creados después: solo los 16 recursos originales.
delete from public.role_permissions where resource not in ('dashboard', 'inventory', 'production', 'purchases', 'sales',
  'finance', 'reports', 'settings', 'users', 'roles', 'units', 'categories', 'warehouses', 'items', 'stock', 'purchase_requests');
drop function if exists private.save_role_permissions(uuid, uuid, jsonb);
drop table if exists public.permission_catalog;
drop table if exists private.role_permissions_pre045;
commit;

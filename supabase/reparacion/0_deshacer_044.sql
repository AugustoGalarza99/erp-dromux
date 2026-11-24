-- Deshacer 044: restaura las tres funciones tal como estaban el 24/11/2026 (permiso por roles:insert, roles:update y
-- users:update; vuelve la escalada H-007) y quita el historial de accesos de la interfaz: la tabla se RENOMBRA a access_audit_events_deshecho_044 (conserva los eventos; sin permisos para la API).
begin;

create or replace function public.create_company_role(p_company uuid, p_name text, p_code text, p_permissions jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_role uuid; v_name text := btrim(p_name); v_entry jsonb;
begin
  if not private.has_permission(p_company, 'roles', 'insert') then raise exception 'Sin permiso para crear roles' using errcode = '42501'; end if;
  if v_name is null or length(v_name) not between 2 and 60 or p_code is null or p_code !~ '^[a-z][a-z0-9_]{1,39}$' then raise exception 'Nombre o código inválido'; end if;
  if jsonb_typeof(p_permissions) is distinct from 'array' or jsonb_array_length(p_permissions) > 100 then raise exception 'Lista de permisos inválida'; end if;
  insert into public.roles(company_id, code, name) values (p_company, p_code, v_name) returning id into v_role;
  insert into public.role_permissions(company_id, role_id, resource, action) select p_company, v_role, p.resource, p.action from jsonb_to_recordset(p_permissions) as p(resource text, action text) where p.resource in ('dashboard', 'inventory', 'production', 'purchases', 'sales', 'finance', 'reports', 'settings', 'users', 'roles', 'units', 'categories', 'warehouses', 'items', 'stock', 'purchase_requests') and p.action in ('read', 'insert', 'update', 'delete', 'manage') on conflict do nothing;
  if (select count(*) from public.role_permissions where role_id = v_role) <> (select count(distinct (entry->>'resource', entry->>'action')) from jsonb_array_elements(p_permissions) as entry) then raise exception 'Permisos desconocidos o repetidos'; end if;
  return v_role;
end;
$$;

create or replace function public.update_company_role(p_company uuid, p_role uuid, p_name text, p_permissions jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_code text; v_name text := btrim(p_name);
begin
  if not private.has_permission(p_company, 'roles', 'update') then raise exception 'Sin permiso para editar roles' using errcode = '42501'; end if;
  select code into v_code from public.roles where id = p_role and company_id = p_company for update;
  if v_code is null then raise exception 'Rol inexistente'; end if;
  if v_code = 'admin' then raise exception 'El rol administrador está protegido'; end if;
  if v_name is null or length(v_name) not between 2 and 60 or jsonb_typeof(p_permissions) is distinct from 'array' or jsonb_array_length(p_permissions) > 100 then raise exception 'Datos del rol inválidos'; end if;
  update public.roles set name = v_name where id = p_role;
  delete from public.role_permissions where role_id = p_role;
  insert into public.role_permissions(company_id, role_id, resource, action) select p_company, p_role, p.resource, p.action from jsonb_to_recordset(p_permissions) as p(resource text, action text) where p.resource in ('dashboard', 'inventory', 'production', 'purchases', 'sales', 'finance', 'reports', 'settings', 'users', 'roles', 'units', 'categories', 'warehouses', 'items', 'stock', 'purchase_requests') and p.action in ('read', 'insert', 'update', 'delete', 'manage') on conflict do nothing;
  if (select count(*) from public.role_permissions where role_id = p_role) <> (select count(distinct (entry->>'resource', entry->>'action')) from jsonb_array_elements(p_permissions) as entry) then raise exception 'Permisos desconocidos o repetidos'; end if;
end;
$$;

create or replace function public.set_company_member(p_company uuid, p_user uuid, p_role uuid, p_active boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v_old_code text; v_new_code text; v_old_active boolean;
begin
  if auth.uid() is null or not private.has_permission(p_company,'users','update') then raise exception 'Sin permiso para editar usuarios' using errcode='42501'; end if;
  if p_active is null then raise exception 'Estado inválido'; end if;
  select r.code into v_new_code from public.roles r where r.id=p_role and r.company_id=p_company;
  if v_new_code is null then raise exception 'El rol no pertenece a esta empresa'; end if;
  perform 1 from public.companies where id=p_company for update;
  select r.code,cu.active into v_old_code,v_old_active from public.company_users cu join public.roles r on r.id=cu.role_id and r.company_id=cu.company_id where cu.company_id=p_company and cu.user_id=p_user for update of cu;
  if v_old_code is null then raise exception 'El usuario no pertenece a esta empresa'; end if;
  if (v_old_code='admin' or v_new_code='admin') and private.get_user_role(p_company)<>'admin' then raise exception 'Solo un administrador puede asignar el rol administrador'; end if;
  if p_user=auth.uid() and not p_active then raise exception 'No podés suspender tu propia cuenta'; end if;
  if v_old_code='admin' and v_old_active and (v_new_code<>'admin' or not p_active) and (select count(*) from public.company_users cu join public.roles r on r.id=cu.role_id and r.company_id=cu.company_id where cu.company_id=p_company and cu.active and r.code='admin')<=1 then raise exception 'Debe permanecer al menos un administrador activo'; end if;
  update public.company_users set role_id=p_role,active=p_active where company_id=p_company and user_id=p_user;
end;
$$;

drop function if exists public.access_audit_events_list(uuid, integer);
drop function if exists private.log_access_event(uuid, text, uuid, uuid, jsonb);
-- El historial NO se borra: se renombra para conservarlo (borrarlo a mano solo si ya no hace falta).
alter table if exists public.access_audit_events rename to access_audit_events_deshecho_044;
drop function if exists private.access_audit_immutable();
commit;

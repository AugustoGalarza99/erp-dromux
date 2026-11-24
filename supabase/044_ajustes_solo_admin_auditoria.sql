-- Dromux ERP · 044 · Ajustes: usuarios y roles solo para el administrador + historial de cambios de acceso.
-- ESTADO: PREPARADA, NO APLICADA. Aplicar solo con autorización del propietario, con respaldo y en este orden:
-- respaldo -> esta migración -> supabase/verificaciones/044_comprobaciones.sql -> pruebas_roles_empresas.sql (grupo 9)
-- -> publicar el frontend. Deshacer: supabase/reparacion/0_deshacer_044.sql (restaura las 3 funciones anteriores).
--
-- Corrige H-007 (escalada por delegación) y H-009 (sin auditoría de cambios de acceso), decididos el 24/11/2026:
--   * create_company_role, update_company_role y set_company_member exigen ser ADMINISTRADOR de la empresa
--     (private.get_user_role = 'admin'); ya no alcanza con roles:insert, roles:update ni users:update.
--   * Un rol nuevo no puede usar los códigos reservados 'admin' ni 'support'.
--   * Cada cambio de rol, de permisos o de miembro queda en public.access_audit_events (inmutable), visible solo
--     para el administrador mediante public.access_audit_events_list.
-- No cambia firmas, tipos de retorno ni permisos de ejecución de las funciones existentes; no toca datos.
-- Los cuerpos parten de los vigentes en la base (leídos el 24/11/2026); solo se agregan el control de administrador,
-- los códigos reservados y el registro de auditoría.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1) Historial de cambios de acceso. Sin políticas ni privilegios directos: se escribe desde las funciones de
--    arriba y se lee por la RPC de abajo.
-- ---------------------------------------------------------------------------------------------
create table public.access_audit_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  actor_id uuid not null,
  action text not null check (action in ('role_created', 'role_updated', 'member_updated')),
  target_user uuid,
  target_role uuid,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp()
);
create index access_audit_events_company_idx on public.access_audit_events (company_id, created_at desc, id);
alter table public.access_audit_events enable row level security;
revoke all on public.access_audit_events from public, anon, authenticated;

create function private.access_audit_immutable() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'El historial de accesos no se modifica ni se borra';
end;
$$;
revoke all on function private.access_audit_immutable() from public, anon, authenticated;
create trigger access_audit_no_change before update or delete on public.access_audit_events
  for each row execute function private.access_audit_immutable();
create trigger access_audit_no_truncate before truncate on public.access_audit_events
  for each statement execute function private.access_audit_immutable();

create function private.log_access_event(p_company uuid, p_action text, p_user uuid, p_role uuid, p_detail jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.access_audit_events(company_id, actor_id, action, target_user, target_role, detail)
  values (p_company, auth.uid(), p_action, p_user, p_role, coalesce(p_detail, '{}'::jsonb));
$$;
revoke all on function private.log_access_event(uuid, text, uuid, uuid, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 2) Roles y miembros: solo administrador + auditoría.
-- ---------------------------------------------------------------------------------------------
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
  -- Rechazamos entradas desconocidas en vez de descartarlas silenciosamente.
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

create or replace function public.set_company_member(p_company uuid, p_user uuid, p_role uuid, p_active boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_old_code text;
  v_new_code text;
  v_old_active boolean;
  v_old_role uuid;
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'admin' then
    raise exception 'Solo el administrador puede editar usuarios' using errcode = '42501';
  end if;
  if p_active is null then raise exception 'Estado inválido'; end if;
  select r.code into v_new_code from public.roles r where r.id = p_role and r.company_id = p_company;
  if v_new_code is null then raise exception 'El rol no pertenece a esta empresa'; end if;
  perform 1 from public.companies where id = p_company for update;
  select r.code, cu.active, cu.role_id into v_old_code, v_old_active, v_old_role
    from public.company_users cu
    join public.roles r on r.id = cu.role_id and r.company_id = cu.company_id
    where cu.company_id = p_company and cu.user_id = p_user for update of cu;
  if v_old_code is null then raise exception 'El usuario no pertenece a esta empresa'; end if;
  if p_user = auth.uid() and not p_active then
    raise exception 'No podés suspender tu propia cuenta';
  end if;
  if v_old_code = 'admin' and v_old_active and (v_new_code <> 'admin' or not p_active)
    and (select count(*) from public.company_users cu
      join public.roles r on r.id = cu.role_id and r.company_id = cu.company_id
      where cu.company_id = p_company and cu.active and r.code = 'admin') <= 1 then
    raise exception 'Debe permanecer al menos un administrador activo';
  end if;
  update public.company_users set role_id = p_role, active = p_active
    where company_id = p_company and user_id = p_user;
  perform private.log_access_event(p_company, 'member_updated', p_user, p_role, jsonb_build_object(
    'before', jsonb_build_object('role_id', v_old_role, 'role', v_old_code, 'active', v_old_active),
    'after', jsonb_build_object('role_id', p_role, 'role', v_new_code, 'active', p_active)));
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- 3) Lectura del historial: solo administrador, paginada en el servidor (25 por página).
-- ---------------------------------------------------------------------------------------------
create function public.access_audit_events_list(p_company uuid, p_page integer default 0)
returns table (
  created_at timestamptz,
  action text,
  actor_email text,
  target_email text,
  target_role_name text,
  detail jsonb,
  total_count bigint
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'admin' then
    raise exception 'Solo el administrador puede ver el historial de accesos' using errcode = '42501';
  end if;
  if p_page is null or p_page < 0 or p_page > 100000 then
    raise exception 'Página inválida';
  end if;
  return query
    select e.created_at, e.action, a.email::text, t.email::text, r.name, e.detail, count(*) over ()
    from public.access_audit_events e
    left join auth.users a on a.id = e.actor_id
    left join auth.users t on t.id = e.target_user
    left join public.roles r on r.id = e.target_role and r.company_id = e.company_id
    where e.company_id = p_company
    order by e.created_at desc, e.id desc
    limit 25 offset p_page * 25;
end;
$$;

revoke all on function public.access_audit_events_list(uuid, integer) from public, anon, authenticated;
grant execute on function public.access_audit_events_list(uuid, integer) to authenticated;

commit;

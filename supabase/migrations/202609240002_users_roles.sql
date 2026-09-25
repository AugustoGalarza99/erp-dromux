-- ERP Dromux · usuarios, roles e invitaciones.
-- Ejecutar una vez después de 202609240001_core.sql.

create table public.company_invitations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  email text not null check (length(email) between 3 and 320),
  role_id uuid not null,
  token_hash text not null unique,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  used_at timestamptz,
  revoked_at timestamptz,
  foreign key (company_id, role_id) references public.roles(company_id, id)
);

create index company_invitations_company_idx
  on public.company_invitations(company_id, created_at desc);

alter table public.company_invitations enable row level security;
revoke all on public.company_invitations from anon, authenticated;

-- Identidad de usuarios sólo para administradores de esa empresa.
create function public.company_members(p_company uuid)
returns table (
  user_id uuid,
  email text,
  display_name text,
  role_id uuid,
  role_name text,
  active boolean,
  joined_at timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.has_permission(p_company, 'users', 'read') then
    raise exception 'Sin permiso para ver usuarios' using errcode = '42501';
  end if;

  return query
    select cu.user_id, u.email::text, nullif(p.name, u.id::text), cu.role_id, r.name,
           cu.active, cu.created_at
    from public.company_users cu
    join auth.users u on u.id = cu.user_id
    join public.roles r on r.id = cu.role_id and r.company_id = cu.company_id
    left join public.profiles p on p.id = cu.user_id
    where cu.company_id = p_company
    order by cu.created_at desc
    limit 500;
end;
$$;

create function public.company_invitation_list(p_company uuid)
returns table (
  id uuid,
  email text,
  role_name text,
  created_at timestamptz,
  expires_at timestamptz,
  used_at timestamptz,
  revoked_at timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.has_permission(p_company, 'users', 'read') then
    raise exception 'Sin permiso para ver invitaciones' using errcode = '42501';
  end if;

  return query
    select i.id, i.email, r.name, i.created_at, i.expires_at,
           i.used_at, i.revoked_at
    from public.company_invitations i
    join public.roles r on r.id = i.role_id and r.company_id = i.company_id
    where i.company_id = p_company
    order by i.created_at desc
    limit 100;
end;
$$;

create function public.create_company_role(
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
                       'finance', 'reports', 'settings', 'users', 'roles')
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

create function public.update_company_role(
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
                       'finance', 'reports', 'settings', 'users', 'roles')
    and p.action in ('read', 'insert', 'update', 'delete', 'manage')
  on conflict do nothing;

  if (select count(*) from public.role_permissions where role_id = p_role)
     <> (select count(distinct (entry->>'resource', entry->>'action'))
         from jsonb_array_elements(p_permissions) as entry) then
    raise exception 'Permisos desconocidos o repetidos';
  end if;
end;
$$;

create function public.create_company_invitation(
  p_company uuid, p_email text, p_role uuid
) returns text
language plpgsql security definer set search_path = '' as $$
declare v_email text := lower(btrim(p_email)); v_token text; v_code text;
begin
  if not private.has_permission(p_company, 'users', 'insert') then
    raise exception 'Sin permiso para invitar usuarios' using errcode = '42501';
  end if;
  if v_email is null or length(v_email) not between 3 and 320
     or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Correo electrónico inválido';
  end if;
  select code into v_code from public.roles
  where id = p_role and company_id = p_company;
  if v_code is null then raise exception 'Rol inexistente'; end if;
  if v_code = 'admin' and private.get_user_role(p_company) <> 'admin' then
    raise exception 'Sólo un administrador puede invitar administradores';
  end if;
  if exists (
    select 1 from public.company_users cu join auth.users u on u.id = cu.user_id
    where cu.company_id = p_company and lower(u.email) = v_email
  ) then raise exception 'Este correo ya pertenece a la empresa'; end if;

  v_token := encode(gen_random_bytes(32), 'hex');
  insert into public.company_invitations(
    company_id, email, role_id, token_hash, created_by
  ) values (
    p_company, v_email, p_role, encode(digest(v_token, 'sha256'), 'hex'), auth.uid()
  );
  return v_token;
end;
$$;

create function public.revoke_company_invitation(p_company uuid, p_invitation uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.has_permission(p_company, 'users', 'delete') then
    raise exception 'Sin permiso para revocar invitaciones' using errcode = '42501';
  end if;
  update public.company_invitations set revoked_at = now()
  where id = p_invitation and company_id = p_company
    and used_at is null and revoked_at is null;
end;
$$;

create function public.accept_company_invitation(p_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_invitation public.company_invitations%rowtype;
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
     or lower(v_user.email) <> v_invitation.email then
    raise exception 'Invitación vencida o no corresponde a tu correo';
  end if;

  insert into public.company_users(company_id, user_id, role_id)
  values(v_invitation.company_id, v_user.id, v_invitation.role_id);
  insert into public.profiles(id, name) values(v_user.id, split_part(v_user.email, '@', 1))
  on conflict (id) do nothing;
  update public.company_invitations set used_at = now() where id = v_invitation.id;
  return v_invitation.company_id;
end;
$$;

create function public.set_company_member(
  p_company uuid, p_user uuid, p_role uuid, p_active boolean
) returns void language plpgsql security definer set search_path = '' as $$
declare v_old_code text; v_new_code text; v_old_active boolean;
begin
  if not private.has_permission(p_company, 'users', 'update') then
    raise exception 'Sin permiso para modificar usuarios' using errcode = '42501';
  end if;
  if p_active is null then raise exception 'Estado inválido'; end if;
  select r.code into v_new_code from public.roles r
  where r.id = p_role and r.company_id = p_company;
  if v_new_code is null then raise exception 'Rol inexistente'; end if;

  select r.code, cu.active into v_old_code, v_old_active
  from public.company_users cu
  join public.roles r on r.id = cu.role_id and r.company_id = cu.company_id
  where cu.company_id = p_company and cu.user_id = p_user for update of cu;
  if v_old_code is null then raise exception 'Usuario inexistente'; end if;
  if (v_old_code = 'admin' or v_new_code = 'admin')
     and private.get_user_role(p_company) <> 'admin' then
    raise exception 'Sólo un administrador puede gestionar administradores';
  end if;
  if p_user = auth.uid() and not p_active then
    raise exception 'No podés desactivar tu propia cuenta';
  end if;
  if v_old_code = 'admin' and v_old_active
     and (v_new_code <> 'admin' or not p_active) then
    perform 1 from public.companies where id = p_company for update;
    if (select count(*) from public.company_users cu
        join public.roles r on r.id = cu.role_id
        where cu.company_id = p_company and cu.active and r.code = 'admin') <= 1 then
      raise exception 'Debe permanecer al menos un administrador activo';
    end if;
  end if;

  update public.company_users set role_id = p_role, active = p_active
  where company_id = p_company and user_id = p_user;
end;
$$;

revoke execute on function public.company_members(uuid),
  public.company_invitation_list(uuid),
  public.create_company_role(uuid,text,text,jsonb),
  public.update_company_role(uuid,uuid,text,jsonb),
  public.create_company_invitation(uuid,text,uuid),
  public.revoke_company_invitation(uuid,uuid),
  public.accept_company_invitation(text),
  public.set_company_member(uuid,uuid,uuid,boolean) from public, anon;

grant execute on function public.company_members(uuid),
  public.company_invitation_list(uuid),
  public.create_company_role(uuid,text,text,jsonb),
  public.update_company_role(uuid,uuid,text,jsonb),
  public.create_company_invitation(uuid,text,uuid),
  public.revoke_company_invitation(uuid,uuid),
  public.accept_company_invitation(text),
  public.set_company_member(uuid,uuid,uuid,boolean) to authenticated;

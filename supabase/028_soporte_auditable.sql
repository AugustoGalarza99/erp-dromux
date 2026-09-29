-- ERP Dromux · acceso de soporte entre empresas, solo lectura.
-- Requiere el esquema base y las migraciones hasta 027.
-- El operador no integra company_users, por lo tanto no figura como empleado.
-- Cada empresa abierta requiere una sesión temporal con motivo y auditoría.

create table private.support_operators (
  user_id uuid primary key references auth.users(id) on delete cascade,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table private.support_sessions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  expires_at timestamptz not null
);

create table private.support_access_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id),
  company_id uuid not null references public.companies(id),
  reason text not null check (length(btrim(reason)) between 8 and 300),
  started_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null
);

create index support_access_log_company_time
  on private.support_access_log(company_id, started_at desc);

revoke all on private.support_operators, private.support_sessions,
  private.support_access_log from public, anon, authenticated;

create function private.support_session_active(p_company uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from private.support_sessions ss
    join private.support_operators so on so.user_id=ss.user_id and so.active
    join public.companies c on c.id=ss.company_id and c.active
    where ss.user_id=(select auth.uid()) and ss.company_id=p_company
      and ss.expires_at>now()
  );
$$;
revoke execute on function private.support_session_active(uuid) from public,anon,authenticated;

create or replace function private.is_company_member(p_company uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.company_users cu
    join public.companies c on c.id=cu.company_id
    where cu.company_id=p_company and cu.user_id=(select auth.uid())
      and cu.active and c.active
  ) or private.support_session_active(p_company);
$$;

create or replace function private.has_permission(
  p_company uuid,p_resource text,p_action text
) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.company_users cu
    join public.companies c on c.id=cu.company_id
    join public.role_permissions rp on rp.role_id=cu.role_id
      and rp.company_id=cu.company_id
    where cu.company_id=p_company and cu.user_id=(select auth.uid())
      and cu.active and c.active and rp.resource=p_resource and rp.action=p_action
  ) or (
    p_action='read' and p_resource in (
      'dashboard','inventory','items','stock','warehouses','units','categories',
      'production','purchases','sales','finance','reports','settings','users','roles'
    ) and private.support_session_active(p_company)
  );
$$;

create or replace function private.get_user_role(p_company uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce((
    select r.code from public.company_users cu
    join public.companies c on c.id=cu.company_id
    join public.roles r on r.id=cu.role_id and r.company_id=cu.company_id
    where cu.company_id=p_company and cu.user_id=(select auth.uid())
      and cu.active and c.active limit 1
  ),case when private.support_session_active(p_company) then 'support' end);
$$;

-- Conservar la misma firma que consume el frontend actual.
create or replace function public.my_company_access()
returns table (
  company_id uuid, company_name text, company_slug text,
  company_active boolean, role_id uuid, role_name text, role_code text
) language sql stable security definer set search_path = '' as $$
  select cu.company_id,c.name,c.slug,c.active,cu.role_id,r.name,r.code
  from public.company_users cu
  join public.companies c on c.id=cu.company_id
  join public.roles r on r.id=cu.role_id and r.company_id=cu.company_id
  where cu.user_id=(select auth.uid()) and cu.active
  union all
  select c.id,c.name,c.slug,c.active,null::uuid,'Soporte Dromux','support'
  from public.companies c
  where c.active and exists (
    select 1 from private.support_operators so
    where so.user_id=(select auth.uid()) and so.active
  ) and not exists (
    select 1 from public.company_users cu
    where cu.company_id=c.id and cu.user_id=(select auth.uid()) and cu.active
  );
$$;

create function public.begin_support_session(p_company uuid,p_reason text)
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare v_expires timestamptz := now()+interval '30 minutes';
begin
  if auth.uid() is null or length(btrim(coalesce(p_reason,''))) not between 8 and 300
    or not exists (select 1 from private.support_operators so
      where so.user_id=auth.uid() and so.active)
    or not exists (select 1 from public.companies c
      where c.id=p_company and c.active) then
    raise exception 'Acceso de soporte no autorizado' using errcode='42501';
  end if;
  insert into private.support_sessions(user_id,company_id,expires_at)
  values(auth.uid(),p_company,v_expires)
  on conflict(user_id) do update set company_id=excluded.company_id,
    expires_at=excluded.expires_at;
  insert into private.support_access_log(user_id,company_id,reason,expires_at)
  values(auth.uid(),p_company,btrim(p_reason),v_expires);
  return v_expires;
end;
$$;
revoke execute on function public.begin_support_session(uuid,text) from public,anon;
grant execute on function public.begin_support_session(uuid,text) to authenticated;

-- Activación manual, solo desde SQL Editor con privilegios de administrador:
-- insert into private.support_operators(user_id)
-- select id from auth.users where lower(email)=lower('TU_EMAIL_VERIFICADO');
-- Consultar accesos: select * from private.support_access_log order by started_at desc;
-- Desactivar: update private.support_operators set active=false where user_id='UUID';

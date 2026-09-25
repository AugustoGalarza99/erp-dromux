-- ERP Dromux · core v1. Aplicar como migración en un proyecto nuevo.
create extension if not exists pgcrypto;
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 name text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.companies (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(btrim(name)) between 2 and 100),
 slug text not null unique,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.roles (
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
 code text not null check(code ~ '^[a-z][a-z0-9_]*$'), name text not null,
 created_at timestamptz not null default now(), unique(company_id,code), unique(company_id,id)
);
create table public.company_users (
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role_id uuid not null, active boolean not null default true,
 created_at timestamptz not null default now(), unique(company_id,user_id),
 foreign key(company_id,role_id) references public.roles(company_id,id)
);
create index company_users_user_idx on public.company_users(user_id,company_id) where active;
create table public.role_permissions (
 company_id uuid not null, role_id uuid not null,
 resource text not null check(resource ~ '^[a-z][a-z0-9_]*$'),
 action text not null check(action in ('read','insert','update','delete','manage')),
 primary key(role_id,resource,action), foreign key(company_id,role_id) references public.roles(company_id,id) on delete cascade
);
create index role_permissions_company_idx on public.role_permissions(company_id,role_id);
create table public.company_settings (
 company_id uuid primary key references public.companies(id) on delete cascade,
 currency_code text not null default 'ARS' check(currency_code ~ '^[A-Z]{3}$'),
 timezone text not null default 'America/Argentina/Cordoba',
 updated_at timestamptz not null default now()
);
create table public.company_modules (
 company_id uuid not null references public.companies(id) on delete cascade,
 module text not null check(module ~ '^[a-z][a-z0-9_]*$'), enabled boolean not null default false,
 primary key(company_id,module)
);

-- Funciones de autorización fuera del esquema Data API.
create function private.is_company_member(p_company uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.company_users cu where cu.company_id=p_company and cu.user_id=(select auth.uid()) and cu.active)
$$;
create function private.has_permission(p_company uuid,p_resource text,p_action text) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.company_users cu join public.role_permissions rp
 on rp.role_id=cu.role_id and rp.company_id=cu.company_id
 where cu.company_id=p_company and cu.user_id=(select auth.uid()) and cu.active
 and rp.resource=p_resource and rp.action=p_action)
$$;
create function private.get_user_role(p_company uuid) returns text
language sql stable security definer set search_path = '' as $$
 select r.code from public.company_users cu join public.roles r on r.id=cu.role_id and r.company_id=cu.company_id
 where cu.company_id=p_company and cu.user_id=(select auth.uid()) and cu.active limit 1
$$;
revoke all on function private.is_company_member(uuid),private.has_permission(uuid,text,text),private.get_user_role(uuid) from public,anon;
grant execute on function private.is_company_member(uuid),private.has_permission(uuid,text,text),private.get_user_role(uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.companies enable row level security;
alter table public.roles enable row level security;
alter table public.company_users enable row level security;
alter table public.role_permissions enable row level security;
alter table public.company_settings enable row level security;
alter table public.company_modules enable row level security;

create policy profiles_self_select on public.profiles for select to authenticated using(id=(select auth.uid()));
create policy profiles_self_update on public.profiles for update to authenticated using(id=(select auth.uid())) with check(id=(select auth.uid()));
create policy companies_member_select on public.companies for select to authenticated using((select private.is_company_member(id)));
create policy companies_admin_update on public.companies for update to authenticated using((select private.has_permission(id,'settings','update'))) with check((select private.has_permission(id,'settings','update')));
create policy roles_member_select on public.roles for select to authenticated using((select private.is_company_member(company_id)));
create policy company_users_self_or_admin_select on public.company_users for select to authenticated using(user_id=(select auth.uid()) or (select private.has_permission(company_id,'users','read')));
create policy role_permissions_member_select on public.role_permissions for select to authenticated using((select private.is_company_member(company_id)));
create policy company_settings_member_select on public.company_settings for select to authenticated using((select private.is_company_member(company_id)));
create policy company_settings_admin_update on public.company_settings for update to authenticated using((select private.has_permission(company_id,'settings','update'))) with check((select private.has_permission(company_id,'settings','update')));
create policy company_modules_member_select on public.company_modules for select to authenticated using((select private.is_company_member(company_id)));

-- Alta inicial atómica: el usuario autenticado crea su empresa y adquiere su propio rol admin.
create function public.create_company(p_name text) returns uuid
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
 (values ('dashboard'),('inventory'),('production'),('purchases'),('finance'),('reports'),('settings'),('users'),('roles')) as r(resource)
 cross join (values ('read'),('insert'),('update'),('delete'),('manage')) as a(action);
 insert into public.profiles(id,name) values(v_user,coalesce(nullif(v_user::text,''),'Usuario')) on conflict (id) do nothing;
 return v_company;
end $$;
revoke all on function public.create_company(text) from public,anon;
grant execute on function public.create_company(text) to authenticated;

-- No se conceden escrituras directas sobre roles, membresías o permisos al cliente.
revoke all on public.profiles,public.companies,public.roles,public.company_users,public.role_permissions,public.company_settings,public.company_modules from anon;
grant select on public.profiles,public.companies,public.roles,public.company_users,public.role_permissions,public.company_settings,public.company_modules to authenticated;
grant update(name) on public.profiles to authenticated;
grant update(name) on public.companies to authenticated;
grant update(currency_code,timezone) on public.company_settings to authenticated;

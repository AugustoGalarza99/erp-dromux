-- ERP Dromux · maestro de ítems V1.
-- Aplicar después de 202609240003_company_status_catalogs.sql.

create table public.items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null check (code ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$'),
  name text not null check (length(btrim(name)) between 2 and 160),
  item_type text not null check (
    item_type in ('raw_material', 'semi_finished', 'finished_product', 'consumable')
  ),
  category_id uuid,
  unit_id uuid not null,
  barcode text check (barcode is null or length(btrim(barcode)) between 4 and 80),
  description text not null default '' check (length(description) <= 1500),
  minimum_stock numeric(18, 6) not null default 0 check (minimum_stock >= 0),
  track_lots boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint items_company_code_unique unique (company_id, code),
  constraint items_company_id_unique unique (company_id, id),
  constraint items_category_company_fk foreign key (company_id, category_id)
    references public.item_categories(company_id, id),
  constraint items_unit_company_fk foreign key (company_id, unit_id)
    references public.units(company_id, id)
);

create index items_company_type_name_idx
  on public.items(company_id, item_type, active, name, id);
create index items_company_name_idx
  on public.items(company_id, name, id);
create index items_category_idx on public.items(company_id, category_id);
create unique index items_company_code_casefold_unique
  on public.items(company_id, lower(code));
create unique index items_company_barcode_unique
  on public.items(company_id, barcode) where barcode is not null;

-- Un ítem nuevo no puede referenciar una unidad/categoría inactiva.
-- Se admiten ítems históricos si el catálogo se desactiva después.
create function private.check_item_catalogs()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_check_unit boolean;
  v_check_category boolean;
begin
  if tg_op = 'INSERT' then
    v_check_unit := true;
    v_check_category := true;
  else
    v_check_unit := new.unit_id is distinct from old.unit_id;
    v_check_category := new.category_id is distinct from old.category_id;
  end if;

  if v_check_unit and not exists (
    select 1 from public.units u
    where u.id = new.unit_id and u.company_id = new.company_id and u.active
  ) then
    raise exception 'Seleccioná una unidad activa de esta empresa';
  end if;

  if v_check_category and new.category_id is not null and not exists (
    select 1 from public.item_categories c
    where c.id = new.category_id and c.company_id = new.company_id and c.active
  ) then
    raise exception 'Seleccioná una categoría activa de esta empresa';
  end if;

  return new;
end;
$$;

create trigger items_check_catalogs
before insert or update of company_id, category_id, unit_id
on public.items for each row execute function private.check_item_catalogs();

create function private.touch_item_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger items_touch_updated_at
before update on public.items for each row
execute function private.touch_item_updated_at();

revoke execute on function private.check_item_catalogs(),
  private.touch_item_updated_at() from public, anon, authenticated;

alter table public.items enable row level security;

create policy items_read on public.items for select to authenticated
  using ((select private.has_permission(company_id, 'items', 'read')));
create policy items_insert on public.items for insert to authenticated
  with check ((select private.has_permission(company_id, 'items', 'insert')));
create policy items_update on public.items for update to authenticated
  using ((select private.has_permission(company_id, 'items', 'update')))
  with check ((select private.has_permission(company_id, 'items', 'update')));

revoke all on public.items from anon, authenticated;
grant select on public.items to authenticated;
grant insert (
  company_id, code, name, item_type, category_id, unit_id,
  barcode, description, minimum_stock, track_lots, active
) on public.items to authenticated;
grant update (
  code, name, item_type, category_id, unit_id,
  barcode, description, minimum_stock, track_lots, active
) on public.items to authenticated;

-- Permisos para administradores de empresas ya creadas.
insert into public.role_permissions(company_id, role_id, resource, action)
select r.company_id, r.id, 'items', a.action
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
                       'units', 'categories', 'warehouses', 'items')
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
                       'units', 'categories', 'warehouses', 'items')
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
 (values ('dashboard'),('inventory'),('production'),('purchases'),('finance'),('reports'),('settings'),('users'),('roles'),('units'),('categories'),('warehouses'),('items')) as r(resource)
 cross join (values ('read'),('insert'),('update'),('delete'),('manage')) as a(action);
 insert into public.profiles(id,name) values(v_user,coalesce(nullif(v_user::text,''),'Usuario')) on conflict (id) do nothing;
 return v_company;
end $$;


-- Dromux ERP · 045 · Permisos por pantalla: catálogo, reparto de los roles actuales y guardado de roles por pantalla.
-- ESTADO: PREPARADA, NO APLICADA. Aplicar solo con autorización del propietario, con respaldo y en este orden:
-- respaldo -> esta migración -> supabase/verificaciones/045_comprobaciones.sql -> pruebas_roles_empresas.sql (grupo 10)
-- -> publicar el frontend. Deshacer: supabase/reparacion/0_deshacer_045.sql (ver advertencia al inicio de ese archivo).
-- Diseño: docs/ai/DISENO_045_PERMISOS_FINOS.md.
--
-- Qué hace (NO cambia el acceso de nadie al aplicarla: ninguna función ni política exige todavía los permisos nuevos;
-- eso se hace por módulo en 046 Compras, 047 Producción y 048 Stock/Ajustes):
--   1) public.permission_catalog: lista cerrada de módulos y pantallas (legible por usuarios autenticados, no es sensible).
--   2) Reparto: cada rol que tiene el permiso de un módulo con pantallas (compras, producción, stock) recibe las mismas
--      acciones en cada una de sus pantallas. ÚNICO ensanchamiento (revisión crítica): purchase_requests ya se exigía
--      desde la 038 y ahora es hija de purchases, así que un rol con purchases:update recibe purchase_requests:update
--      (cancelar sus propios pedidos pendientes; antes solo podía rechazar). Es consistente con "módulo completo". Los administradores reciben además costs_materials y costs_production.
--   3) create_company_role y update_company_role validan contra el catálogo, expanden "módulo completo" a sus pantallas
--      y derivan el permiso del módulo solo cuando el rol tiene TODAS sus pantallas (así un rol parcial no abre el resto
--      mientras las funciones todavía miran el módulo). Siguen siendo solo del administrador y auditadas (044).
--   4) create_company da al administrador de una empresa nueva todo el catálogo.
--   5) has_permission: el rol de soporte (solo lectura) alcanza también las pantallas nuevas, excepto los costos.
-- Los cuerpos de las funciones reemplazadas parten de los vigentes en la base (leídos el 24/11/2026).

begin;

-- Copia de seguridad de los permisos actuales: el deshacer los restaura tal cual estaban (sin acceso para la API).
create table private.role_permissions_pre045 as select * from public.role_permissions;
alter table private.role_permissions_pre045 enable row level security;
revoke all on private.role_permissions_pre045 from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 1) Catálogo
-- ---------------------------------------------------------------------------------------------
create table public.permission_catalog (
  resource text primary key check (resource ~ '^[a-z][a-z0-9_]*$'),
  module text not null,
  parent text references public.permission_catalog(resource),
  label text not null check (length(btrim(label)) between 2 and 80),
  help text not null default '',
  sort integer not null,
  actions text[] not null default array['read', 'insert', 'update', 'delete', 'manage'],
  is_group boolean not null default false,      -- agrupa pantallas: no es una pantalla en sí
  admin_only boolean not null default false,    -- no se puede delegar a otros roles
  enforced boolean not null default false,      -- true cuando el servidor ya exige este permiso por pantalla
  check (parent is null or parent <> resource),
  check (actions <@ array['read', 'insert', 'update', 'delete', 'manage'] and cardinality(actions) > 0)
);
create index permission_catalog_parent_idx on public.permission_catalog (parent);
alter table public.permission_catalog enable row level security;
create policy permission_catalog_read on public.permission_catalog for select to authenticated using (true);
revoke all on public.permission_catalog from public, anon, authenticated;
grant select on public.permission_catalog to authenticated;

-- Módulos: home, stock, production, sales, purchases, finance, reports, settings, sensitive (orden = orden del menú).
insert into public.permission_catalog (resource, module, parent, label, help, sort, is_group, admin_only, actions) values
  ('dashboard', 'home', null, 'Inicio', 'Panel principal con las decisiones del día.', 10, false, false, default),
  -- Stock
  ('inventory', 'stock', null, 'Resumen de stock', 'Panel general de existencias y alertas.', 100, false, false, default),
  ('items', 'stock', null, 'Ítems', 'Fichas de materiales y productos, altas e importación.', 110, false, false, default),
  ('stock', 'stock', null, 'Stock (todas las pantallas)', 'Agrupa existencias, movimientos y remitos.', 120, true, false, default),
  ('stock_levels', 'stock', 'stock', 'Stock por depósito', 'Existencias por depósito e ingresos o egresos manuales.', 121, false, false, default),
  ('stock_movements', 'stock', 'stock', 'Movimientos', 'Historial de entradas y salidas.', 122, false, false, default),
  ('stock_delivery_notes', 'stock', 'stock', 'Remitos de entrega', 'Remitos de entrega de materiales y productos.', 123, false, false, default),
  -- Producción
  ('production', 'production', null, 'Producción (todas las pantallas)', 'Agrupa todas las pantallas de producción.', 200, true, false, default),
  ('production_overview', 'production', 'production', 'Resumen de producción', 'Qué se fabrica, qué falta y qué decidir hoy.', 201, false, false, default),
  ('production_orders', 'production', 'production', 'Órdenes de fabricación', 'Crear, iniciar, entregar insumos, devolver y terminar órdenes.', 202, false, false, default),
  ('production_formulas', 'production', 'production', 'Fórmulas', 'Fórmulas o recetas de los productos.', 203, false, false, default),
  ('production_planning', 'production', 'production', 'Planificación', 'Planes de producción.', 204, false, false, default),
  ('production_availability', 'production', 'production', '¿Alcanza el stock para fabricar?', 'Simulador de faltantes.', 205, false, false, default),
  ('production_replenishment', 'production', 'production', 'Pronóstico y reposición', 'Qué reponer y cuándo.', 206, false, false, default),
  ('production_packaging', 'production', 'production', 'Envases y presentaciones', 'Tipos de envase y presentaciones.', 207, false, false, default),
  ('production_stats', 'production', 'production', 'Estadística de producción', 'Cuánto se produjo por mes, semana o rango.', 208, false, false, default),
  ('production_documents', 'production', 'production', 'Formato de documentos de producción', 'Logo, código y campos de la hoja de fabricación.', 209, false, false, default),
  -- Ventas (todavía una sola entrada; se divide por pantalla en una ronda posterior)
  ('sales', 'sales', null, 'Ventas (todas las pantallas)', 'Resumen, presupuestos, clientes, listas de precios y registro de ventas.', 300, false, false, default),
  -- Compras
  ('purchases', 'purchases', null, 'Compras (todas las pantallas)', 'Agrupa todas las pantallas de compras.', 400, true, false, default),
  ('purchases_overview', 'purchases', 'purchases', 'Resumen de compras', 'Panel general de compras.', 401, false, false, default),
  ('purchase_requests', 'purchases', 'purchases', 'Pedidos internos', 'Pedir materiales que faltan; Compras los revisa.', 402, false, false, default),
  ('purchases_orders', 'purchases', 'purchases', 'Órdenes de compra', 'Órdenes de compra y recepción de mercadería.', 403, false, false, default),
  ('purchases_suppliers', 'purchases', 'purchases', 'Proveedores', 'Proveedores y catálogo de precios.', 404, false, false, default),
  ('purchases_accounts', 'purchases', 'purchases', 'Compras y cuentas', 'Deuda con proveedores, órdenes de pago y estadísticas.', 405, false, false, default),
  -- Finanzas y reportes
  ('finance', 'finance', null, 'Finanzas (todas las pantallas)', 'Cuentas por cobrar, tesorería y rentabilidad.', 500, false, false, default),
  ('reports', 'reports', null, 'Reportes', 'Resumen por período y exportaciones.', 600, false, false, default),
  -- Ajustes
  ('settings', 'settings', null, 'Datos de la empresa', 'Nombre y datos generales de la empresa.', 700, false, false, default),
  ('units', 'settings', null, 'Unidades', 'Unidades de medida.', 710, false, false, default),
  ('categories', 'settings', null, 'Categorías', 'Categorías de ítems.', 720, false, false, default),
  ('warehouses', 'settings', null, 'Depósitos', 'Depósitos y ubicaciones.', 730, false, false, default),
  ('users', 'settings', null, 'Usuarios', 'Alta, cambio de rol y suspensión. Solo el administrador.', 740, false, true, default),
  ('roles', 'settings', null, 'Roles y permisos', 'Crear roles y definir accesos. Solo el administrador.', 750, false, true, default);
-- Datos sensibles: independientes de los módulos; los decide el administrador rol por rol. Solo la acción "ver".
insert into public.permission_catalog (resource, module, parent, label, help, sort, is_group, admin_only, actions) values
  ('costs_materials', 'sensitive', null, 'Ver costos de materiales', 'Costo de referencia de materias primas y semielaborados.', 800, false, false, array['read']),
  ('costs_production', 'sensitive', null, 'Ver costos y márgenes de producción', 'Costos de fórmulas y órdenes, márgenes y listas con costos.', 810, false, false, array['read']);

-- ---------------------------------------------------------------------------------------------
-- 2) Reparto de los permisos actuales (sin cambio de acceso real)
-- ---------------------------------------------------------------------------------------------
insert into public.role_permissions (company_id, role_id, resource, action)
select rp.company_id, rp.role_id, c.resource, rp.action
from public.role_permissions rp
join public.permission_catalog c on c.parent = rp.resource
where rp.action = any (c.actions)
on conflict do nothing;

-- Los administradores reciben los dos permisos de costos de forma explícita.
insert into public.role_permissions (company_id, role_id, resource, action)
select r.company_id, r.id, c.resource, 'read'
from public.roles r cross join public.permission_catalog c
where r.code = 'admin' and c.module = 'sensitive'
on conflict do nothing;

-- ---------------------------------------------------------------------------------------------
-- 3) Guardado de permisos de un rol (ayudante privado, sin acceso para la API)
-- ---------------------------------------------------------------------------------------------
-- Sin SECURITY DEFINER a propósito: solo lo llaman las funciones de administración (que sí lo son) y no tiene EXECUTE para la API.
create function private.save_role_permissions(p_company uuid, p_role uuid, p_permissions jsonb)
returns void language plpgsql set search_path = '' as $$
declare
  v_total integer;
  v_distinct integer;
  v_valid integer;
begin
  if not exists (select 1 from public.roles where id = p_role and company_id = p_company) then
    raise exception 'Rol inexistente en esta empresa';
  end if;
  if jsonb_typeof(p_permissions) is distinct from 'array' then
    raise exception 'Lista de permisos inválida';
  end if;
  if jsonb_array_length(p_permissions) > 300 then
    raise exception 'Lista de permisos inválida';
  end if;
  if exists (select 1 from jsonb_array_elements(p_permissions) e
    where jsonb_typeof(e) <> 'object' or jsonb_typeof(e->'resource') is distinct from 'string'
      or jsonb_typeof(e->'action') is distinct from 'string') then
    raise exception 'Lista de permisos inválida';
  end if;
  select count(*), count(distinct (e->>'resource', e->>'action')) into v_total, v_distinct
    from jsonb_array_elements(p_permissions) e;
  if v_total <> v_distinct then raise exception 'Permisos repetidos'; end if;
  select count(*) into v_valid
    from (select distinct e->>'resource' as r, e->>'action' as a from jsonb_array_elements(p_permissions) e) x
    join public.permission_catalog c on c.resource = x.r and x.a = any (c.actions) and not c.admin_only;
  if v_valid <> v_distinct then
    raise exception 'Permisos desconocidos o reservados al administrador';
  end if;

  insert into public.role_permissions (company_id, role_id, resource, action)
  select p_company, p_role, e->>'resource', e->>'action' from jsonb_array_elements(p_permissions) e
  on conflict do nothing;

  -- "Módulo completo" en el pedido = todas sus pantallas.
  insert into public.role_permissions (company_id, role_id, resource, action)
  select p_company, p_role, c.resource, rp.action
  from public.role_permissions rp
  join public.permission_catalog c on c.parent = rp.resource
  where rp.role_id = p_role and rp.action = any (c.actions)
  on conflict do nothing;

  -- El permiso del módulo existe solo si el rol tiene TODAS sus pantallas con esa acción.
  insert into public.role_permissions (company_id, role_id, resource, action)
  select p_company, p_role, g.resource, a.action
  from public.permission_catalog g cross join lateral unnest(g.actions) as a(action)
  where g.is_group
    and exists (select 1 from public.permission_catalog ch where ch.parent = g.resource)
    and not exists (
      select 1 from public.permission_catalog ch
      where ch.parent = g.resource and a.action = any (ch.actions)
        and not exists (select 1 from public.role_permissions rp
          where rp.role_id = p_role and rp.resource = ch.resource and rp.action = a.action))
  on conflict do nothing;
end;
$$;
revoke all on function private.save_role_permissions(uuid, uuid, jsonb) from public, anon, authenticated;

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
  insert into public.roles(company_id, code, name) values (p_company, p_code, v_name) returning id into v_role;
  perform private.save_role_permissions(p_company, v_role, p_permissions);
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
  if v_name is null or length(v_name) not between 2 and 60 then
    raise exception 'Datos del rol inválidos';
  end if;
  select coalesce(array_agg(rp.resource || ':' || rp.action order by rp.resource, rp.action), '{}')
    into v_before from public.role_permissions rp where rp.role_id = p_role;
  update public.roles set name = v_name where id = p_role;
  delete from public.role_permissions where role_id = p_role;
  perform private.save_role_permissions(p_company, p_role, p_permissions);
  select coalesce(array_agg(rp.resource || ':' || rp.action order by rp.resource, rp.action), '{}')
    into v_after from public.role_permissions rp where rp.role_id = p_role;
  perform private.log_access_event(p_company, 'role_updated', null, p_role, jsonb_build_object(
    'name_before', v_old_name, 'name_after', v_name,
    'added', coalesce((select jsonb_agg(x order by x) from unnest(v_after) x where x <> all (v_before)), '[]'::jsonb),
    'removed', coalesce((select jsonb_agg(x order by x) from unnest(v_before) x where x <> all (v_after)), '[]'::jsonb)));
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- 4) Empresa nueva: su administrador recibe todo el catálogo.
-- ---------------------------------------------------------------------------------------------
create or replace function public.create_company(p_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_company uuid;
  v_role uuid;
  v_user uuid := auth.uid();
  v_name text := nullif(btrim(p_name), '');
begin
  if v_user is null then raise exception 'Iniciá sesión' using errcode = '42501'; end if;
  if v_name is null or length(v_name) not between 2 and 100 then
    raise exception 'El nombre debe tener entre 2 y 100 caracteres';
  end if;
  insert into public.companies(name, slug) values (v_name, 'empresa-' || replace(gen_random_uuid()::text, '-', ''))
    returning id into v_company;
  insert into public.roles(company_id, code, name) values (v_company, 'admin', 'Administrador') returning id into v_role;
  insert into public.company_users(company_id, user_id, role_id) values (v_company, v_user, v_role);
  insert into public.company_settings(company_id) values (v_company);
  insert into public.company_modules(company_id, module, enabled) values
    (v_company, 'inventory', true), (v_company, 'production', true), (v_company, 'purchases', true),
    (v_company, 'sales', true), (v_company, 'finance', true), (v_company, 'reports', true);
  insert into public.role_permissions(company_id, role_id, resource, action)
  select v_company, v_role, c.resource, a.action
  from public.permission_catalog c cross join lateral unnest(c.actions) as a(action);
  insert into public.profiles(id, name) values (v_user, coalesce(nullif(v_user::text, ''), 'Usuario'))
    on conflict (id) do nothing;
  return v_company;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- 5) Soporte (solo lectura): alcanza también las pantallas del catálogo, salvo los datos sensibles.
-- ---------------------------------------------------------------------------------------------
create or replace function private.has_permission(p_company uuid, p_resource text, p_action text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.company_users cu
    join public.companies c on c.id = cu.company_id
    join public.role_permissions rp on rp.role_id = cu.role_id and rp.company_id = cu.company_id
    where cu.company_id = p_company and cu.user_id = (select auth.uid()) and cu.active and c.active
      and rp.resource = p_resource and rp.action = p_action
  ) or (
    p_action = 'read'
    and (
      p_resource in ('dashboard', 'inventory', 'items', 'stock', 'warehouses', 'units', 'categories',
        'production', 'purchases', 'sales', 'finance', 'reports', 'settings', 'users', 'roles')
      or exists (select 1 from public.permission_catalog pc where pc.resource = p_resource and pc.module <> 'sensitive')
    )
    and private.support_session_active(p_company)
  );
$$;

commit;

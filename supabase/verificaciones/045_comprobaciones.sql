-- Comprobaciones de solo lectura para 045 (después de aplicarla). No leen datos de clientes.

-- 1) Catálogo: conteos, RLS y privilegios.
select count(*) as entradas, count(*) filter (where is_group) as grupos, count(*) filter (where admin_only) as solo_admin,
  count(*) filter (where module = 'sensitive') as sensibles, count(*) filter (where enforced) as exigidos
from public.permission_catalog;
-- Esperado: entradas = 34, grupos = 3, solo_admin = 2, sensibles = 2, exigidos = 0.
select c.relrowsecurity as rls, has_table_privilege('authenticated', c.oid, 'SELECT') as auth_select,
  has_table_privilege('authenticated', c.oid, 'INSERT,UPDATE,DELETE') as auth_write,
  has_table_privilege('anon', c.oid, 'SELECT') as anon_select
from pg_class c where c.oid = 'public.permission_catalog'::regclass;
-- Esperado: rls = true, auth_select = true, auth_write = false, anon_select = false.

-- 0) ANTES de aplicar: permisos que la nueva pantalla de roles descarta al guardar un rol existente
-- (users y roles ya no se delegan desde 044; manage no se usa). Revisar si hay roles no admin con ellos.
select r.code, rp.resource, rp.action from public.role_permissions rp join public.roles r on r.id = rp.role_id
where (r.code <> 'admin' and rp.resource in ('users', 'roles')) or rp.action = 'manage' and r.code <> 'admin';
-- Esperado el 24/11: 0 filas para roles no admin salvo, quizá, 'manage' del vendedor (sin efecto: ninguna función lo exige).

-- 2) Reparto completo: ningún rol tiene un permiso de módulo sin todas sus pantallas. Esperado: 0 filas.
select rp.role_id, rp.resource as modulo, rp.action, c.resource as pantalla_faltante
from public.role_permissions rp
join public.permission_catalog c on c.parent = rp.resource and rp.action = any (c.actions)
where not exists (select 1 from public.role_permissions x
  where x.role_id = rp.role_id and x.resource = c.resource and x.action = rp.action);

-- 3) Costos: solo administradores. Esperado: todas las filas con code = admin.
select r.code, rp.resource, count(*) as roles
from public.role_permissions rp join public.roles r on r.id = rp.role_id
where rp.resource in ('costs_materials', 'costs_production') group by 1, 2 order by 1, 2;

-- 4) Cada administrador tiene todo el catálogo. Esperado: 0 filas.
select r.id as rol_admin, c.resource, a.action
from public.roles r cross join public.permission_catalog c cross join lateral unnest(c.actions) as a(action)
where r.code = 'admin' and not exists (select 1 from public.role_permissions rp
  where rp.role_id = r.id and rp.resource = c.resource and rp.action = a.action);

-- 4b) Copia de seguridad de permisos previos a 045 creada y sin acceso para la API. Esperado: filas > 0; auth_any = false.
select (select count(*) from private.role_permissions_pre045) as filas,
  has_table_privilege('authenticated', 'private.role_permissions_pre045', 'SELECT') as auth_any;

-- 5) Funciones.
select p.oid::regprocedure as firma, p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '') as config,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where (n.nspname = 'public' and p.proname in ('create_company_role', 'update_company_role', 'create_company'))
   or (n.nspname = 'private' and p.proname in ('save_role_permissions', 'has_permission')) order by 1;
-- Esperado: 5 filas (save_role_permissions con prosecdef = false), anon_exec = false en todas, auth_exec = true en las 3 públicas y false en save_role_permissions.

-- PRUEBAS DE COMPORTAMIENTO: pruebas_roles_empresas.sql, grupo "10 Tras 045" (todo debe PASAR).

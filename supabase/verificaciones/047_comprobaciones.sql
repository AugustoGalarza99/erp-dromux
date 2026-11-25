-- Comprobaciones de solo lectura para 047 (después de aplicarla). No leen datos de clientes.

-- 1) Políticas que conservan el permiso de módulo de Producción. Esperado: 0 filas.
select tablename, policyname from pg_policies
where schemaname = 'public' and coalesce(qual, '') || coalesce(with_check, '') ~ 'has_permission\([^,]+,\s*''production''::text';

-- 2) Funciones que exigen todavía el módulo completo "production". Esperado: 0 filas.
select p.oid::regprocedure::text as funcion
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'private') and p.prokind = 'f' and p.proname <> 'has_permission'
  and pg_get_functiondef(p.oid) ~ 'has_permission\(\s*[a-z_]+\s*,\s*''production''\s*,';

-- 3) Costos de producción: la función usa costs_production. Esperado: 1 fila, usa_costs_production = true, usa_finanzas = false.
select pg_get_functiondef('private.can_see_production_costs(uuid)'::regprocedure) like '%costs_production%' as usa_costs_production,
       pg_get_functiondef('private.can_see_production_costs(uuid)'::regprocedure) like '%''finance''%' as usa_finanzas;

-- 4) Reposición ya no exige Compras. Esperado: usa_production_replenishment = true, exige_compras = false.
select pg_get_functiondef('public.erp_replenishment_forecast(uuid)'::regprocedure) like '%production_replenishment%' as usa_production_replenishment,
       pg_get_functiondef('public.erp_replenishment_forecast(uuid)'::regprocedure) ~ '''purchases''' as exige_compras;

-- 5) Seguridad conservada en las funciones tocadas: SECURITY DEFINER y sin EXECUTE para anon. Esperado: 0 filas.
select p.oid::regprocedure::text as funcion, p.prosecdef, has_function_privilege('anon', p.oid, 'execute') as anon_exec
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'private') and p.prokind = 'f'
  and pg_get_functiondef(p.oid) ~ '''production_(overview|orders|formulas|planning|availability|replenishment|packaging|stats)'''
  and (not p.prosecdef or has_function_privilege('anon', p.oid, 'execute'));

-- 6) Catálogo: pantallas de Producción y costs_production exigidas. Esperado: 11.
select count(*) as exigidos from public.permission_catalog where enforced and (module = 'production' or resource = 'costs_production');

-- 7) Copias para deshacer. Esperado: 36, 14, filas > 0; auth_any = false.
select (select count(*) from private.function_defs_pre047) as funciones, (select count(*) from private.policy_defs_pre047) as politicas,
  (select count(*) from private.permission_catalog_pre047) as catalogo,
  has_table_privilege('authenticated', 'private.function_defs_pre047', 'SELECT') as auth_any;

-- 8) REVISAR ANTES DE APLICAR: administradores sin finance:read (ahora verían costos) y roles no admin con costs_production (ahora los ven).
select r.company_id, r.code, exists (select 1 from public.role_permissions x where x.role_id = r.id and x.resource = 'finance' and x.action = 'read') as tiene_finanzas
from public.roles r where r.code = 'admin' and not exists (select 1 from public.role_permissions x where x.role_id = r.id and x.resource = 'finance' and x.action = 'read');
-- Esperado 0 filas. Y roles no admin con costs_production:
select r.company_id, r.code from public.roles r where r.code <> 'admin' and exists (select 1 from public.role_permissions x where x.role_id = r.id and x.resource = 'costs_production');
-- Esperado 0 filas.
-- 9) Roles no admin con permisos de Producción y su acceso a costos (informativo: solo ven costos si tienen costs_production).
select r.company_id, r.code,
  exists (select 1 from public.role_permissions x where x.role_id = r.id and x.resource = 'costs_production') as ve_costos_produccion
from public.roles r
where exists (select 1 from public.role_permissions p where p.role_id = r.id and p.resource like 'production%')
order by 1, 2;

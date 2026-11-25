-- Comprobaciones de solo lectura para 048 (después de aplicarla). No leen datos de clientes.

-- 1) Políticas de LECTURA que conservan el módulo 'stock'. Esperado: 0 filas.
select tablename, policyname from pg_policies
where schemaname = 'public' and cmd = 'SELECT' and coalesce(qual, '') || coalesce(with_check, '') ~ 'has_permission\([^,]+,\s*''stock''::text';

-- 2) Funciones que todavía piden stock/read (módulo). Esperado: solo issue_sale_delivery_note (lote de Ventas).
select p.oid::regprocedure::text as funcion
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'private') and p.prokind = 'f' and p.proname <> 'has_permission'
  and pg_get_functiondef(p.oid) ~ 'has_permission\(\s*[a-z_]+\s*,\s*''stock''\s*,\s*''read''';

-- 3) Seguridad conservada en las funciones tocadas: SECURITY DEFINER y sin EXECUTE para anon. Esperado: 0 filas.
select p.oid::regprocedure::text as funcion, p.prosecdef, has_function_privilege('anon', p.oid, 'execute') as anon_exec
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'private') and p.prokind = 'f'
  and p.proname in ('stock_summary','stock_item_options','stock_warehouse_options','stock_lot_options','stock_lot_breakdown','erp_can_manufacture',
    'erp_replenishment_forecast','recalculate_production_reservations','erp_production_alerts','erp_operational_dashboard','cleanup_target')
  and ((not p.prosecdef and p.proname <> 'cleanup_target') or has_function_privilege('anon', p.oid, 'execute'));

-- 4) cleanup_target usa pantallas y nadie de la API la ejecuta. Esperado: 1 fila, usa_pantallas = true, auth_exec = false.
select pg_get_functiondef('private.cleanup_target(text)'::regprocedure) ~ 'production_orders' as usa_pantallas,
       has_function_privilege('authenticated', 'private.cleanup_target(text)', 'execute') as auth_exec;

-- 5) Catálogo: pantallas exigidas. Esperado: 9 filas (inventory, items, stock, stock_levels, stock_movements, stock_delivery_notes, units, categories, warehouses).
select resource from public.permission_catalog where enforced and resource in
  ('inventory','items','stock','stock_levels','stock_movements','stock_delivery_notes','units','categories','warehouses') order by 1;

-- 6) Copias para deshacer. Esperado: 12, 11, filas > 0; auth_any = false.
select (select count(*) from private.function_defs_pre048) as funciones, (select count(*) from private.policy_defs_pre048) as politicas,
  (select count(*) from private.permission_catalog_pre048) as catalogo,
  has_table_privilege('authenticated', 'private.function_defs_pre048', 'SELECT') as auth_any;

-- 7) REVISAR ANTES DE APLICAR (informativo): roles con Stock PARCIAL. Cambian de acceso: ahora ven lo de sus pantallas.
select r.company_id, r.code,
  count(*) filter (where x.resource in ('stock_levels','stock_movements','stock_delivery_notes','inventory') and x.action = 'read') as pantallas_de_stock_con_ver
from public.roles r join public.role_permissions x on x.role_id = r.id
where r.code <> 'admin' and x.resource in ('stock_levels','stock_movements','stock_delivery_notes','inventory')
group by 1, 2 order by 1, 2;

-- 7b) REVISAR ANTES DE APLICAR: roles con inventory:read (Resumen de stock) que NO tienen stock_levels:read ni stock:read. Con la 048 pasan a
-- VER saldos y lotes (antes no). Esperado: 0 filas o roles que el propietario acepta.
select r.company_id, r.code from public.roles r
where r.code <> 'admin'
  and exists (select 1 from public.role_permissions x where x.role_id = r.id and x.resource = 'inventory' and x.action = 'read')
  and not exists (select 1 from public.role_permissions x where x.role_id = r.id and x.resource in ('stock','stock_levels') and x.action = 'read');

-- 8) GUARDIA GENERAL (nueva; heurística, NO es una prueba de seguridad: no detecta chequeos en una sola rama ni sobre otra empresa).
-- Lista esperada hoy (conocidas, no requieren permiso de empresa): my_company_access, accept_company_invitation, rls_auto_enable, create_company y
-- helpers de perfil propio. Cualquier otra fila: revisar a mano.
-- GUARDIA GENERAL (descripción original): funciones de `public` ejecutables por usuarios con sesión (authenticated) que NO llaman a has_permission ni a
-- una guarda de empresa (get_user_role, support_session_active, auth.uid() = ..., private.is_member). Esperado: solo funciones triviales conocidas;
-- cualquier fila nueva hay que revisarla a mano (puede ser legítima: perfil propio, helpers de interfaz).
select p.oid::regprocedure::text as funcion
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prokind = 'f' and has_function_privilege('authenticated', p.oid, 'execute')
  and p.prosecdef
  and pg_get_functiondef(p.oid) !~ '(has_permission|get_user_role|is_member|can_see_|support_session_active|company_users)'
order by 1;

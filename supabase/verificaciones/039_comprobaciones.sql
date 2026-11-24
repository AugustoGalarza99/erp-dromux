-- Comprobaciones de solo lectura para 039 (después de aplicarla). No leen datos de clientes.

-- 1) RLS y permisos de tabla (esperado: rls=true y anon sin acceso en las 8).
select c.relname, c.relrowsecurity as rls,
  has_table_privilege('anon', c.oid, 'SELECT') as anon_select,
  has_table_privilege('authenticated', c.oid, 'SELECT') as auth_select,
  has_table_privilege('authenticated', c.oid, 'INSERT') as auth_insert,
  has_table_privilege('authenticated', c.oid, 'UPDATE') as auth_update,
  has_table_privilege('authenticated', c.oid, 'DELETE') as auth_delete
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname in ('price_settings', 'price_lists', 'price_list_items',
  'price_list_item_pricing', 'price_list_item_history', 'price_change_requests', 'item_sale_settings',
  'customer_price_lists') order by 1;
-- Esperado: auth_select=true SOLO en price_lists, price_list_items, item_sale_settings, customer_price_lists;
-- price_settings, price_list_item_pricing, price_list_item_history y price_change_requests: todo false
-- (el vendedor no puede ver margen, costo ni comisiones). auth_insert/update/delete=false en las 8.

-- 2) Funciones: security definer, search_path vacío, EXECUTE solo authenticated.
select p.proname, p.prosecdef as security_definer, coalesce(array_to_string(p.proconfig, ','), '') as config,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where (n.nspname = 'public' and p.proname in ('save_price_settings', 'erp_price_settings', 'save_price_list',
  'set_price_list_item', 'remove_price_list_item', 'bulk_price_change', 'import_price_list_items',
  'save_item_sale_settings', 'assign_customer_price_list', 'erp_price_list_rows',
  'erp_admin_price_list_rows', 'erp_price_list_history', 'erp_resolve_sale_price'))
  or (n.nspname = 'private' and p.proname like 'price\_%')
order by n.nspname, p.proname;
-- Esperado: las 13 public con security_definer=true, config=search_path="" y anon_exec=false, auth_exec=true;
-- las private: auth_exec=false y anon_exec=false.

-- 3) Políticas (esperado: 4 de lectura con private.has_permission(...,'sales','read')).
select tablename, policyname, cmd, roles from pg_policies
where schemaname = 'public' and tablename in ('price_lists', 'price_list_items', 'item_sale_settings',
  'customer_price_lists') order by 1, 2;

-- 4) Integridad: índices únicos (una lista predeterminada por empresa, nombre único) y disparadores.
select indexname from pg_indexes where schemaname = 'public'
  and indexname in ('price_lists_one_default', 'price_lists_name_unique', 'price_list_item_history_idx');
select tgname, tgrelid::regclass from pg_trigger
where tgname in ('price_lists_guard', 'price_history_immutable') and not tgisinternal;

-- 5) No se tocó el camino de dinero: la venta sigue igual (esperado: la definición NO menciona price_list).
select p.proname, position('price_list' in pg_get_functiondef(p.oid)) as menciona_listas
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('post_sale_with_payment', 'adjust_sale');
-- Esperado: menciona_listas = 0 en ambas.

-- PRUEBAS DE COMPORTAMIENTO (con 2 empresas y 3 roles; no incluidas aquí, hacerlas en base de prueba):
--  a) vendedor (sales:read, no admin): erp_price_list_rows OK; erp_admin_price_list_rows,
--     set_price_list_item, bulk_price_change, erp_price_list_history -> error 42501.
--  b) admin sin finance:read: set_price_list_item con 'fixed' OK; con 'margin' -> 42501.
--  c) admin de otra empresa: ninguna función acepta ids de la primera (listas/ítems/clientes ajenos).
--  d) bulk_price_change/import con el mismo p_request_id dos veces -> mismo resultado, un solo historial.
--  e) lista derivada: base con descuento 10 % y redondeo 10 -> precio esperado; override propio prevalece.
--  f) 200+ y 5000 filas: tiempo de erp_admin_price_list_rows (calcula el costo solo de la página; los filtros
--     low_margin/cost_changed lo calculan para hasta 1000 productos). Los productos 101+ deben traer costo.
--  g) invariante: ninguna fila de price_list_items sin su fila en price_list_item_pricing:
--       select count(*) from public.price_list_items i left join public.price_list_item_pricing p
--         using (company_id, price_list_id, item_id) where p.item_id is null;   -- esperado 0
--  h) UPDATE o DELETE sobre price_list_item_history deben fallar (disparador).
--  i) un precio fijo de 100.000.000 o más se guarda sin desborde; una lista derivada de otra derivada se rechaza.
--  j) erp_resolve_sale_price devuelve la columna currency (ARS para el precio del producto).

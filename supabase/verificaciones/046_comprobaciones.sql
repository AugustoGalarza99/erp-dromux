-- Comprobaciones de solo lectura para 046 (después de aplicarla). No leen datos de clientes.

-- 1) Ninguna política conserva el permiso de módulo de Compras. Esperado: 0 filas.
select tablename, policyname from pg_policies
where schemaname = 'public' and coalesce(qual, '') || coalesce(with_check, '') like '%''purchases''::text%';

-- 2) Funciones que todavía exigen el módulo completo de Compras. Esperado: solo erp_replenishment_forecast (pasa a 047).
select p.oid::regprocedure::text as funcion
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'private') and p.prokind = 'f' and p.proname <> 'has_permission'
  and pg_get_functiondef(p.oid) ~ 'has_permission\(\s*[a-z_]+\s*,\s*''purchases''\s*,';

-- 3) Mapa aplicado: cada función exige el permiso nuevo. Esperado: 34 filas con ok = true.
select m.f as funcion, m.recurso,
  pg_get_functiondef(m.f::regprocedure) like '%''' || m.recurso || '''%' as ok
from (values
  ('public.add_exchange_rate_type(uuid,text)', 'purchases_suppliers'),
  ('public.add_exchange_rate(uuid,uuid,numeric,date)', 'purchases_suppliers'),
  ('public.adjust_supplier_prices(uuid,uuid,uuid,numeric,uuid)', 'purchases_suppliers'),
  ('public.set_preferred_supplier(uuid,uuid,uuid)', 'purchases_suppliers'),
  ('public.save_supplier_quote(uuid,uuid,uuid,numeric,text,text,uuid,numeric,timestamp with time zone,boolean)', 'purchases_suppliers'),
  ('public.supplier_adjustment_preview(uuid,uuid,uuid,numeric)', 'purchases_suppliers'),
  ('public.supplier_directory(uuid,text,integer)', 'purchases_suppliers'),
  ('public.supplier_quote_catalog(uuid,uuid,uuid,text,integer)', 'purchases_suppliers'),
  ('private.prepare_item_import(uuid,jsonb,uuid)', 'purchases_suppliers'),
  ('public.exchange_rate_overview(uuid)', 'costs_materials'),
  ('public.cancel_purchase_order(uuid,uuid)', 'purchases_orders'),
  ('public.create_purchase_order_once(uuid,uuid,text,jsonb,uuid)', 'purchases_orders'),
  ('public.create_purchase_order(uuid,uuid,text,jsonb)', 'purchases_orders'),
  ('public.receive_purchase_order(uuid,uuid,uuid,text,jsonb)', 'purchases_orders'),
  ('public.purchase_receivable_lines(uuid,uuid)', 'purchases_orders'),
  ('public.purchase_suppliers_for_items(uuid,uuid[])', 'purchases_orders'),
  ('public.purchase_item_options(uuid,text)', 'purchases_orders'),
  ('public.purchase_material_options(uuid,text,uuid)', 'purchases_orders'),
  ('public.purchase_supplier_quotes(uuid,uuid,uuid)', 'purchases_orders'),
  ('public.supplier_cost_comparison(uuid,uuid,uuid)', 'purchases_orders'),
  ('public.create_purchase_request(uuid,text,date,text,jsonb,uuid)', 'purchase_requests'),
  ('public.purchase_request_item_options(uuid,text)', 'purchase_requests'),
  ('public.reject_purchase_request(uuid,uuid,text)', 'purchase_requests'),
  ('public.convert_purchase_request(uuid,uuid,uuid,text,jsonb,uuid)', 'purchase_requests'),
  ('public.confirm_supplier_payment_order(uuid,uuid)', 'purchases_accounts'),
  ('public.create_supplier_payment_order(uuid,uuid,uuid,date,text,text,jsonb,uuid)', 'purchases_accounts'),
  ('public.supplier_account(uuid,uuid,date,date,integer)', 'purchases_accounts'),
  ('public.supplier_payable_orders(uuid,uuid,integer)', 'purchases_accounts'),
  ('public.supplier_purchase_statistics(uuid,date,date)', 'purchases_accounts'),
  ('public.erp_dashboard(uuid)', 'purchases_overview'),
  ('public.erp_operational_dashboard(uuid)', 'purchases_overview'),
  ('public.erp_operational_report(uuid,date,date)', 'purchases_overview'),
  ('private.can_see_reference_cost(uuid)', 'costs_materials'),
  ('public.item_cost_context(uuid,uuid)', 'costs_materials')
) as m(f, recurso)
order by ok, 1;

-- 4) Seguridad conservada: SECURITY DEFINER, search_path vacío, anon sin EXECUTE. Esperado: 0 filas.
select p.oid::regprocedure::text as funcion, p.prosecdef, p.proconfig, has_function_privilege('anon', p.oid, 'execute') as anon_exec
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('add_exchange_rate_type', 'add_exchange_rate', 'adjust_supplier_prices',
  'set_preferred_supplier', 'save_supplier_quote', 'supplier_adjustment_preview', 'supplier_directory', 'supplier_quote_catalog',
  'exchange_rate_overview', 'cancel_purchase_order', 'create_purchase_order_once', 'create_purchase_order', 'receive_purchase_order',
  'purchase_receivable_lines', 'purchase_suppliers_for_items', 'purchase_item_options', 'purchase_material_options',
  'purchase_supplier_quotes', 'supplier_cost_comparison', 'create_purchase_request', 'purchase_request_item_options',
  'reject_purchase_request', 'convert_purchase_request', 'confirm_supplier_payment_order', 'create_supplier_payment_order',
  'supplier_account', 'supplier_payable_orders', 'supplier_purchase_statistics', 'item_cost_context')
  and (not p.prosecdef or has_function_privilege('anon', p.oid, 'execute'));

-- 5) Catálogo: "manage" solo en Pedidos internos y pantallas exigidas. Esperado: manage_en = {purchase_requests}; exigidos = 7.
select (select array_agg(resource order by resource) from public.permission_catalog where 'manage' = any (actions)) as manage_en,
  (select count(*) from public.permission_catalog where enforced) as exigidos;

-- 6) Políticas nuevas (17 re-apuntadas, ninguna con 'purchases'). Esperado: 17 filas con el recurso nuevo + purchase_request_lines_read (menciona la tabla, no el permiso).
select tablename, policyname, cmd, coalesce(qual, '') || ' ' || coalesce(with_check, '') as expresion
from pg_policies where schemaname = 'public'
  and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(purchases_(overview|orders|suppliers|accounts)|purchase_requests|costs_materials)'
order by 1, 2;

-- 7) Copias para deshacer creadas y sin acceso para la API. Esperado: 34, 17, filas > 0; auth_any = false.
select (select count(*) from private.function_defs_pre046) as funciones,
  (select count(*) from private.policy_defs_pre046) as politicas,
  (select count(*) from private.permission_catalog_pre046) as catalogo,
  has_table_privilege('authenticated', 'private.function_defs_pre046', 'SELECT') as auth_any;

-- 8) Roles que hoy quedan con permisos de módulo sin 'costs_materials' (informativo: ven costos de materiales solo los
-- administradores hasta que el administrador de la empresa los tilde en Roles y permisos). Revisar roles no admin.
select r.company_id, r.code,
  exists (select 1 from public.role_permissions x where x.role_id = r.id and x.resource = 'costs_materials') as ve_costos_materiales
from public.roles r
where exists (select 1 from public.role_permissions p where p.role_id = r.id and p.resource like 'purchases%')
order by 1, 2;

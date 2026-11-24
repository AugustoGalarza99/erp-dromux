-- Comprobaciones de solo lectura para 038. No leen datos de clientes.

-- 1) Tablas con RLS activada y sin permisos de escritura para authenticated/anon (esperado: rls=true).
select c.relname, c.relrowsecurity as rls,
  has_table_privilege('anon', c.oid, 'SELECT') as anon_select,
  has_table_privilege('authenticated', c.oid, 'SELECT') as auth_select,
  has_table_privilege('authenticated', c.oid, 'INSERT') as auth_insert,
  has_table_privilege('authenticated', c.oid, 'UPDATE') as auth_update,
  has_table_privilege('authenticated', c.oid, 'DELETE') as auth_delete
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname in
  ('purchase_requests', 'purchase_request_lines', 'purchase_request_counters', 'purchase_request_submissions')
order by 1;
-- Esperado: anon_select=false en todas; auth_select=true solo en purchase_requests y purchase_request_lines;
-- auth_insert/update/delete=false en todas.

-- 2) Funciones: security definer, search_path fijo, EXECUTE solo para authenticated (anon=false).
select p.proname, p.prosecdef as security_definer,
  coalesce(array_to_string(p.proconfig, ','), '') as config,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in
  ('purchase_request_item_options', 'create_purchase_request', 'cancel_purchase_request',
   'reject_purchase_request', 'convert_purchase_request')
order by 1;

-- 3) Políticas de lectura.
select tablename, policyname, cmd, roles from pg_policies
where schemaname = 'public' and tablename in ('purchase_requests', 'purchase_request_lines')
order by 1, 2;

-- 4) La lista blanca de roles incluye el recurso nuevo (esperado: 3 filas con true).
select p.proname, position('purchase_requests' in p.prosrc) > 0 as incluye_recurso
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('create_company_role', 'update_company_role', 'create_company')
order by 1;

-- 5) Cada rol administrador tiene los 5 permisos del recurso (esperado: filas = cantidad de empresas, con 5).
select r.company_id, count(*) filter (where rp.resource = 'purchase_requests') as permisos
from public.roles r
left join public.role_permissions rp on rp.role_id = r.id and rp.company_id = r.company_id
where r.code = 'admin'
group by r.company_id;

-- 6) PRUEBAS DE COMPORTAMIENTO (manuales, con dos empresas A y B y tres roles: operario, comprador, admin).
-- Estas consultas de catálogo NO las reemplazan. Ejecutar como cada usuario real desde la aplicación o la API:
--  a) Operario de A: ve solo SUS pedidos y sus líneas; no ve los de otro operario de A.
--  b) Comprador de A (purchases:read): ve todos los pedidos de A y ninguno de B.
--  c) Usuario de B llama cancel/reject/convert con un pedido de A: error 42501/inexistente, sin cambios.
--  d) Mismo p_request_id dos veces (mismo usuario y contenido) devuelve el mismo pedido; con otro contenido
--     o con otro usuario falla.
--  e) Pedido de 200 líneas se acepta; de 201 se rechaza; ítem repetido, inactivo o de otra empresa se rechaza.
--  f) Dos compradores convierten el mismo pedido en paralelo: queda UNA sola orden y el segundo recibe
--     "El pedido ya fue resuelto".
--  g) Operario no puede cancelar un pedido ajeno; comprador no puede cancelar un pedido ajeno (debe rechazar).
--  h) purchase_request_item_options no devuelve costos ni precios (solo id, código, nombre, unidad, tipo).

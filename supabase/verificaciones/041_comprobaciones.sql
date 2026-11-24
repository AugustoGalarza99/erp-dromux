-- Comprobaciones de solo lectura para 041 (después de aplicarla). No leen datos de clientes.

-- 1) RLS y permisos de tabla.
select c.relname, c.relrowsecurity as rls,
  has_table_privilege('anon', c.oid, 'SELECT') as anon_select,
  has_table_privilege('authenticated', c.oid, 'SELECT') as auth_select,
  has_table_privilege('authenticated', c.oid, 'INSERT') as auth_insert,
  has_table_privilege('authenticated', c.oid, 'UPDATE') as auth_update,
  has_table_privilege('authenticated', c.oid, 'DELETE') as auth_delete
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname in ('company_profile', 'quote_counters', 'quotes', 'quote_lines', 'quote_status_events') order by 1;
-- Esperado: rls=true y anon_select=false en las 4. auth_select: quotes y quote_lines = true (quotes por columnas:
-- puede figurar false a nivel tabla y true por columna, ver punto 2); company_profile y quote_counters = false.
-- auth_insert/update/delete = false en todas.

-- 2) Lectura por columna de quotes: request_payload NO debe ser legible.
select column_name, has_column_privilege('authenticated', 'public.quotes', column_name, 'SELECT') as auth_select
from information_schema.columns where table_schema = 'public' and table_name = 'quotes'
order by column_name;
-- Esperado: auth_select=false SOLO en request_id, request_payload, created_by y status_changed_by; true en el resto.

-- 3) Funciones: security definer, search_path vacío, EXECUTE solo authenticated.
select n.nspname, p.proname, p.prosecdef as security_definer, coalesce(array_to_string(p.proconfig, ','), '') as config,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where (n.nspname = 'public' and p.proname in ('save_company_profile', 'erp_company_profile', 'create_quote',
  'set_quote_status', 'erp_quotes_page', 'erp_quote_detail'))
  or (n.nspname = 'private' and p.proname in ('quotes_guard', 'quote_lines_immutable'))
order by 1, 2;
-- Esperado: las 6 public con security_definer=true, search_path="" y anon_exec=false, auth_exec=true;
-- las 2 private sin EXECUTE para nadie.

-- 3b) Políticas de lectura (esperado: 3 con private.has_permission(...,'sales','read')) y Realtime.
select tablename, policyname, cmd from pg_policies where schemaname = 'public'
  and tablename in ('quotes', 'quote_lines', 'quote_status_events') order by 1, 2;
select count(*) as tablas_en_realtime from pg_publication_tables where schemaname = 'public'
  and tablename in ('company_profile', 'quote_counters', 'quotes', 'quote_lines', 'quote_status_events');
-- Esperado: tablas_en_realtime = 0.

-- 4) Disparadores de integridad.
select tgname, tgrelid::regclass from pg_trigger
where tgname in ('quote_lines_immutable', 'quote_status_events_immutable', 'quotes_guard') and not tgisinternal;
-- Esperado: 3 filas.

-- PRUEBAS DE COMPORTAMIENTO (base de prueba, 2 empresas y 3 roles; no incluidas aquí):
--  a) crear presupuesto con cliente con lista: precios de esa lista; sin cliente: lista predeterminada.
--  b) mismo request_id dos veces: mismo id; con otro dato: "Esta solicitud ya se utilizó con otros datos".
--  c) descuento sobre el tope: vendedor rechazado; admin con motivo OK; precio en cero rechazado.
--  d) el total del PDF coincide con net_total/tax_total/gross_total guardados (IVA por alícuota).
--  e) UPDATE de líneas o del importe de un presupuesto falla; solo cambia el estado; DELETE falla.
--  f) set_quote_status: de abierto a aceptado/rechazado/cancelado; reabrir solo admin.
--  g) 200 líneas: crear, listar y abrir; 2 empresas: ningún id cruza.
--  h2) aceptar un presupuesto vencido: un vendedor falla, el admin puede; aceptar, reabrir y rechazar deja 3
--      eventos en quote_status_events; sum(line_total) = net_total; un reintento tardío (otro día) devuelve el id.
--  h) ningún rol sin sales:read puede leer presupuestos ni los datos de la empresa; vendedor no ve costos.

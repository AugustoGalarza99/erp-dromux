-- Comprobaciones de solo lectura para 042 (después de aplicarla). No leen datos de clientes.

-- 1) Columna nueva, restricción y permiso de lectura.
select column_name, data_type, column_default, is_nullable,
  has_column_privilege('authenticated', 'public.quotes', column_name, 'SELECT') as auth_select
from information_schema.columns where table_schema = 'public' and table_name = 'quotes' and column_name = 'tax_included';
-- Esperado: boolean, default false, not null, auth_select = true.
select conname, pg_get_constraintdef(oid) from pg_constraint where conname = 'quotes_tax_mode_check';
-- Esperado: CHECK (NOT (show_tax AND tax_included)).

-- 2) Funciones: una sola create_quote (13 parámetros, el último con valor por defecto), seguridad y permisos.
select p.oid::regprocedure as firma, p.prosecdef as security_definer, coalesce(array_to_string(p.proconfig, ','), '') as config,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec, has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('create_quote', 'erp_quote_detail') order by 1;
-- Esperado: 2 filas (create_quote con 13 parámetros y erp_quote_detail), secdef=true, search_path="", anon=false, auth=true.

-- 3) Los presupuestos anteriores no cambiaron: ninguno con tax_included (esperado: 0).
select count(*) as con_iva_sumado from public.quotes where tax_included;

-- 4) Coherencia del modo incluido: la suma de los importes con IVA por línea debe igualar el total (esperado: 0).
select count(*) as incoherentes from public.quotes q where q.tax_included and q.gross_total <>
  (select sum(round(l.line_total * (1 + l.tax_percent / 100), 2)) from public.quote_lines l
   where l.company_id = q.company_id and l.quote_id = q.id);

-- PRUEBAS DE COMPORTAMIENTO (base de prueba):
--  a) create_quote con p_show_tax = false y p_tax_included = true: gross_total = neto + IVA línea por línea, y la
--     suma de round(line_total * (1 + tax_percent/100), 2) de las líneas = gross_total.
--  b) p_show_tax = true con p_tax_included = true: error. Un reintento con el mismo request_id devuelve el mismo id.
--  c) una llamada con 12 parámetros (frontend anterior) sigue funcionando (modo discriminado o no incluido).
--  d) un usuario cuyo perfil tiene un identificador como nombre: created_by_label = 'Usuario'.

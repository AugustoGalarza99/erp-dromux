-- Comprobaciones de solo lectura para 043 (después de aplicarla). No leen datos de clientes.

-- 1) Las 3 funciones: una sola firma cada una, SECURITY DEFINER, search_path vacío, sin acceso para anon.
select p.oid::regprocedure as firma, p.prosecdef as security_definer,
  coalesce(array_to_string(p.proconfig, ','), '') as config,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('production_output_summary', 'production_output_by_product', 'finish_production_job_adjusted')
order by 1;
-- Esperado: 3 filas, secdef = true, config = search_path="", anon = false, auth = true.

-- 2) Los 8 índices existen.
select indexname from pg_indexes where schemaname = 'public' and indexname in (
  'production_jobs_done_idx', 'production_jobs_product_idx', 'production_job_events_issue_idx',
  'production_job_events_component_idx', 'production_runs_product_idx', 'production_run_lines_component_idx',
  'production_formula_lines_component_idx', 'stock_lots_expiry_idx') order by 1;
-- Esperado: 8 filas.

-- 3) Ninguna función de 043 devuelve columnas de costo.
select p.proname, pg_get_function_result(p.oid) as resultado
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('production_output_summary', 'production_output_by_product');
-- Esperado: sin "cost" en el resultado.

-- 4) Las funciones originales no cambiaron (mismas firmas y permisos que antes).
select p.oid::regprocedure, has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec
from pg_proc p where p.pronamespace = 'public'::regnamespace
  and p.proname in ('finish_production_job', 'issue_production_material', 'return_production_material');
-- Esperado: 3 filas, anon = false.

-- PRUEBAS DE COMPORTAMIENTO (base de prueba, 2 empresas y 3 roles: admin, operario con production+stock, usuario sin producción):
--  a) Estadística: terminar 3 órdenes en meses distintos; production_output_summary por mes/semana/día coincide con
--     la suma de actual_quantity; el rango personalizado excluye lo anterior/posterior; empresa B no ve datos de A;
--     un usuario sin production:read recibe 42501; p_tz inválida y rangos > 10 años dan error.
--  b) by_product: con 200+ productos, limit/offset paginan sin repetir ni saltar filas y total_count es constante.
--  c) Cierre con ajustes, material de menos: entregar 10, usar 8 -> return 2: el stock del depósito de origen sube 2, el
--     lote es el de origen y la orden queda con consumo neto 8. Con 3 entregas parciales de un mismo insumo, devolver
--     más que la última reparte entre salidas. Devolver más de lo entregado: error y NADA queda registrado.
--  d) Cierre con ajustes, material de más: entregar 10, usar 12 -> issue 2 con depósito/lote: el stock baja 2; sin
--     stock suficiente: error y la orden sigue 'in_progress' sin movimientos nuevos (transacción atómica).
--  e) Idempotencia: repetir la misma llamada (mismo request_id) devuelve el mismo run_id sin movimientos nuevos;
--     reusar request_id con otra cantidad real: error 'ya fue completada con otros datos'. Dos llamadas simultáneas:
--     una espera la otra, un solo ingreso de producto terminado.
--  f) Envases: p_packaging con un id ajeno a la orden o cantidad no entera: error; con todos los envases en la unidad del
--     producto, work_options.unpackaged_quantity = real - suma(cantidad x capacidad); si falta un envase, null.
--  g) Operario sin 'stock:insert': 42501. Operario: ninguna respuesta de estas funciones contiene costos.

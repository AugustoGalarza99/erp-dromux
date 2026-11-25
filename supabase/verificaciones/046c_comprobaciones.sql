-- Comprobaciones de solo lectura para 046c (después de aplicarla).
-- 1) Las dos funciones fijan y limpian la variable. Esperado: 2 filas con fija = true y limpia = true.
select p.oid::regprocedure::text as funcion,
  pg_get_functiondef(p.oid) like '%set_config(''dromux.production_job'',p_job::text,true)%' as fija,
  pg_get_functiondef(p.oid) like '%set_config(''dromux.production_job'','''',true)%' as limpia,
  p.prosecdef, has_function_privilege('anon', p.oid, 'execute') as anon_exec
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where p.proname = 'issue_production_material' and n.nspname in ('public', 'private');
-- 2) Copia para deshacer. Esperado: 2 filas.
select count(*) as copias from private.function_defs_pre046c;
-- 3) Prueba funcional (la hace la app): crear una orden que reserve un lote al 100 % y entregar ese lote desde el remito:
--    debe confirmarse sin "Stock libre insuficiente". Entregar MÁS de lo reservado + libre sigue fallando.

-- 047b: ambas funciones deben devolver siempre true/false (nunca NULL) y seguir cerradas a anon.
-- 1) Debe dar 2 filas con coalesce_ok = true y anon_exec = false.
select p.oid::regprocedure::text as funcion,
  pg_get_functiondef(p.oid) ~ 'coalesce\(private\.get_user_role' as coalesce_ok,
  has_function_privilege('anon', p.oid, 'execute') as anon_exec
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'private' and p.proname in ('can_see_production_costs', 'can_see_reference_cost');
-- 2) Debe dar 0 filas: ninguna otra función del esquema private compara el rol con 'admin' dentro de un OR sin coalesce.
select p.oid::regprocedure::text as funcion
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('private', 'public') and p.prosrc ~ 'get_user_role\([a-z_]+\) *= *''admin''\s*\)? *or'
  and p.prosrc !~ 'coalesce\(private\.get_user_role';

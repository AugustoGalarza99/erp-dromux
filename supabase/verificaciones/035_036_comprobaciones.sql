-- Consultas de solo lectura para comprobar 035 y 036. No leen datos de clientes.

-- 035: las funciones existen, son SECURITY DEFINER con search_path fijo y solo las ejecuta authenticated.
select p.proname, p.prosecdef, coalesce(array_to_string(p.proconfig,','),'') as config,
  has_function_privilege('anon',p.oid,'EXECUTE') as anon_exec,
  has_function_privilege('authenticated',p.oid,'EXECUTE') as auth_exec
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where (n.nspname='public' and p.proname in ('list_production_jobs','list_production_plans',
  'list_production_runs','list_production_items','get_item_detail'))
  or (n.nspname='private' and p.proname in ('can_see_production_costs','can_see_reference_cost','strip_snapshot_cost'))
order by 1;

-- 036: tras aplicarla, todas estas columnas deben dar false para authenticated.
select c.relname, a.attname, has_column_privilege('authenticated',c.oid,a.attnum,'SELECT') as auth_select
from pg_class c join pg_namespace n on n.oid=c.relnamespace
join pg_attribute a on a.attrelid=c.oid and not a.attisdropped
where n.nspname='public' and (
  (c.relname='items' and a.attname in ('reference_unit_cost','reference_cost_usd')) or
  (c.relname='production_job_events' and a.attname='unit_cost') or
  (c.relname='production_plans' and a.attname in ('estimated_cost','component_snapshot')) or
  (c.relname='production_run_lines' and a.attname='unit_cost') or
  (c.relname='production_runs' and a.attname='estimated_cost') or
  (c.relname='production_jobs' and a.attname='formula_snapshot') or
  (c.relname='sale_lines' and a.attname='estimated_unit_cost'))
order by 1,2;

-- 036: tras aplicarla, tampoco debe poder escribir el costo de referencia directo (ni anon ni authenticated).
select r.rol, c.col,
  has_column_privilege(r.rol,'public.items'::regclass,c.col,'INSERT') as ins,
  has_column_privilege(r.rol,'public.items'::regclass,c.col,'UPDATE') as upd,
  has_column_privilege(r.rol,'public.items'::regclass,c.col,'SELECT') as sel
from (values ('anon'),('authenticated')) r(rol)
cross join (values ('reference_unit_cost'),('reference_cost_usd')) c(col);

-- 035: save_item_with_cost e import_items públicas son envoltorios; los núcleos están en private
-- y no los ejecuta authenticated. production_formula_cost debe seguir con EXECUTE para authenticated.
select n.nspname, p.proname, has_function_privilege('authenticated',p.oid,'EXECUTE') as auth_exec,
  has_function_privilege('anon',p.oid,'EXECUTE') as anon_exec
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where p.proname in ('save_item_with_cost','import_items','production_formula_cost','row_has_cost')
  and n.nspname in ('public','private')
order by 2,1;

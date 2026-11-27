-- 05. Solo lectura. Ejecutar al final; devuelve una fila por comprobación.
with funciones as (
  select p.oid, p.prorettype, l.lanname,
    coalesce((select g.tgrelid from pg_trigger g where g.tgfoid = p.oid limit 1), 0::oid) as tabla
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join pg_language l on l.oid = p.prolang
  where n.nspname in ('public', 'private')
),
revisables as materialized (
  select f.oid, f.tabla
  from funciones f
  where f.lanname = 'plpgsql'
    and f.prorettype <> 'event_trigger'::regtype
    and (f.prorettype <> 'trigger'::regtype or f.tabla <> 0)
),
revision as (
  select r.oid::regprocedure::text || ': ' || c.message as aviso
  from revisables r
  cross join lateral extensions.plpgsql_check_function_tb(r.oid::regprocedure, r.tabla::regclass) c
  where c.level = 'error'
)
select 'tablas (esperado 76)' as comprobacion,
  (select count(*) from pg_tables where schemaname in ('public', 'private'))::text as resultado
union all select 'funciones (esperado 200)',
  (select count(*) from funciones)::text
union all select 'politicas (esperado 79)',
  (select count(*) from pg_policies where schemaname in ('public', 'private'))::text
union all select 'disparadores (esperado 60)',
  (select count(*) from pg_trigger g join pg_class c on c.oid = g.tgrelid
   join pg_namespace n on n.oid = c.relnamespace
   where not g.tgisinternal and n.nspname in ('public', 'private'))::text
union all select 'permisos del catalogo (esperado 34)',
  (select count(*) from public.ajustes_permisos_catalogo)::text
union all select 'tablas sin seguridad por filas (esperado 0)',
  (select count(*) from pg_tables where schemaname = 'public' and not rowsecurity)::text
union all select 'funciones que puede ejecutar un anonimo (esperado 1)',
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute'))::text
union all select 'errores en funciones (esperado 0)',
  (select count(*) from revision)::text
union all (select 'detalle', aviso from revision order by aviso limit 40);

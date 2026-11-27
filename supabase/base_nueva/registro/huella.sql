-- Solo lectura. Resume la estructura en una huella por categoría. Si la base real da las
-- mismas huellas que `huella.json`, el registro del proyecto coincide con la base.
with espacios as (
  select oid, nspname from pg_namespace where nspname in ('public', 'private')
),
partes as (
  select 'columnas' as categoria,
    format('%s.%s.%s %s %s %s', e.nspname, c.relname, a.attname, format_type(a.atttypid, a.atttypmod),
      a.attnotnull, coalesce(pg_get_expr(d.adbin, d.adrelid), '')) as parte
  from pg_class c
  join espacios e on e.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where c.relkind in ('r', 'v')
  union all
  select 'restricciones', format('%s.%s %s %s', e.nspname, c.relname, k.conname, pg_get_constraintdef(k.oid))
  from pg_constraint k join pg_class c on c.oid = k.conrelid join espacios e on e.oid = c.relnamespace
  where k.contype <> 'n'
  union all
  select 'indices', pg_get_indexdef(i.indexrelid)
  from pg_index i join pg_class c on c.oid = i.indrelid join espacios e on e.oid = c.relnamespace
  union all
  select 'funciones', format('%s.%s(%s) %s %s %s', e.nspname, p.proname, pg_get_function_identity_arguments(p.oid),
    p.prosecdef, coalesce(array_to_string(p.proconfig, ','), ''),
    md5(btrim(replace(p.prosrc, chr(13), ''), E' \n\t')))
  from pg_proc p join espacios e on e.oid = p.pronamespace
  union all
  select 'politicas', format('%s.%s %s %s %s %s %s', schemaname, tablename, policyname, cmd,
    array_to_string(roles, ','), coalesce(qual, ''), coalesce(with_check, ''))
  from pg_policies where schemaname in ('public', 'private')
  union all
  select 'disparadores', pg_get_triggerdef(g.oid)
  from pg_trigger g join pg_class c on c.oid = g.tgrelid join espacios e on e.oid = c.relnamespace
  where not g.tgisinternal
  union all
  select 'permisos_tablas', format('%s.%s %s %s %s', e.nspname, c.relname, r.rol, a.attname,
    concat_ws(',',
      case when has_column_privilege(r.rol, c.oid, a.attnum, 'select') then 'ver' end,
      case when has_column_privilege(r.rol, c.oid, a.attnum, 'insert') then 'crear' end,
      case when has_column_privilege(r.rol, c.oid, a.attnum, 'update') then 'editar' end,
      case when has_table_privilege(r.rol, c.oid, 'delete') then 'eliminar' end))
  from pg_class c
  join espacios e on e.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  cross join (values ('anon'), ('authenticated')) r(rol)
  where c.relkind in ('r', 'v')
  union all
  select 'permisos_funciones', format('%s.%s(%s) %s %s', e.nspname, p.proname, pg_get_function_identity_arguments(p.oid),
    has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'))
  from pg_proc p join espacios e on e.oid = p.pronamespace
  union all
  select 'catalogo_permisos', to_jsonb(x)::text from public.ajustes_permisos_catalogo x
)
select categoria, count(*) as cantidad, md5(string_agg(parte, '|' order by parte collate "C")) as huella
from partes
group by categoria
order by categoria

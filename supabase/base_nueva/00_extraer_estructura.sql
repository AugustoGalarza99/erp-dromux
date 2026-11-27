-- D-009. Ejecutar en el proyecto VIEJO (drcexqsewiwfhiowrgtv), en el SQL Editor.
-- Solo lee: no modifica nada. No incluye datos de empresas, usuarios ni operaciones;
-- el único contenido que copia es el catálogo de permisos (configuración del sistema).
-- Devuelve UNA fila: descargarla como CSV y guardarla en supabase/base_nueva/origen.csv
with esquemas as (
  select oid, nspname from pg_namespace where nspname in ('public', 'private')
),
tablas as (
  select c.oid, e.nspname as esquema, c.relname as nombre, c.relkind, c.relrowsecurity,
         c.relforcerowsecurity, c.relacl, c.reloptions
  from pg_class c
  join esquemas e on e.oid = c.relnamespace
  where c.relkind in ('r', 'p', 'v', 'm')
    and c.relname !~ '_pre0[0-9]+[a-z]?$'
    and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
),
funciones as (
  select p.oid, e.nspname as esquema, p.proname as nombre, p.proacl, p.prolang
  from pg_proc p
  join esquemas e on e.oid = p.pronamespace
  where not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
)
select jsonb_build_object(
  'version', current_setting('server_version'),
  'extensiones', (
    select jsonb_agg(jsonb_build_object('nombre', x.extname, 'esquema', n.nspname) order by x.extname)
    from pg_extension x join pg_namespace n on n.oid = x.extnamespace
  ),
  'esquemas', (
    select jsonb_agg(jsonb_build_object('nombre', n.nspname, 'permisos', n.nspacl::text[]))
    from pg_namespace n where n.nspname in ('public', 'private')
  ),
  'permisos_por_defecto', (
    select jsonb_agg(jsonb_build_object(
      'rol', pg_get_userbyid(d.defaclrole), 'esquema', n.nspname,
      'tipo', d.defaclobjtype, 'permisos', d.defaclacl::text[]))
    from pg_default_acl d left join pg_namespace n on n.oid = d.defaclnamespace
    where n.nspname in ('public', 'private') or d.defaclnamespace = 0
  ),
  'tipos', (
    select jsonb_agg(jsonb_build_object(
      'esquema', e.nspname, 'nombre', t.typname, 'clase', t.typtype,
      'valores', (select jsonb_agg(v.enumlabel order by v.enumsortorder)
                  from pg_enum v where v.enumtypid = t.oid)))
    from pg_type t join esquemas e on e.oid = t.typnamespace
    where t.typtype in ('e', 'd')
      and not exists (select 1 from pg_depend d where d.objid = t.oid and d.deptype = 'e')
  ),
  'secuencias', (
    select jsonb_agg(jsonb_build_object(
      'esquema', e.nspname, 'nombre', c.relname, 'permisos', c.relacl::text[]))
    from pg_class c join esquemas e on e.oid = c.relnamespace
    where c.relkind = 'S'
  ),
  'tablas', (
    select jsonb_agg(jsonb_build_object(
      'esquema', t.esquema, 'nombre', t.nombre, 'clase', t.relkind,
      'rls', t.relrowsecurity, 'rls_forzado', t.relforcerowsecurity,
      'permisos', t.relacl::text[], 'opciones', t.reloptions,
      'vista', case when t.relkind in ('v', 'm') then pg_get_viewdef(t.oid, true) end,
      'columnas', (
        select jsonb_agg(jsonb_build_object(
          'nombre', a.attname,
          'tipo', format_type(a.atttypid, a.atttypmod),
          'obligatoria', a.attnotnull,
          'defecto', pg_get_expr(d.adbin, d.adrelid),
          'identidad', a.attidentity,
          'generada', a.attgenerated,
          'permisos', a.attacl::text[]
        ) order by a.attnum)
        from pg_attribute a
        left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
        where a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped
      ),
      'restricciones', (
        select jsonb_agg(jsonb_build_object(
          'nombre', k.conname, 'tipo', k.contype, 'definicion', pg_get_constraintdef(k.oid)
        ) order by k.contype, k.conname)
        from pg_constraint k where k.conrelid = t.oid
      ),
      'indices', (
        select jsonb_agg(pg_get_indexdef(i.indexrelid) order by i.indexrelid::regclass::text)
        from pg_index i
        where i.indrelid = t.oid
          and not exists (select 1 from pg_constraint k where k.conindid = i.indexrelid
                          and k.conrelid = t.oid)
      )
    ) order by t.esquema, t.nombre)
    from tablas t
  ),
  'politicas', (
    select jsonb_agg(to_jsonb(p) order by p.schemaname, p.tablename, p.policyname)
    from pg_policies p where p.schemaname in ('public', 'private', 'storage')
  ),
  'funciones', (
    select jsonb_agg(jsonb_build_object(
      'esquema', f.esquema, 'nombre', f.nombre,
      'argumentos', pg_get_function_identity_arguments(f.oid),
      'lenguaje', l.lanname,
      'permisos', f.proacl::text[],
      'definicion', pg_get_functiondef(f.oid)
    ) order by f.esquema, f.nombre, pg_get_function_identity_arguments(f.oid))
    from funciones f join pg_language l on l.oid = f.prolang
  ),
  'disparadores', (
    select jsonb_agg(jsonb_build_object(
      'tabla', g.tgrelid::regclass::text, 'nombre', g.tgname,
      'activo', g.tgenabled, 'definicion', pg_get_triggerdef(g.oid)
    ) order by g.tgrelid::regclass::text, g.tgname)
    from pg_trigger g
    where not g.tgisinternal and g.tgfoid in (select oid from funciones)
  ),
  'disparadores_de_evento', (
    select jsonb_agg(jsonb_build_object(
      'nombre', v.evtname, 'evento', v.evtevent, 'funcion', v.evtfoid::regproc::text,
      'etiquetas', v.evttags, 'activo', v.evtenabled))
    from pg_event_trigger v where v.evtfoid in (select oid from funciones)
  ),
  'tiempo_real', (
    select jsonb_agg(jsonb_build_object('esquema', schemaname, 'tabla', tablename))
    from pg_publication_tables where pubname = 'supabase_realtime'
  ),
  'catalogo_permisos', (
    select jsonb_agg(to_jsonb(c)) from public.permission_catalog c
  )
) as estructura;

-- Solo lectura. Esperado: 1 fila con correcto = true.
select 'funciones nuevas cerradas' as control,
  exists (select 1 from pg_default_acl d
    where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 0 and d.defaclobjtype = 'f'
      and not exists (select 1 from unnest(d.defaclacl) a where a::text like '=%')) as correcto;

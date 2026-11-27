-- Solo lectura. Esperado: perfiles_con_codigo = 0, usa_correo = true, anonimo_puede = false.
select
  (select count(*) from public.ajustes_perfiles p where p.nombre = p.id::text) as perfiles_con_codigo,
  (select position('split_part(u.email' in prosrc) > 0
     from pg_proc where oid = 'public.create_company(text)'::regprocedure) as usa_correo,
  has_function_privilege('anon', 'public.create_company(text)', 'execute') as anonimo_puede;

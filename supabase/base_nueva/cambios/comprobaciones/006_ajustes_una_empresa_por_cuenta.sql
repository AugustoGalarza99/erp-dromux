-- Solo lectura. Esperado: 1 fila con correcto = true.
select 'alta solo sin empresa' as control,
  (select position('ya pertenece a una empresa' in prosrc) > 0 from pg_proc
    where oid = to_regprocedure('public.create_company(text)')) as correcto;

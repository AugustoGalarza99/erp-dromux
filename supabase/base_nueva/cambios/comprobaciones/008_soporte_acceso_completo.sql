-- Solo lectura. Esperado: 4 filas con correcto = true.
select 'soporte actúa como administrador' as control,
  (select position('then ' || quote_literal('administrador') || ' end' in prosrc) > 0 from pg_proc
    where oid = to_regprocedure('private.get_user_role(uuid)')) as correcto
union all
select 'soporte con todas las acciones',
  (select position('p_action = any(pc.acciones)' in prosrc) > 0 from pg_proc
    where oid = to_regprocedure('private.has_permission(uuid,text,text)'))
union all
select 'sesión de 4 horas',
  (select position('4 hours' in prosrc) > 0 from pg_proc
    where oid = to_regprocedure('public.begin_support_session(uuid,text)'))
union all
select 'cierre de sesión solo con usuario',
  coalesce((select has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')
    from pg_proc p where p.oid = to_regprocedure('public.end_support_session()')), false);

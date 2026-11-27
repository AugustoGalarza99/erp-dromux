-- Solo lectura. Esperado: 2 filas con correcto = true.
select 'etiqueta protegida' as control,
  coalesce((select not has_function_privilege('authenticated', p.oid, 'execute')
    from pg_proc p where p.oid = to_regprocedure('private.etiqueta_soporte(uuid,uuid)')), false) as correcto
union all
select 'cuatro pantallas la usan',
  (select count(*) = 4 from pg_proc where pronamespace = 'public'::regnamespace
    and proname in ('access_audit_events_list', 'create_purchase_request', 'create_quote', 'erp_price_list_history')
    and position('private.etiqueta_soporte' in prosrc) > 0);

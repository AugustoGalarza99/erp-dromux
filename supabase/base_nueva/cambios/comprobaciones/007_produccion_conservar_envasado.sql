-- Solo lectura. Esperado: 1 fila con correcto = true.
select 'controles conservan datos' as control,
  (select position('coalesce(v_job.opciones_trabajo,' || quote_literal('{}') || '::jsonb)' in prosrc) > 0
    from pg_proc where proname = 'save_production_work_details'
      and pronamespace = 'public'::regnamespace) as correcto;

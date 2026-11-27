-- Solo lectura. Esperado: 4 filas, todas con correcto = true.
select 'función por material protegida' as control,
  coalesce((select p.prosecdef
      and not has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')
    from pg_proc p
    where p.oid = to_regprocedure('private.rebalance_production_reservations_item(uuid,uuid)')), false) as correcto
union all
select 'índice de entregas por material',
  to_regclass('public.produccion_ordenes_eventos_componente_idx') is not null
union all
select 'los movimientos recalculan por material',
  (select position('rebalance_production_reservations_item' in prosrc) > 0
      and position('rebalance_production_reservations(' in prosrc) = 0
    from pg_proc where oid = to_regprocedure(
      'public.post_stock_operation(uuid,uuid,uuid,uuid,text,numeric,text,uuid,text,date)'))
union all
select 'las entregas recalculan por material',
  (select position('rebalance_production_reservations_item' in prosrc) > 0
    from pg_proc where oid = to_regprocedure('private.rebalance_production_on_event()'));

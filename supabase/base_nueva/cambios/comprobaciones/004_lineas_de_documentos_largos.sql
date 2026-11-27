-- Solo lectura. Esperado: 2 filas; compras_ordenes_lineas con tope 200 y
-- stock_remitos_lineas con tope 500.
select conrelid::regclass::text as tabla, pg_get_constraintdef(oid) as regla
from pg_constraint
where conname in ('stock_remitos_lineas_linea_check', 'compras_ordenes_lineas_linea_check')
order by 1;

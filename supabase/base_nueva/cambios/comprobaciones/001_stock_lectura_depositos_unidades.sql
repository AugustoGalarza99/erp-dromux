-- Solo lectura. Esperado: 2 filas, ambas con orden = SELECT.
select tablename, policyname, cmd as orden
from pg_policies
where schemaname = 'public'
  and policyname in ('stock_depositos_lectura_operativa', 'stock_unidades_lectura_operativa')
order by tablename;

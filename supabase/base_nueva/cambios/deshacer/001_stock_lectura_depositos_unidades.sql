-- Deshace el cambio 001.
begin;
drop policy if exists stock_depositos_lectura_operativa on public.stock_depositos;
drop policy if exists stock_unidades_lectura_operativa on public.stock_unidades;
commit;

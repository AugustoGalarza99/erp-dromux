-- Deshace el cambio 004 (vuelve al tope de 40).
-- Si ya existen remitos u órdenes de compra con más de 40 ítems, falla y no cambia nada:
-- esos documentos son historial y no deben borrarse para poder deshacer.
begin;

alter table public.stock_remitos_lineas
  drop constraint stock_remitos_lineas_linea_check,
  add constraint stock_remitos_lineas_linea_check check (linea >= 1 and linea <= 40);

alter table public.compras_ordenes_lineas
  drop constraint compras_ordenes_lineas_linea_check,
  add constraint compras_ordenes_lineas_linea_check check (linea >= 1 and linea <= 40);

commit;

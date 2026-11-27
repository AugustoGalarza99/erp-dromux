-- 004 · Remitos de más de 40 ítems y órdenes de compra de más de 40 ítems.
-- Motivo: las funciones y la pantalla permiten hasta 500 ítems por remito y 200 por orden de
-- compra, pero las tablas conservaban un tope de 40 en el número de línea. Al superar 40 se
-- rechazaba el documento completo (no quedaba nada a medias ni se movía stock).
-- Solo cambia el tope de esas dos reglas. Ventas y órdenes de pago siguen en 40 a propósito.
begin;

alter table public.stock_remitos_lineas
  drop constraint stock_remitos_lineas_linea_check,
  add constraint stock_remitos_lineas_linea_check check (linea >= 1 and linea <= 500);

alter table public.compras_ordenes_lineas
  drop constraint compras_ordenes_lineas_linea_check,
  add constraint compras_ordenes_lineas_linea_check check (linea >= 1 and linea <= 200);

commit;

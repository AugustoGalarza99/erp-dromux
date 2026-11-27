-- 001 · Stock: quien trabaja con existencias u órdenes puede LEER nombres de depósitos y unidades.
-- Motivo: un rol sin la pantalla de Ajustes (p. ej. operario) veía los saldos sin el nombre del
-- depósito y no podía elegir depósito al entregar insumos o terminar una orden.
-- Solo lectura. Crear y editar siguen exigiendo los permisos de depósitos y unidades.
-- has_permission ya exige pertenecer a la empresa, estar activo y tener el módulo contratado.
begin;

create policy stock_depositos_lectura_operativa on public.stock_depositos
  as permissive for select to authenticated
  using (
    exists (
      select 1
      from unnest(array[
        'inventario', 'stock_saldos', 'stock_movimientos', 'stock_remitos',
        'produccion_ordenes', 'produccion_planificacion', 'produccion_disponibilidad',
        'compras_ordenes', 'ventas'
      ]) as permitido(recurso)
      where private.has_permission(stock_depositos.empresa_id, permitido.recurso, 'ver')
    )
  );

create policy stock_unidades_lectura_operativa on public.stock_unidades
  as permissive for select to authenticated
  using (
    exists (
      select 1
      from unnest(array[
        'items', 'inventario', 'stock_saldos', 'stock_movimientos', 'stock_remitos',
        'produccion_ordenes', 'produccion_formulas', 'produccion_planificacion',
        'produccion_disponibilidad', 'produccion_envasado', 'compras_ordenes', 'ventas'
      ]) as permitido(recurso)
      where private.has_permission(stock_unidades.empresa_id, permitido.recurso, 'ver')
    )
  );

commit;

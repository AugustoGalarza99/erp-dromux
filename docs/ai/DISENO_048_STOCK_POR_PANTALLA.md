# Diseño 048 — Stock (lecturas) y Archivados por pantalla

Origen: hallazgo H-O1 (25/11): un operario con Stock parcial veía existencias en blanco y reservas/faltantes falsos, porque el servidor pedía el módulo `stock` completo (la 045 solo lo deriva con TODAS las pantallas).

## Qué cambia (lecturas)
| Objeto | Antes | Ahora |
| --- | --- | --- |
| stock_balances, stock_lots, stock_lot_balances, stock_lot_openings | stock:read | Stock por depósito, Resumen de stock o Remitos (ver) |
| stock_movements, stock_operations | stock:read | Movimientos (ver) |
| delivery_notes, _lines, _reversals | stock:read (+ producción: Órdenes) | Remitos (ver) (+ producción: Órdenes) |
| production_job_reservations / _locations | (Alcanza u Órdenes) + stock:read | (Alcanza u Órdenes) + Stock por depósito |
| stock_summary | stock:read | Stock por depósito o Resumen de stock |
| stock_item/warehouse options | stock:read | cualquiera de las 4 pantallas de Stock |
| stock_lot_options, stock_lot_breakdown (traen saldo por lote) | stock:read | Stock por depósito, Remitos o Resumen (SIN Movimientos) |
| erp_can_manufacture, erp_replenishment_forecast, recalculate_production_reservations, erp_production_alerts (pública y privada), erp_operational_dashboard | stock:read | Stock por depósito |
| private.cleanup_target (Archivados) | módulo (items, purchases, production, stock) | eliminar en la pantalla del recurso (items, purchases_suppliers, production_formulas / orders / planning, stock_delivery_notes) |

## Qué NO cambia y por qué (048b pendiente)
Las ESCRITURAS que mueven stock siguen pidiendo `stock:insert/delete` a nivel módulo. Todas las funciones de flujo (remitos, producción, compras, ventas) llaman a `public.post_stock_operation`, cuyo control interno no distingue quién la invoca. Pasar a "Stock por depósito: crear" abriría el ingreso manual a un rol que solo emite remitos. Solución futura: una marca de "flujo interno" en la transacción (set_config local) fijada por cada función de flujo ya autorizada. Consecuencia hoy: un rol con Stock parcial puede VER, no registrar (la pantalla Roles lo avisa).
`issue_sale_delivery_note` (remito de venta) queda para el lote de Ventas.

## Decisiones tomadas por el diseñador (confirmar con el propietario)
1. Reposición y ¿Alcanza? exigen su pantalla + Stock por depósito (igual que la decisión de Reposición en la 047).
2. El operario con Órdenes + Stock por depósito (ver) ve reservas y existencias.
3. Un rol solo de Movimientos no ve saldos ni lotes por tabla/resumen/opciones, pero el historial trae balance_after y lote: puede reconstruir el saldo (aceptado).
4. Catálogo: se marcan "exigidos" ítems, unidades, categorías, depósitos y las pantallas de Stock (las políticas de ítems/unidades/categorías/depósitos ya eran por recurso).

## Cambios de acceso a revisar antes de aplicar
Comprobación 7 de `048_comprobaciones.sql` lista los roles con Stock parcial (informativo).

## Revisión crítica (erp-revisor-critico, 25/11): "aplicar tras corregir" — corregido
- P1-1 Movimientos veía saldos por stock_lot_options/breakdown: sacado Movimientos de esas dos; se documenta que balance_after expone el saldo.
- P1-2 roles con inventory:read sin stock:read ganan lectura de saldos/lotes: declarado en la cabecera y comprobación 7b para revisarlos antes de aplicar.
- P2: guarda de cleanup_target ahora exige 7 filas; casos nuevos del grupo 13 (lotes con solo Movimientos, inventory); guardia 8 aclarada como heurística; navegación y Inicio usan los permisos por pantalla de Stock (navConfig, Dashboard).
- Pendiente (P2, sin hacer): deshacer sin comparar definiciones posteriores (documentado); controles "datos" faltantes en algunos "negado" con tablas posiblemente vacías (stock_lots, delivery_notes).

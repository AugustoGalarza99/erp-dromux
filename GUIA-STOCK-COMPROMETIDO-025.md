# Dromux Producción · protección de stock reservado (versión 025)

## Instalar

1. Hacé una copia de la base de prueba y de tu proyecto local. Esta migración interviene en la operación central de stock: **probala en la base de prueba antes de aplicarla donde haya datos reales**.
2. Descomprimí `erp-dromux-stock-comprometido-025.zip` y copiá el contenido de `erp-dromux/` encima de tu proyecto local. Conservá `.env.local`.
3. En Supabase SQL Editor ejecutá **una sola vez** `supabase/025_proteger_reservas.sql`, después de `supabase/024_reservas_disponibilidad.sql` y del resto de migraciones anteriores. El SQL conserva la lógica original de lotes y movimientos, pero hace pasar las salidas por un control de reservas. No borra el historial.
4. Reiniciá Vite si estaba abierto. En la raíz del proyecto ejecutá `npm install` y `npm run dev`. `npm run build` verifica la compilación de la interfaz.

## Qué cambia

- Las **salidas independientes** de stock, ventas y remitos de materiales/productos no pueden consumir la cantidad reservada para órdenes de fabricación. El sistema indica el saldo físico libre para esa operación.
- Una **entrega de insumos para una orden**, con remito o sin él, puede usar la reserva de esa misma orden, más el stock libre. Sigue exigiendo permiso, depósito, lote y stock físico suficientes. Los reintentos idempotentes no vuelven a descontar.
- Entradas, salidas, devoluciones y cierres **reasignan reservas automáticamente** según la fecha de las órdenes. La opción «Recalcular» permanece disponible.
- La campana y el inicio muestran un aviso cuando una orden activa tiene algún componente con reserva insuficiente. El aviso desaparece al cubrirse o cerrar la orden.

## Prueba mínima indispensable en tu base de prueba

1. Elegí un material con 12 unidades en un depósito, fórmula que requiera 8 y dos usuarios con permisos pertinentes. Creá una orden que necesite 8. En «¿Tengo stock para fabricar?» deben verse 12 físicas, 8 reservadas y 4 libres.
2. Intentá una **salida manual o remito independiente de 5**: debe rechazarse sin mover stock. Repetí con 4: debe registrarse una sola vez, quedar 8 físicas y 8 reservadas.
3. Entregá 3 a **esa orden** con remito de producción: deben quedar 5 físicas y 5 reservadas para el resto de su fórmula. Intentá emitir el mismo remito de nuevo mediante el reintento de la interfaz; la salida física no se debe duplicar.
4. Registrá una venta que consuma 1 del material reservado si el tipo de ítem admite venta; debe rechazarse. Para el producto terminado, probá venta y remito de venta: emitir el remito vinculado no debe descontar otra vez.
5. Recibí 10 unidades y confirmá que el stock libre aumenta y que una segunda orden parcial recibe prioridad según fechas. Cancelá una orden sin insumos consumidos o finalizá una en proceso: su reserva debe liberarse.
6. Probá un ítem con lotes y dos depósitos. La reserva actual es **global por ítem**; una orden puede tener cantidad reservada y no encontrarla en el depósito/lote elegido. En ese caso la entrega debe rechazar por stock físico local. No prometas reserva de un lote determinado todavía.
7. Probá dos usuarios operando a la vez: uno crea orden mientras el otro hace una salida. Ninguno debe consumir el stock reservado por la orden confirmada. Verificá permisos entre empresas.

## Límites y etapa siguiente

Las reservas de 024–025 son **por ítem en toda la empresa**. Esta entrega impide que las salidas ajenas consuman el total comprometido, pero todavía no asigna depósito o lote a la orden. Tampoco usa fechas de llegada de compras para prometer una fecha de fabricación, ni calcula días hasta el agotamiento. Esos cálculos necesitan una siguiente etapa de asignación por depósito/lote y previsión de demanda con datos comprobables.

Si un movimiento antiguo ya había dejado menos stock físico que reservas antes de instalar 025, la reasignación reduce las reservas y muestra el faltante: no modifica el historial de movimientos. El SQL debe ejecutarse y probarse en tu instancia; esta entrega solo pasó la compilación local del código.

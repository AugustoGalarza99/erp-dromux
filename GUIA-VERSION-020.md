# Dromux ERP · órdenes de fabricación reales (versión 020)

## Instalación

1. Hacé copia de seguridad de tu proyecto y de la base antes de actualizar.
2. Descomprimí `erp-dromux-produccion-020.zip`. Copiá el contenido de `erp-dromux/` encima de tu proyecto local, respetando las carpetas `src/` y `supabase/`. Mantené tu `.env.local` actual: el ZIP no incluye claves ni credenciales.
3. En el editor SQL de **tu proyecto Supabase**, ejecutá una sola vez `supabase/020_production_jobs.sql`, después de haber aplicado las versiones previas hasta la 019. Si el editor devuelve un error, conservá el texto completo y no intentes ejecutar partes por separado; la migración crea funciones, permisos y tablas vinculadas.
4. En la carpeta raíz de tu proyecto ejecutá `npm install` y `npm run dev`. `npm run build` debe terminar sin errores.
5. Antes de utilizar esto con un cliente, probá el recorrido siguiente en una empresa de prueba con datos de ejemplo. El SQL no fue ejecutado contra tu base porque no tenemos acceso a ella.

## Qué cambia

En **Producción → Órdenes**, indicás producto, cantidad teórica y depósito destino. Elegís **Dejar en la cola** para crear una orden sin tocar stock, o **Ya está fabricado** para ingresar el consumo real y la producción en una operación atómica. Si el producto requiere lote, el campo *Lote del producto terminado* aparece y es obligatorio. Si no requiere lote queda desactivado. Podés añadir un insumo no previsto a la fabricación directa.

En una orden de la cola, **Iniciar fabricación** cambia el estado. Registrás salidas de insumos parciales, con depósito, cantidad y lote cuando corresponda. Cada salida descuenta stock en ese momento. Desde el movimiento de salida podés **devolver** la parte no utilizada; vuelve al depósito y lote originales. Una orden sin consumos netos no puede cerrarse. Para cancelar una orden con consumos pendientes, primero hay que devolverlos. Las operaciones quedan registradas como historial, incluso después del cierre.

Al finalizar, indicás **cantidad real obtenida** y, si aplica, lote y vencimiento. Si el consumo o el rendimiento se apartó de la fórmula, explicás la diferencia. Solo entonces se ingresa el producto terminado al stock por la cantidad real. El costo efectivo suma los insumos retirados menos los devueltos, al costo registrado al retirar cada uno; el costo por unidad terminada considera el rendimiento real. Los precios de venta no se cambian automáticamente.

**Descargar PDF** genera una hoja interna de fabricación con fórmula congelada al crear la orden, movimientos reales, rendimiento, lote, motivo de diferencias y espacio para firma. Podés imprimir una orden antes de empezar y descargarla de nuevo al finalizar.

La pantalla **Planificación** abre o muestra la orden asociada a cada plan; no permite crear dos órdenes para el mismo plan. Las fabricaciones antiguas quedan disponibles bajo *Fabricaciones anteriores*. No se reescribe su historial.

## Prueba recomendada

1. Elegí un producto con fórmula y seguimiento por lotes y asegurate de tener stock de los insumos en un depósito.
2. Creá una orden de **100 kg** en la cola; verificá que no cambien los saldos. Descargá el PDF inicial.
3. Iniciá la orden. Retirá una parte de un insumo; verificá que baje el stock. Retirá otra parte y devolvé el sobrante de una salida; verificá que vuelva al depósito y lote correspondiente.
4. Si se usó un componente extra, registralo. Finalizá con **90 kg reales**, un lote nuevo y el motivo de merma. Verificá que el stock de producto terminado aumente 90, no 100, y que aparezcan el costo real y el PDF actualizado.
5. Probá una segunda orden con **Ya está fabricado**. Elegí depósitos y lotes de los insumos, indicá cantidades efectivamente consumidas y confirmá. Si te faltan permisos de stock, material, lote o costo de referencia, corregí esos datos antes de repetir.
6. Si querés cancelar una orden con material retirado, primero devolvé todas las salidas pendientes. Las devoluciones y la finalización tienen notificaciones y validaciones tanto en la pantalla como en la base.

## Archivos principales

| Archivo | Función |
| --- | --- |
| `supabase/020_production_jobs.sql` | Tablas de órdenes y movimientos, permisos y funciones transaccionales |
| `src/services/production.js` | Conexión de la pantalla con las funciones SQL |
| `src/modules/production/ProductionOrdersPage.jsx` | Creación inmediata o en cola y seguimiento |
| `src/modules/production/ProductionJobCard.jsx` | Consumos, devoluciones, cierre y cancelación |
| `src/modules/production/ProductionPlanningPage.jsx` | Enlace de planes con órdenes |
| `src/modules/production/productionJobPdf.js` | Hoja de fabricación descargable |
| `src/modules/production/production.css` | Estilos adaptables |
| `src/modules/inventory/ItemEditor.jsx` | Ajuste de validación del código interno |

Los movimientos de stock son transaccionales: si falla la fabricación inmediata o el cierre, la operación se revierte. No sustituyen la valoración contable por lotes ni los controles de calidad: esa parte conviene validar con el procedimiento concreto del cliente.

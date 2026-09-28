# Dromux ERP · remitero y producción (versión 022)

## Instalación local

1. Guardá una copia de tu proyecto y de la base de prueba.
2. Descomprimí `erp-dromux-remitos-022.zip` y copiá **el contenido de `erp-dromux/`** sobre la raíz de tu proyecto local, respetando `src/` y `supabase/`.
3. Conservá tu `.env.local`: el archivo no está incluido en el ZIP. No coloques claves de servicio en el navegador. Si empezás desde cero, seguí `.env.example` para las variables públicas de tu proyecto.
4. En el editor SQL de **tu base de prueba**, ejecutá una sola vez `supabase/022_remitos_produccion.sql`, después de las migraciones 001–021. Este archivo crea el historial de remitos, números, líneas, permisos y funciones que registran las entregas de forma transaccional.
5. En la carpeta del proyecto ejecutá `npm install`, `npm run dev` y abrí la dirección que muestre Vite. Para la compilación: `npm run build`.

## Uso

- **Inventario → Remitero → Nuevo remito:** elegí entrega de materiales, de semielaborados/productos, de una orden de fabricación o de una venta registrada. Indicá destinatario, depósito, ítems y cantidades. Para ítems con lote seleccioná el lote. Buscá cada ítem dentro de su propio renglón. El PDF muestra cantidades, lotes, firma de quien entrega y recibe; no muestra costos.
- **Entrega de materiales o productos independiente:** confirmar descuenta stock del ítem elegido. Si entregás un semielaborado fabricado, sus materias primas ya fueron consumidas al fabricarlo: se descuenta el stock del semielaborado, sin repetir su fórmula. Un remito independiente no crea una venta ni un cobro.
- **Para fabricación:** abrí Producción → Órdenes, entrá a un proceso y pulsá «Entregar con remito». Podés remitir todo lo pendiente o una parte, cambiar cantidades y añadir otros insumos. La entrega descuenta stock y registra el consumo real una sola vez. La vista de la orden muestra previsto, entregado y pendiente por insumo. Desde los otros botones podés descargar el proceso, agregar un insumo sin remito, devolver sobrantes, finalizar con cantidad real o cancelar.
- **Venta registrada:** desde Ventas → Últimas ventas pulsá «Emitir remito de entrega», o elegí una venta en el Remitero. Podés repartir la entrega entre varios remitos hasta la cantidad vendida y no devuelta. La venta **ya descontó stock**; emitir este remito solo documenta la entrega y no descuenta por segunda vez. Para entregar una venta existente, usá siempre esta opción.
- **Anular remito:** requiere motivo y confirmación. Los remitos independientes reingresan el stock. Los vinculados a fabricación revierten sus consumos mientras la orden siga en proceso y la salida aún no tenga devoluciones. La anulación del documento vinculado a venta no cambia la venta ni su stock; para devolver mercadería usá la acción de devolución de la venta. Si el proceso ya terminó o el material fue devuelto parcialmente, ajustá desde la orden conforme al historial.

Los números de remito son consecutivos por empresa. El historial es auditable y dos confirmaciones concurrentes con la misma solicitud no generan una doble salida. Los roles deben tener los permisos de stock y, para entregas de fabricación o ventas, también los permisos del módulo respectivo.

## Recorrido breve con datos de prueba

1. Registrá una materia prima, un semielaborado y un producto terminado, con sus depósitos y cantidades disponibles. Emití un remito independiente de una pequeña cantidad y comprobá el stock y el PDF.
2. Creá una orden con receta; remití una primera parte de un insumo y luego otra. Verificá en el proceso las columnas previsto, entregado y pendiente, así como las dos salidas en stock. Devolvé un sobrante y terminá con un rendimiento real distinto al teórico.
3. Registrá una venta. Comprobá su salida de stock; generá dos remitos parciales desde esa venta y verificá que el stock **no vuelva a bajar**. Anulá uno y emití otro por el saldo liberado. Probá también una devolución de venta desde Ventas.
4. Probá un lote, un intento de entrega superior al stock y un intento de entregar más unidades que las vendidas. Deben rechazarse sin modificar los saldos. Revisá la interfaz y los modales en teléfono y escritorio.

## Archivos principales

| Ruta dentro de `erp-dromux/` | Para qué sirve |
| --- | --- |
| `supabase/022_remitos_produccion.sql` | Tablas, permisos, secuencia, emisión y anulación atómicas |
| `src/services/deliveryNotes.js` | Lectura y comandos de remitos |
| `src/modules/inventory/DeliveryNotesPage.jsx` | Remitero, historial, PDF y anulación |
| `src/modules/inventory/DeliveryNoteComposer.jsx` | Formulario por tipo de entrega y entregas parciales |
| `src/modules/inventory/deliveryNotePdf.js` | PDF operativo sin precios ni costos |
| `src/modules/production/ProductionJobCard.jsx` | Panel de cada proceso y sus acciones en modales |
| `src/modules/production/ProductionOrdersPage.jsx` | Órdenes activas y acceso a remitos |
| `src/components/ActionDialog.jsx` | Ventana de acciones adaptable a móvil |
| `src/modules/sales/SalesOrdersPage.jsx` | Acceso directo al remito de cada venta |

La compilación local verifica el código de interfaz. La migración SQL y los movimientos reales deben comprobarse en una copia de la base con tus datos; esta entrega no ejecuta SQL en tu instancia remota. El PDF es un comprobante interno de entrega; si necesitás un documento fiscal con requisitos locales, habrá que adaptar numeración, datos y tratamiento legal.

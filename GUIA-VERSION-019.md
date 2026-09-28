# Dromux ERP · ventas, devoluciones y compras (019)

## Instalación

1. Guardá una copia de tu proyecto y una copia de seguridad de la base antes de actualizar.
2. Copiá **el contenido de `erp-dromux/`** del ZIP sobre la carpeta local de tu proyecto. Conservá el archivo `.env.local` que ya utilizás; el ZIP no contiene contraseñas ni claves.
3. Ejecutá **`supabase/019_ventas_devoluciones_compras.sql`** en el editor SQL de tu base **después de `supabase/018_panel_precios_roles.sql`** y de todas las migraciones anteriores. No vuelvas a ejecutar 019 si ya se aplicó: crea tablas y disparadores nuevos.
4. En la carpeta local del proyecto corré `npm install` y `npm run dev`; reiniciá el servidor si estaba abierto. Si una función nueva aparece como inexistente inmediatamente después de aplicar SQL, actualizá la página y esperá la actualización del esquema de la API.

## Cómo se usa

### Venta y cobro al momento

En **Ventas → Registrar venta** elegí productos y cliente, luego el estado del cobro:

- **Pendiente:** crea la venta y descuenta stock. La venta queda por cobrar.
- **Parcial:** indicá cuánto entra, el medio de pago y la caja o cuenta que lo recibe. El resto queda pendiente.
- **Pagada:** el importe completo se cobra en la misma transacción de la venta. No tenés que repetir el registro en Tesorería.

Para registrar un cobro inmediato se necesitan permisos de Ventas, Stock y Finanzas, y una cuenta activa de Tesorería. **Efectivo** exige una cuenta de tipo **Caja**. Si solo tenés permisos de venta y stock, podés dejar la venta pendiente. Los cobros posteriores siguen disponibles en **Finanzas → Cobros de clientes**. La venta, salida de stock y cobro inicial se confirman juntos: si falla un paso, no se guarda ninguno.

### Anulación y devolución

En **Ventas → Últimas ventas**, abrí **Productos y gestión de devoluciones**. Podés anular toda la venta o devolver una parte; el sistema no permite devolver más de lo vendido. Indicá el motivo y, en cada producto, marcá **Recibido y apto** solo si la mercadería volvió físicamente y puede venderse. Los productos marcados reingresan al depósito original y a su lote original si corresponde. Los no marcados quedan descontados del stock; la devolución y el crédito se registran igualmente.

La venta original y los cobros no se borran. El importe neto, la cuenta por cobrar, el inicio y las ganancias estimadas descuentan la devolución. Si había cobros mayores al nuevo total, se muestra el crédito pendiente del cliente. Desde el mismo detalle, un usuario autorizado puede **registrar un reintegro** seleccionando cuenta, importe y motivo. El reintegro descuenta dinero de Tesorería y queda vinculado a la venta. No se permite reintegrar más que el crédito disponible ni anular un cobro que ya fue reintegrado.

**Ejemplo:** venta $100; cobro inicial $40; devolución por $30. El importe vigente es $70 y restan $30 por cobrar. Si se habían cobrado $100, quedan $30 para reintegrar al cliente.

### Compras

En **Compras → Órdenes de compra** podés elegir primero el proveedor: cada línea ofrece solo los ítems que ese proveedor tiene asociados. También podés elegir primero uno o varios ítems: la lista de proveedores muestra únicamente quienes tienen cotización para todos. Cada línea tiene su buscador inmediatamente encima de su selección, así podés trabajar en el renglón 10 sin volver al inicio de la pantalla. La cotización del proveedor completa el precio en pesos; si está en dólares, se utiliza el tipo de cambio vigente. Antes de crear la orden, la base vuelve a validar que el proveedor efectivamente cotiza cada ítem. La orden mantiene el precio capturado al crearla.

Si un ítem no aparece, cargá antes la relación y cotización en **Compras → Proveedores**. La nueva creación de órdenes conserva el identificador de solicitud para evitar órdenes duplicadas si falla la respuesta de la red.

## Recorrido recomendado antes de publicar

1. Creá una cuenta **Caja** y otra **Banco** en Tesorería, si todavía no existen. Registrá una venta **pagada en efectivo**, verificá la caja, stock y la cuenta por cobrar en cero.
2. Registrá otra venta con **cobro parcial** y completá el resto en Cobros de clientes. Comprobá que no aparecen dos cobros iniciales.
3. Devolvé parte de una venta: una unidad recibida y apta y otra sin reingreso. Revisá movimientos de stock, importe vigente y margen. Probá anular la cantidad restante con un motivo.
4. Para una venta cobrada, registrá una devolución y luego un reintegro parcial desde la cuenta elegida. Comprobá el saldo y que el reintegro aparece en Tesorería.
5. Prepará una compra primero por proveedor, luego otra buscando el ítem en la última línea y eligiendo proveedor después. Intentá un ítem sin cotización para confirmar el aviso. Confirmá una orden y recibila.
6. Repetí las pantallas con el tamaño de un teléfono y con las cuentas de vendedor y administrador.

## Límites de esta entrega

`npm run build` terminó correctamente; **no se ejecutó el SQL en tu base ni se probó la interfaz con datos reales**. La anulación y devolución son movimientos internos del ERP: **no emiten una nota de crédito fiscal ni hacen una transferencia bancaria real**. El reintegro registra la salida declarada de la caja o cuenta elegida. El margen sigue siendo estimado y los productos devueltos sin reingreso conservan su costo como pérdida. Los costos de los ítems todavía están en la tabla general de ítems: si los vendedores tienen lectura de Inventario, esa API requiere una separación adicional de permisos antes de considerarlos datos confidenciales.

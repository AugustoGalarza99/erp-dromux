# ERP Dromux · Proveedores y órdenes de compra

## Instalación

1. Ejecutá **solo** `supabase/migrations/202609250008_purchases.sql` una vez en el SQL Editor del proyecto ERP. Requiere las migraciones `001` a `007`. Si aplicás todas las migraciones exclusivamente con Supabase CLI, utilizá `npx supabase db push` en lugar del editor.
2. Copiá los archivos `src/` incluidos en este ZIP a las mismas rutas de tu proyecto. Conservá tu `.env.local` y reiniciá Vite con `npm run dev`.
3. Ingresá en **Compras → Proveedores** y después en **Compras → Órdenes de compra**.

## Qué hace cada pantalla

**Proveedores:** creá una ficha con nombre, identificación, correo, teléfono y notas. Podés editarla o desactivarla. Un proveedor inactivo permanece en las órdenes históricas y no se ofrece para órdenes nuevas.

**Órdenes:** elegí proveedor, buscá ítems, agregá hasta 40 líneas con cantidad y precio unitario y guardá. La base asigna el número consecutivo de orden por empresa y valida los ítems. El precio se muestra en pesos argentinos como referencia comercial, sin impuestos ni conversión monetaria; todavía no se registran facturas ni pagos.

Crear una orden **no aumenta stock**: una orden expresa lo pedido, no lo recibido. Esta etapa tampoco crea una cuenta por pagar. Las órdenes se conservan y pueden cancelarse mediante una confirmación. No se elimina su historial.

## Prueba guiada

1. Creá un proveedor, por ejemplo **Acero del Centro**. Debe aparecer una notificación de Sonner.
2. Creá una orden para ese proveedor con `10` unidades del ítem A a `2500` cada una y `5` unidades del ítem B a `1000` cada una. El total estimado será `$30.000`.
3. Verificá que la orden aparezca **Abierta** y que el stock de A y B no haya cambiado.
4. Intentá incluir dos veces el mismo ítem: el formulario debe rechazar la orden con un aviso.
5. Desactivá el proveedor: no debe desaparecer de la orden guardada ni estar disponible al crear otra.
6. Si querés cancelar una orden de prueba, hacé clic en **Cancelar orden** y confirmá. Quedará visible como **Cancelada**.

Los permisos se toman del recurso `purchases` que ya usa el menú: `read` para consultar, `insert` para crear y `update` para modificar proveedores o cancelar órdenes. La base verifica empresa activa, pertenencia, ítems y proveedor antes de guardar.

## Siguiente etapa

La **recepción de mercadería** podrá recibir una orden por partes, indicar depósito y lote, y registrar la entrada de stock mediante la operación transaccional ya existente. Al recibir, habrá que distinguir cantidad pedida, recibida y pendiente, manteniendo los importes de la orden como referencia.

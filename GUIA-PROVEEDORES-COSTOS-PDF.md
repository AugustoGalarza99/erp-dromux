# ERP Dromux · materias primas, proveedores y órdenes PDF

## Instalación

1. Ejecutá **solo** `supabase/migrations/202609250009_supplier_material_prices.sql` una vez en Supabase SQL Editor. Deben estar aplicadas las migraciones `001` a `008`. Si utilizás exclusivamente Supabase CLI para todas tus migraciones, aplicá la pendiente con `npx supabase db push` en lugar del editor.
2. Copiá los archivos `src/`, `package.json` y `package-lock.json` del ZIP a las mismas rutas de tu proyecto. Conservá tu `.env.local`.
3. Desde la raíz del proyecto ejecutá `npm install` y luego `npm run dev`. El PDF utiliza `jspdf` y `jspdf-autotable`.

## Cómo se conectan los precios

El ítem de tipo **Materia prima** tiene un **costo de referencia por la unidad** de su ficha: por kg si la unidad es kg, por unidad si la unidad es unidad, etc. Se trata de una referencia interna; no es todavía el costo contable de las existencias.

Una materia prima puede tener varios proveedores. Cada relación guarda el **precio por esa misma unidad** y, opcionalmente, el código que usa el proveedor. Estos precios se ven en **Compras → Proveedores → Materias primas y precios**. Podés filtrar por proveedor y por material; al mostrar varios proveedores del mismo material se destaca el precio registrado más bajo entre los proveedores activos. El comparador no considera calidad, transporte, plazos ni impuestos.

Al crear una orden de compra, primero elegís proveedor. Cuando seleccionás un ítem, el formulario propone el precio de ese proveedor. Si todavía no hay cotización para el material, propone el costo de referencia de la ficha. Podés cambiar el precio para negociar esa orden. **Al guardarla, la orden conserva ese precio:** cambios posteriores en la ficha o la cotización no alteran órdenes anteriores. Cambiar de proveedor mientras completás una orden limpia las líneas para evitar conservar precios del proveedor anterior.

## Prueba guiada

1. Creá dos proveedores, **Acero Norte** y **Acero Sur**.
2. Creá una materia prima **Acero A** con unidad `kg` y costo de referencia `2500` por kg. En la misma ficha, vinculá los dos proveedores: Norte a `2400` por kg y Sur a `2250` por kg. Guardá.
3. Abrí **Compras → Proveedores → Materias primas y precios**. Filtrá por **Acero A** dejando el proveedor en **Todos**. Verificá que aparezcan ambos precios y que Sur figure con el menor precio registrado.
4. Creá una orden con **Acero Sur**, 10 kg de **Acero A**. Al elegir el material, el precio debe quedar en `2250` por kg. El total estimado debe ser `$22.500`.
5. Modificá la cotización del proveedor a `2300`. La orden ya guardada debe seguir mostrando `2250` por kg. Una orden nueva propondrá `2300`.
6. En esa orden, pulsá **Descargar PDF**. Abrí el archivo `orden-compra-00001.pdf` (el número dependerá de tus órdenes previas) e imprimilo si lo necesitás.
7. Para quitar una relación materia prima-proveedor, usá **Quitar relación** en el comparador. Aparecerá la confirmación **«¿Seguro que quieres eliminar?»**. Las órdenes históricas no se borran.

## Límites actuales y siguiente paso

Los importes se muestran en **ARS** y sirven como referencia comercial; todavía no se calculan impuestos, flete, pagos ni valoración de stock. La orden y su PDF documentan lo pedido, **no una recepción ni una factura**. El siguiente flujo conectará la recepción parcial o total de la orden con entradas de stock, depósito, lote y cantidades pendientes, sin volver a cargar el mismo ítem o precio.

Las cotizaciones muestran el precio vigente de cada proveedor; las órdenes conservan su propio precio histórico. El ERP impide cambiar la unidad de un material que ya tiene precios asociados hasta quitar esas relaciones, para evitar comparar precios calculados en unidades diferentes.

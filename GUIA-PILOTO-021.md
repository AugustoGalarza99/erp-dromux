# Dromux ERP · preparación del piloto (versión 021)

Esta entrega está hecha a partir del proyecto `erp-dromux(1).zip` que adjuntaste. Incluye el proyecto completo, no solamente archivos sueltos.

## Instalar en tu proyecto local

1. Guardá una copia de tu carpeta local y de la base antes de actualizar.
2. Descomprimí `erp-dromux-piloto-021.zip`. Copiá el contenido de la carpeta `erp-dromux/` sobre la carpeta raíz de tu proyecto local, conservando la estructura de archivos.
3. **Conservá tu `.env.local` actual**. Por seguridad el ZIP entregado no incluye ese archivo ni sus claves. Usá `.env.example` solamente como referencia si iniciás en otra computadora.
4. En el editor SQL del proyecto de prueba ejecutá **una sola vez** `supabase/021_informes_clientes.sql`, después de `supabase/020_production_jobs.sql`. Si alguno de los anteriores no está aplicado, hacelo en orden. Este SQL agrega dos consultas de lectura e implementa el resumen de ganancias con costos completos; no modifica ventas existentes.
5. Ejecutá `npm install`, `npm run dev` y abrí la dirección local que indique Vite. Para verificar la entrega, corré también `npm run build`.

## Cambios visibles

- **Guía de uso:** está al pie del menú lateral, tiene buscador y muestra pasos de cada área según los permisos del usuario. En los módulos hay un enlace plegable «¿Cómo funciona…?».
- **Navegación:** se abre el grupo de la pantalla actual; «Reportes» lleva a un informe real y se quitó el enlace de «Empresa» que no tenía destino.
- **Movimientos de stock:** una salida asociada a una venta muestra «Venta Nº … · Cliente» cuando hay permiso de ventas. Para otros roles dice «Venta registrada». Los UUID siguen guardados en la base para auditoría, pero no se muestran como título de negocio.
- **Hoja PDF de fabricación:** ahora presenta producto, fórmula, cantidades previstas, salidas/devoluciones reales y lote, sin precios ni costos de insumos. El archivo PDF se genera al descargarlo desde la orden.
- **Finanzas → Rentabilidad y precios:** el administrador ve el resumen histórico y un listado de ventas filtrable por fecha, cliente, número o producto. El detalle muestra importe neto, costo registrado al vender y ganancia bruta. Si falta un costo, muestra «Sin calcular», sin inventar una ganancia. Se puede avanzar por páginas.
- **Reportes:** permite consultar hasta un año de ventas netas, productos vendidos, fabricación y órdenes de compra. Las cifras de cada área se devuelven únicamente si ese usuario puede consultarla. Las órdenes en proceso reflejan el estado actual.

## Cómo se calcula la ganancia

Al registrar una venta, el ERP conserva el precio y un costo estimado unitario del producto. Para un producto fabricado, toma el costo por unidad de la **última fabricación registrada en ese momento**. Si se gastaron más insumos o hubo menor rendimiento y la fabricación ya estaba cerrada, el costo estimado de ventas posteriores contempla esa diferencia.

Cuando hay devolución, el importe devuelto reduce la venta. El costo se reduce solamente si el producto volvió al stock; si no volvió, ese costo continúa en el resultado. Una venta anulada y reintegrada al stock puede quedar con venta neta y costo cero. La rentabilidad histórica usa los valores registrados en cada operación: cambiar hoy la fórmula o el precio no reescribe una venta anterior.

**Límite actual:** si hay stock mezclado de varios lotes de un mismo producto con distintos costos, la venta toma el costo de la última fabricación de ese producto, no un costo individual del lote entregado. La ganancia es **bruta**; no descuenta impuestos, comisiones, sueldos, energía o fletes. Para tomar decisiones contables definitivas, revisar la valuación de lotes y los gastos indirectos con el cliente.

## Recorrido concreto para probar con tu cliente

1. **Administrador:** comprobar que están creadas la empresa, las unidades, depósitos, categorías y roles. Asignar un usuario vendedor y otro operario; verificar que el vendedor ve Lista de precios sin costos y que el operario descarga el PDF sin precios.
2. **Compras/Inventario:** dar de alta una materia prima con proveedor y costo, crear una orden y recibirla. Revisar que el stock aumente una sola vez.
3. **Producción:** crear una fórmula y una orden de 100 kg. Retirar insumos en dos momentos, devolver un sobrante, añadir un insumo extra y cerrar con 90 kg y lote. Confirmar que entran 90 kg y que el PDF muestra cantidades y movimientos, no costos.
4. **Ventas:** establecer el precio, vender una parte del producto a un cliente y cobrarla parcial o totalmente. Verificar que el stock desciende una sola vez y que el cobro no se duplica en tesorería.
5. **Finanzas:** abrir Rentabilidad y precios, buscar esa venta y comparar el importe vendido con el costo registrado. Probar también un producto con costo faltante; la ganancia debe decir «Sin calcular».
6. **Devoluciones y reportes:** devolver una venta a stock y otra sin reposición; comprobar el resultado bruto y el saldo. Consultar Reportes con un período que incluya las operaciones.
7. **Pantallas:** probar al menos con anchos de 360 px, 768 px y escritorio. Abrir todos los grupos del menú en móvil, alcanzar el cierre de sesión y utilizar las tablas desplazándolas horizontalmente cuando sea necesario.

## Archivos que se agregan o cambian

| Ubicación relativa | Función |
| --- | --- |
| `supabase/021_informes_clientes.sql` | Consultas de informes y rentabilidad con permisos de servidor |
| `src/modules/finance/SalesProfitTable.jsx`, `CostsPage.jsx` | Detalle paginado y resumen administrativo |
| `src/modules/reports/ReportsPage.jsx` | Informe operativo por período |
| `src/modules/help/` | Guía con pasos y ayuda contextual |
| `src/components/AdminLayout.jsx`, `src/app/App.jsx` | Menú, rutas y acceso a la guía |
| `src/modules/production/productionJobPdf.js` | Hoja de fabricación sin costos |
| `src/modules/inventory/movementLabels.js`, `MovementsPage.jsx` | Notas comerciales legibles |
| `src/erpPolish.css` y CSS de cada módulo | Ajustes de lectura y adaptación |

`npm run build` se ejecutó correctamente con el código entregado. El SQL necesita ejecutarse y comprobarse con datos en tu proyecto de prueba; no se aplicó en tu proyecto remoto desde esta entrega.

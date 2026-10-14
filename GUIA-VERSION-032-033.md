# Dromux ERP 1.2.0 · compras y producción

Actualización preparada sobre el proyecto adjunto `erp-dromux(2).zip` con las migraciones hasta 031.

## Instalar

1. Ejecutá una sola vez `supabase/032_compras_pagos.sql` completo en el editor SQL de tu proyecto.
2. Después ejecutá una sola vez `supabase/033_documentos_produccion.sql` completo.
3. Copiá el contenido de la carpeta `erp-dromux` del ZIP de actualización sobre tu proyecto, respetando las rutas. Conservá `.env.local`.
4. Reiniciá con `npm run dev`. No hay dependencias nuevas para el sistema.
5. Para publicar, ejecutá `npm run build` y subí el contenido de `dist`, incluidos `meta.json`, `updates.json` y las carpetas públicas.

Cada SQL tiene su propia transacción. Si el 033 falla, su transacción revierte y podés corregir y repetir el 033; no vuelvas a ejecutar el 032 si ya terminó correctamente. Se mantiene el historial de stock, recepciones y pagos existentes.

## Importes del Excel

Se admiten los siguientes ejemplos en costos, precios y stock mínimo:

| Valor | Interpretación |
| --- | --- |
| `$16.500,50` | 16500,50 |
| `16.500,50` | 16500,50 |
| `16500.50` | 16500,50 |
| `1,6` | 1,6 |
| `0,00` | Cero real, no un campo vacío |

Una celda numérica de Excel se lee por su valor original, independientemente de su formato visual. Por ejemplo, una celda numérica con valor 1,6 mantiene ese decimal aunque tenga una presentación personalizada. En texto, un punto seguido por tres cifras se interpreta como separador de miles: `16.500` representa 16500. Para cantidades decimales escritas como texto, usá coma si hay ambigüedad.

Los importes admiten hasta dos decimales y el stock mínimo hasta seis. Los códigos, nombres y códigos de barras no se transforman. Las plantillas anteriores siguen siendo compatibles. Antes de enviar a la base se normalizan los números; no se modifica la precisión de las columnas existentes.

## Compras y cuentas de proveedores

Abrí **Compras → Compras y cuentas**.

### Estadísticas

- Filtrá por fecha inicial y final, ambas incluidas, según horario argentino.
- El total y los rankings consideran **recepciones de mercadería**, no órdenes abiertas todavía sin recibir.
- El top 10 de proveedores se ordena por importe recibido.
- Los productos se pueden ordenar por importe o por frecuencia de recepción. También se muestra la cantidad en su unidad.
- No se suman kilos, metros y unidades como si fueran cantidades comparables.

### Cuenta corriente

Requiere permisos de lectura en Compras y Finanzas. Seleccioná un proveedor con el buscador.

- **Compras:** importe de cada recepción, calculado con su precio histórico.
- **Pagos:** registros de Tesorería asociados a órdenes de ese proveedor. Incluye pagos anteriores a esta actualización.
- **Saldo anterior:** movimientos anteriores al inicio del rango.
- **Saldo al cierre:** saldo acumulado hasta la fecha final, no solo la página visible.
- **Saldo positivo:** deuda por mercadería recibida. **Negativo:** anticipos a favor.

Los movimientos se muestran de a 25. Esta es una cuenta operativa basada en recepciones y pagos: no incluye un módulo de facturas de proveedores, impuestos, notas de crédito ni conciliación bancaria. No registres el mismo pago además como un egreso manual sin vínculo, porque ese egreso genérico no integra la cuenta del proveedor.

### Órdenes de pago

1. Elegí **Nueva orden de pago**, buscá el proveedor y seleccioná una cuenta de Tesorería.
2. Asigná importes parciales o totales a una o varias órdenes de compra del mismo proveedor. Las órdenes a pagar se muestran de a 25; las selecciones se conservan al cambiar de página.
3. Completá la fecha, referencia y detalle. Guardá el borrador.
4. Revisalo en **Órdenes de pago** y usá **Registrar pago** cuando corresponda registrarlo como realizado.
5. Confirmá: se crean los egresos en Tesorería y la cuenta corriente se actualiza en la misma transacción.

Los anticipos pueden pagarse antes de recibir mercadería, hasta el saldo del total de cada orden. Se admiten órdenes abiertas, parcialmente recibidas y recibidas. El sistema vuelve a comprobar los saldos al confirmar, porque otro usuario puede haber registrado un pago mientras el borrador estaba abierto.

Confirmar dos veces la misma OP no duplica egresos. Si un pago compuesto falla en una línea, no se registra ninguna de sus líneas. Los borradores no reservan saldos ni descuentan dinero.

La OP puede descargarse como PDF, con estado **Borrador**, **Pagada** o **Anulada**. Para corregir un borrador, anulalo y creá otro. Un pago confirmado no se elimina ni anula desde esta pantalla; este paquete no agrega la reversión de pagos confirmados. La confirmación registra el movimiento declarado, no ejecuta transferencias bancarias.

## Fórmulas y rendimiento

Ahora hay buscadores para el producto a fabricar, cada componente y la lista de fórmulas. El componente seleccionado se conserva visible aunque el filtro cambie.

En cada producto con fórmula podés activar **Aplicar factor de rendimiento**. Por defecto está desactivado y se usa 1.

| Cantidad base | Factor | Salida esperada |
| --- | --- | --- |
| 100 kg | 1 | 100 kg |
| 100 kg | 0,98 | 98 kg |
| 100 kg | 1,2 | 120 kg |

La fórmula mantiene los insumos de la cantidad base. El factor modifica la salida esperada, y el costo estimado por unidad se divide por esa salida. También se aplica recursivamente al costo de los semielaborados con fórmula.

**Este factor no es densidad física.** La densidad en kg/litro sirve para convertir volumen a masa; no multiplica directamente una masa por otra masa. Para conservar el comportamiento de tus ejemplos se implementó un factor de rendimiento en la misma unidad del producto. Si necesitás una conversión kg/litro real, deben definirse ambas magnitudes y sus unidades.

Cada orden nueva conserva su factor, salida esperada y fórmula al crearse. Cambiar el factor después no altera órdenes existentes. Las órdenes anteriores mantienen factor 1 y su cantidad esperada original.

Al terminar, **solo ingresa al stock la cantidad real confirmada**. El valor sugerido es la salida esperada, pero podés modificarlo y justificar diferencias. Los consumos reales, adicionales y devoluciones siguen registrándose con las acciones habituales. La fórmula y el factor no sustituyen el registro de insumos realmente usados.

La cantidad de la orden representa la base del proceso. Si necesitás un objetivo final distinto, calculá la base según el factor y respetá la precisión de seis decimales. La disponibilidad y las reservas calculan los insumos para esa base.

## Tipos de envasado

Abrí **Producción → Tipos de envasado**. Creá una presentación con nombre, capacidad por envase y unidad existente, por ejemplo “Bidón de 20 litros” o “Bolsa de 25 kg”. Podés editarla o desactivarla.

Al crear una orden, el bloque **Envasado previsto** permite elegir varias presentaciones y cantidades enteras de envases. Es opcional. La orden conserva los nombres, capacidades y cantidades vigentes al crearse.

En la orden, el botón **Envasado y controles** permite cargar las cantidades reales de envases y los resultados de los campos personalizados. Se pueden completar durante el proceso o después de finalizarlo. Un cero real de envases se admite; vacío significa no informado. Si otro usuario modifica esos controles, se pide reabrir el formulario.

El envasado describe la distribución del producto. No descuenta envases automáticamente ni crea un segundo stock de producto envasado. Si bolsas, bidones o cajas tienen stock y costo, se deben registrar como componentes/insumos del proceso mediante el flujo de consumos correspondiente. No se convierten capacidades entre unidades distintas ni se fuerza que la suma envasada coincida con la salida: puede haber remanentes o envasado parcial.

## Logo, campos personalizados y PDF

Abrí **Configuración → Documentos de producción** como administrador.

1. Subí un logo PNG, JPG o WebP de hasta 2 MB. Se adapta a un formato liviano para el documento.
2. Completá el código y revisión del formato.
3. Definí hasta doce títulos de observación o control, uno por línea, por ejemplo “Control de calidad”, “Equipo utilizado” y “Responsable de liberación”.
4. Guardá. Los campos nuevos se muestran en las nuevas órdenes.

El PDF incluye número de OF por empresa, logo, producto, versión de fórmula, fecha, lote, cantidad base, factor, salida esperada y real. La tabla muestra materiales, casillas de verificación, cantidades previstas y reales netas de devoluciones, unidades y espacios para anotaciones. Sigue el bloque de envasado y los controles personalizados, con firmas al final.

No incluye costos, prueba de color ni controles específicos de pintura. Tampoco calcula porcentajes mezclando unidades incompatibles. Las órdenes nuevas conservan el código, revisión y títulos configurados; el logo se obtiene del formato vigente al descargar.

## Archivos y rutas

El ZIP contiene solo los archivos nuevos o modificados y esta guía. Copiá cada archivo en la misma ruta dentro de tu proyecto. Las entradas principales son:

| Parte | Archivo |
| --- | --- |
| Compras y pagos | `src/modules/purchases/SupplierAccountsPage.jsx` |
| Servicio de compras | `src/services/supplierFinance.js` |
| PDF de OP | `src/modules/purchases/supplierPaymentPdf.js` |
| Números de Excel | `src/modules/inventory/importNumber.js`, `itemImportSchema.js`, `ItemImport.jsx` |
| Fórmulas | `src/modules/production/FormulasPage.jsx` |
| Envasado | `src/modules/production/PackagingPage.jsx` |
| Campos de la orden | `src/modules/production/WorkOrderOptions.jsx`, `WorkDetailsDialog.jsx` |
| Órdenes y PDF | `src/modules/production/ProductionOrdersPage.jsx`, `ProductionJobCard.jsx`, `productionJobPdf.js` |
| Configuración | `src/modules/settings/ProductionDocumentSettings.jsx` |
| Servicio documental | `src/services/productionDocuments.js` |
| Menú y rutas | `src/components/AdminLayout.jsx`, `src/app/App.jsx` |

También se incluyen los estilos, el servicio de producción actualizado y `public/meta.json`/`public/updates.json` de la versión 1.2.0.

## Prueba en tu proyecto

1. Importá un ítem con texto `$16.500,50` y otro con una celda numérica de Excel. Revisá los importes antes de confirmar.
2. Creá una OC, recibí una parte y comprobá el ranking y el débito de la cuenta corriente.
3. Registrá una OP parcial. Confirmala dos veces: debe aparecer un único pago. Revisá el egreso en Tesorería.
4. Recibí el resto de la OC y pagá su saldo desde una segunda OP. Comprobá el cierre de la cuenta.
5. Creá una fórmula con cantidad base 100 y factor 0,98. Creá una OF y comprobá salida esperada 98.
6. Definí presentaciones de envasado y controles, seleccioná cantidades y descargá el PDF.
7. Registrá consumos y resultado real distinto del esperado. Verificá stock real y costo consumido.
8. Cambiá los controles y envases reales, descargá de nuevo y comprobá los datos.

## Validación realizada

Se ejecutaron las migraciones anteriores y las nuevas en una instancia PostgreSQL local de prueba mediante PGlite, con identidad de prueba para simular autenticación. Pasaron los escenarios de recepción parcial, pago de OC recibida, cuenta corriente con pagos previos, estadísticas, saldo pendiente, rechazo de sobrepago, confirmación repetida y reversión completa de un pago compuesto que falla. También se probaron rendimiento 0,98, costo por unidad, envasado, actualización de controles, reintento de orden, stock real y bloqueo de consultas de una empresa ajena mediante permisos y RLS.

Pasaron las pruebas de interpretación numérica y renderizado de pantallas. El PDF se generó y revisó visualmente en versiones de una y dos páginas, incluida una orden con 40 materiales. La compilación de producción pasó.

Estas pruebas son locales. No se modificó ni probó tu Supabase real, ni se realizó una prueba interactiva completa en navegador. Aplicá las migraciones y ejecutá la lista anterior en tu empresa de prueba antes de publicar.

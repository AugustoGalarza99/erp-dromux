# Dromux ERP · proveedores y compras · actualización 030 / versión 1.1.0

## Aplicar sobre tu proyecto actual

El paquete se preparó usando el RAR que adjuntaste. Conserva tus códigos de ítems, relaciones, fórmulas, stock y comprobantes. La actualización no renumera ni reemplaza materiales.

1. Ejecutá **una vez** el archivo completo `supabase/030_proveedores_compras.sql` en el SQL Editor de Supabase, después de 029. El archivo abre una transacción: ante un error se revierte su aplicación. No ejecutes nuevamente las migraciones anteriores.
2. Copiá los archivos de la carpeta `erp-dromux` del ZIP sobre tu proyecto local, respetando las rutas. Es un paquete de actualización: no hace falta borrar tu proyecto. Conservá tu `.env.local`.
3. En la raíz del proyecto ejecutá `npm run dev`. La actualización no agrega dependencias. Si preparás una instalación en otra carpeta, primero ejecutá `npm install`.
4. Para publicar, ejecutá `npm run build` y publicá el contenido completo de `dist/`, incluyendo `meta.json`, `updates.json`, `vendor` y `plantillas`.

La guía de instalación usa el número de SQL **030**. La versión visible se actualizó de tu **1.0.0** a **1.1.0**.

## Archivos incluidos y sus ubicaciones

- `src/modules/purchases/SuppliersPage.jsx`: nuevo directorio y acceso a comparador/cotizaciones.
- `src/modules/purchases/SupplierCatalog.jsx`: listado paginado de ítems del proveedor y comparador.
- `src/modules/purchases/SupplierDialogs.jsx`: modales de proveedor, precio y ajuste porcentual.
- `src/modules/purchases/SupplierExchangePanel.jsx`: cotizaciones e historial del dólar.
- `src/modules/purchases/supplierUi.js`: formato de importes y actualización de datos en pantalla.
- `src/modules/purchases/suppliers.css`: estilos y adaptación a pantallas pequeñas.
- `src/modules/purchases/PurchaseOrdersPage.jsx`: órdenes en listado, búsqueda/filtros y preparación mediante modal.
- `src/modules/purchases/ReceiveOrderPanel.jsx`: control del modal durante una recepción.
- `src/services/purchases.js`: consultas paginadas y operaciones de proveedores/compras.
- `src/services/costing.js`: consulta del dólar vigente por cada tipo.
- `public/meta.json` y `public/updates.json`: aviso de nueva versión y novedades.
- `supabase/030_proveedores_compras.sql`: actualización de base.
- `supabase/verificaciones/030_comprobaciones.sql`: verificaciones de instalación, sólo lectura.

## Cómo usar proveedores

1. Entrá en Compras → Proveedores → Nuevo proveedor. Completá nombre y «¿Qué nos provee?». Esa descripción se muestra debajo del nombre. Los datos de contacto y las notas son opcionales.
2. Abrí el proveedor desde su nombre. Allí aparece su catálogo, con búsqueda y paginación de 25 ítems.
3. Usá «Agregar ítem». Buscá un ítem existente en inventario, indicá su precio por la unidad que ya tiene definida y elegí pesos o dólares. Podés crear el ítem de inventario en otra pestaña desde el enlace del modal.
4. Para un ítem en dólares elegí su tipo de dólar. El modal muestra el costo convertido a pesos. El código del proveedor y el ajuste adicional están en una sección desplegable.
5. Si el ítem ya está asociado, usá «Editar precio» en su renglón. Agregarlo nuevamente muestra un aviso y conserva la relación existente. Una edición desactualizada se rechaza si otra persona cambió el precio mientras la ventana estaba abierta.
6. «Comparar proveedores» abre los precios del mismo ítem, ordenados por costo en pesos. Los proveedores inactivos quedan identificados y no se consideran para marcar el menor costo.
7. «Elegir principal» sincroniza el costo de referencia del ítem con ese proveedor. No modifica el precio de venta. Un principal no se puede quitar sin elegir antes otro.
8. «Ajustar %» cambia un solo precio; «Ajustar todos los precios» cambia los de todos los ítems activos de ese proveedor. Se muestran cantidad y hasta cinco ejemplos antes de confirmar. El porcentaje afecta el precio base en su moneda y conserva el ajuste adicional.

No se realizan cambios de stock desde estos modales. Las órdenes, recepciones y ventas previas conservan los importes registrados. Las notificaciones muestran el resultado y quitar una relación requiere confirmación.

## Corrección del dólar

La base antes prohibía repetir tipo + fecha + importe. Eso impedía guardar **1540 → 1545 → 1540** en el mismo día.

Ahora se conserva cada cambio en el historial. Repetir el valor más reciente para esa fecha no crea otro registro, mientras que volver a un valor anterior después de otro cambio sí registra la corrección. La cotización vigente se determina por la fecha más reciente y el último registro de esa fecha. Cambiar una fecha antigua no reemplaza valores de fechas posteriores.

El resumen consulta el valor vigente de cada tipo de dólar sin depender del límite del historial mostrado. Los costos asociados se recalculan y se actualizan los datos en pantalla.

## Cómo usar órdenes de compra

- El listado permite buscar por número de orden o nombre del proveedor y filtrar por estado. Se consultan 25 órdenes por página.
- «Nueva orden de compra» abre un modal. Podés elegir proveedor primero para ver sólo sus ítems o elegir ítems primero para encontrar proveedores comunes.
- Cada renglón tiene su buscador. El precio del proveedor se carga convertido a pesos y se puede negociar un importe distinto para esa orden.
- «Cambiar proveedor» libera la selección y vuelve a buscar proveedores para los ítems elegidos. Si ningún proveedor tiene todos, asociá las cotizaciones que faltan o separá la compra en varias órdenes.
- Cerrar el modal conserva el borrador en esa pantalla. Al guardar se limpia. Cambiar de empresa o salir de la pantalla descarta ese borrador.
- Cada orden muestra su total, un desplegable con materiales y pendientes, y acciones de recepción, historial, cancelación y PDF.
- La recepción sigue registrando el stock una sola vez. No se puede cerrar la ventana mientras se procesa.

## Prueba recomendada en tu empresa

1. Editá un proveedor existente y completá su descripción; verificá que aparezca debajo del nombre.
2. Agregá una materia prima y un insumo, con precios por su unidad. Intentá agregar uno repetido: debe avisarte sin duplicarlo.
3. Asociá el mismo material con un segundo proveedor; compará ambos costos y elegí el principal.
4. Editá un precio; probá un aumento del 10 % sobre un ítem y otro sobre el proveedor. Revisá la vista previa antes de confirmar.
5. Guardá 1540, después 1545 y después 1540 para el mismo tipo y fecha. Verificá el resumen y un material en dólares.
6. Creá una compra, descargá su PDF y recibí parcialmente. Revisá stock y pendiente; repetí la recepción sólo mediante el flujo normal y verificá que el reintento no duplique el ingreso.

## Validación realizada

- Compilación de producción con `npm run build`.
- Renderizado con datos simulados para directorio, acciones del catálogo, formato de pesos, mensaje de dólar faltante, conversión de costo en dólares y detalle/total de órdenes.
- Revisión de permisos y separación por empresa en las nuevas funciones.

No se ejecutó la migración contra tu Supabase ni se realizaron operaciones sobre tus proveedores reales. La prueba del dólar, los ajustes y las recepciones debe completarse en tu entorno después de instalar el SQL.

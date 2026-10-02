# Dromux ERP 1.1.1 · Importación con proveedores y costos en dólares

Esta actualización se aplica sobre el proyecto 1.1.0 que adjuntaste y requiere las migraciones anteriores hasta la 030.

## Instalación

1. Ejecutá **una sola vez** `supabase/031_importacion_costos_proveedores.sql` en el editor SQL de tu proyecto Supabase. Ejecutalo completo: contiene una transacción.
2. Descomprimí el paquete de actualización. Copiá el contenido de la carpeta `erp-dromux` sobre la raíz de tu proyecto local, conservando las rutas. El nombre de tu carpeta local puede ser distinto.
3. Conservá tu `.env.local`. El paquete no contiene credenciales ni modifica la conexión.
4. Reiniciá con `npm run dev`. No hay dependencias nuevas que instalar.
5. Para publicar, ejecutá `npm run build` y subí el contenido de `dist` a tu hosting, incluidos `meta.json`, `updates.json` y la carpeta `plantillas`.

Podés ejecutar `supabase/verificaciones/031_comprobaciones.sql` después de instalar para comprobar columnas, funciones y trigger. Es una consulta de lectura, no una prueba de importación.

## Archivos y ubicación

| Archivo | Ubicación dentro del proyecto |
| --- | --- |
| Migración | `supabase/031_importacion_costos_proveedores.sql` |
| Comprobaciones | `supabase/verificaciones/031_comprobaciones.sql` |
| Formulario de ítems | `src/modules/inventory/ItemEditor.jsx` |
| Campos de costos y proveedor | `src/modules/inventory/ItemCostFields.jsx` |
| Importador | `src/modules/inventory/ItemImport.jsx` |
| Encabezados y validaciones | `src/modules/inventory/itemImportSchema.js` |
| Estilos | `src/modules/inventory/items.css`, `src/modules/inventory/itemImport.css` |
| Servicio de ítems | `src/services/items.js` |
| Actualización de caché relacionada | `src/modules/purchases/supplierUi.js` |
| Plantilla Excel | `public/plantillas/importacion-items.xlsx` |
| Versión y novedades | `public/meta.json`, `public/updates.json` |

## Nuevas columnas de Excel

Las columnas anteriores se mantienen. Se agregan tres al final y pueden quedar vacías. También se aceptan archivos de la plantilla anterior de 13 columnas. Los encabezados identifican las columnas, por lo que podés cambiar su orden sin cambiar sus nombres.

| Columna | Qué completar |
| --- | --- |
| `costo_usd` | Costo por unidad en dólares, hasta dos decimales. Es opcional; 0 es un valor válido. |
| `proveedor` | Nombre exacto de un proveedor activo que ya exista en esta empresa. Es opcional. |
| `tipo_dolar` | Nombre exacto de un tipo de dólar activo que ya exista, con cotización vigente. Se requiere únicamente si completás `costo_usd`. |

Se ignoran las diferencias entre mayúsculas y minúsculas y los espacios al principio/final de los nombres. Si hubiera más de un proveedor activo con el mismo nombre, la importación pide corregir la ambigüedad. No crea proveedores ni tipos de dólar automáticamente.

Los costos son **por la unidad seleccionada**, no por la cantidad de stock. Si la unidad es metro, cargá el costo por metro. El stock mínimo admite hasta seis decimales, por ejemplo 1,6 en una celda numérica de Excel. Si escribís números como texto, usá punto decimal: `1.6`.

### Combinaciones admitidas

| Situación | Costo en pesos | Costo USD | Proveedor | Tipo de dólar |
| --- | --- | --- | --- | --- |
| Costo en pesos sin proveedor | Completar | Vacío | Vacío | Vacío |
| Costo en pesos asociado a proveedor | Completar | Vacío | Existente | Vacío |
| Costo USD sin proveedor | Vacío o informativo | Completar | Vacío | Existente con cotización |
| Costo USD asociado a proveedor | Vacío o informativo | Completar | Existente | Existente con cotización |
| Ítem sin costo ni proveedor | Vacío | Vacío | Vacío | Vacío |

La última combinación se admite para insumos, semielaborados y productos terminados. Las materias primas siguen requiriendo un costo; puede ser en pesos o en dólares, y 0 está permitido.

Si indicás proveedor, necesitás un costo y el ítem debe estar activo. Asociar proveedores requiere permiso **editar Compras**, además de crear Ítems.

Si completás ambos costos, **el dólar es la fuente**: costo en pesos = costo USD × cotización vigente, redondeado a dos decimales. El importe escrito en pesos no fija una cotización particular y se reemplaza por el cálculo. Ejemplo: USD 2,50 × $1540 = $3850 por unidad.

## Qué ocurre al importar

1. El sistema lee el Excel y valida números, opciones, códigos repetidos y campos obligatorios.
2. Antes de confirmar, consulta la empresa para verificar unidades, categorías, proveedores, tipos de dólar y cotizaciones. Muestra el costo calculado en pesos.
3. Al confirmar, vuelve a validar y crea todas las fichas y sus relaciones en una sola transacción. Si alguna fila falla, no queda una importación parcial.
4. Cada proveedor indicado queda como **principal de ese nuevo ítem**. El precio original ARS/USD aparece en Compras → Proveedores, junto con su equivalente en pesos.
5. Sin proveedor, un costo USD queda guardado como referencia del ítem y se recalcula cuando registrás una nueva cotización de ese dólar.

La cotización vigente se determina por fecha de vigencia y luego por la última carga, como en la versión 1.1.0. Si cambia entre la vista previa y la confirmación, se utiliza la vigente al guardar. Las operaciones y órdenes ya registradas conservan sus valores históricos.

La importación **crea ítems nuevos**. No sobrescribe materiales por código, no cambia fórmulas ni movimientos existentes, y no carga stock inicial. Los códigos repetidos se rechazan. Cada fila admite un proveedor; los adicionales se agregan luego en su catálogo.

La plantilla contiene una fila con USD y nombres de ejemplo. Reemplazalos por tus datos reales o dejá vacías esas tres celdas antes de importar. Borrá los ejemplos que no uses.

## Alta manual y edición

En Inventario → Ítems → Nuevo ítem, la sección **Costos y proveedor** ahora está disponible para los cuatro tipos de ítem:

- Buscar proveedor y seleccionarlo en un desplegable, o dejarlo vacío.
- Elegir pesos o dólares y cargar el costo por unidad.
- En dólares, buscar y seleccionar el tipo de dólar y ver el equivalente en pesos.
- Guardar ficha y asociación de proveedor conjuntamente.

Si el ítem ya tiene proveedor principal, su costo se muestra protegido. Se modifica en **Compras → Proveedores**. Podés agregar otro proveedor desde la ficha: se conserva el principal. Si intentás agregar una relación que ya existe, el sistema te indica editar el precio en Compras.

Cuando no hay proveedor principal, el primero asociado desde la ficha pasa a ser principal. A partir de ese momento sus precios son la fuente de costo y reemplazan la referencia independiente en dólares.

Para cargar o editar USD manualmente se necesita acceso de lectura a Compras para elegir cotizaciones. Una ficha con costo existente conserva su costo si solo modificás sus datos generales. Si otra persona o una actualización de costos modifica la ficha mientras la editás, se pide recargar para evitar pisar cambios.

## Prueba recomendada

1. Creá un proveedor de prueba, un tipo de dólar activo y una cotización de $1540.
2. Importá una materia prima con código nuevo, unidad existente, `costo_usd=2.50`, el nombre del proveedor y del tipo de dólar. Dejá `costo_referencia_ars` vacío. Revisá $3850 en la vista previa.
3. Confirmá y verificá la ficha y su catálogo en Compras: precio USD 2,50, equivalente $3850 y proveedor principal.
4. Cambiá la cotización a $1545: verificá $3862,50. Volvé a $1540: verificá $3850.
5. Importá otra fila con costo en pesos y las tres nuevas columnas vacías. Debe funcionar como antes.
6. Probá USD sin proveedor: debe guardar la fuente USD en la ficha y recalcular al cambiar la cotización.
7. Probá proveedor inexistente, dólar sin cotización, USD sin tipo y código repetido. Deben impedir la confirmación.
8. Creá un ítem manualmente con los mismos campos. Después agregá un segundo proveedor y verificá que el principal no cambie.

## Validación realizada

La compilación de producción pasó. Se probaron el mapeo de encabezados de plantillas nuevas y anteriores, columnas reordenadas, campos opcionales, stock decimal, costo USD cero y detección de duplicados. Se verificó el renderizado de los selectores, conversión a pesos, aviso de cotización faltante, protección del costo principal y envío del formulario a la función transaccional. La plantilla se exportó, se revisó visualmente y se comprobó que sus ejemplos se leen con el esquema del importador.

La migración se revisó contra las funciones y columnas anteriores. **No se ejecutó en tu Supabase**: la instalación y las pruebas de base de datos quedan por realizar allí. Las comprobaciones de renderizado no sustituyen una prueba interactiva en navegador ni una prueba de las transacciones en PostgreSQL.

# ERP Dromux · fórmulas y primeras órdenes de producción

## Instalación en tu proyecto local

Si descargás el ZIP de esta entrega, copiá el contenido de su carpeta `erp-dromux/` sobre tu proyecto `D:/Planos/turnero/erp-dromux/`, conservando las rutas. La entrega incluye el código completo del proyecto sin `node_modules`, `dist` ni credenciales. No reemplaces tu `.env` local.

1. Abrí **Supabase → SQL Editor** y ejecutá **una sola vez** `supabase/migrations/202609250011_production.sql` después de la migración 010. Esperá que termine sin error antes de probar la interfaz.
2. En tu carpeta local, ejecutá `npm install` si aún no instalaste las dependencias y luego `npm run dev`.
3. Aparecerán **Producción → Fórmulas** y **Producción → Órdenes de fabricación**. Para operar se necesitan permisos `production.read/update/insert` y `stock.read/insert`.

### Archivos incorporados o modificados

| Ruta desde `erp-dromux/` | Función |
| --- | --- |
| `supabase/migrations/202609250011_production.sql` | Tablas, permisos y funciones transaccionales |
| `src/services/production.js` | Consultas y llamadas a funciones SQL |
| `src/modules/production/FormulasPage.jsx` | Editor de fórmulas |
| `src/modules/production/ProductionOrdersPage.jsx` | Fabricación y consulta del historial |
| `src/modules/production/production.css` | Estilos del módulo |
| `src/app/App.jsx` y `src/components/AdminLayout.jsx` | Rutas y menú |

## Prueba de principio a fin

1. Confirmá que una **materia prima** tenga costo de referencia por su unidad, por ejemplo harina a $1.000/kg. Si usa lotes, confirmá que haya stock en un lote concreto.
2. Creá un **producto terminado** en Inventario, por ejemplo Pan. Su unidad puede ser `unidad`; la unidad de la harina debe ser `kg`.
3. En Fórmulas, elegí Pan; indicá rendimiento **10 unidades**, harina **2 kg** y guardá. El costo estimado del pan será **$200 por unidad**. Agregá más componentes si la receta los lleva. Cada componente se registra en su propia unidad; no hay conversión automática de unidades.
4. Ingresá harina en Inventario → Movimientos si todavía no hay saldo. En Órdenes de fabricación seleccioná Pan, cantidad **20**, depósito de destino y depósito de origen de harina. La vista mostrará que hacen falta **4 kg**. Si la harina usa lotes, elegí el lote con cantidad suficiente.
5. Confirmá la fabricación. Comprobá en Inventario → Stock y Movimientos que se descontaron **4 kg** de harina y entraron **20 unidades** de pan. La orden queda en Últimas fabricaciones con versión, consumo y costo estimado.
6. Probá pedir más harina de la disponible: no se podrá confirmar. Si otro usuario consume stock entre la vista previa y la confirmación, el servidor rechazará la orden completa.
7. Para usar un semielaborado, creale primero su propia fórmula, fabricá sus existencias y después incluilo en la fórmula del producto terminado. Su costo estimado se calcula recursivamente; se consume su **stock real** al fabricar el producto final.

## Cómo trabaja

Una fórmula expresa los insumos necesarios para producir cierta cantidad. Para una orden, el servidor multiplica los insumos por `cantidad a fabricar / rendimiento de la fórmula`, valida hasta seis decimales y consume el stock de cada depósito y lote elegido. Luego ingresa el producto fabricado en su depósito. Si el producto lleva seguimiento por lotes, tenés que indicarle también un lote de salida. Todas las operaciones ocurren en **una sola transacción SQL**: ante cualquier error, no queda ni salida ni entrada parcial.

El costo mostrado es **estimado**, basado en los costos de referencia de las materias primas o las fórmulas de semielaborados. No incorpora mano de obra, gastos indirectos ni precios reales de cada compra. La orden conserva una copia de cantidades y costos utilizados aunque después se modifique la fórmula. Una materia prima sin costo de referencia impide guardar la fórmula; también se detectan fórmulas circulares.

Por ahora cada componente con lotes se consume desde **un solo lote por orden**; si necesitás juntar dos lotes, registrá fabricaciones separadas. Las órdenes ya confirmadas son históricas e inmutables. La pestaña Planificación del menú sigue reservada para la siguiente etapa.

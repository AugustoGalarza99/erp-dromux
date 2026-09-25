# ERP Dromux · planificación de producción (012)

## Instalar

Copiá el contenido de la carpeta `erp-dromux/` del ZIP sobre el proyecto local, respetando la estructura. El ZIP contiene el proyecto completo, sin `node_modules`, `dist`, `.env` ni `.env.local`; conservá tus variables existentes.

1. Ejecutá **una sola vez** `supabase/migrations/202609250012_production_planning.sql` en Supabase → SQL Editor, después de la migración 011.
2. Reiniciá Vite con `npm run dev` si no recargó los archivos.
3. Abrí **Producción → Planificación**.

| Archivo | Uso |
| --- | --- |
| `supabase/migrations/202609250012_production_planning.sql` | Planes y funciones para crearlos, cancelarlos y completarlos |
| `src/modules/production/ProductionPlanningPage.jsx` | Vista de planificación, necesidades y planes |
| `src/modules/production/ProductionOrdersPage.jsx` | Completar planes usando el formulario de fabricación |
| `src/modules/production/production.css` | Diseño del módulo |
| `src/services/production.js` | Llamadas a Supabase |
| `src/app/App.jsx` y `src/components/AdminLayout.jsx` | Ruta y acceso desde el menú |
| `supabase/tests/20260925_production_plans_integrity.sql` | Comprobaciones opcionales de solo lectura |

## Prueba guiada

1. Usá el producto y la fórmula que ya creaste. En **Planificación**, seleccioná el producto, la cantidad a fabricar, el depósito donde recibís el producto y, si querés, una fecha prevista. Revisá los insumos calculados. El disponible que aparece suma todos los depósitos y sirve para planificar; todavía **no reserva** ni descuenta stock.
2. Creá el plan. Confirmá que aparece con estado **Pendiente** y que el stock no cambió.
3. Hacé clic en **Completar fabricación**. El producto, cantidad y destino vienen precargados desde el plan. Elegí el depósito de origen y el lote de cada insumo que use lotes; ingresá el lote de salida si el producto final requiere trazabilidad.
4. Confirmá. Volvé a Planificación: el estado será **Completado**. En Inventario → Movimientos verás las salidas de componentes y la entrada del producto.
5. Creá otro plan y usá **Cancelar plan**. La cancelación pide confirmación y no modifica stock.
6. Si cambiás la fórmula después de crear un plan pendiente, el plan anterior indicará que quedó desactualizado. Creá uno nuevo para revisar necesidades antes de fabricarlo.

La confirmación hace todo dentro de una transacción: si falta stock en un depósito o lote, no se completa la planificación ni se registran movimientos parciales. Si querés verificar los registros una vez probado el flujo, ejecutá el archivo de `supabase/tests/`; cada consulta debe devolver cero filas.

**Costos:** la planificación conserva una estimación del momento en que se creó. La fabricación conserva su propia estimación. No se calculan todavía mano de obra ni gastos generales. La venta y su lista de precios forman parte de la etapa siguiente.

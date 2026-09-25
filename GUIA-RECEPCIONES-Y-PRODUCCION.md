# ERP Dromux · recepciones de compra y próximo módulo de producción

## Instalar esta etapa

1. Ejecutá **solo** `supabase/migrations/202609250010_purchase_receipts.sql` en el SQL Editor del ERP, una vez. Requiere las migraciones `001` a `009`. Si usás Supabase CLI para todo el historial, aplicá la pendiente con `npx supabase db push` en vez del editor.
2. Copiá los archivos `src/` del ZIP a las mismas rutas en tu proyecto local. Conservá `.env.local` y reiniciá Vite.
3. El rol que recibe mercadería necesita `purchases.read`, `purchases.insert`, `stock.read` y `stock.insert`. El administrador ya tiene estos permisos. Se siguen aplicando las reglas de empresa activa.

## Flujo de recepción

La orden dice **cuánto pedimos**. En **Compras → Órdenes de compra**, pulsá **Recibir mercadería** en una orden abierta. Marcá únicamente los ítems que llegaron, elegí depósito, indicá cantidad y completá lote si el ítem lo exige. El precio viene de la orden, no se vuelve a cargar. Podés recibir una parte ahora y el resto en otra recepción.

Al confirmar, la base registra la recepción, genera una entrada de stock por cada ítem, actualiza la cantidad recibida y cambia la orden a **Parcial** o **Recibida**. Todo ocurre en una sola transacción: si falla un depósito, lote o cantidad, ninguna línea de esa recepción queda registrada. La entrada de stock conserva un motivo con el número de orden; el historial de recepciones conserva la operación de stock asociada.

Una orden parcialmente recibida puede cancelarse para dejar sin efecto **lo pendiente**. Lo que ya ingresó a stock permanece en el historial; cualquier corrección debe hacerse con un movimiento compensatorio explicado. Si la red se corta al confirmar, revisá el historial antes de iniciar otra solicitud: repetir exactamente los mismos datos conserva el identificador y evita duplicar la recepción.

## Prueba con números

1. Prepará dos depósitos A y B. Creá una orden con 10 kg de materia prima **Acero A** a `$2.500/kg` y 5 unidades del ítem B a `$1.000/unidad`. Total pedido: `$30.000`.
2. Elegí **Recibir mercadería**, depósito A. Marcá solo Acero A e indicá **4 kg**. Si sigue lotes, ingresá el lote `L-A1` y, si corresponde, el vencimiento. Confirmá con motivo `Remito 001`. La orden debe quedar **Parcial**, Acero A con **4 kg recibidos y 6 pendientes** y stock de A con **4 kg más**.
3. Abrí nuevamente la misma orden, elegí depósito B y recibí los **6 kg** pendientes de Acero A y las **5 unidades** del ítem B. Usá otro lote si corresponde. La orden debe quedar **Recibida** y el stock debe incrementarse en B según las cantidades indicadas. Los precios de la orden no cambian.
4. Consultá **Ver recepciones**: deben aparecer ambas entregas, el depósito y el lote. En **Inventario → Movimientos** verás las entradas asociadas al número de orden.
5. Intentá recibir más de lo pendiente en una orden de prueba: la base debe rechazarlo sin alterar ninguna línea. Opcionalmente ejecutá `supabase/tests/20260925_purchase_receipts_integrity.sql`; sus tres consultas de solo lectura deben devolver **cero filas**.

## Siguiente módulo: producción

El producto final se definirá mediante una **fórmula de fabricación** o lista de materiales: cantidades de materias primas y semielaborados por unidad de producto terminado. Un semielaborado podrá tener su propia fórmula. Evitaremos fórmulas circulares y conservaremos versiones para que una orden antigua no cambie si luego se modifica la receta.

La fórmula mostrará el costo estimado sumando cantidades por costo unitario; distinguiremos este cálculo referencial del costo real derivado de compras, merma y mano de obra. Al crear la orden de producción, el ERP multiplicará la fórmula por las unidades deseadas y mostrará faltantes por ítem y depósito antes de confirmar. Para un insumo seguido por lotes habrá que seleccionar de qué lote se consume.

Confirmar la fabricación requerirá **una única transacción en la base** para descontar todos los componentes, registrar quién y cuánto se consumió, y sumar el producto terminado al depósito elegido. Si falta cualquier componente, no se descontará ni fabricará nada. La operación tendrá su propio identificador para evitar dobles consumos al reintentar.

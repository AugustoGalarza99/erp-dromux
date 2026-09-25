# Guía de uso · ERP Dromux · inventario inicial

## Qué construimos hasta ahora

| Parte | Para qué sirve | Regla clave |
| --- | --- | --- |
| Empresa | Separa los datos de cada cliente del ERP. | `company_id` y RLS impiden cruzar datos. |
| Estado de empresa | Suspende por falta de pago u otra decisión operativa. | `companies.active = false` deniega permisos; la cuenta de Auth no se borra. |
| Usuarios y roles | Asignan a cada persona qué puede ver y hacer. | La interfaz consulta `role_permissions`; PostgreSQL vuelve a comprobar el permiso. |
| Unidades | Definen si el ítem se maneja en kg, unidades, litros, etc. | Después del primer movimiento, la unidad de un ítem no puede cambiar. |
| Categorías | Agrupan ítems para encontrarlos y analizarlos. | Su pertenencia a la misma empresa se valida con claves foráneas. |
| Depósitos | Identifican dónde está físicamente cada ítem. | No se pueden desactivar si todavía contienen stock. |
| Ítems | Son las fichas de materias primas, semielaborados, productos e insumos. | No guardan directamente una cantidad editable. |
| Stock | Guarda el saldo actual por ítem y depósito. | Las entradas, salidas y transferencias lo actualizan mediante una transacción SQL. |
| Movimientos | Conservan quién movió cuánto, dónde, cuándo y por qué. | El historial no se edita ni borra desde la aplicación. |

### Código interno y código de barras

El **código interno** (`MP-001`, por ejemplo) es obligatorio y sirve para identificar el ítem en el ERP. No se repite dentro de la empresa, aunque cambies mayúsculas y minúsculas.

El **código de barras** es opcional. Podés guardar el EAN del fabricante o un código de una etiqueta propia si ya existe, pero **no necesitás un lector** para usar el ERP. Podés buscar ese código escribiéndolo en el formulario de movimiento. Un lector compatible suele introducir los números como si fuera un teclado; más adelante podemos agregarle un flujo de escaneo dedicado. Si no usás etiquetas, dejá el campo vacío. No inventes un código de barras por obligación.

El **stock mínimo** es un umbral informativo de la ficha. La vista Stock compara ese mínimo con el total de todos los depósitos. No modifica las existencias ni genera compras automáticamente.

### Cómo cambia el stock

Una operación de entrada agrega una cantidad a un depósito. Una salida la descuenta del depósito elegido y falla si no hay suficiente. Una transferencia descuenta del depósito origen y suma al destino en **una sola operación**; en el historial aparecen dos líneas relacionadas por el mismo identificador.

`stock_balances` conserva los saldos rápidos para las pantallas. `stock_movements` conserva el historial de variaciones. `post_stock_operation()` realiza ambas escrituras en una transacción y registra el usuario autenticado y el motivo. Si una parte falla, toda la operación se revierte. Las filas de saldo tienen una versión consecutiva para poder cotejarlas con el último movimiento.

No hay una casilla para escribir “stock = 100” directamente: para abrir las existencias se hace una **Entrada** de 100 con motivo “Conteo inicial”. Si cometés un error después, registrá la operación contraria con una explicación. Por ejemplo, ante una entrada duplicada de 5 unidades, registrá una salida de 5 con motivo “Corrección de entrada duplicada ...”. El historial conserva ambas decisiones.

## Prueba guiada con números

Para esta primera prueba, usá un ítem sin la opción “seguir por lotes”. Si solo tenés un depósito, creá otro temporalmente desde Configuración → Depósitos.

1. En **Inventario → Stock por depósito**, elegí **Entrada**, el ítem, el depósito **A**, cantidad `100` y motivo `Conteo inicial`. Confirmá. A debe mostrar `100`.
2. Elegí **Salida**, el mismo ítem y depósito A, cantidad `15`, motivo `Consumo de prueba`. A debe mostrar `85`.
3. Elegí **Transferencia**, A como origen y **B** como destino, cantidad `20`, motivo `Reubicación de prueba`. El desglose debe mostrar A `65`, B `20` y total `85`.
4. Intentá una **Salida** de `66` desde A. La base debe rechazarla por stock insuficiente. A debe seguir en `65` y B en `20`.
5. Abrí **Inventario → Movimientos**. Vas a ver entrada `+100`, salida `−15` y transferencia `−20` en A y `+20` en B. Las dos líneas de transferencia comparten operación.
6. Si pusiste stock mínimo `10`, el total `85` todavía no se marca como bajo. La alerta se refiere al total del ítem; no calcula un mínimo independiente para cada depósito.
7. Opcional: en Supabase SQL Editor ejecutá `supabase/tests/20260924_stock_integrity.sql`. Sus tres consultas son de **solo lectura** y cada una debería devolver **cero filas**. La primera compara saldo con último movimiento; la segunda comprueba transferencias; la tercera compara saldo con la suma de todo el historial.

Podés revisar en la pestaña Network que el historial descarga 25 filas por página. Los filtros de fecha, ítem, depósito y tipo se aplican en Supabase.

## Prueba guiada de lotes

Aplicá la migración `006` y copiá los archivos de esta entrega antes de probar. Creá un ítem nuevo con **Seguir por lotes** activado. Podés usar un código de barras opcional, sin lector.

1. En el depósito A, ingresá `20` unidades al lote `L-001` con un vencimiento opcional. Ingresá otras `10` unidades al lote `L-002`. El total del depósito debe mostrar `30` y el desglose de lotes `20` y `10`.
2. Elegí **Salida**, depósito A y lote `L-001`; descontá `5`. Deben quedar `15` en L-001, `10` en L-002 y `25` en el total.
3. Transferí `8` de L-001 de A hacia B. A debe quedar con `7` de L-001 y `10` de L-002; B, con `8` de L-001. El total del ítem debe seguir siendo `25`.
4. Intentá descontar `9` de L-001 en B: debe aparecer **Stock insuficiente para el lote**. Ningún saldo debe cambiar.
5. Revisá **Inventario → Movimientos**: cada fila lleva el código de lote y, cuando corresponde, su vencimiento. Las dos filas de transferencia llevan el mismo lote y comparten operación.

Los códigos de lote no se repiten dentro del mismo ítem, incluso si varían mayúsculas. Si volvés a ingresar en un lote existente, se conserva su vencimiento original. Un lote ya utilizado no puede borrarse ni cambiar de fecha: para corregir existencias registrá otro movimiento con motivo. Con la migración `007`, un ítem con historial previo puede activar lotes; su stock actual queda en lotes iniciales por depósito y los movimientos viejos conservan su estado original. Un ítem que ya tiene lotes no puede desactivarlos. Las salidas piden un lote concreto: esta versión no reparte automáticamente entre varios lotes ni bloquea por fecha vencida. Evaluá la fecha al elegirlo.

## Costos y siguientes módulos

Esta etapa registra movimientos **manuales**. Una compra aún no genera automáticamente una entrada, una orden de producción aún no consume materia prima y un pedido aún no reserva ni descuenta producto. Esos documentos se conectarán al mismo libro de movimientos cuando construyamos Compras, Producción y Ventas. Tampoco hay valoración monetaria del stock todavía.

## Instalación

Esta entrega presupone las migraciones `001` a `005` ya ejecutadas. Corré **solo** `supabase/migrations/202609240006_stock_lots.sql` una vez en el SQL Editor del proyecto ERP. Si administrás las migraciones con Supabase CLI, usá `npx supabase db push` en vez del editor. Copiá los archivos `src` del ZIP al proyecto, conservá `.env.local` y reiniciá Vite. Aplicá SQL y archivos juntos: la versión anterior del formulario llama a una función SQL que esta migración reemplaza.

El rol `admin` de empresas existentes recibe los permisos `stock` automáticamente. Para otros roles, asigná `stock.read` para consultar, y `stock.insert` para registrar operaciones, en **Configuración → Roles y permisos**. Las políticas RLS comprueban también que la empresa esté activa.

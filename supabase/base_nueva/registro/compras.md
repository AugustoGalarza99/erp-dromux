# Compras

_Generado por `documentar.mjs`; no editar a mano._

## compras_ordenes

Órdenes de compra.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver |
| numero | bigint | sí |  |  | ver |
| proveedor_id | uuid | sí |  | → compras_proveedores | ver |
| proveedor_nombre | text | sí |  |  | ver |
| estado | text | sí | 'abierta'::text |  | ver |
| nota | text | sí | ''::text |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |
| cancelado_en | timestamp with time zone | no |  |  | ver |

Reglas:
- `UNIQUE (empresa_id, numero)`
- `UNIQUE (empresa_id, id)`
- `CHECK ((estado = ANY (ARRAY['abierta'::text, 'parcial'::text, 'recibida'::text, 'cancelada'::text])))`
- `CHECK ((length(nota) <= 500))`
- `CHECK ((numero > 0))`

Seguridad por filas: compras_ordenes_read (SELECT).

## compras_ordenes_antiduplicado

Evita crear dos veces una orden de compra.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | — |
| solicitud_id | uuid | sí |  | clave | — |
| orden_compra_id | uuid | sí |  | → compras_ordenes | — |
| solicitud_datos | jsonb | sí |  |  | — |
| autor_id | uuid | sí |  | → users | — |

Reglas:
- `UNIQUE (empresa_id, orden_compra_id)`

## compras_ordenes_lineas

Ítems de cada orden de compra.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| orden_compra_id | uuid | sí |  | clave → compras_ordenes | ver |
| linea | smallint | sí |  | clave | ver |
| item_id | uuid | sí |  | → stock_items | ver |
| item_codigo | text | sí |  |  | ver |
| unidad_simbolo | text | sí |  |  | ver |
| cantidad | numeric(18,6) | sí |  |  | ver |
| precio_unitario | numeric(18,2) | sí |  |  | ver |
| item_nombre | text | no |  |  | ver |
| cantidad_recibida | numeric(18,6) | sí | 0 |  | ver |

Reglas:
- `CHECK ((cantidad > (0)::numeric))`
- `CHECK (((cantidad_recibida >= (0)::numeric) AND (cantidad_recibida <= cantidad)))`
- `CHECK (((linea >= 1) AND (linea <= 40)))`
- `CHECK ((precio_unitario >= (0)::numeric))`
- `UNIQUE (empresa_id, orden_compra_id, item_id)`

Seguridad por filas: compras_ordenes_lineas_purchase_lines_read (SELECT).

Automatismos: guard_purchase_supplier_item → guard_purchase_supplier_item, purchase_lines_snapshot_name → snapshot_purchase_item_name.

## compras_pagos

Órdenes de pago a proveedores.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver |
| numero | bigint | sí |  |  | ver |
| proveedor_id | uuid | sí |  | → compras_proveedores | ver |
| cuenta_id | uuid | sí |  | → finanzas_cuentas | ver |
| solicitud_id | uuid | sí |  |  | ver |
| solicitud_datos | jsonb | sí |  |  | ver |
| importe | numeric(18,2) | sí |  |  | ver |
| fecha_pago | date | sí |  |  | ver |
| nota | text | sí |  |  | ver |
| referencia | text | sí | ''::text |  | ver |
| estado | text | sí | 'borrador'::text |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |
| confirmado_en | timestamp with time zone | no |  |  | ver |

Reglas:
- `CHECK (((estado = 'pagado'::text) = (confirmado_en IS NOT NULL)))`
- `UNIQUE (empresa_id, id)`
- `UNIQUE (empresa_id, numero)`
- `UNIQUE (empresa_id, solicitud_id)`
- `CHECK ((estado = ANY (ARRAY['borrador'::text, 'pagado'::text, 'cancelado'::text])))`
- `CHECK ((importe > (0)::numeric))`
- `CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 240)))`
- `CHECK ((numero > 0))`
- `CHECK ((length(referencia) <= 120))`

Seguridad por filas: compras_pagos_payment_orders_read (SELECT).

## compras_pagos_lineas

Compras que cubre cada pago.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| pago_id | uuid | sí |  | clave → compras_pagos | ver |
| orden_compra_id | uuid | sí |  | clave → compras_ordenes | ver |
| importe | numeric(18,2) | sí |  |  | ver |
| solicitud_finanzas_id | uuid | sí | gen_random_uuid() |  | ver |
| movimiento_finanzas_id | uuid | no |  | → finanzas_movimientos | ver |

Reglas:
- `CHECK ((importe > (0)::numeric))`

Seguridad por filas: compras_pagos_lineas_payment_order_lines_read (SELECT).

## compras_pedidos

Pedidos internos de compra.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver |
| numero | bigint | sí |  |  | ver |
| solicitado_por | uuid | sí |  |  | ver |
| solicitante_nombre | text | sí |  |  | ver |
| estado | text | sí | 'pendiente'::text |  | ver |
| prioridad | text | sí | 'normal'::text |  | ver |
| fecha_necesaria | date | no |  |  | ver |
| nota | text | sí | ''::text |  | ver |
| nota_resolucion | text | sí | ''::text |  | ver |
| orden_compra_id | uuid | no |  | → compras_ordenes | ver |
| resuelto_por | uuid | no |  |  | ver |
| resuelto_en | timestamp with time zone | no |  |  | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |

Reglas:
- `CHECK (((estado = 'pendiente'::text) = (resuelto_en IS NULL)))`
- `CHECK (((estado <> 'ordenado'::text) OR (orden_compra_id IS NOT NULL)))`
- `UNIQUE (empresa_id, id)`
- `UNIQUE (empresa_id, numero)`
- `CHECK ((estado = ANY (ARRAY['pendiente'::text, 'ordenado'::text, 'rechazado'::text, 'cancelado'::text])))`
- `CHECK ((length(nota) <= 500))`
- `CHECK ((length(nota_resolucion) <= 500))`
- `CHECK ((prioridad = ANY (ARRAY['normal'::text, 'urgente'::text])))`
- `CHECK (((length(solicitante_nombre) >= 1) AND (length(solicitante_nombre) <= 200)))`

Seguridad por filas: compras_pedidos_read (SELECT).

Automatismos: purchase_requests_guard → purchase_requests_guard.

## compras_pedidos_antiduplicado

Evita crear dos veces un pedido interno.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave → empresas | — |
| solicitud_id | uuid | sí |  | clave | — |
| pedido_id | uuid | sí |  | → compras_pedidos | — |
| solicitud_datos | jsonb | sí |  |  | — |
| autor_id | uuid | sí |  |  | — |

## compras_pedidos_lineas

Ítems de cada pedido interno.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  |  | ver |
| pedido_id | uuid | sí |  | clave → compras_pedidos | ver |
| linea | smallint | sí |  | clave | ver |
| item_id | uuid | no |  | → stock_items | ver |
| item_codigo | text | no |  |  | ver |
| item_nombre | text | sí |  |  | ver |
| unidad_simbolo | text | sí | ''::text |  | ver |
| cantidad | numeric | sí |  |  | ver |
| nota | text | sí | ''::text |  | ver |

Reglas:
- `CHECK (((cantidad > (0)::numeric) AND (cantidad < ('1000000000000'::bigint)::numeric)))`
- `CHECK (((item_id IS NOT NULL) OR (item_codigo IS NULL)))`
- `CHECK (((length(btrim(item_nombre)) >= 2) AND (length(btrim(item_nombre)) <= 160)))`
- `CHECK (((linea >= 1) AND (linea <= 200)))`
- `CHECK ((length(nota) <= 200))`
- `CHECK ((length(unidad_simbolo) <= 20))`

Seguridad por filas: compras_pedidos_lineas_read (SELECT).

Automatismos: purchase_request_lines_immutable → purchase_request_lines_immutable.

## compras_proveedores

Proveedores.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver, crear |
| nombre | text | sí |  |  | ver, crear, editar |
| identificacion_fiscal | text | sí | ''::text |  | ver, crear, editar |
| email | text | sí | ''::text |  | ver, crear, editar |
| telefono | text | sí | ''::text |  | ver, crear, editar |
| nota | text | sí | ''::text |  | ver, crear, editar |
| activo | boolean | sí | true |  | ver, crear, editar |
| creado_en | timestamp with time zone | sí | now() |  | ver |
| demora_dias | integer | sí | 7 |  | ver, crear, editar |
| provee_descripcion | text | sí | ''::text |  | ver, crear, editar |

Reglas:
- `CHECK (((demora_dias >= 0) AND (demora_dias <= 365)))`
- `CHECK ((length(email) <= 160))`
- `UNIQUE (empresa_id, id)`
- `CHECK ((length(identificacion_fiscal) <= 30))`
- `CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 160)))`
- `CHECK ((length(nota) <= 500))`
- `CHECK ((length(provee_descripcion) <= 200))`
- `CHECK ((length(telefono) <= 40))`

Seguridad por filas: compras_proveedores_insert (INSERT), compras_proveedores_read (SELECT), compras_proveedores_update (UPDATE).

## compras_proveedores_ajustes_precio

Historial de aumentos o rebajas de precios de proveedor.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver |
| solicitud_id | uuid | sí |  |  | ver |
| proveedor_id | uuid | no |  |  | ver |
| item_id | uuid | no |  |  | ver |
| porcentaje | numeric(8,2) | sí |  |  | ver |
| cantidad_cambiados | integer | sí |  |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | now() |  | ver |

Reglas:
- `UNIQUE (empresa_id, solicitud_id)`
- `CHECK (((porcentaje >= '-99.99'::numeric) AND (porcentaje <= (1000)::numeric)))`

Seguridad por filas: compras_proveedores_ajustes_precio_read (SELECT).

Automatismos: supplier_adjustments_immutable → reject_stock_history_mutation.

## compras_proveedores_items

Precio de cada ítem según cada proveedor.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver, crear |
| proveedor_id | uuid | sí |  | clave → compras_proveedores | ver, crear |
| item_id | uuid | sí |  | clave → stock_items | ver, crear |
| precio_unitario | numeric(18,2) | sí |  |  | ver, crear, editar |
| proveedor_codigo | text | sí | ''::text |  | ver, crear, editar |
| actualizado_en | timestamp with time zone | sí | now() |  | ver |
| moneda | text | sí | 'ARS'::text |  | ver, crear, editar |
| tipo_cambio_id | uuid | no |  | → finanzas_tipos_cambio | ver, crear, editar |
| ajuste_porcentaje | numeric(8,2) | sí | 0 |  | ver, crear, editar |
| preferido | boolean | sí | false |  | ver, crear, editar |

Reglas:
- `CHECK (((ajuste_porcentaje >= '-99.99'::numeric) AND (ajuste_porcentaje <= (1000)::numeric)))`
- `CHECK ((((moneda = 'ARS'::text) AND (tipo_cambio_id IS NULL)) OR ((moneda = 'USD'::text) AND (tipo_cambio_id IS NOT NULL))))`
- `CHECK ((moneda = ANY (ARRAY['ARS'::text, 'USD'::text])))`
- `CHECK ((precio_unitario >= (0)::numeric))`
- `CHECK ((length(proveedor_codigo) <= 80))`

Seguridad por filas: compras_proveedores_items_delete (DELETE), compras_proveedores_items_insert (INSERT), compras_proveedores_items_read (SELECT), compras_proveedores_items_update (UPDATE).

Automatismos: supplier_items_check → check_supplier_item, supplier_preferred_protect → prevent_preferred_quote_deletion, supplier_quote_cost_changed → refresh_quote_cost.

## compras_recepciones

Recepciones de mercadería.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  |  | ver |
| orden_compra_id | uuid | sí |  | → compras_ordenes | ver |
| solicitud_id | uuid | sí |  |  | ver |
| solicitud_datos | jsonb | sí |  |  | ver |
| nota | text | sí |  |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |

Reglas:
- `UNIQUE (empresa_id, id)`
- `CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 430)))`
- `UNIQUE (empresa_id, solicitud_id)`

Seguridad por filas: compras_recepciones_read (SELECT).

Automatismos: purchase_receipts_immutable → reject_stock_history_mutation.

## compras_recepciones_lineas

Ítems recibidos en cada recepción.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| recepcion_id | uuid | sí |  | clave → compras_recepciones | ver |
| orden_compra_id | uuid | sí |  |  | ver |
| linea | smallint | sí |  | clave → compras_ordenes_lineas | ver |
| item_id | uuid | sí |  | → stock_items | ver |
| deposito_id | uuid | sí |  | → stock_depositos | ver |
| deposito_codigo | text | sí |  |  | ver |
| cantidad | numeric(18,6) | sí |  |  | ver |
| precio_unitario | numeric(18,2) | sí |  |  | ver |
| lote_codigo | text | no |  |  | ver |
| vencimiento | date | no |  |  | ver |
| operacion_stock_id | uuid | sí |  | → stock_operaciones | ver |

Reglas:
- `CHECK ((cantidad > (0)::numeric))`
- `CHECK ((precio_unitario >= (0)::numeric))`

Seguridad por filas: compras_recepciones_lineas_read (SELECT).

Automatismos: purchase_receipt_lines_immutable → reject_stock_history_mutation.

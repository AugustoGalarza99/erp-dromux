# Ventas

_Generado por `documentar.mjs`; no editar a mano._

## ventas

Ventas registradas.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  |  | ver |
| numero | bigint | sí |  |  | ver |
| solicitud_id | uuid | sí |  |  | ver |
| solicitud_datos | jsonb | sí |  |  | ver |
| cliente_id | uuid | sí |  | → ventas_clientes | ver |
| cliente_nombre | text | sí |  |  | ver |
| cliente_identificacion_fiscal | text | sí |  |  | ver |
| nota | text | sí |  |  | ver |
| total | numeric(18,2) | sí |  |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |

Reglas:
- `UNIQUE (empresa_id, id)`
- `UNIQUE (empresa_id, numero)`
- `UNIQUE (empresa_id, solicitud_id)`
- `CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 500)))`
- `CHECK ((numero > 0))`
- `CHECK ((total >= (0)::numeric))`

Seguridad por filas: ventas_read (SELECT).

Automatismos: sales_immutable → reject_stock_history_mutation.

## ventas_ajustes

Anulaciones y devoluciones de ventas.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  |  | ver |
| venta_id | uuid | sí |  | → ventas | ver |
| solicitud_id | uuid | sí |  |  | ver |
| tipo | text | sí |  |  | ver |
| motivo | text | sí |  |  | ver |
| credito_total | numeric(18,2) | sí |  |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |

Reglas:
- `CHECK ((credito_total >= (0)::numeric))`
- `UNIQUE (empresa_id, id)`
- `UNIQUE (empresa_id, solicitud_id)`
- `CHECK (((length(btrim(motivo)) >= 5) AND (length(btrim(motivo)) <= 300)))`
- `CHECK ((tipo = ANY (ARRAY['anulacion'::text, 'devolucion'::text])))`

Seguridad por filas: ventas_ajustes_read (SELECT).

Automatismos: sale_adjustments_immutable → reject_stock_history_mutation.

## ventas_ajustes_lineas

Productos de cada anulación o devolución.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| ajuste_id | uuid | sí |  | clave → ventas_ajustes | ver |
| venta_id | uuid | sí |  |  | ver |
| venta_linea | smallint | sí |  | clave → ventas_lineas | ver |
| cantidad | numeric(18,6) | sí |  |  | ver |
| credito_importe | numeric(18,2) | sí |  |  | ver |
| reingresado | boolean | sí |  |  | ver |
| operacion_stock_id | uuid | no |  | → stock_operaciones | ver |

Reglas:
- `CHECK ((cantidad > (0)::numeric))`
- `CHECK ((reingresado = (operacion_stock_id IS NOT NULL)))`
- `CHECK ((credito_importe >= (0)::numeric))`

Seguridad por filas: ventas_ajustes_lineas_read (SELECT).

Automatismos: sale_adjustment_lines_immutable → reject_stock_history_mutation.

## ventas_clientes

Clientes, con su lista de precios.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver, crear |
| nombre | text | sí |  |  | ver, crear, editar |
| identificacion_fiscal | text | sí | ''::text |  | ver, crear, editar |
| email | text | sí | ''::text |  | ver, crear, editar |
| telefono | text | sí | ''::text |  | ver, crear, editar |
| direccion | text | sí | ''::text |  | ver, crear, editar |
| nota | text | sí | ''::text |  | ver, crear, editar |
| activo | boolean | sí | true |  | ver, crear, editar |
| creado_en | timestamp with time zone | sí | now() |  | ver |
| lista_precio_id | uuid | no |  | → ventas_listas_precios | ver |

Reglas:
- `CHECK ((length(direccion) <= 240))`
- `CHECK ((length(email) <= 160))`
- `UNIQUE (empresa_id, id)`
- `CHECK ((length(identificacion_fiscal) <= 30))`
- `CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 160)))`
- `CHECK ((length(nota) <= 500))`
- `CHECK ((length(telefono) <= 40))`

Seguridad por filas: ventas_clientes_insert (INSERT), ventas_clientes_read (SELECT), ventas_clientes_update (UPDATE).

## ventas_cobros

Cobros de ventas.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  |  | ver |
| venta_id | uuid | sí |  | → ventas | ver |
| solicitud_id | uuid | sí |  |  | ver |
| importe | numeric(18,2) | sí |  |  | ver |
| medio_pago | text | sí |  |  | ver |
| fecha_pago | date | sí |  |  | ver |
| referencia | text | sí | ''::text |  | ver |
| nota | text | sí | ''::text |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |

Reglas:
- `UNIQUE (empresa_id, id)`
- `UNIQUE (empresa_id, solicitud_id)`
- `CHECK ((importe > (0)::numeric))`
- `CHECK ((medio_pago = ANY (ARRAY['efectivo'::text, 'transferencia'::text, 'tarjeta'::text, 'cheque'::text, 'otro'::text])))`
- `CHECK ((length(nota) <= 500))`
- `CHECK ((length(referencia) <= 100))`

Seguridad por filas: ventas_cobros_read (SELECT).

Automatismos: guard_sale_payment_net → guard_sale_payment_net, sale_payments_immutable → reject_stock_history_mutation.

## ventas_cobros_antiduplicado

Evita registrar dos veces una venta con cobro.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | — |
| solicitud_id | uuid | sí |  | clave | — |
| venta_id | uuid | sí |  | → ventas | — |
| solicitud_cobro_id | uuid | no |  |  | — |
| modo_pago | text | sí |  |  | — |
| importe | numeric(18,2) | no |  |  | — |
| medio_pago | text | no |  |  | — |
| cuenta_id | uuid | no |  | → finanzas_cuentas | — |
| autor_id | uuid | sí |  | → users | — |

Reglas:
- `UNIQUE (empresa_id, venta_id)`
- `CHECK ((modo_pago = ANY (ARRAY['pendiente'::text, 'parcial'::text, 'pagado'::text])))`

## ventas_cobros_reversiones

Cobros anulados.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  |  | ver |
| venta_id | uuid | sí |  | → ventas | ver |
| cobro_id | uuid | sí |  | → ventas_cobros | ver |
| motivo | text | sí |  |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |

Reglas:
- `UNIQUE (empresa_id, cobro_id)`
- `CHECK (((length(btrim(motivo)) >= 5) AND (length(btrim(motivo)) <= 300)))`

Seguridad por filas: ventas_cobros_reversiones_read (SELECT).

Automatismos: guard_reversal_after_refund → guard_reversal_after_refund, sale_payment_reversals_immutable → reject_stock_history_mutation.

## ventas_items_config

Impuesto y contenido de venta por producto.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| item_id | uuid | sí |  | clave → stock_items | ver |
| impuesto_porcentaje | numeric(5,2) | no |  |  | ver |
| contenido_cantidad | numeric(18,6) | no |  |  | ver |
| contenido_unidad_id | uuid | no |  | → stock_unidades | ver |
| actualizado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |
| actualizado_por | uuid | no |  |  | ver |

Reglas:
- `CHECK (((contenido_cantidad IS NULL) = (contenido_unidad_id IS NULL)))`
- `CHECK (((contenido_cantidad IS NULL) OR (contenido_cantidad > (0)::numeric)))`
- `CHECK (((impuesto_porcentaje IS NULL) OR ((impuesto_porcentaje >= (0)::numeric) AND (impuesto_porcentaje <= (100)::numeric))))`

Seguridad por filas: ventas_items_config_read (SELECT).

## ventas_lineas

Productos de cada venta.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| venta_id | uuid | sí |  | clave → ventas | ver |
| linea | smallint | sí |  | clave | ver |
| item_id | uuid | sí |  | → stock_items | ver |
| item_codigo | text | sí |  |  | ver |
| item_nombre | text | sí |  |  | ver |
| unidad_simbolo | text | sí |  |  | ver |
| deposito_id | uuid | sí |  | → stock_depositos | ver |
| deposito_codigo | text | sí |  |  | ver |
| lote_codigo | text | no |  |  | ver |
| cantidad | numeric(18,6) | sí |  |  | ver |
| precio_unitario | numeric(18,2) | sí |  |  | ver |
| total_linea | numeric(18,2) | sí |  |  | ver |
| costo_unitario_estimado | numeric(18,2) | no |  |  | — |
| operacion_stock_id | uuid | sí |  | → stock_operaciones | ver |
| lista_precio_id | uuid | no |  | → ventas_listas_precios | ver |
| precio_unitario_lista | numeric(18,2) | no |  |  | ver |
| descuento_porcentaje | numeric(5,2) | sí | 0 |  | ver |
| descuento_motivo | text | no |  |  | ver |
| impuesto_porcentaje | numeric(5,2) | no |  |  | ver |

Reglas:
- `CHECK ((cantidad > (0)::numeric))`
- `CHECK (((descuento_motivo IS NULL) OR (length(descuento_motivo) <= 200)))`
- `CHECK (((descuento_porcentaje >= (0)::numeric) AND (descuento_porcentaje < (100)::numeric)))`
- `UNIQUE (empresa_id, venta_id, item_id)`
- `CHECK (((impuesto_porcentaje IS NULL) OR ((impuesto_porcentaje >= (0)::numeric) AND (impuesto_porcentaje <= (100)::numeric))))`
- `CHECK (((linea >= 1) AND (linea <= 40)))`
- `CHECK ((precio_unitario >= (0)::numeric))`
- `CHECK (((precio_unitario_lista IS NULL) OR (precio_unitario_lista >= (0)::numeric)))`
- `CHECK ((total_linea >= (0)::numeric))`

Seguridad por filas: ventas_lineas_read (SELECT).

Automatismos: sale_lines_immutable → reject_stock_history_mutation.

## ventas_listas_items

Precio de cada producto en cada lista.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| lista_precio_id | uuid | sí |  | clave → ventas_listas_precios | ver |
| item_id | uuid | sí |  | clave → stock_items | ver |
| precio_neto | numeric(18,2) | sí |  |  | ver |
| actualizado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |
| actualizado_por | uuid | no |  |  | ver |

Reglas:
- `CHECK (((precio_neto >= (0)::numeric) AND (precio_neto < ('10000000000000000'::bigint)::numeric)))`

Seguridad por filas: ventas_listas_items_read (SELECT).

## ventas_listas_items_historial

Historial de cambios de precios.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | — |
| empresa_id | uuid | sí |  |  | — |
| lista_precio_id | uuid | sí |  | → ventas_listas_precios | — |
| item_id | uuid | sí |  | → stock_items | — |
| precio_neto_anterior | numeric(18,2) | no |  |  | — |
| precio_neto_nuevo | numeric(18,2) | no |  |  | — |
| metodo | text | no |  |  | — |
| metodo_valor | numeric(18,4) | no |  |  | — |
| costo_copia | numeric(18,2) | no |  |  | — |
| origen | text | sí |  |  | — |
| motivo | text | sí | ''::text |  | — |
| cambiado_por | uuid | sí |  |  | — |
| cambiado_en | timestamp with time zone | sí | clock_timestamp() |  | — |

Reglas:
- `CHECK ((length(motivo) <= 200))`
- `CHECK ((origen = ANY (ARRAY['manual'::text, 'masivo'::text, 'recalculo'::text, 'importacion'::text, 'quitado'::text])))`

Automatismos: price_history_immutable → price_history_immutable.

## ventas_listas_items_metodo

Cómo se calculó cada precio.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | — |
| lista_precio_id | uuid | sí |  | clave | — |
| item_id | uuid | sí |  | clave → ventas_listas_items | — |
| metodo | text | sí |  |  | — |
| metodo_valor | numeric(18,4) | sí |  |  | — |
| costo_copia | numeric(18,2) | no |  |  | — |
| actualizado_en | timestamp with time zone | sí | clock_timestamp() |  | — |

Reglas:
- `CHECK ((metodo = ANY (ARRAY['margen'::text, 'recargo'::text, 'fijo'::text])))`
- `CHECK ((metodo_valor >= (0)::numeric))`

## ventas_listas_precios

Listas de precios.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver |
| nombre | text | sí |  |  | ver |
| moneda | text | sí | 'ARS'::text |  | ver |
| lista_base_id | uuid | no |  | → ventas_listas_precios | ver |
| descuento_base_porcentaje | numeric(6,3) | sí | 0 |  | ver |
| redondeo | numeric(12,2) | sí | 0 |  | ver |
| vigente_desde | date | no |  |  | ver |
| vigente_hasta | date | no |  |  | ver |
| es_predeterminada | boolean | sí | false |  | ver |
| archivado | boolean | sí | false |  | ver |
| nota | text | sí | ''::text |  | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |
| creado_por | uuid | no |  |  | ver |

Reglas:
- `CHECK (((lista_base_id IS NULL) OR (lista_base_id <> id)))`
- `CHECK (((vigente_hasta IS NULL) OR (vigente_desde IS NULL) OR (vigente_hasta >= vigente_desde)))`
- `CHECK (((lista_base_id IS NOT NULL) OR (descuento_base_porcentaje = (0)::numeric)))`
- `CHECK (((descuento_base_porcentaje > ('-1000'::integer)::numeric) AND (descuento_base_porcentaje < (100)::numeric)))`
- `UNIQUE (empresa_id, id)`
- `CHECK ((moneda = ANY (ARRAY['ARS'::text, 'USD'::text])))`
- `CHECK (((length(btrim(nombre)) >= 1) AND (length(btrim(nombre)) <= 80)))`
- `CHECK ((length(nota) <= 300))`
- `CHECK ((redondeo >= (0)::numeric))`

Seguridad por filas: ventas_listas_precios_read (SELECT).

Automatismos: price_lists_guard → price_lists_guard.

## ventas_precios_antiduplicado

Evita aplicar dos veces un cambio masivo de precios.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave → empresas | — |
| solicitud_id | uuid | sí |  | clave | — |
| lista_precio_id | uuid | sí |  |  | — |
| tipo | text | sí |  |  | — |
| resultado | jsonb | sí |  |  | — |
| creado_por | uuid | sí |  |  | — |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | — |

Reglas:
- `CHECK ((tipo = ANY (ARRAY['porcentaje'::text, 'recalculo'::text, 'importacion'::text])))`

## ventas_precios_config

Impuesto, márgenes y descuentos por defecto.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave → empresas | — |
| impuesto_porcentaje_predeterminado | numeric(5,2) | sí | 21 |  | — |
| margen_minimo_porcentaje | numeric(5,2) | sí | 0 |  | — |
| comision_porcentaje | numeric(5,2) | sí | 0 |  | — |
| estructura_porcentaje | numeric(5,2) | sí | 0 |  | — |
| actualizado_en | timestamp with time zone | sí | clock_timestamp() |  | — |
| actualizado_por | uuid | no |  |  | — |
| descuento_maximo_porcentaje | numeric(5,2) | sí | 0 |  | — |

Reglas:
- `CHECK (((comision_porcentaje >= (0)::numeric) AND (comision_porcentaje <= (100)::numeric)))`
- `CHECK (((descuento_maximo_porcentaje >= (0)::numeric) AND (descuento_maximo_porcentaje < (100)::numeric)))`
- `CHECK (((estructura_porcentaje >= (0)::numeric) AND (estructura_porcentaje <= (100)::numeric)))`
- `CHECK (((impuesto_porcentaje_predeterminado >= (0)::numeric) AND (impuesto_porcentaje_predeterminado <= (100)::numeric)))`
- `CHECK (((margen_minimo_porcentaje >= (0)::numeric) AND (margen_minimo_porcentaje < (100)::numeric)))`

## ventas_presupuestos

Presupuestos.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver |
| numero | bigint | sí |  |  | ver |
| solicitud_id | uuid | sí |  |  | — |
| solicitud_datos | jsonb | sí |  |  | — |
| cliente_id | uuid | no |  | → ventas_clientes | ver |
| cliente_nombre | text | sí |  |  | ver |
| cliente_identificacion_fiscal | text | sí | ''::text |  | ver |
| cliente_email | text | sí | ''::text |  | ver |
| cliente_telefono | text | sí | ''::text |  | ver |
| cliente_direccion | text | sí | ''::text |  | ver |
| estado | text | sí | 'abierto'::text |  | ver |
| vigente_hasta | date | sí |  |  | ver |
| nota | text | sí | ''::text |  | ver |
| mostrar_impuesto | boolean | sí | true |  | ver |
| total_neto | numeric(18,2) | sí |  |  | ver |
| total_impuesto | numeric(18,2) | sí |  |  | ver |
| total_bruto | numeric(18,2) | sí |  |  | ver |
| impuestos_detalle | jsonb | sí | '[]'::jsonb |  | ver |
| creado_por | uuid | sí |  |  | — |
| creado_por_nombre | text | sí | ''::text |  | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |
| estado_cambiado_en | timestamp with time zone | no |  |  | ver |
| estado_cambiado_por | uuid | no |  |  | — |
| impuesto_incluido | boolean | sí | false |  | ver |

Reglas:
- `CHECK ((total_bruto = (total_neto + total_impuesto)))`
- `CHECK ((length(cliente_direccion) <= 240))`
- `CHECK ((length(cliente_email) <= 160))`
- `CHECK ((length(cliente_identificacion_fiscal) <= 30))`
- `CHECK (((length(btrim(cliente_nombre)) >= 1) AND (length(btrim(cliente_nombre)) <= 160)))`
- `CHECK ((length(cliente_telefono) <= 40))`
- `UNIQUE (empresa_id, id)`
- `UNIQUE (empresa_id, numero)`
- `UNIQUE (empresa_id, solicitud_id)`
- `CHECK ((estado = ANY (ARRAY['abierto'::text, 'aceptado'::text, 'rechazado'::text, 'cancelado'::text])))`
- `CHECK ((length(nota) <= 1000))`
- `CHECK ((NOT (mostrar_impuesto AND impuesto_incluido)))`
- `CHECK ((total_bruto >= (0)::numeric))`
- `CHECK ((total_impuesto >= (0)::numeric))`
- `CHECK (((total_neto >= (0)::numeric) AND (total_neto < ('10000000000000000'::bigint)::numeric)))`

Seguridad por filas: ventas_presupuestos_read (SELECT).

Automatismos: quotes_guard → quotes_guard.

## ventas_presupuestos_estados

Historial de estados de cada presupuesto.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  |  | ver |
| presupuesto_id | uuid | sí |  | → ventas_presupuestos | ver |
| estado_anterior | text | no |  |  | ver |
| estado_nuevo | text | sí |  |  | ver |
| cambiado_por | uuid | sí |  |  | ver |
| cambiado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |

Seguridad por filas: ventas_presupuestos_estados_read (SELECT).

Automatismos: quote_status_events_immutable → quote_lines_immutable.

## ventas_presupuestos_lineas

Productos de cada presupuesto.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| presupuesto_id | uuid | sí |  | clave → ventas_presupuestos | ver |
| linea | smallint | sí |  | clave | ver |
| item_id | uuid | sí |  | → stock_items | ver |
| item_codigo | text | sí |  |  | ver |
| item_nombre | text | sí |  |  | ver |
| unidad_simbolo | text | sí |  |  | ver |
| cantidad | numeric(18,6) | sí |  |  | ver |
| lista_precio_id | uuid | no |  | → ventas_listas_precios | ver |
| precio_unitario_lista | numeric(18,2) | sí |  |  | ver |
| descuento_porcentaje | numeric(5,2) | sí | 0 |  | ver |
| descuento_motivo | text | no |  |  | ver |
| precio_unitario | numeric(18,2) | sí |  |  | ver |
| total_linea | numeric(18,2) | sí |  |  | ver |
| impuesto_porcentaje | numeric(5,2) | sí |  |  | ver |

Reglas:
- `CHECK ((cantidad > (0)::numeric))`
- `CHECK (((descuento_motivo IS NULL) OR (length(descuento_motivo) <= 200)))`
- `CHECK (((descuento_porcentaje >= (0)::numeric) AND (descuento_porcentaje < (100)::numeric)))`
- `UNIQUE (empresa_id, presupuesto_id, item_id)`
- `CHECK (((impuesto_porcentaje >= (0)::numeric) AND (impuesto_porcentaje <= (100)::numeric)))`
- `CHECK (((linea >= 1) AND (linea <= 200)))`
- `CHECK ((precio_unitario >= (0)::numeric))`
- `CHECK ((precio_unitario_lista >= (0)::numeric))`
- `CHECK ((total_linea >= (0)::numeric))`

Seguridad por filas: ventas_presupuestos_lineas_read (SELECT).

Automatismos: quote_lines_immutable → quote_lines_immutable.

## ventas_reintegros

Dinero devuelto a clientes.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  |  | ver |
| venta_id | uuid | sí |  | → ventas | ver |
| solicitud_id | uuid | sí |  |  | ver |
| cuenta_id | uuid | sí |  | → finanzas_cuentas | ver |
| movimiento_finanzas_id | uuid | sí |  | → finanzas_movimientos | ver |
| importe | numeric(18,2) | sí |  |  | ver |
| motivo | text | sí |  |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |

Reglas:
- `UNIQUE (empresa_id, movimiento_finanzas_id)`
- `UNIQUE (empresa_id, solicitud_id)`
- `CHECK ((importe > (0)::numeric))`
- `CHECK (((length(btrim(motivo)) >= 5) AND (length(btrim(motivo)) <= 240)))`

Seguridad por filas: ventas_reintegros_read (SELECT).

Automatismos: sale_refunds_immutable → reject_stock_history_mutation.

# Stock

_Generado por `documentar.mjs`; no editar a mano._

## stock_categorias

Categorías de ítems.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver, crear |
| codigo | text | sí |  |  | ver, crear, editar |
| nombre | text | sí |  |  | ver, crear, editar |
| descripcion | text | sí | ''::text |  | ver, crear, editar |
| activo | boolean | sí | true |  | ver, crear, editar |
| creado_en | timestamp with time zone | sí | now() |  | ver |

Reglas:
- `CHECK ((codigo ~ '^[a-z][a-z0-9_]{0,39}$'::text))`
- `CHECK ((length(descripcion) <= 500))`
- `UNIQUE (empresa_id, codigo)`
- `UNIQUE (empresa_id, id)`
- `CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)))`

Seguridad por filas: stock_categorias_categories_insert (INSERT), stock_categorias_categories_read (SELECT), stock_categorias_categories_update (UPDATE).

## stock_depositos

Depósitos.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver, crear |
| codigo | text | sí |  |  | ver, crear, editar |
| nombre | text | sí |  |  | ver, crear, editar |
| ubicacion | text | sí | ''::text |  | ver, crear, editar |
| activo | boolean | sí | true |  | ver, crear, editar |
| creado_en | timestamp with time zone | sí | now() |  | ver |

Reglas:
- `CHECK ((codigo ~ '^[a-z][a-z0-9_]{0,39}$'::text))`
- `UNIQUE (empresa_id, codigo)`
- `UNIQUE (empresa_id, id)`
- `CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)))`
- `CHECK ((length(ubicacion) <= 250))`

Seguridad por filas: stock_depositos_insert (INSERT), stock_depositos_read (SELECT), stock_depositos_update (UPDATE).

Automatismos: warehouses_prevent_stock_stranding → check_stock_catalog_deactivation.

## stock_items

Materias primas, insumos, semielaborados y productos.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver, crear |
| codigo | text | sí |  |  | ver, crear, editar |
| nombre | text | sí |  |  | ver, crear, editar |
| tipo_item | text | sí |  |  | ver, crear, editar |
| categoria_id | uuid | no |  | → stock_categorias | ver, crear, editar |
| unidad_id | uuid | sí |  | → stock_unidades | ver, crear, editar |
| codigo_barras | text | no |  |  | ver, crear, editar |
| descripcion | text | sí | ''::text |  | ver, crear, editar |
| stock_minimo | numeric(18,6) | sí | 0 |  | ver, crear, editar |
| usa_lotes | boolean | sí | false |  | ver, crear, editar |
| activo | boolean | sí | true |  | ver, crear, editar |
| creado_en | timestamp with time zone | sí | now() |  | ver |
| actualizado_en | timestamp with time zone | sí | now() |  | ver |
| costo_unitario_referencia | numeric(18,2) | no |  |  | — |
| precio_venta_unitario | numeric(18,2) | no |  |  | ver |
| stock_infinito | boolean | sí | false |  | ver, crear, editar |
| costo_referencia_usd | numeric(14,2) | no |  |  | — |
| tipo_cambio_referencia_id | uuid | no |  | → finanzas_tipos_cambio | ver |
| usa_rendimiento | boolean | sí | false |  | ver |
| factor_rendimiento | numeric(12,6) | sí | 1 |  | ver |
| archivado | boolean | sí | false |  | ver |
| activo_antes_de_archivar | boolean | no |  |  | ver |

Reglas:
- `CHECK (((codigo_barras IS NULL) OR ((length(btrim(codigo_barras)) >= 4) AND (length(btrim(codigo_barras)) <= 80))))`
- `CHECK ((codigo ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$'::text))`
- `UNIQUE (empresa_id, codigo)`
- `CHECK (((costo_unitario_referencia IS NULL) OR (costo_unitario_referencia >= (0)::numeric)))`
- `CHECK ((length(descripcion) <= 1500))`
- `UNIQUE (empresa_id, id)`
- `CHECK (((factor_rendimiento > (0)::numeric) AND (factor_rendimiento <= (1000)::numeric)))`
- `CHECK (((NOT stock_infinito) OR ((NOT usa_lotes) AND (stock_minimo = (0)::numeric))))`
- `CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 160)))`
- `CHECK (((precio_venta_unitario IS NULL) OR (precio_venta_unitario >= (0)::numeric)))`
- `CHECK ((((costo_referencia_usd IS NULL) AND (tipo_cambio_referencia_id IS NULL)) OR ((costo_referencia_usd IS NOT NULL) AND (costo_referencia_usd >= (0)::numeric) AND (tipo_cambio_referencia_id IS NOT NULL))))`
- `CHECK ((stock_minimo >= (0)::numeric))`
- `CHECK ((tipo_item = ANY (ARRAY['materia_prima'::text, 'semielaborado'::text, 'producto_terminado'::text, 'insumo'::text])))`

Seguridad por filas: stock_items_insert (INSERT), stock_items_read (SELECT), stock_items_update (UPDATE).

Automatismos: item_archived_activity → protect_archived_activity, items_check_catalogs → check_item_catalogs, items_infinite_transition → check_infinite_stock_change, items_preferred_cost_protect → protect_preferred_material_cost, items_prevent_late_lot_tracking → prevent_late_lot_tracking, items_prevent_stock_stranding → check_stock_catalog_deactivation, items_prevent_unit_change → prevent_stock_unit_change, items_protect_supplier_prices → prevent_supplier_price_unit_mismatch, items_reference_fx_cost → check_reference_fx_cost, items_touch_updated_at → touch_item_updated_at.

## stock_lotes

Lotes y vencimientos de ítems que los usan.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  |  | ver |
| item_id | uuid | sí |  | → stock_items | ver |
| codigo | text | sí |  |  | ver |
| vencimiento | date | no |  |  | ver |
| creado_en | timestamp with time zone | sí | now() |  | ver |

Reglas:
- `CHECK (((length(btrim(codigo)) >= 1) AND (length(btrim(codigo)) <= 80) AND (codigo = btrim(codigo))))`
- `UNIQUE (empresa_id, item_id, id)`

Seguridad por filas: stock_lotes_read (SELECT).

Automatismos: stock_lots_immutable → reject_stock_history_mutation.

## stock_lotes_aperturas

Registro de cuando un ítem con stock empezó a usar lotes.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| item_id | uuid | sí |  | clave | ver |
| deposito_id | uuid | sí |  | clave → stock_depositos | ver |
| lote_id | uuid | sí |  | → stock_lotes | ver |
| cantidad | numeric(18,6) | sí |  |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |

Reglas:
- `CHECK ((cantidad > (0)::numeric))`

Seguridad por filas: stock_lotes_aperturas_read (SELECT).

Automatismos: stock_lot_openings_immutable → reject_stock_history_mutation.

## stock_lotes_saldos

Existencia actual por lote y depósito.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| item_id | uuid | sí |  | clave | ver |
| deposito_id | uuid | sí |  | clave → stock_depositos | ver |
| lote_id | uuid | sí |  | clave → stock_lotes | ver |
| cantidad | numeric(18,6) | sí | 0 |  | ver |

Reglas:
- `CHECK ((cantidad >= (0)::numeric))`

Seguridad por filas: stock_lotes_saldos_read (SELECT).

## stock_movimientos

Renglones de historial de stock con saldo resultante.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  |  | ver |
| operacion_id | uuid | sí |  | → stock_operaciones | ver |
| linea | smallint | sí |  |  | ver |
| item_id | uuid | sí |  | → stock_items | ver |
| deposito_id | uuid | sí |  | → stock_depositos | ver |
| tipo | text | sí |  |  | ver |
| variacion | numeric(18,6) | sí |  |  | ver |
| saldo_posterior | numeric(18,6) | sí |  |  | ver |
| saldo_version | bigint | sí |  |  | ver |
| item_codigo | text | sí |  |  | ver |
| deposito_codigo | text | sí |  |  | ver |
| unidad_simbolo | text | sí |  |  | ver |
| nota | text | sí |  |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |
| lote_id | uuid | no |  | → stock_lotes | ver |
| lote_codigo | text | no |  |  | ver |
| lote_vencimiento | date | no |  |  | ver |

Reglas:
- `CHECK ((linea = ANY (ARRAY[1, 2])))`
- `UNIQUE (operacion_id, linea)`
- `CHECK ((saldo_posterior >= (0)::numeric))`
- `CHECK ((saldo_version > 0))`
- `CHECK ((((tipo = ANY (ARRAY['ingreso'::text, 'transferencia_entrada'::text])) AND (variacion > (0)::numeric)) OR ((tipo = ANY (ARRAY['egreso'::text, 'transferencia_salida'::text])) AND (variacion < (0)::numeric))))`
- `CHECK ((tipo = ANY (ARRAY['ingreso'::text, 'egreso'::text, 'transferencia_salida'::text, 'transferencia_entrada'::text])))`
- `CHECK ((variacion <> (0)::numeric))`

Seguridad por filas: stock_movimientos_read (SELECT).

Automatismos: stock_movements_immutable → reject_stock_history_mutation, stock_movements_infinite_guard → prevent_infinite_physical_movement.

## stock_operaciones

Cada ingreso, egreso o transferencia registrada.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver |
| solicitud_id | uuid | sí |  |  | ver |
| item_id | uuid | sí |  | → stock_items | ver |
| deposito_id | uuid | sí |  | → stock_depositos | ver |
| deposito_destino_id | uuid | no |  | → stock_depositos | ver |
| tipo | text | sí |  |  | ver |
| cantidad | numeric(18,6) | sí |  |  | ver |
| nota | text | sí |  |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |
| lote_id | uuid | no |  | → stock_lotes | ver |
| lote_codigo | text | no |  |  | ver |
| lote_vencimiento | date | no |  |  | ver |

Reglas:
- `CHECK ((cantidad > (0)::numeric))`
- `CHECK ((((tipo = 'transferencia'::text) AND (deposito_destino_id IS NOT NULL) AND (deposito_destino_id <> deposito_id)) OR ((tipo <> 'transferencia'::text) AND (deposito_destino_id IS NULL))))`
- `UNIQUE (empresa_id, id)`
- `CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 500)))`
- `UNIQUE (empresa_id, solicitud_id)`
- `CHECK ((tipo = ANY (ARRAY['ingreso'::text, 'egreso'::text, 'transferencia'::text])))`

Seguridad por filas: stock_operaciones_read (SELECT).

Automatismos: stock_operations_immutable → reject_stock_operation_mutation.

## stock_remitos

Remitos de entrega.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver |
| numero | bigint | sí |  |  | ver |
| solicitud_id | uuid | sí |  |  | ver |
| solicitud_datos | jsonb | sí |  |  | ver |
| tipo | text | sí |  |  | ver |
| orden_id | uuid | no |  | → produccion_ordenes | ver |
| venta_id | uuid | no |  | → ventas | ver |
| destinatario | text | sí |  |  | ver |
| nota | text | sí |  |  | ver |
| estado | text | sí | 'emitido'::text |  | ver |
| motivo_anulacion | text | no |  |  | ver |
| anulado_en | timestamp with time zone | no |  |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |
| archivado | boolean | sí | false |  | ver |

Reglas:
- `CHECK (((tipo = 'produccion'::text) = (orden_id IS NOT NULL)))`
- `CHECK (((tipo = 'venta'::text) = (venta_id IS NOT NULL)))`
- `CHECK (((estado = 'anulado'::text) = ((anulado_en IS NOT NULL) AND (motivo_anulacion IS NOT NULL))))`
- `CHECK (((length(btrim(destinatario)) >= 3) AND (length(btrim(destinatario)) <= 120)))`
- `UNIQUE (empresa_id, id)`
- `UNIQUE (empresa_id, numero)`
- `UNIQUE (empresa_id, solicitud_id)`
- `CHECK ((estado = ANY (ARRAY['emitido'::text, 'anulado'::text])))`
- `CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 300)))`
- `CHECK ((numero > 0))`
- `CHECK ((tipo = ANY (ARRAY['produccion'::text, 'materiales'::text, 'productos'::text, 'venta'::text])))`

Seguridad por filas: stock_remitos_read (SELECT).

## stock_remitos_lineas

Ítems de cada remito.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| remito_id | uuid | sí |  | clave → stock_remitos | ver |
| linea | smallint | sí |  | clave | ver |
| item_id | uuid | sí |  | → stock_items | ver |
| item_codigo | text | sí |  |  | ver |
| item_nombre | text | sí |  |  | ver |
| unidad_simbolo | text | sí |  |  | ver |
| deposito_id | uuid | sí |  | → stock_depositos | ver |
| deposito_nombre | text | sí |  |  | ver |
| lote_codigo | text | no |  |  | ver |
| cantidad | numeric(18,6) | sí |  |  | ver |
| operacion_stock_id | uuid | sí |  | → stock_operaciones | ver |
| evento_produccion_id | uuid | no |  | → produccion_ordenes_eventos | ver |
| venta_id | uuid | no |  |  | ver |
| venta_linea | smallint | no |  | → ventas_lineas | ver |

Reglas:
- `CHECK ((cantidad > (0)::numeric))`
- `CHECK (((venta_id IS NULL) = (venta_linea IS NULL)))`
- `UNIQUE (empresa_id, evento_produccion_id)`
- `CHECK (((linea >= 1) AND (linea <= 40)))`

Seguridad por filas: stock_remitos_lineas_delivery_lines_read (SELECT).

Automatismos: delivery_note_lines_immutable → reject_stock_history_mutation.

## stock_remitos_reversiones

Movimientos que revierten un remito anulado.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| remito_id | uuid | sí |  | clave | ver |
| linea | smallint | sí |  | clave → stock_remitos_lineas | ver |
| operacion_stock_id | uuid | sí |  | → stock_operaciones | ver |
| evento_produccion_id | uuid | no |  | → produccion_ordenes_eventos | ver |
| venta_id | uuid | no |  |  | ver |
| venta_linea | smallint | no |  | → ventas_lineas | ver |

Reglas:
- `CHECK (((venta_id IS NULL) = (venta_linea IS NULL)))`

Seguridad por filas: stock_remitos_reversiones_delivery_reversals_read (SELECT).

Automatismos: delivery_note_reversals_immutable → reject_stock_history_mutation.

## stock_saldos

Existencia actual por ítem y depósito.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave → empresas | ver |
| item_id | uuid | sí |  | clave → stock_items | ver |
| deposito_id | uuid | sí |  | clave → stock_depositos | ver |
| cantidad | numeric(18,6) | sí | 0 |  | ver |
| version | bigint | sí | 0 |  | ver |
| actualizado_en | timestamp with time zone | sí | now() |  | ver |

Reglas:
- `CHECK ((cantidad >= (0)::numeric))`
- `CHECK ((version >= 0))`

Seguridad por filas: stock_saldos_read (SELECT).

## stock_unidades

Unidades de medida.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver, crear |
| codigo | text | sí |  |  | ver, crear, editar |
| nombre | text | sí |  |  | ver, crear, editar |
| simbolo | text | sí |  |  | ver, crear, editar |
| magnitud | text | sí |  |  | ver, crear, editar |
| activo | boolean | sí | true |  | ver, crear, editar |
| creado_en | timestamp with time zone | sí | now() |  | ver |

Reglas:
- `CHECK ((codigo ~ '^[a-z][a-z0-9_]{0,19}$'::text))`
- `UNIQUE (empresa_id, codigo)`
- `UNIQUE (empresa_id, id)`
- `CHECK ((magnitud = ANY (ARRAY['cantidad'::text, 'masa'::text, 'volumen'::text, 'longitud'::text, 'superficie'::text, 'tiempo'::text])))`
- `CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 80)))`
- `CHECK (((length(btrim(simbolo)) >= 1) AND (length(btrim(simbolo)) <= 12)))`

Seguridad por filas: stock_unidades_insert (INSERT), stock_unidades_read (SELECT), stock_unidades_update (UPDATE).

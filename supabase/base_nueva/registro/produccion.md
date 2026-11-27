# Producción

_Generado por `documentar.mjs`; no editar a mano._

## produccion_documentos_config

Logo y datos de los documentos de producción.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave → empresas | ver |
| logo | text | sí | ''::text |  | ver |
| documento_codigo | text | sí | 'OP'::text |  | ver |
| revision | text | sí | '01'::text |  | ver |
| observaciones_etiquetas | jsonb | sí | '[]'::jsonb |  | ver |
| actualizado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |

Seguridad por filas: produccion_documentos_config_document_settings_read (SELECT).

## produccion_fabricaciones

Fabricaciones registradas.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  |  | ver |
| producto_id | uuid | sí |  | → stock_items | ver |
| formula_version | integer | sí |  |  | ver |
| cantidad | numeric(18,6) | sí |  |  | ver |
| deposito_id | uuid | sí |  | → stock_depositos | ver |
| operacion_producto_id | uuid | sí |  | → stock_operaciones | ver |
| costo_estimado | numeric(18,2) | sí |  |  | — |
| solicitud_id | uuid | sí |  |  | ver |
| solicitud_datos | jsonb | sí |  |  | ver |
| nota | text | sí |  |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |
| archivado | boolean | sí | false |  | ver |

Reglas:
- `CHECK ((cantidad > (0)::numeric))`
- `UNIQUE (empresa_id, id)`
- `UNIQUE (empresa_id, solicitud_id)`

Seguridad por filas: produccion_fabricaciones_read (SELECT).

Automatismos: guard_archived_run_recipe → guard_archived_recipe, production_runs_immutable → reject_stock_history_mutation.

## produccion_fabricaciones_antiduplicado

Evita registrar dos veces una fabricación en un paso.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | — |
| solicitud_id | uuid | sí |  | clave | — |
| solicitud_datos | jsonb | sí |  |  | — |
| orden_id | uuid | sí |  | → produccion_ordenes | — |
| fabricacion_id | uuid | sí |  | → produccion_fabricaciones | — |
| autor_id | uuid | sí |  | → users | — |

## produccion_fabricaciones_lineas

Materiales consumidos en cada fabricación.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| fabricacion_id | uuid | sí |  | clave → produccion_fabricaciones | ver |
| componente_id | uuid | sí |  | clave → stock_items | ver |
| deposito_id | uuid | sí |  | → stock_depositos | ver |
| cantidad | numeric(18,6) | sí |  |  | ver |
| lote_codigo | text | no |  |  | ver |
| costo_unitario | numeric(18,2) | sí |  |  | — |
| operacion_stock_id | uuid | sí |  | → stock_operaciones | ver |

Reglas:
- `CHECK ((cantidad > (0)::numeric))`

Seguridad por filas: produccion_fabricaciones_lineas_read (SELECT).

Automatismos: production_run_lines_immutable → reject_stock_history_mutation.

## produccion_formulas

Fórmula o receta de cada producto.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| producto_id | uuid | sí |  | clave → stock_items | ver |
| cantidad_base | numeric(18,6) | sí |  |  | ver |
| version | integer | sí | 1 |  | ver |
| actualizado_en | timestamp with time zone | sí | now() |  | ver |
| archivado | boolean | sí | false |  | ver |

Reglas:
- `CHECK ((cantidad_base > (0)::numeric))`

Seguridad por filas: produccion_formulas_read (SELECT).

Automatismos: guard_archived_formula_edit → guard_archived_formula_edit.

## produccion_formulas_lineas

Componentes y cantidades de cada fórmula.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| producto_id | uuid | sí |  | clave → produccion_formulas | ver |
| componente_id | uuid | sí |  | clave → stock_items | ver |
| cantidad | numeric(18,6) | sí |  |  | ver |

Reglas:
- `CHECK ((cantidad > (0)::numeric))`
- `CHECK ((producto_id <> componente_id))`

Seguridad por filas: produccion_formulas_lineas_read (SELECT).

## produccion_ordenes

Órdenes de fabricación.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver |
| solicitud_id | uuid | sí |  |  | ver |
| solicitud_datos | jsonb | sí |  |  | ver |
| producto_id | uuid | sí |  | → stock_items | ver |
| plan_id | uuid | no |  | → produccion_planes | ver |
| cantidad_planificada | numeric(18,6) | sí |  |  | ver |
| cantidad_real | numeric(18,6) | no |  |  | ver |
| deposito_id | uuid | sí |  | → stock_depositos | ver |
| fecha_limite | date | no |  |  | ver |
| formula_version | integer | sí |  |  | ver |
| formula_copia | jsonb | sí |  |  | — |
| estado | text | sí | 'pendiente'::text |  | ver |
| nota | text | sí |  |  | ver |
| motivo_cancelacion | text | no |  |  | ver |
| nota_diferencia | text | no |  |  | ver |
| producto_lote | text | no |  |  | ver |
| producto_vencimiento | date | no |  |  | ver |
| fabricacion_id | uuid | no |  | → produccion_fabricaciones | ver |
| solicitud_cierre_id | uuid | no |  |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |
| iniciado_en | timestamp with time zone | no |  |  | ver |
| terminado_en | timestamp with time zone | no |  |  | ver |
| cancelado_en | timestamp with time zone | no |  |  | ver |
| numero | bigint | sí |  |  | ver |
| factor_rendimiento | numeric(12,6) | sí | 1 |  | ver |
| cantidad_esperada | numeric(18,6) | sí |  |  | ver |
| documento_copia | jsonb | sí | '{}'::jsonb |  | ver |
| opciones_trabajo | jsonb | sí | '{}'::jsonb |  | ver |
| opciones_trabajo_solicitadas | jsonb | sí | '{}'::jsonb |  | ver |
| detalles_actualizado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |
| archivado | boolean | sí | false |  | ver |

Reglas:
- `CHECK ((cantidad_planificada > (0)::numeric))`
- `CHECK ((cantidad_real > (0)::numeric))`
- `CHECK (((estado = 'terminada'::text) = ((fabricacion_id IS NOT NULL) AND (terminado_en IS NOT NULL) AND (cantidad_real IS NOT NULL) AND (solicitud_cierre_id IS NOT NULL))))`
- `CHECK (((estado = 'cancelada'::text) = (cancelado_en IS NOT NULL)))`
- `UNIQUE (empresa_id, id)`
- `UNIQUE (empresa_id, plan_id)`
- `UNIQUE (empresa_id, solicitud_id)`
- `CHECK ((estado = ANY (ARRAY['pendiente'::text, 'en_proceso'::text, 'terminada'::text, 'cancelada'::text])))`
- `CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 400)))`
- `UNIQUE (empresa_id, numero)`

Seguridad por filas: produccion_ordenes_read (SELECT).

Automatismos: guard_archived_job_recipe → guard_archived_recipe, production_job_document → prepare_production_document, release_production_job_after_update → release_closed_production_job, reserve_production_job_after_insert → reserve_new_production_job.

## produccion_ordenes_eventos

Entregas y devoluciones de material de cada orden.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  |  | ver |
| orden_id | uuid | sí |  | → produccion_ordenes | ver |
| solicitud_id | uuid | sí |  |  | ver |
| tipo | text | sí |  |  | ver |
| entrega_id | uuid | no |  | → produccion_ordenes_eventos | ver |
| componente_id | uuid | sí |  | → stock_items | ver |
| deposito_id | uuid | sí |  | → stock_depositos | ver |
| lote_codigo | text | no |  |  | ver |
| cantidad | numeric(18,6) | sí |  |  | ver |
| costo_unitario | numeric(18,2) | sí |  |  | — |
| operacion_stock_id | uuid | sí |  | → stock_operaciones | ver |
| nota | text | sí |  |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |

Reglas:
- `CHECK ((cantidad > (0)::numeric))`
- `CHECK (((tipo = 'devolucion'::text) = (entrega_id IS NOT NULL)))`
- `CHECK ((costo_unitario >= (0)::numeric))`
- `UNIQUE (empresa_id, id)`
- `UNIQUE (empresa_id, solicitud_id)`
- `CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 300)))`
- `CHECK ((tipo = ANY (ARRAY['entrega'::text, 'devolucion'::text])))`

Seguridad por filas: produccion_ordenes_eventos_read (SELECT).

Automatismos: production_job_events_immutable → reject_stock_history_mutation, rebalance_production_after_event → rebalance_production_on_event.

## produccion_ordenes_reservas

Cantidad que cada orden tiene reservada por componente.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| orden_id | uuid | sí |  | clave → produccion_ordenes | ver |
| componente_id | uuid | sí |  | clave → stock_items | ver |
| cantidad_requerida | numeric(18,6) | sí |  |  | ver |
| cantidad_reservada | numeric(18,6) | sí | 0 |  | ver |
| actualizado_en | timestamp with time zone | sí | now() |  | ver |

Reglas:
- `CHECK ((cantidad_requerida > (0)::numeric))`
- `CHECK ((cantidad_reservada >= (0)::numeric))`

Seguridad por filas: produccion_ordenes_reservas_production_reservations_read (SELECT).

## produccion_planes

Planificación de fabricación.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  |  | ver |
| solicitud_id | uuid | sí |  |  | ver |
| producto_id | uuid | sí |  | → stock_items | ver |
| deposito_id | uuid | sí |  | → stock_depositos | ver |
| cantidad | numeric(18,6) | sí |  |  | ver |
| formula_version | integer | sí |  |  | ver |
| costo_estimado | numeric(18,2) | sí |  |  | — |
| componentes_copia | jsonb | sí |  |  | — |
| fecha_limite | date | no |  |  | ver |
| nota | text | sí |  |  | ver |
| estado | text | sí | 'planificado'::text |  | ver |
| fabricacion_id | uuid | no |  | → produccion_fabricaciones | ver |
| solicitud_cierre_id | uuid | no |  |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | now() |  | ver |
| terminado_en | timestamp with time zone | no |  |  | ver |
| cancelado_en | timestamp with time zone | no |  |  | ver |
| archivado | boolean | sí | false |  | ver |

Reglas:
- `CHECK ((cantidad > (0)::numeric))`
- `CHECK ((((estado = 'terminado'::text) AND (fabricacion_id IS NOT NULL) AND (terminado_en IS NOT NULL) AND (solicitud_cierre_id IS NOT NULL)) OR ((estado <> 'terminado'::text) AND (fabricacion_id IS NULL) AND (terminado_en IS NULL) AND (solicitud_cierre_id IS NULL))))`
- `CHECK (((estado = 'cancelado'::text) = (cancelado_en IS NOT NULL)))`
- `CHECK ((costo_estimado >= (0)::numeric))`
- `UNIQUE (empresa_id, fabricacion_id)`
- `UNIQUE (empresa_id, id)`
- `UNIQUE (empresa_id, solicitud_id)`
- `CHECK ((estado = ANY (ARRAY['planificado'::text, 'terminado'::text, 'cancelado'::text])))`
- `CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 400)))`

Seguridad por filas: produccion_planes_read (SELECT).

Automatismos: guard_archived_plan_recipe → guard_archived_recipe.

## produccion_reservas_ubicaciones

De qué depósito y lote sale cada reserva.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  |  | ver |
| orden_id | uuid | sí |  |  | ver |
| componente_id | uuid | sí |  | → produccion_ordenes_reservas | ver |
| deposito_id | uuid | sí |  | → stock_depositos | ver |
| lote_id | uuid | no |  | → stock_lotes | ver |
| lote_codigo | text | no |  |  | ver |
| cantidad | numeric(18,6) | sí |  |  | ver |

Reglas:
- `CHECK ((cantidad > (0)::numeric))`
- `CHECK (((lote_id IS NULL) = (lote_codigo IS NULL)))`

Seguridad por filas: produccion_reservas_ubicaciones_reservation_locations_read (SELECT).

## produccion_tipos_envase

Envases y presentaciones.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver |
| nombre | text | sí |  |  | ver |
| capacidad | numeric(18,6) | sí |  |  | ver |
| unidad_id | uuid | sí |  | → stock_unidades | ver |
| activo | boolean | sí | true |  | ver |

Reglas:
- `CHECK ((capacidad > (0)::numeric))`
- `UNIQUE (empresa_id, id)`
- `CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)))`

Seguridad por filas: produccion_tipos_envase_packaging_types_read (SELECT).

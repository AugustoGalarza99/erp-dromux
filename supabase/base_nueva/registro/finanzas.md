# Finanzas

_Generado por `documentar.mjs`; no editar a mano._

## finanzas_cobros_cuentas

En qué cuenta entró cada cobro.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave | ver |
| cobro_id | uuid | sí |  | clave → ventas_cobros | ver |
| cuenta_id | uuid | sí |  | → finanzas_cuentas | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |

Seguridad por filas: finanzas_cobros_cuentas_read (SELECT).

Automatismos: treasury_sale_accounts_immutable → reject_stock_history_mutation.

## finanzas_cotizaciones

Valor de cada tipo de dólar por fecha.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  |  | ver |
| tipo_cambio_id | uuid | sí |  | → finanzas_tipos_cambio | ver |
| ars_por_usd | numeric(18,6) | sí |  |  | ver |
| vigente_desde | date | sí |  |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |

Reglas:
- `CHECK ((ars_por_usd > (0)::numeric))`
- `UNIQUE (empresa_id, id)`

Seguridad por filas: finanzas_cotizaciones_read (SELECT).

Automatismos: exchange_rates_immutable → reject_stock_history_mutation, fx_rate_cost_changed → refresh_fx_costs.

## finanzas_cuentas

Cajas y cuentas bancarias.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver |
| nombre | text | sí |  |  | ver |
| tipo | text | sí |  |  | ver |
| saldo_inicial | numeric(18,2) | sí | 0 |  | ver |
| activo | boolean | sí | true |  | ver |
| creado_en | timestamp with time zone | sí | now() |  | ver |

Reglas:
- `UNIQUE (empresa_id, id)`
- `CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)))`
- `CHECK ((tipo = ANY (ARRAY['caja'::text, 'banco'::text, 'otra'::text])))`

Seguridad por filas: finanzas_cuentas_read (SELECT).

## finanzas_movimientos

Ingresos, egresos y transferencias de dinero.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  |  | ver |
| cuenta_id | uuid | sí |  | → finanzas_cuentas | ver |
| solicitud_id | uuid | sí |  |  | ver |
| tipo | text | sí |  |  | ver |
| importe | numeric(18,2) | sí |  |  | ver |
| orden_compra_id | uuid | no |  | → compras_ordenes | ver |
| nota | text | sí |  |  | ver |
| fecha | date | sí |  |  | ver |
| autor_id | uuid | sí |  | → users | ver |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | ver |

Reglas:
- `CHECK (((tipo = 'pago_proveedor'::text) = (orden_compra_id IS NOT NULL)))`
- `UNIQUE (empresa_id, id)`
- `UNIQUE (empresa_id, solicitud_id, tipo)`
- `CHECK ((importe > (0)::numeric))`
- `CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 240)))`
- `CHECK ((tipo = ANY (ARRAY['ingreso'::text, 'egreso'::text, 'pago_proveedor'::text, 'transferencia_entrada'::text, 'transferencia_salida'::text])))`

Seguridad por filas: finanzas_movimientos_read (SELECT).

Automatismos: treasury_entries_immutable → reject_stock_history_mutation.

## finanzas_tipos_cambio

Tipos de dólar definidos por la empresa.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver |
| nombre | text | sí |  |  | ver |
| activo | boolean | sí | true |  | ver |
| archivado | boolean | sí | false |  | ver |
| activo_antes_de_archivar | boolean | no |  |  | ver |

Reglas:
- `UNIQUE (empresa_id, id)`
- `UNIQUE (empresa_id, nombre)`
- `CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 60)))`

Seguridad por filas: finanzas_tipos_cambio_read (SELECT).

Automatismos: exchange_archived_activity → protect_archived_activity.

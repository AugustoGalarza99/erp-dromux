# Tablas internas (esquema private)

_Generado por `documentar.mjs`; no editar a mano._

## private.produccion_solicitudes_eliminadas

Evita que un reintento recree una orden o plan eliminado.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave → empresas | — |
| recurso | text | sí |  | clave | — |
| solicitud_id | uuid | sí |  | clave | — |
| autor_id | uuid | sí |  | → users | — |
| eliminado_en | timestamp with time zone | sí | clock_timestamp() |  | — |

## private.soporte_accesos

Historial de accesos de soporte.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | bigint | sí | automático | clave | — |
| usuario_id | uuid | sí |  | → users | — |
| empresa_id | uuid | sí |  | → empresas | — |
| motivo | text | sí |  |  | — |
| iniciado_en | timestamp with time zone | sí | clock_timestamp() |  | — |
| vence_en | timestamp with time zone | sí |  |  | — |

Reglas:
- `CHECK (((length(btrim(motivo)) >= 8) AND (length(btrim(motivo)) <= 300)))`

## private.soporte_operadores

Usuarios habilitados como soporte.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| usuario_id | uuid | sí |  | clave → users | — |
| activo | boolean | sí | true |  | — |
| creado_en | timestamp with time zone | sí | now() |  | — |

## private.soporte_sesiones

Sesiones de soporte abiertas.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| usuario_id | uuid | sí |  | clave → users | — |
| empresa_id | uuid | sí |  | → empresas | — |
| vence_en | timestamp with time zone | sí |  |  | — |

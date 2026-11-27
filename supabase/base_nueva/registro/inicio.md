# Inicio

_Generado por `documentar.mjs`; no editar a mano._

## inicio_alertas_leidas

Avisos que cada usuario ya marcó como leídos.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave → empresas | ver, crear, editar |
| usuario_id | uuid | sí |  | clave → users | ver, crear, editar |
| alerta_clave | text | sí |  | clave | ver, crear, editar |
| huella | text | sí |  |  | ver, crear, editar |
| leido_en | timestamp with time zone | sí | now() |  | ver, crear, editar |

Reglas:
- `CHECK (((length(alerta_clave) >= 5) AND (length(alerta_clave) <= 120)))`
- `CHECK (((length(huella) >= 1) AND (length(huella) <= 150)))`

Seguridad por filas: inicio_alertas_leidas_insert (INSERT), inicio_alertas_leidas_select (SELECT), inicio_alertas_leidas_update (UPDATE).

# Empresas

_Generado por `documentar.mjs`; no editar a mano._

## empresas

Cada empresa: nombre, si está activa y qué módulos tiene habilitados.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| nombre | text | sí |  |  | ver |
| identificador | text | sí |  |  | ver |
| creado_en | timestamp with time zone | sí | now() |  | ver |
| actualizado_en | timestamp with time zone | sí | now() |  | ver |
| activo | boolean | sí | true |  | ver |
| moneda | text | sí | 'ARS'::text |  | ver |
| zona_horaria | text | sí | 'America/Argentina/Cordoba'::text |  | ver |
| modulos | jsonb | sí | '{"stock": true, "ventas": false, "compras": false, "finanzas": false, "reportes": false, "produccion": true}'::jsonb |  | ver |

Reglas:
- `UNIQUE (identificador)`
- `CHECK ((jsonb_typeof(modulos) = 'object'::text))`
- `CHECK ((moneda ~ '^[A-Z]{3}$'::text))`
- `CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)))`

Seguridad por filas: empresas_member_select (SELECT).

## empresas_numeradores

Próximo número de cada tipo de documento por empresa.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave → empresas | — |
| documento | text | sí |  | clave | — |
| proximo_numero | bigint | sí | 1 |  | — |

Reglas:
- `CHECK ((proximo_numero > 0))`

## empresas_perfil

Datos fiscales, contacto y logo de la empresa.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  | clave → empresas | — |
| razon_social | text | sí | ''::text |  | — |
| identificacion_fiscal | text | sí | ''::text |  | — |
| condicion_fiscal | text | sí | ''::text |  | — |
| direccion | text | sí | ''::text |  | — |
| telefono | text | sí | ''::text |  | — |
| email | text | sí | ''::text |  | — |
| sitio_web | text | sí | ''::text |  | — |
| logo | text | sí | ''::text |  | — |
| actualizado_en | timestamp with time zone | sí | clock_timestamp() |  | — |
| actualizado_por | uuid | no |  |  | — |

Reglas:
- `CHECK ((length(condicion_fiscal) <= 60))`
- `CHECK ((length(direccion) <= 240))`
- `CHECK ((length(email) <= 160))`
- `CHECK ((length(identificacion_fiscal) <= 30))`
- `CHECK ((length(logo) <= 3000000))`
- `CHECK ((length(razon_social) <= 160))`
- `CHECK ((length(sitio_web) <= 160))`
- `CHECK ((length(telefono) <= 40))`

## empresas_usuarios

Qué usuarios pertenecen a cada empresa y con qué rol.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver |
| usuario_id | uuid | sí |  | → users | ver |
| rol_id | uuid | sí |  | → ajustes_roles | ver |
| activo | boolean | sí | true |  | ver |
| creado_en | timestamp with time zone | sí | now() |  | ver |

Reglas:
- `UNIQUE (empresa_id, usuario_id)`

Seguridad por filas: empresas_usuarios_self_or_admin_select (SELECT).

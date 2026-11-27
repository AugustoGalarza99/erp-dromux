# Ajustes y permisos

_Generado por `documentar.mjs`; no editar a mano._

## ajustes_auditoria_accesos

Historial de cambios de roles y usuarios.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | — |
| empresa_id | uuid | sí |  | → empresas | — |
| autor_id | uuid | sí |  |  | — |
| accion | text | sí |  |  | — |
| usuario_destino_id | uuid | no |  |  | — |
| rol_destino_id | uuid | no |  |  | — |
| detalle | jsonb | sí | '{}'::jsonb |  | — |
| creado_en | timestamp with time zone | sí | clock_timestamp() |  | — |

Reglas:
- `CHECK ((accion = ANY (ARRAY['rol_creado'::text, 'rol_editado'::text, 'miembro_editado'::text])))`

Automatismos: access_audit_no_change → access_audit_immutable, access_audit_no_truncate → access_audit_immutable.

## ajustes_perfiles

Nombre visible de cada usuario.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí |  | clave → users | ver |
| nombre | text | no |  |  | ver, editar |
| creado_en | timestamp with time zone | sí | now() |  | ver |
| actualizado_en | timestamp with time zone | sí | now() |  | ver |

Seguridad por filas: ajustes_perfiles_self_select (SELECT), ajustes_perfiles_self_update (UPDATE).

## ajustes_permisos_catalogo

Lista fija de permisos que existen en el sistema.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| recurso | text | sí |  | clave | ver |
| modulo | text | sí |  |  | ver |
| padre | text | no |  | → ajustes_permisos_catalogo | ver |
| etiqueta | text | sí |  |  | ver |
| ayuda | text | sí | ''::text |  | ver |
| orden | integer | sí |  |  | ver |
| acciones | text[] | sí | ARRAY['ver'::text, 'crear'::text, 'editar'::text, 'eliminar'::text, 'gestionar'::text] |  | ver |
| es_grupo | boolean | sí | false |  | ver |
| solo_admin | boolean | sí | false |  | ver |
| exigido | boolean | sí | false |  | ver |

Reglas:
- `CHECK (((acciones <@ ARRAY['ver'::text, 'crear'::text, 'editar'::text, 'eliminar'::text, 'gestionar'::text]) AND (cardinality(acciones) > 0)))`
- `CHECK (((padre IS NULL) OR (padre <> recurso)))`
- `CHECK (((length(btrim(etiqueta)) >= 2) AND (length(btrim(etiqueta)) <= 80)))`
- `CHECK ((recurso ~ '^[a-z][a-z0-9_]*$'::text))`

Seguridad por filas: ajustes_permisos_catalogo_read (SELECT).

## ajustes_roles

Roles definidos por cada empresa.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| id | uuid | sí | gen_random_uuid() | clave | ver |
| empresa_id | uuid | sí |  | → empresas | ver |
| codigo | text | sí |  |  | ver |
| nombre | text | sí |  |  | ver |
| creado_en | timestamp with time zone | sí | now() |  | ver |

Reglas:
- `CHECK ((codigo ~ '^[a-z][a-z0-9_]*$'::text))`
- `UNIQUE (empresa_id, codigo)`
- `UNIQUE (empresa_id, id)`

Seguridad por filas: ajustes_roles_member_select (SELECT).

## ajustes_roles_permisos

Qué puede ver o hacer cada rol.

| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |
|---|---|---|---|---|---|
| empresa_id | uuid | sí |  |  | ver |
| rol_id | uuid | sí |  | clave → ajustes_roles | ver |
| recurso | text | sí |  | clave | ver |
| accion | text | sí |  | clave | ver |

Reglas:
- `CHECK ((accion = ANY (ARRAY['ver'::text, 'crear'::text, 'editar'::text, 'eliminar'::text, 'gestionar'::text])))`
- `CHECK ((recurso ~ '^[a-z][a-z0-9_]*$'::text))`

Seguridad por filas: ajustes_roles_permisos_member_select (SELECT).

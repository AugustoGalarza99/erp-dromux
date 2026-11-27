# Bitácora de la base de datos

Un renglón por cada cambio aplicado a la base real, del más nuevo al más antiguo. La completa quien prepara el cambio; la fecha de aplicación y la comprobación se agregan al verificarlo.

| Aplicado | Archivo | Qué cambió | Comprobación |
|---|---|---|---|
| 26/11/2026 | `sql/01` a `sql/04` | Línea base: 76 tablas en español, 200 funciones, 79 reglas de acceso, 60 automatismos, 34 permisos, módulos por empresa. | `plpgsql_check` 0 errores (14 avisos); 9 huellas iguales entre base real y proyecto. |

## Ajustes hechos a mano en el panel de Supabase (no están en los SQL)
| Fecha | Ajuste | Estado comprobado |
|---|---|---|
| 26/11/2026 | Registro público de usuarios desactivado | Sí (`disable_signup: true`) |

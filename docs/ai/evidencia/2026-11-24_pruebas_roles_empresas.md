# Pruebas de aislamiento y roles — resultado (24/11/2026)

Script: `supabase/verificaciones/pruebas_roles_empresas.sql`, ejecutado por el propietario en el editor SQL (suplantación de usuarios con ROLLBACK; sin cambios). Entorno: proyecto `drcexqsewiwfhiowrgtv`, empresas A Dromux ERP, B Espacio Demo, C Metalurgica Cerquatti; usuarios admin A/C, vendedor A, admin B. Código vigente: `main` + 043 aplicada, 044 NO aplicada.

## Resultado: 178 casos → 168 PASA, 3 FALLA (falsos positivos, ver abajo), 7 INFO
- PASA verificado: controles positivos (6); lectura cruzada entre empresas en 24 tablas × 4 combinaciones + companies (todas con 0 filas o error); escrituras cruzadas y escrituras directas no permitidas (error de permiso o RLS); funciones cruzadas (dashboards, stock, miembros, estadística, costos, cambio de rol, crear rol, terminar orden de otra empresa → 42501); lectura directa de las 9 columnas de costo bloqueada incluso al admin (usa RPC); costos de fórmula, parámetros de margen, filas de lista y guardar precios bloqueados al vendedor; tablero operativo sin ganancia para el vendedor; roles y usuarios: vendedor sin permisos no puede nada, el rol admin está protegido, no se puede suspender la propia cuenta; validaciones de la estadística (rango, agrupación, zona horaria, paginación) y de `return_production_material`; anónimo sin acceso a nada.
- Limitación de lo verificado: la lectura cruzada con 0 filas es contundente solo donde la empresa A tiene datos (items 73, órdenes 5, depósitos 2); en tablas vacías el 0 es trivial. Los casos 157, 162 y 172 pasan de forma débil (no hay rol no-admin en B; C sin órdenes terminadas; orden inexistente).

## Los 3 FALLA eran falsos positivos del script
`list_production_runs/jobs/plans` devuelven las claves de costo con valor `null` para quien no es admin (`case when v_costs then … end`); la prueba buscaba la clave, no un valor. Verificado leyendo los cuerpos de las funciones. El script ya busca valores no nulos (`: [^n]`).

## INFO (decisiones y hallazgos)
- H-007 CONFIRMADO CON PRUEBA: con `users:update` + `roles:insert`, el vendedor se creó un rol con permisos y se lo asignó; con `roles:update` amplió su propio rol. Corrección: migración 044 (solo admin + historial).
- H-011 (nuevo, P2): el vendedor recibe el costo de referencia de los materiales (`list_production_items`, `reference_unit_cost`) porque su rol tiene `purchases` (`can_see_reference_cost` = admin o `purchases:read`). Es el diseño D-004, pero para un rol de ventas probablemente no es lo deseado. Decisión del propietario: quitar `purchases` al rol o crear el permiso explícito "ver costos" (Fase 4).
- El admin ve costos de corridas (esperado).

## Pendiente
- Aplicar 044 (revisión crítica en curso) y correr el grupo 9 del script.
- Pruebas de concurrencia (HI-001) y de PDF/exportaciones sin costos (C-013): no cubiertas.

## Segunda ronda — tras aplicar 044 (24/11/2026)
- 044 aplicada por el propietario. Verificado por catálogo (lectura propia): las 3 funciones de Ajustes y `access_audit_events_list` con SECURITY DEFINER, `search_path` vacío, anon sin acceso, `authenticated` con acceso solo a las públicas; las 3 de Ajustes exigen admin y auditan; `private.log_access_event` y `access_audit_immutable` sin acceso para la API. Comprobación de la tabla (pegada por el propietario): RLS activa, sin privilegios para `authenticated`/`anon`, 2 disparadores.
- Script (189 casos): todos los casos con veredicto PASAN salvo 2 defectos del propio script (no del sistema): los casos 179 y 185 fallaron con "unterminated dollar-quoted string" (al generar el grupo 9 un `$$` se redujo a `$`). Corregido en el archivo; hay que volver a correrlo para que esos dos casos pasen de verdad (179 = escalada H-007 de crearse un rol y asignárselo; 185 = crear un rol deja un evento en el historial).
- H-007 verificado tras 044: casos 159, 160, 180, 181, 152–154 devuelven 42501 "Solo el administrador…". Cerrado a nivel de funciones; falta confirmar 179 y 185 con el script corregido.
- Historial: "Admin A ve el historial" sin error (0 filas: aún no hay cambios reales); vendedor y admin de otra empresa reciben 42501; lectura directa de la tabla denegada. Códigos reservados `admin` y `support` rechazados.
- Sigue pendiente: concurrencia (HI-001), PDF/exportaciones sin costos (C-013), H-011 (decisión), H-012 (latente).

## Tercera ronda — tras 044 y 045 (24/11/2026)
- Script completo (204 casos): todos con veredicto PASAN; solo quedan INFO (149, 150, 159, 160). Los casos 179 y 185 (corregidos) pasan: la escalada H-007 da 42501 y crear un rol deja evento en el historial. H-007 cerrado.
- Grupo 10 (045): ver `2026-11-24_permisos_045_preparada.md`.

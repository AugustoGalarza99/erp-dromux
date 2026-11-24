# Avance de la hoja de ruta (HOJA_DE_RUTA_PRODUCCION.md)

Actualizar al cerrar cada sesión. Si es la primera lectura de la sesión: leer esto, luego `ESTADO.md`.

| Fase | Estado | Evidencia | Próxima tarea |
| --- | --- | --- | --- |
| 1. Recorrido completo (1 empresa) | EN CURSO — guía lista, falta que el propietario ejecute los 19 pasos | `FASE1_GUIA_RECORRIDO.md` | Propietario: preparar cuentas/roles de prueba y recorrer A–H; pasar resultados |
| 2a. Auditoría de base (solo lectura) | HECHA parcial 24/11 (RLS, grants, funciones, roles) | `AUDITORIA_FASE2_3_2026-11-24.md` | Falta leer a fondo `post_stock_operation`, funciones de dinero, PDF/exportaciones sin costos (C-013) |
| 2b/2c. Pruebas con 2 empresas y roles | HECHA 2 rondas (24/11): aislamiento entre empresas y costos OK, H-007 cerrado en funciones; faltan concurrencia, PDF/exportaciones sin costos | `evidencia/2026-11-24_pruebas_roles_empresas.md` | Re-correr script tras corregir 179/185; luego Fase 1 con usuarios reales |
| 3. Auditoría de Ajustes | HECHA parcial 24/11 (funciones de usuarios/roles, rutas) | idem | Probar en la app Usuarios/Roles con los usuarios de prueba; revisar pantalla Usuarios (alta) |
| 4a. Ajustes solo admin + historial (migración 044) | HECHA: aplicada, verificada y probada (casos 179 y 185 pasan; H-007 cerrado); frontend con puertas solo admin e historial | `evidencia/2026-11-24_pruebas_roles_empresas.md` | Publicar frontend y probar en la app un cambio de rol y su historial |
| 4b. Permisos finos por pantalla (045 base, 046 Compras, 047 Producción, 048 Stock/Ajustes) | 045 APLICADA y verificada (204 casos pasan); 046–048 PENDIENTES (el servidor aún exige el módulo completo; `costs_*` sin exigir) | `evidencia/2026-11-24_permisos_045_preparada.md`, `DISENO_045_PERMISOS_FINOS.md` | Preparar 046 Compras (+ `can_see_reference_cost` con `costs_materials`) con deshacer, verificaciones, revisión crítica y grupo 11 del script |
| 5. Vista "ver como rol" (solo interfaz) | PENDIENTE — alcance confirmado; usa `role_permissions` del rol elegido; incluye candados en Ctrl+K e Inicio | `DISENO_045_PERMISOS_FINOS.md` §2c | Implementar después de 046 (o en paralelo) |
| 6. Cierre | PENDIENTE | — | — |

## Usuarios y empresas de prueba (ids, sin contraseñas)
- Empresa A Dromux ERP `2f4264a3-96fc-4663-a965-480bae4f0a52`; B Espacio Demo `539c24c9-955e-4e86-ab1e-5b40672dc7d0`; C Metalurgica Cerquatti `f5d93ed5-6c1a-4895-b41a-021ad8e912ce`.
- Admin Augusto `3c69e2c8-…` (admin de A y C); Vendedor `f086a333-…` (solo A; rol vendedor con production:ir, purchases:imr, sales:imr, items/stock:imru; sin finanzas); Demo `23f10efa-…` (admin solo de B).

## Última actualización: cierre de sesión 24/11/2026 — migraciones 043, 044 y 045 aplicadas; commit lo hace el propietario; siguiente: `PROMPT_PROXIMA_SESION.md`

## Hallazgos abiertos de este tramo
H-007 (P1, escalada por delegación en roles/usuarios; confirmado con prueba, corrección en 044), H-011 (vendedor ve costo de referencia por tener `purchases`), H-008 (rutas sin puerta), H-009 (sin auditoría de cambios de permisos), H-010 (costos atados al código `admin`). Detalle en `AUDITORIA_FASE2_3_2026-11-24.md` y `HALLAZGOS.md`.

## Decisiones tomadas (24/11)
- Pruebas en este mismo proyecto de Supabase, con 2–3 empresas dentro (así funcionará en producción). Prohibido cargar datos reales de clientes mientras se prueba.
- "Ver como rol" = solo interfaz.

- Fase 4 / H-007: gestión de roles y usuarios SOLO para el rol admin (decidido 24/11).
- Pruebas: la UI la recorre el propietario; las pruebas entre empresas y roles se hacen con un script SQL que suplanta usuarios dentro de una transacción con ROLLBACK (lo prepara Claude; el propietario lo corre en el editor SQL y pega el resultado). Claude no recibe contraseñas ni inicia sesión como usuarios.

## Decisiones pendientes del propietario
- ¿Permiso explícito "ver costos" para roles no admin (H-010)?
- Cómo se da de alta un empleado (HI-003): invitación por email o alta manual.
- Si la estadística debe incluir órdenes archivadas (hoy sí).

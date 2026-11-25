# Avance de la hoja de ruta (HOJA_DE_RUTA_PRODUCCION.md)

Actualizar al cerrar cada sesión. Si es la primera lectura de la sesión: leer esto, luego `ESTADO.md`.

| Fase | Estado | Evidencia | Próxima tarea |
| --- | --- | --- | --- |
| 1. Recorrido completo (1 empresa) | EN CURSO: Claude recorrió pasos 1–12 y parte del 14 en Espacio Demo (ver evidencia/2026-11-24_flujo_completo_fase1.md): 1 defecto funcional (H-E1) y 11 de UX | `FASE1_GUIA_RECORRIDO.md` | Propietario: preparar cuentas/roles de prueba y recorrer A–H; pasar resultados |
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

## Sesión 24/11 (2): 046 Compras preparada + ver como rol
- 4b: 046 PREPARADA, revisada (P0 corregido; H-011 abierto en precios de proveedor), NO aplicada. Siguiente: propietario decide H-011, aplica 046, corre 046_comprobaciones y grupo 11.
- 5: "Ver como rol" implementado en interfaz (botón en Roles, barra fija inferior, candados en Ctrl+K e Inicio); build OK, sin prueba visual en arnés.
- Paso 0 (recorrido del propietario) no recibido en esta sesión. Paso 3 (047) no iniciado.

## Sesión 24/11 (3)
- 046 aplicada por el propietario (resultados de 046_comprobaciones y grupo 11: pendientes de pegar).
- Decisión: el precio de proveedor ES costo -> 046b PREPARADA (supabase/046b_precio_proveedor_es_costo.sql + reparacion/0_deshacer_046b.sql): 5 funciones y 2 políticas exigen además costs_materials. Sin revisión crítica ni aplicar. Abierto H-011b: purchase_order_lines/receipt_lines/purchase_receivable_lines.
- UX/UI de Ajustes: Roles (lista con búsqueda y personas por rol, plantillas, barra de guardado con cambios sin guardar, descartar) y Usuarios (búsqueda, filtros, mostrar más, confirmación al cambiar rol) rediseñados. Build OK; SIN prueba visual en navegador (pendiente 360/768/1024/1440).
- Pendiente UX: Unidades, Categorías, Depósitos, Archivados, Perfil, Documentos de producción, Historial de accesos.
- 24/11 (4): 046b aplicada. UX de Ajustes rediseñada y probada en arnés simulado (1440 y 360, sin desborde): Roles, Usuarios, Archivados, Documentos de producción (con vista previa). Unidades/Categorías/Depósitos ya eran correctas (CatalogPage). Arnés borrado.

## Sesión 24/11 (5): Fase 1 con Claude + correcciones
- 046/046b aplicadas; script de pruebas: 2 FALLA (ver evidencia), resto PASA; H-011 cerrado también en supplier_items (fila 270: 0 filas).
- Fase 1: recorrido de Claude en Espacio Demo: pasos 1–12, 13, 14–15, 18, 19 (cancelar, devolver, archivar y recuperar) y envasado OK; H-E1 cerrado. Pendiente: PDF, orden grande, reintento con corte de red, operario/vendedor.
- 046c (H-E1) preparada y revisada: veredicto "aplicar" (sin P0/P1). Cierre de la OF 1 y estadística OK en pantalla. Defectos de interfaz D1–D9 corregidos en código (build OK, sin verificar en pantalla).

## Sesión 24/11 (6): 047 Producción preparada
- 047 PREPARADA y revisada (aplicar tras las correcciones ya hechas; no aplicada): 36 funciones + 14 políticas + costs_production; deshacer, comprobaciones y grupo 12 (52 casos). Frontend por pantalla, build OK. Falta: que el propietario la aplique, corra 047_comprobaciones.sql y el script completo.
- Pendiente 048 Stock/Ajustes; lote de Ventas (precios/márgenes con costs_production); cleanup_target por pantalla.

## Cierre de sesión 24/11/2026 (final)
- 047 APLICADA por el propietario; comprobación 8 = 0 filas; consulta 9 muestra que solo los administradores ven costos de producción (Vendedor no). Pendiente de pegar: el resto de 047_comprobaciones.sql y el script completo con grupo 12.
- Fase 1: pasos 1–15, 18, 19 y envasado OK por pantalla; pendientes los que necesitan al propietario (PDF, operario/vendedor, red, stock insuficiente, 200 insumos).
- Siguiente: ver PROMPT_PROXIMA_SESION.md.

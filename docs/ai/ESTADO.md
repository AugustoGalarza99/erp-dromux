# Estado — cierre de sesión 24/11/2026: Producción lista para pruebas, Ajustes endurecidos, permisos por pantalla (base) aplicados

## Resumen en una frase
Foco vigente: dejar PRODUCCIÓN, costos, stock y Ajustes listos para el primer cliente (sin registrar ventas ni clientes). Migraciones 043 (cierre con ajustes + estadística + índices), 044 (usuarios y roles solo admin + historial de accesos) y 045 (catálogo de permisos por pantalla) APLICADAS por el propietario y verificadas por catálogo y por script. Falta: el recorrido real de 19 pasos, exigir los permisos por pantalla en el servidor (046 Compras, 047 Producción, 048 Stock/Ajustes) y la vista "ver como rol". Seguimiento por fases: `docs/ai/AVANCE_FASES.md` (leer primero). Ventas L5 quedó funcional (039–042) con pendientes en `VENTAS_PLAN.md`.

## Evidencia y entorno
- Repo `main`, HEAD de partida `61a364e`; trabajo de esta sesión SIN commit hasta que el propietario lo suba. Base: proyecto `drcexqsewiwfhiowrgtv` (conector de solo lectura). Migraciones aplicadas: 035–045. Locales: `018`–`045`.
- VERIFICADO: 043/044/045 por catálogo (funciones SECURITY DEFINER, `search_path` vacío, anon sin acceso, tablas con RLS sin privilegios para la API, 34 entradas en `permission_catalog`) y por `supabase/verificaciones/pruebas_roles_empresas.sql`: 204 casos, TODOS PASAN (aislamiento entre las empresas Dromux ERP, Espacio Demo y Metalurgica Cerquatti; costos; roles; producción; anónimo; grupos 9 y 10). Evidencia: `evidencia/2026-11-24_pruebas_roles_empresas.md`, `_produccion_cierre_043.md`, `_permisos_045_preparada.md`, `_menu_bloqueado.md`.
- VERIFICADO: `npm run build` OK; interfaz probada en arnés simulado (Estadística, cierre con 220 insumos, menú con candados, pantalla de roles por módulo). NO probado: contra la base real con datos, impresión de PDF, concurrencia (HI-001), exportaciones/PDF sin costos (C-013), `post_stock_operation` a fondo.
- Usuarios y empresas de prueba (ids, sin contraseñas): ver `AVANCE_FASES.md`.

## Hecho en esta línea (producción y permisos)
- 043: `finish_production_job_adjusted` (terminar con insumos usados de más/menos y recuento de envases, una transacción, idempotente), `production_output_summary` y `production_output_by_product` (producción por día/semana/mes y rango, paginada), 8 índices. UI: pestaña Estadística, diálogo de cierre en 2 pasos con alerta de stock, confirmaciones de entrega/devolución.
- 044: crear/editar roles y cambiar usuarios solo admin (H-007 cerrado), códigos `admin`/`support` reservados, `access_audit_events` inmutable + pantalla "Historial de accesos" en Roles y permisos; Usuarios y Roles solo admin en menú y rutas.
- 045: `permission_catalog` (módulos → pantallas, `costs_materials`, `costs_production`), reparto sin cambio de acceso real (único ensanchamiento aceptado: `purchases:update` → `purchase_requests:update`), `save_role_permissions`, `create_company` con catálogo, soporte sin costos, copia `private.role_permissions_pre045` para deshacer. UI: pantalla de roles "¿Puede entrar al módulo? → pantallas → acciones" con resumen Puede/No puede; menú con módulos y pantallas bloqueadas (gris, candado, "Acceso restringido").

## Incompleto o sin hacer
- Permisos por pantalla en el servidor: hasta 046–048 las funciones y políticas siguen mirando el módulo completo (un rol con acceso parcial a un módulo queda SIN esas pantallas; la grilla lo avisa en rojo). Los permisos `costs_*` aún no se exigen: H-011 (el vendedor ve el costo de referencia de materiales por tener `purchases:read`) sigue vigente hasta que `can_see_reference_cost` use `costs_materials`.
- H-008 (rutas sin puerta), H-010 (costos atados al código `admin`), H-012 (invitaciones, latente), HI-002 (`create_company` sin cuota), HI-003 (alta de empleados), HI-005 (esquema `private` en la API: confirmar en el panel), H-002 (esquema no reproducible), H-003 (índices medidos con datos).
- Fase 1: recorrido de 19 pasos con datos reales (`FASE1_GUIA_RECORRIDO.md`) y decisiones abiertas: si la estadística incluye órdenes archivadas (hoy sí), cuota de `create_company`, alta de empleados.
- Búsqueda Ctrl+K y tarjetas del Inicio no muestran lo bloqueado; vista "ver como rol" (solo interfaz) sin hacer.
- Ventas L5 (conversión presupuesto→venta, ofertas/kits, lista imprimible, etc.), Finanzas L6, Reportes L7: después de cerrar producción.

## Riesgos
- Sin recorrido real todavía: los cierres son de catálogo, script de suplantación e interfaz simulada.
- Ventas toca dinero: no tocar `post_sale` ni cobros sin revisión crítica y autorización. Toda migración que cree tablas revoca a `public,anon,authenticated`.
- Cierre de órdenes con muchos ajustes toma el bloqueo de reservas de la empresa (tope 300 ajustes): medir con volumen.

## Decisiones vigentes
- Costos: hoy referencia = admin o `purchases:read`; producción y márgenes = admin + `finance:read` (D-004). Decidido 24/11: pasan a permisos explícitos `costs_materials` y `costs_production`, que el administrador da rol por rol (Compras normalmente sí; Vendedor solo ve el precio de lista); alta/edición de listas sigue siendo del admin.
- Roles y usuarios solo del administrador; permisos por pantalla con flujo módulo → pantallas → acciones; módulos y pantallas sin permiso se ven bloqueados (candado, "Acceso restringido"); "ver como rol" = solo interfaz con botón para salir.
- Pruebas en el MISMO proyecto con 2–3 empresas de prueba, sin datos reales; la UI la recorre el propietario; las pruebas entre empresas/roles se corren con el script de suplantación (el propietario lo ejecuta y pega el resultado; Claude no recibe contraseñas).
- D-005 paleta por módulo, D-006 multirrubro, D-007 volumen. IVA: precios sin IVA, IVA informativo en la venta. No tocar base/permisos/RPC sin autorización.

## Próximo paso concreto (prompt listo en `docs/ai/PROMPT_PROXIMA_SESION.md`)
1. Propietario: commit de esta sesión; publicar el frontend (si no está publicado); recorrido de la Fase 1.
2. Claude: 046 Compras (funciones, políticas, rutas y menú por pantalla; `costs_materials`), con deshacer, verificaciones, revisión crítica y casos de prueba; luego "ver como rol"; luego 047 y 048.

## Datos de sesión
- Verificación habitual: `npm run build` + arnés local temporal (login y supabase simulados, alias de Vite a `mockSupabase.js`, siempre borrado) en 360/768/1024/1440 con 200+ filas.
- El conector de la base es de solo lectura (ni tablas temporales): los scripts con suplantación los corre el propietario en el editor SQL.
- En el shell, evitar heredocs largos con comillas: usar la herramienta de archivos. En `String.replace` de Node, `$$` se reduce a `$` (usar función de reemplazo).
- No hay Python: leer .xlsx con Node (`fflate` transitiva). Servidor de desarrollo del propietario en el puerto 5173; ante "Outdated Optimize Dep", reiniciar Vite.

## Regla de mantenimiento
Reemplazar este resumen al avanzar; máximo 100 líneas. Preservar decisiones vigentes y próximo paso. No marcar algo resuelto sin evidencia.

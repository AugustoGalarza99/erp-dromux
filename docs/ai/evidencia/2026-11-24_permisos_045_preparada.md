# Migración 045 — APLICADA y verificada (24/11/2026)
- Archivos: `supabase/045_permisos_por_pantalla_base.sql`, `reparacion/0_deshacer_045.sql`, `verificaciones/045_comprobaciones.sql`, grupo "10 Tras 045" en `verificaciones/pruebas_roles_empresas.sql`.
- Contenido: `public.permission_catalog` (34 entradas: 3 grupos, pantallas de Stock/Producción/Compras, Ventas/Finanzas/Reportes/Ajustes como hojas, `users`/`roles` solo admin, `costs_materials`/`costs_production`); reparto de permisos de módulo a pantallas (nadie gana ni pierde acceso real porque ninguna función exige aún los permisos nuevos); costos solo a administradores; `private.save_role_permissions` (valida contra catálogo, expande módulo completo, deriva el módulo solo si el rol tiene todas sus pantallas); `create_company_role`/`update_company_role`/`create_company` reemplazadas; `private.has_permission` solo cambia la rama de soporte (sin costos).
- Frontend (compila): `PermissionsGrid` por módulo → pantallas con "¿Puede entrar al módulo? Sí/No", acceso por pantalla, acciones y resumen "Puede / No puede"; datos sensibles aparte; sin catálogo usa la grilla anterior; `RolesPage` filtra los permisos de grupo; `core.js` soporte con catálogo.
- Probado en navegador con arnés simulado (borrado): rol Vendedor carga 5 de 5 pantallas de Compras; dejar solo Pedidos internos y dar Producción completa envía 40 permisos sin filas de grupo; 360 px sin desborde global. NO probado contra la base real.
- Aviso en pantalla: mientras 046–048 no estén aplicadas, el servidor aplica el permiso a todo el módulo (la pantalla lo dice).

## Revisión crítica (subagente, solo lectura) y ajustes aplicados a la 045 (aún sin aplicar)
- Ensanchamiento aceptado y documentado: `purchase_requests` pasa a ser hija de `purchases`; un rol con `purchases:update` recibe `purchase_requests:update` (cancelar sus pedidos propios pendientes). Único cambio de acceso al aplicar.
- Deshacer fiel: la 045 guarda `private.role_permissions_pre045` (sin acceso para la API) y el deshacer devuelve los roles existentes a su estado anterior.
- `private.save_role_permissions` sin SECURITY DEFINER, con verificación de que el rol pertenezca a la empresa, y chequeo de tipo antes de la longitud; el catálogo exige `cardinality(actions) > 0`.
- Riesgo de transición señalado y mostrado en pantalla: hasta 046–048 el servidor solo habilita un módulo si el rol tiene TODAS sus pantallas; un acceso parcial no abre esas pantallas. La grilla lo avisa en rojo.
- Editar un rol existente descarta `manage`, los grupos y `users`/`roles` (ya no delegables): consulta previa en `045_comprobaciones.sql` (punto 0).
- Pendiente de prueba: con sesión de soporte `costs_production:read` debe dar false y `production_orders:read` true; grupo 10 del script; consulta previa en la base real.

## Aplicación y resultado (24/11/2026)
- El propietario aplicó 045 y corrió las comprobaciones: funciones con SECURITY DEFINER y `search_path` vacío (`private.save_role_permissions` sin SECURITY DEFINER, sin acceso para la API), anon sin acceso.
- Script de pruebas (204 casos): TODOS PASAN, incluido el grupo 9 (044) y el grupo 10 (045): catálogo legible solo con sesión y no escribible (34 entradas), el vendedor recibió las 5 pantallas de Compras y NO recibió costos, el admin tiene costos y todas las pantallas, rol con solo Pedidos internos no abre el resto, módulo derivado solo con todas las pantallas, módulo completo de Producción expande a 9 pantallas, permisos desconocidos/repetidos/solo-admin/costos con acción distinta de ver rechazados, editar un rol quita pantallas y el módulo, el vendedor no crea roles.
- INFO vigente: el vendedor todavía recibe el costo de referencia de materiales (caso 149) porque `can_see_reference_cost` sigue usando `purchases:read`; se corrige en 046.
- Pendiente: sesión de soporte con costs_production:read = false (sin caso automático), concurrencia, recorrido real.

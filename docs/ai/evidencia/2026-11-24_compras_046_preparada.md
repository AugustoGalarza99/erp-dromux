# Evidencia — 046 Compras por pantalla (PREPARADA, NO APLICADA)

- Archivos: supabase/046_permisos_compras_por_pantalla.sql, reparacion/0_deshacer_046.sql, verificaciones/046_comprobaciones.sql, grupo 11 de pruebas_roles_empresas.sql.
- Relevamiento (solo lectura, 24/11): 39 funciones y 17 políticas mencionan purchases; 34 funciones + 17 políticas se re-apuntan; quedan sin tocar erp_replenishment_forecast (047), has_permission, create_company, cleanup_target, cancel_purchase_request.
- Decisiones del propietario: Gestionar = purchase_requests:manage (rechazar = manage+update; convertir = manage + órdenes:insert); tableros/reporte -> Resumen de compras; ficha del ítem -> costs_materials; tipos de cambio y ajustes -> Proveedores.
- Revisión crítica (erp-revisor-critico): veredicto inicial "no aplicar". P0 corregido (la política usaba private.support_session_active, no ejecutable por authenticated: rama eliminada). P1 gestionar/RolesPage corregido en frontend. P1 H-011 ABIERTO: precios de proveedor (supplier_items, líneas de orden, funciones de cotización) siguen visibles sin costs_materials; decide el propietario.
- P2 pendientes: comprobaciones 046 con like débil para 2 funciones; deshacer no verifica cambios posteriores.
- Frontend: npm run build OK. NO probado en arnés 360/768/1024/1440 ni con 200+ filas. Frontend compatible con el servidor actual (045) porque los roles ya tienen todas las pantallas.
- No corrido contra ninguna base: el grupo 11 lo ejecuta el propietario tras aplicar 046.

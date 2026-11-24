# Evidencia — L4b Compras: pedidos de compra internos, 23/11/2026

Método: arnés local temporal (ya eliminado) con autenticación y `supabase` simulados (rol operario con solo `purchase_requests`, rol administrador). `npm run build` OK. La migración 038 NO se aplicó: la interfaz se probó contra datos simulados.

## Migración 038 (preparada, no aplicada)
`supabase/038_pedidos_compra_internos.sql` + `reparacion/0_deshacer_038.sql` + `verificaciones/038_comprobaciones.sql`.
- Recurso de permisos nuevo `purchase_requests` (ver propios / crear / cancelar propios). Quien tiene `purchases:read` ve todos, `purchases:update` rechaza con motivo, `purchases:insert` convierte en orden (`convert_purchase_request`, una sola transacción).
- Parchea solo el literal de la lista blanca en `create_company_role`, `update_company_role` y `create_company` sobre la definición vigente (comprobado en solo lectura: 1 aparición en cada una) y da el recurso al rol `admin` de cada empresa.
- Tablas con RLS y sin escritura directa; contador propio; idempotencia con bloqueo y tabla de solicitudes; líneas inmutables; `purchase_request_item_options` no devuelve costos.
- Revisión crítica (subagente de solo lectura): sin P0. Corregido: conversión atómica (antes eran dos llamadas), cancelación solo propia con permiso previo al bloqueo, clave foránea compuesta a la orden, rango de fecha, nombre visible sin dominio de correo. Queda como hipótesis: la baja de empresa fallaría por los disparadores de inmutabilidad si existiera un proceso de borrado (no se encontró uno).
- Pendiente antes de aplicar: autorización del entorno, respaldo y pruebas de comportamiento con dos empresas y tres roles (lista en `038_comprobaciones.sql`, sección 6).

## Interfaz (verificada con datos simulados)
- Operario: ve solo la pestaña y el menú "Pedidos internos"; "Mis pedidos de compra" con sus pedidos y estados (pendiente, ordenado, rechazado con motivo, cancelado); "Nuevo pedido" con prioridad, fecha, nota, búsqueda en el catálogo o "No lo encuentro: escribirlo" (texto libre y unidad), tabla paginada, resumen "¿Enviar el pedido a Compras?" y cancelación con confirmación. Sin desborde a 360 px.
- Compras/administración: bandeja de todos los pedidos (pendientes por defecto), búsqueda, urgentes y fecha vencida resaltados, líneas escritas a mano marcadas, "Crear orden de compra" (abre el armado con las líneas del catálogo; avisa cuáles escritas a mano no se incluyeron), "Rechazar" con motivo; el Resumen suma indicador y decisión de pedidos pendientes (se omite sin error si la base aún no tiene 038).
- Navegación y permisos: pantallas con varios recursos (`any`), `PermissionGate anyOf`, recurso en la grilla de roles.
- PDF de orden de compra con 200 líneas generado en Node: 13 páginas (verificado).

No verificado: nada contra la base real; creación/conversión/rechazo/cancelación reales; permisos por rol reales; lista de roles con el recurso nuevo guardada en el servidor; PDF de remitos y de orden de fabricación con muchas líneas; catálogo y comparación de precios de Proveedores (sin rediseño interno).

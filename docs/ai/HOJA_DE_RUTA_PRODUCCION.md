# Hoja de ruta — salir a producción con el primer cliente (parte de producción)

Creada 24/11/2026. Alcance: producción, costos, márgenes, precios y listas, stock, fórmulas, Ajustes (usuarios/roles/permisos). Fuera de alcance por ahora: registrar ventas y clientes (Ventas L5 pendiente en `VENTAS_PLAN.md`).
Reglas: una fase por lote (máx. 3 problemas relacionados), evidencia en `docs/ai/evidencia/`, nada de tocar la base remota sin autorización (migraciones se preparan con deshacer y las aplica el propietario), costos solo `admin` + `finance:read`.
Estados: verificado / hipótesis / pendiente. Hoy: 043 aplicada y verificada por catálogo; UI probada solo en arnés simulado.

## Situación de partida (verificada 24/11)
- Permisos: tabla `role_permissions` con 16 recursos × 5 acciones (`read, insert, update, delete, manage`): categories, dashboard, finance, inventory, items, production, purchase_requests, purchases, reports, roles, sales, settings, stock, units, users, warehouses. 5 roles en la base de hoy.
- Granularidad actual = un recurso por módulo (ej. `purchases` abre Resumen, Órdenes, Proveedores, Cuentas). Excepción que sirve de modelo: `purchase_requests` ya es un recurso aparte (pedido interno).
- Ajustes: Usuarios, Roles y permisos, Unidades, Categorías, Depósitos, Archivados, Documentos de producción (`src/modules/settings/*`, rutas `/settings/*`).
- Hallazgos abiertos relevantes: H-002 (esquema no reproducible), H-004 (higiene de grants), HI-001 (concurrencia sin probar), HI-002 (`create_company` sin cuota), HI-003 (invitaciones), HI-004 (quien tiene `roles:insert` puede armar un rol casi total), HI-005 (esquema `private` expuesto en la API: se confirma en el panel).

## Fase 1 — Recorrido completo de una empresa (prueba funcional con datos reales)
Objetivo: un solo hilo de punta a punta, con capturas y números, sin ventas/clientes.
Pasos a recorrer y registrar (cada uno con "esperado / obtenido / error"):
1. Alta de unidades, depósitos, categorías; alta de materia prima (con costo, con y sin lote); alta de envase; alta de producto terminado.
2. Ingreso de stock (compra recibida y lote inicial) y verificación del saldo y del movimiento.
3. Fórmula (versión, rendimiento) y costo de la fórmula; listado de "¿alcanza el stock?".
4. Precio de venta y lista de precios: costo → margen → precio; lista derivada; cambio masivo con vista previa; verificar que quien no es admin no ve costos ni márgenes.
5. Orden de fabricación: crear, iniciar, PDF de la orden de trabajo (sin costos para el operario; probar con 5 y con 200 insumos).
6. Entrega de insumos por remito y "insumo sin remito": stock baja una sola vez; confirmaciones.
7. Devolución de sobrante; cierre con diferencias (usó de más / de menos), envases y resto sin envasar; ingreso del producto terminado con lote.
8. Reintentos: doble clic y reenvío del mismo cierre no duplican movimientos.
9. Estadística de producción: la orden cerrada aparece en mes, semana y rango personalizado.
10. Cancelación de orden con insumos entregados; archivado y trazabilidad.
Entregable: `evidencia/…_flujo_completo.md` + lista de defectos corregidos. Criterio de cierre: el recorrido se repite sin errores y los saldos de stock coinciden con lo calculado a mano.

## Fase 2 — Auditoría de seguridad de la base (solo lectura, luego base de pruebas)
Lote 2a (solo lectura, ya posible): leer cuerpo completo de las funciones de dinero/stock/producción (`post_stock_operation`, `finish_production_job`, `issue/return_production_material`, `cleanup_record`, `create_company`, `update_company_role`); revisar políticas RLS por tabla; grants por columna; que ninguna RPC devuelva costos a roles sin permiso; H-004 (revocar EXECUTE de funciones de disparador a `anon`/`public`).
Lote 2b (requiere decisión): base de pruebas con la línea base (`supabase/linea_base`) para cerrar H-002 y poder probar con 2 empresas × 3 roles + concurrencia (HI-001). Cuesta un proyecto adicional de Supabase: pedir autorización.
Lote 2c: pruebas negativas: usuario de la empresa B no lee ni escribe en A; rol sin `finance:read` recibe error/vacío en cada RPC de costos; operario sin costos en PDF/exportaciones (C-013); anon sin acceso.
Entregable: actualizar `COBERTURA.md` (C-006, C-012, C-013) y `HALLAZGOS.md`.

## Fase 3 — Auditoría de Ajustes: usuarios, roles, permisos y rutas
1. Mapa ruta → permiso exigido en frontend (`PermissionGate`) → permiso exigido en backend (RPC/RLS). Cualquier ruta cuyo permiso solo exista en el frontend es hallazgo.
2. Revisar Usuarios (alta, baja, cambio de rol, suspensión, último admin no puede quitarse el acceso), Roles (crear/editar/borrar, rol con usuarios asignados, HI-004), Unidades/Categorías/Depósitos/Archivados.
3. Auditoría legible: quién cambió qué permiso y cuándo (hoy faltante en `PLAN.md` L8).
4. Decidir HI-002 (cuota en `create_company`) y HI-003 (invitaciones).
Entregable: tabla de rutas y hallazgos; correcciones pequeñas en frontend; migración solo si hace falta.

## Fase 4 — Permisos finos por pantalla (migración 044, requiere autorización)
Problema: hoy `purchases` da todo Compras. Meta: que un empleado vea solo "Pedido de compra interno".
Diseño propuesto (a confirmar):
- Catálogo de permisos con clave por pantalla, agrupado por módulo, p. ej. `purchases.overview`, `purchases.orders`, `purchases.suppliers`, `purchases.accounts`, `purchases.requests`; Producción: `production.overview/orders/formulas/planning/availability/replenishment/packaging/stats`; Stock: ítems, saldos, movimientos, remitos, importación; Ventas: listas de precios, presupuestos, clientes, registrar venta; Ajustes: usuarios, roles, unidades, categorías, depósitos, documentos; Finanzas y Reportes por pestaña. Acciones por pantalla: ver, crear, editar, eliminar/anular, más acciones sensibles explícitas (ver costos, aprobar, exportar).
- Compatibilidad: los roles actuales conservan acceso (cada permiso de módulo se expande a sus pantallas); no se quita nada sin que el administrador lo decida. Esquema aditivo + migración de datos reversible.
- Aplicación en el servidor: cada RPC y política RLS pasa a exigir el permiso fino (no solo ocultar menú). Revisión crítica obligatoria (`erp-revisor-critico`) y pruebas negativas de la Fase 2c.
- UI: cuadrícula de Roles y permisos agrupada por módulo y pantalla, con resumen en lenguaje claro ("este rol puede…"), plantillas de rol (operario, compras, supervisor) y confirmación al guardar. Sin cambios en ningún permiso hasta que el administrador guarde.
Decisión abierta: ¿permisos finos en todos los módulos a la vez o empezar por Compras y Producción (primer cliente) y extender? Recomendado: Compras + Producción + Stock + Ajustes primero.

## Fase 5 — Vista "ver como rol" (simulación para el administrador)
- Qué es: el administrador elige un rol (o usuario) y la app muestra menú, pestañas, botones y pantallas como los vería ese rol, con una barra fija "Estás viendo como: <rol> · Salir de esta vista".
- Cómo: sustituye solo la función `can()` y la lista de permisos del frontend por los del rol elegido; se pierde al recargar y al cerrar sesión; no cambia la sesión ni escribe nada; solo roles de la misma empresa y solo para `admin`. Queda registrado en auditoría que se usó la vista.
- Límite honesto, visible en la propia barra: es una vista de la interfaz. El servidor sigue respondiendo con los permisos reales del administrador. Para probar el servidor hay que entrar con un usuario real de ese rol (la Fase 2c lo cubre). Alternativa más fuerte, opcional: RPC de lectura que evalúe permisos de otro rol en servidor (migración).
- Debe depender del catálogo de la Fase 4 (si no, simula solo los 16 recursos actuales). Se puede hacer una primera versión con los 16 recursos y ampliarla.

## Fase 6 — Cierre de producción
Revisión de paginación y volumen (200+ filas) en todas las listas del alcance, índices con `EXPLAIN` en la base de pruebas, textos multirrubro (D-006), ayuda por pantalla, guía de uso para el cliente, lista de verificación de lanzamiento (`erp-validar`), plan de respaldo/restauración y de soporte autorizado. Actualizar `ESTADO.md`, `PLAN.md` y `COBERTURA.md`.

## Orden recomendado
1. Fase 1 (con tu app y datos reales: yo preparo la lista de pasos y corrijo lo que aparezca) en paralelo con Fase 2a y Fase 3.1–3.2 (solo lectura).
2. Fase 4 (diseño → migración 044 preparada y revisada) → tú la aplicás.
3. Fase 5 sobre el catálogo de la 4.
4. Fase 2b/2c con la base de pruebas, ya con permisos finos.
5. Fase 6.

## Decisiones que necesito de vos
- Fase 4: ¿empezamos por Compras + Producción + Stock + Ajustes, o todos los módulos juntos?
- Fase 2b: ¿autorizás crear un proyecto de Supabase de pruebas (costo posible)? Sin él, las pruebas con 2 empresas × 3 roles no son reales.
- Fase 5: ¿alcanza con la vista de interfaz, o querés además la verificación en servidor?

# Hallazgos y evidencia

Base observada: proyecto `drcexqsewiwfhiowrgtv`, conexión de solo lectura, 20/11/2026. Repo: rama `main`, HEAD `74786d5` (mensaje "DromuxERP 1.0.4"), con cambios sin confirmar ajenos a este lote. Solo metadatos; no se leyeron datos de clientes ni se ejecutaron funciones de negocio. Nada de lo de abajo está probado con ataques o pruebas negativas.

## Confirmados (por catálogo o por código)

### H-001 — P1 — cerrado a nivel de esquema (23/11/2026); pruebas con roles reales pendientes — Costos legibles por API con permisos no financieros
- Cierre (23/11/2026): el propietario aplicó 035 y 036 en Supabase y reportó comprobaciones OK (declaración del propietario). Verificado además por catálogo en solo lectura el mismo día: `has_column_privilege('authenticated', …, 'SELECT')` = false en las 9 columnas de costo (`items.reference_unit_cost/reference_cost_usd`, `production_job_events.unit_cost`, `production_jobs.formula_snapshot`, `production_plans.component_snapshot/estimated_cost`, `production_run_lines.unit_cost`, `production_runs.estimated_cost`, `sale_lines.estimated_unit_cost`); 5 RPC nuevas con SECURITY DEFINER, EXECUTE solo `authenticated` (anon=false); núcleos `private.save_item_with_cost`/`private.import_items` sin EXECUTE para `authenticated`/`anon`; envoltorios públicos y `production_formula_cost` con EXECUTE para `authenticated`.
- Alcance NO probado: comportamiento con usuarios reales (admin, compras, operario) ni con dos empresas; creación de ítem sin costo por rol sin compras; filtros/límites de `list_production_*` frente al frontend anterior; no se confirmó que el frontend nuevo esté publicado ni que se haya respetado el orden 035 → frontend → 036 (si no, pestañas/ficha de ítem fallan con "permission denied" hasta publicar y recargar). Se mantiene como seguimiento de validación, no como riesgo de exposición.
- Estado de la corrección (20/11/2026): `supabase/035_costos_funciones.sql` (aditiva, 5 RPC + 3 helpers privados), cambios de frontend en `services/production.js`, `services/items.js`, `FormulasPage.jsx` e `ItemEditor.jsx` (`npm run build` pasa), y `supabase/036_costos_revocar.sql` (revoca SELECT por columna; aplicar solo con el frontend publicado). Comprobaciones de solo lectura en `supabase/verificaciones/035_036_comprobaciones.sql`. Orden: 035 → publicar frontend → 036. Falta: prueba en base de pruebas con roles admin, compras y operario, y revisión crítica.
- Revisión crítica (subagente `erp-revisor-critico`, solo lectura; sus afirmaciones se verificaron contra el código y la base antes de actuar):
  - Confirmado y corregido en 035: `save_item_with_cost` e `import_items` solo pedían `items:insert/update` y el cliente decidía `p_preserve_cost`; un rol sin costos podía cambiar el costo que alimenta las fotos de costo de producción. Ahora hay envoltorios que exigen admin o `purchases:read` para definir costos; el resto conserva el costo vigente.
  - Confirmado y corregido en 035: `production_formula_cost` solo pedía `production:read` y devolvía el costo de fabricación; ahora exige admin + `finance:read` (la pantalla ya lo exigía).
  - Confirmado, aceptado y documentado: sin acceso a costos no se pueden crear materias primas (el servidor exige costo); la ficha lo explica.
  - Ajustado: las RPC de listados devuelven lista vacía sin permiso, igual que antes bajo RLS (el subagente advirtió que ahora darían error 42501).
  - No era hallazgo: `erp_sales_profit_summary` no tiene EXECUTE para `authenticated`; `erp_operational_dashboard` solo calcula ganancia para admin; `reference_cost_usd` y su tipo de dólar no tienen permiso de escritura directa hoy.
  - Hipótesis por probar en base de pruebas: que un rol no privilegiado pueda crear un ítem sin costo (los envoltorios revisan claves de costo en la fila preparada); que `list_production_*` conserven filtros y límites del frontend anterior.
- Otro hecho verificado: `protect_preferred_material_cost` (invoker) solo usa NEW/OLD, así que la revocación por columna no lo rompe; ninguna política RLS referencia columnas de costo.
- Evidencia: `has_column_privilege('authenticated', …, 'SELECT')` es verdadero para `items.reference_unit_cost`, `items.reference_cost_usd`, `production_runs.estimated_cost`, `production_run_lines.unit_cost`, `production_job_events.unit_cost`, `production_plans.estimated_cost` y `sale_lines.estimated_unit_cost`. Las políticas de lectura de esas tablas piden solo `items:read`, `production:read` o `sales:read`, no `finance`.
- Actor y condiciones: cualquier usuario activo de la empresa con esos permisos de lectura (por ejemplo un rol de operario con `production:read`) puede pedir esas columnas directamente a la API REST, aunque la pantalla las oculte.
- Impacto: contradice la invariante "costos solo para roles autorizados, incluidas respuestas API". Exposición de costos y márgenes a roles operativos.
- Clasificación: confirmado en el esquema; no probado con un usuario real ni se leyeron los permisos de roles concretos.
- Mapa de lecturas en el frontend (verificado con `rg`, 20/11/2026, commit `74786d5`; los selects piden la columna a todos y la pantalla solo oculta el valor):
  | Columna | Lectura (archivo:línea) | Quién la pide | Gating de pantalla |
  | --- | --- | --- | --- |
  | `items.reference_unit_cost` | `services/production.js:12` (`listProductionItems`) | cualquiera con `production:read` | La pantalla de fórmulas (`FormulasPage.jsx:90,139,335`) pide `admin` + `finance:read`; la consulta no |
  | `items.reference_unit_cost`, `reference_cost_usd` | `services/items.js:10` (`detailColumns`, editor de ítem) | cualquiera con `items:read` | Sin gating de rol: `ItemEditor`/`ItemCostFields` muestran y editan el costo; falta decidir si es deseado |
  | `production_runs.estimated_cost`, `production_run_lines.unit_cost` | `services/production.js:103` | `production:read` | `ProductionOrdersPage.jsx:942` oculta con `admin` + `finance:read` |
  | `production_plans.estimated_cost` | `services/production.js:137` | `production:read` | `ProductionPlanningPage.jsx:355` oculta |
  | `production_job_events.unit_cost` | `services/production.js:203` | `production:read` | `ProductionJobCard.jsx:99-106` calcula el costo real con `unit_cost` para todos; solo el render va tras `admin` + `finance:read` (`:405`) |
  | `sale_lines.estimated_unit_cost` | ninguna | nadie | Sin lectura en el frontend; accesible solo por API directa con `sales:read` |
  | `supplier_items.unit_price`, `purchase_*_lines.unit_price` | compras | `purchases:read` | Esperado (precio de compra del rol de compras) |
  | `items.sale_unit_price` | `services/sales.js:42` | `items:read` | Esperado (precio de venta); `PricesPage.jsx:40` tiene un aviso de costo que nunca se muestra porque esa consulta no trae `reference_unit_cost` |
- Ampliación (confirmada en la base, 20/11/2026): `create_production_job` y `create_production_plan` guardan `unit_cost` por componente dentro de los JSON `production_jobs.formula_snapshot` y `production_plans.component_snapshot`, y `listProductionJobs`/`listProductionPlans` los traen completos. Revocar solo `estimated_cost` y `unit_cost` NO cierra la fuga: los costos siguen en esos JSON, que `production:read` puede leer. Origen: `supabase/020_production_jobs.sql:131`.
- Decisión del propietario (20/11/2026): el costo de referencia del ítem lo ven admin y compras, o sea `purchases:read`, que es el criterio que ya usan `purchase_supplier_quotes`, `purchase_material_options` e `item_cost_context`. Costos de producción (corridas, planes, eventos, costo real): solo `admin` + `finance:read`, como hoy en las pantallas.
- Conclusión: el ocultamiento depende solo de la interfaz en las 4 lecturas de producción e ítems. Un operario con `production:read` recibe costos en la respuesta de red aunque no los vea.
- Otro detalle: `items.reference_unit_cost` también se puede insertar o modificar directo por API (permiso por columna, con `items:insert/update`), sin pasar por `save_item_with_cost`.
- Corrección mínima: revocar SELECT de esas columnas a `authenticated` y servir costos por funciones que exijan rol admin (como `erp_admin_product_costs`). Antes hay que mapear qué pantallas leen esas columnas en `src/services`. Compatibilidad: puede romper pantallas que hoy seleccionan `*`.
- Prueba de regresión: con un usuario de prueba sin permisos financieros, `select` de esas columnas debe fallar; la pantalla de producción debe seguir funcionando.

### H-002 — P1 — abierto — Esquema no reproducible desde el repositorio
- Evidencia: `list_migrations` devuelve vacío. El repo tiene solo `supabase/018`–`034`, sin 001–017. 53 funciones de la base no tienen fuente local por nombre, entre ellas `post_sale`, `post_sale_payment`, `receive_purchase_order`, `stock_summary`, `create_company`, `update_company_role`, `private.post_stock_operation` y `private.issue_production_material`. Todos los objetos definidos en los archivos locales sí existen en la base.
- Impacto: no se puede crear una base de pruebas ni restaurar solo con el repo; bloquea las pruebas de concurrencia y el ensayo de despliegue del piloto.
- Clasificación: confirmado por nombres. No se compararon los cuerpos: que un archivo coincida por nombre no prueba que esté aplicado igual.
- Avance (20/11/2026): con autorización del propietario se generó `supabase/linea_base/001_esquema_observado_2026-11-20.sql` desde catálogos en solo lectura (67 tablas, 144 funciones, restricciones, índices, RLS, 74 políticas, 51 triggers, permisos de `anon`/`authenticated`; sin datos). No se pudo usar `supabase db dump` (requiere Docker, ausente). El archivo NO se validó: no se cargó en ninguna base. H-002 sigue abierto hasta cargarlo en un entorno de pruebas y comparar el esquema resultante con el observado.
- Próximo paso: cargar la línea base en Supabase local o en un proyecto de pruebas (ver `supabase/linea_base/LEEME.md`).

### H-003 — P2 — abierto — Claves foráneas sin índice de cobertura
- Evidencia: unas 100 claves foráneas sin índice que empiece por sus columnas (claves compuestas `(company_id, x_id)` hacia `items`, `warehouses`, `stock_operations`, `sale_lines`, etc., y los `actor_id` hacia `auth.users`).
- Impacto: posible lentitud en joins y borrados al crecer los datos. No medido.
- Corrección: medir con `EXPLAIN` en una base de pruebas antes de agregar índices; priorizar los que usan las pantallas con listados.

### H-004 — P2 — abierto — Higiene de permisos
- Evidencia: `rls_auto_enable` y los disparadores `rebalance_production_on_event`, `release_closed_production_job` y `reserve_new_production_job` tienen EXECUTE para `anon`/`public`. Las 7 tablas de `private` no tienen RLS (sin privilegios para `anon`/`authenticated`).
- Además: los privilegios por defecto del esquema `public` otorgan todos los permisos sobre tablas nuevas a `anon` y `authenticated` (valores por defecto de Supabase). Hoy lo contiene RLS (activada por `rls_auto_enable`), pero toda migración que cree una tabla debe terminar con `revoke all … from public,anon,authenticated` y los grants mínimos.
- Impacto: ninguno observado; `anon` no tiene USAGE sobre `private` y son disparadores. Es defensa en profundidad.
- Corrección: revocar EXECUTE a `public`/`anon` y activar RLS sin políticas en `private`, en una migración nueva.

### H-005 — P2 — abierto — Código muerto
- `completeProductionPlan` en `src/services/production.js:169` llama a `complete_production_plan`, que la migración 020 revoca. No se usa en ninguna pantalla. Borrarlo o dejar un comentario.

### H-006 — P1 — abierto (23/11/2026) — Tope de 40 líneas incompatible con fábricas grandes (D-007)
- Evidencia (fuente local, no se comparó el cuerpo remoto): `save_production_formula` exige `jsonb_array_length(p_lines) not between 1 and 40` (`supabase/033_documentos_produccion.sql:377`); `issue_delivery_note` y el remito de venta, igual (`022_remitos_produccion.sql:155,352`); venta (`019:142`) y orden de pago (`032:65`) también. La UI de fórmulas copia el tope en `FORMULA_LINE_LIMIT` (`services/production.js`).
- Impacto: una fórmula de 200 componentes no se puede guardar, y un remito de entrega para una orden de 200 insumos exige varios remitos de 40 líneas. Bloquea el caso de fábrica grande.
- Corrección propuesta (NO aplicada, requiere migración y autorización): subir el tope a un valor acordado (por ejemplo 500 en fórmulas y 200 en remitos) en las funciones afectadas con `create or replace`, probar rendimiento y concurrencia en base de pruebas, y luego subir `FORMULA_LINE_LIMIT`. Interfaz ya preparada (tabla paginada, buscador, cambios resaltados).
- Clasificación: confirmado en archivos locales y en la base (catálogo, solo lectura, 23/11/2026: 6 funciones relevantes con exactamente una aparición del literal).
- Avance (23/11/2026): preparada `supabase/037_limites_lineas_volumen.sql` (NO aplicada), con `reparacion/0_deshacer_037.sql` y `verificaciones/037_comprobaciones.sql`. Sube a 500 `save_production_formula`, `complete_production_now` e `issue_delivery_note`, y a 200 `issue_sale_delivery_note`, `create_purchase_order` y `receive_purchase_order`. Lee la definición vigente de cada función y cambia solo el literal (conserva cuerpo, SECURITY DEFINER, search_path y permisos); aborta sin cambios si una función no tiene exactamente una aparición. No toca `post_sale`, `adjust_sale` ni `create_supplier_payment_order` (dinero). Comprobado en solo lectura que las 6 firmas resuelven y empiezan con CREATE OR REPLACE FUNCTION; la migración en sí no se ejecutó. Frontend: topes centralizados en `src/lib/limits.js` (hoy 40; subir tras aplicar y comprobar).
- Pendiente para cerrar: autorización del entorno, respaldo, aplicar, correr comprobaciones, subir `LINE_LIMITS`, publicar frontend, probar guardar una fórmula de 200 componentes y emitir un remito de 200 líneas (rendimiento y PDF).

### H-007 a H-010 — 24/11/2026 — auditoría de Ajustes (detalle en `AUDITORIA_FASE2_3_2026-11-24.md`)
- H-007 (P1, CERRADO el 24/11: 044 aplicada y probada con el script, 204 casos; falta publicar el frontend; antes: CONFIRMADO CON PRUEBA 24/11, ver `evidencia/2026-11-24_pruebas_roles_empresas.md`; corrección preparada en 044, no aplicada): escalada por delegación: `roles:insert/update` y `users:update` permiten darse a uno mismo cualquier rol/permisos no admin. Confirmado por código; sin probar. Corrección en migración 044.
- H-008 (P2): rutas sin puerta de permiso en el frontend (`/inventory`, `/archivados`, y las libres `/ayuda`, `/mi-perfil`, `/actualizaciones`); datos protegidos en servidor.
- H-009 (P2): no hay auditoría de cambios de roles, permisos y miembros.
- H-011 (P2, ABIERTO hasta 046; el vendedor ya NO tiene filas `costs_*` desde 045 pero `can_see_reference_cost` sigue mirando `purchases:read`):  un rol con `purchases:read` (p. ej. vendedor) recibe el costo de referencia de los materiales; es el diseño D-004 pero probablemente no deseado para ventas. Quitar `purchases` al rol o permiso explícito "ver costos".
- H-012 (P2, latente, revisión crítica de 044): `create_company_invitation`/`revoke_company_invitation` siguen exigiendo solo `users:insert`/`users:delete` y `accept_company_invitation` no deja historial. Hoy NO son ejecutables por `authenticated`; antes de habilitar invitaciones (HI-003) hay que exigir administrador y auditar el alta. El historial de 044 cubre solo la interfaz (3 funciones): `create_company`, el script de operador `operaciones/asignar_usuario_empresa.sql` y el SQL directo no se registran. La FK del historial a companies es NO ACTION: borrar una empresa con eventos se rechaza (decisión de trazabilidad).
- H-010 (P2, decisión): costos y márgenes atados al código de rol `admin`; un rol personalizado con `finance:read` no los ve.

## Hipótesis o falta de evidencia

- HI-001 (P1): concurrencia e idempotencia. Las funciones usan `request_id`, bloqueos asesores y `for update`, pero no se probaron con llamadas simultáneas ni reintentos. Requiere base de pruebas.
- HI-002 (P2): `create_company` lo ejecuta cualquier usuario autenticado sin cuota; `profiles.name` se llena con el UUID.
- HI-003 (P2): `accept_company_invitation`, `create_company_invitation` y `revoke_company_invitation` no son ejecutables por `authenticated` ni se usan en `src/`. Decidir si las invitaciones forman parte del piloto.
- HI-004 (P2): quien tiene `roles:insert` puede crear un rol con casi todos los permisos (no con el código `admin`, que es único por empresa).
- HI-005 (P1, no verificable): que la API no exponga el esquema `private`. Se confirma en el panel de Supabase.
- HI-006 (P2): las lecturas del frontend se contaron con una búsqueda por texto de `rpc(...)` en una línea; las llamadas partidas en varias líneas pueden faltar.

## Verificado sin problema (no son hallazgos)

- 61 tablas con RLS; todas tienen `company_id` salvo `companies` y `profiles`; sin vistas ni sobrecargas de funciones en `public`/`private`.
- Escrituras directas desde el cliente solo en 10 tablas de catálogo, con permisos por columna y política por permiso; no pueden tocar `company_id` en UPDATE ni `active` de empresas.
- Triggers de inmutabilidad en tablas de historial (stock, ventas, pagos, remitos, recepciones, tesorería, producción).
- `src/` no usa `service_role`, ni Realtime ni Storage; las únicas variables VITE son la URL y la clave publicable.

## Plantilla
- ID / severidad (P0/P1/P2) / estado:
- Evidencia (ruta y líneas u objeto SQL/firma, entorno y commit):
- Actor y condiciones de explotación/error:
- Impacto y reproducción mínima sanitizada:
- Clasificación: confirmado / hipótesis / falta de evidencia:
- Corrección mínima y compatibilidad:
- Prueba de regresión y resultado:
- Riesgo residual / reversión / próximo paso:

P0: fuga entre empresas, escalada de privilegios, corrupción monetaria/stock o pérdida de datos. P1: confiabilidad, rendimiento o usabilidad que impide un flujo. P2: mejora no bloqueante. No inventar vulnerabilidades para completar una cuota; no cerrar por cambio de código sin verificar el comportamiento.
- H-011 (24/11, 046 preparada): can_see_reference_cost/item_cost_context pasan a costs_materials, pero supplier_items y precios de líneas de orden siguen visibles con acceso a las pantallas de Compras. ABIERTO hasta decidir si el precio de proveedor es costo.
- H-E1 (24/11, Fase 1): entrega de insumo reservado por la propia orden en un lote 100% reservado falla con 'Stock libre insuficiente' aunque la pantalla muestra disponibles. Pendiente revisar issue_delivery_note.
- H-E1 (24/11) CERRADO: 046c aplicada y verificada en pantalla (entrega del lote 100% reservado por la propia orden y sin duplicar).
- H-011 y H-011b (24/11): precio de proveedor cerrado por tabla y funciones (046b); queda abierto el precio dentro de purchase_order_lines/receipt_lines (se ven con acceso a Órdenes).

- H-047b (25/11, P1, CERRADO): can_see_production_costs y can_see_reference_cost devolvían NULL a no miembros de la empresa; production_formula_cost no rechazaba. Corregido con 047b (coalesce) y verificado en catálogo. Caso 336 del script lo detectó.
- H-O1 (25/11, P1, CERRADO por 048 salvo reprueba con el operario): Stock parcial dejaba existencias y reservas en blanco/falsas.
- H-048a (P2, abierto): escrituras de stock solo por módulo completo (048b).
- H-048b (P2, abierto): guardia general de funciones sin chequeo visible lista funciones de precios/importación/soporte que delegan a helpers; revisar en el lote de Ventas.
- H-UX1 a H-UX4 (P2/P3, abiertos): error de stock insuficiente detrás del diálogo; mensaje de pérdida de conexión engañoso; window.confirm en cambio de rol; ayuda inicial ocupa la pantalla a 360 px; PDF imprime "Deposito | Deposito".
- 25/11 (cierre): H-048a cerrado por decisión (escrituras de Stock = módulo completo; sin 048b). H-UX1, H-UX2 y H-UX3 corregidos (error dentro del diálogo, mensaje de conexión, diálogo de cambio de rol); H-UX4 (ayuda inicial a 360 px) abierto; "Deposito | Deposito" explicado (sin permiso de Depósitos). H-011b sigue abierto: orderPdf imprime precios de proveedor.

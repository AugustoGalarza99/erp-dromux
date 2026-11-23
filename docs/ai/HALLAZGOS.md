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

# Cobertura de auditoría

Entorno observado: base `drcexqsewiwfhiowrgtv` (solo lectura, metadatos) el 20/11/2026. Repo `main` HEAD `74786d5`. "Inspeccionado" no implica "probado": ninguna fila está probada con pruebas negativas.

| ID | Área/rutas/objetos | Estado | Evidencia y entorno/commit | Prueba negativa o de negocio | Próximo paso |
| --- | --- | --- | --- | --- | --- |
| C-001 | Repo: estructura, `package.json`, `src/`, `supabase/` | Inspeccionado | React 18/Vite 6, supabase-js 2, TanStack Query 5, jsPDF; `src/{app,components,contexts,hooks,lib,modules,services}`; migraciones locales `018`–`034` | No aplica | Confirmar versión real (package.json 0.1.0 vs commits "1.0.4" vs ESTADO "1.2.1") |
| C-002 | `public`: 61 tablas, columnas, PK, FK, checks, índices | Inspeccionado | Catálogo remoto. PK en todas; `company_id` en todas salvo `companies`/`profiles`; 0 vistas | No | Medir índices con `EXPLAIN` en base de pruebas (H-003) |
| C-003 | RLS y políticas `public` | Inspeccionado | 61/61 con RLS, ninguna forzada; solo rol `authenticated`; 7 tablas sin políticas (solo RPC) | No | Prueba con 2 empresas y roles distintos en base de pruebas |
| C-004 | Grants de tablas y columnas | Inspeccionado | `anon` sin acceso a `public`; escritura por columna en 10 tablas de catálogo; costos legibles por columna (H-001) | No | H-001 aplicado 23/11/2026 (revocación verificada por catálogo); probar con rol sin finanzas |
| C-005 | Triggers `public`/`auth`/`storage` | Inspeccionado | triggers en `public` (más los propios de `storage`); inmutabilidad en historial, guardas de archivado, reservas de producción; sin triggers sobre `auth.users` | No | Leer cuerpos de `guard_*`, `rebalance_*`, `refresh_*` |
| C-006 | Funciones `public` (por firma) | Inspeccionado parcial | ~100 funciones, sin sobrecargas; todas `SECURITY DEFINER` con `search_path` fijo; escaneo de autorización en las ejecutables; cabecera leída en ~25 | No | Leer cuerpo completo de: `post_sale`, `post_sale_with_payment`, `adjust_sale`, `refund_sale_credit`, `issue_delivery_note`, `void_delivery_note`, `finish_production_job`, `post_production_run`, `cleanup_record` |
| C-007 | Esquema `private` (tablas, 41 funciones, helpers) | Inspeccionado | Tablas sin privilegios para `anon`/`authenticated`; helpers `has_permission`, `is_company_member`, `get_user_role` leídos completos | No | RLS deny-all; confirmar que la API no expone `private` (HI-005) |
| C-008 | Soporte autorizado/auditado | Inspeccionado | `begin_support_session`, `support_session_active`, `get_user_role`, tablas `private.support_*`; sesión 30 min, solo lectura, registro de acceso | No | No se leyeron las filas de `support_operators`; verificar quién es operador con el propietario |
| C-009 | Storage y Realtime | Inspeccionado | Sin buckets, sin políticas en `storage`; `supabase_realtime` sin tablas; `src/` no los usa | No aplica | Sin trabajo hasta que se agreguen |
| C-010 | Migraciones locales vs esquema | Inspeccionado | Por nombre: todo lo definido en `018`–`034` existe en la base; 53 funciones de la base sin fuente local; `list_migrations` vacío (H-002) | No | Volcar esquema como línea base; comparar cuerpos |
| C-011 | Frontend → base | Inspeccionado | 84 RPC distintas; 1 sin EXECUTE (código muerto, H-005); 27 tablas leídas directo; sin `service_role` | No | Revisar qué columnas de costo leen las pantallas (H-001) |
| C-012 | Concurrencia, idempotencia, reintentos | No revisado | Solo lectura estática de cabeceras | Pendiente | Base de pruebas + llamadas simultáneas (HI-001) |
| C-013 | Costos/márgenes en PDF, exportaciones y pantallas | No revisado | Solo la capa SQL | Pendiente | Revisar `src/modules`, `src/services/*pdf*` y exportaciones |
| C-014 | UX/UI, tablet, ayuda contextual, cache por usuario/empresa | No revisado | — | Pendiente | Lote de diseño con `erp-diseno` |
| C-015 | Rendimiento y consumo (consultas, paginación, cache) | No revisado | — | Pendiente | `erp-optimizar` con métricas |

## Excluidos o bloqueados
- Datos de clientes y filas de tablas de negocio: excluidos por alcance.
- Pruebas con escrituras y ejecución de funciones: excluidas (conexión de solo lectura, sin base de pruebas).
- Panel de Supabase (esquemas expuestos de la API, respaldos, Auth): no observable desde esta conexión.

Estados: no revisado, inspeccionado, probado, bloqueado. Anotar funciones por firma/sobrecarga, no solo nombre. Separar pruebas locales, entorno de pruebas y remoto observado. No guardar datos de clientes.

## Filas agregadas al cierre (20/11/2026)
| ID | Área/rutas/objetos | Estado | Evidencia y entorno/commit | Prueba negativa o de negocio | Próximo paso |
| --- | --- | --- | --- | --- | --- |
| C-016 | Corrección de costos 035/036 y frontend asociado | Inspeccionado (revisión crítica por subagente + lectura propia); NO aplicado, NO probado | `supabase/035_*.sql`, `036_*.sql`, `services/production.js`, `services/items.js`, `ItemEditor.jsx`, `FormulasPage.jsx`; `npm run build` OK; repo `74786d5` + cambios sin commit | Pendiente: roles admin/compras/operario y dos empresas | Ejecutar según `supabase/reparacion/LEEME.md` |
| C-017 | Línea base `supabase/linea_base/001_*.sql` | Inspeccionado (conteos coinciden con lo observado); no cargado | 67 tablas, 144 funciones, 74 políticas, 51 triggers; generado desde catálogos remotos en solo lectura | Pendiente: cargar en base vacía y comparar | Elegir entorno de pruebas |

## Filas agregadas 24/11/2026
| ID | Área/rutas/objetos | Estado | Evidencia y entorno/commit | Prueba negativa o de negocio | Próximo paso |
| --- | --- | --- | --- | --- | --- |
| C-018 | RLS/grants/funciones ejecutables y funciones de usuarios, roles y permisos (cuerpos) | Inspeccionado (catálogo y código, solo lectura, 24/11) | `AUDITORIA_FASE2_3_2026-11-24.md` | Pendiente: 2 empresas × 3 roles en este proyecto | H-007: probar escalada con usuario `users:update`; migración 044 |
| C-019 | Migración 043 (cierre con ajustes, estadística, índices) | Verificado por catálogo y script (validaciones, permisos y aislamiento); sin prueba de cierre con orden real | `evidencia/2026-11-24_produccion_cierre_043.md` | Pendiente: lista a–g en `verificaciones/043_comprobaciones.sql` | Recorrido Fase 1 pasos 12–18 |
| C-020 | Migraciones 044 y 045 (solo admin, historial, catálogo de permisos) | Probado con script de suplantación: 204 casos PASAN (24/11) | `evidencia/2026-11-24_pruebas_roles_empresas.md` | Pendiente: concurrencia, soporte sin costos, recorrido real | 046 Compras |

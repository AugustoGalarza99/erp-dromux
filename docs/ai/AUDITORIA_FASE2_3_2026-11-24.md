# Auditoría Fases 2a y 3 (solo lectura) — 24/11/2026

Entorno: proyecto `drcexqsewiwfhiowrgtv`, conector de solo lectura (catálogos y cuerpos de funciones). Repo `main` + trabajo sin commit. Sin datos de clientes. **Nada de esto está probado con usuarios reales**: es lectura de código y catálogo. Estados: verificado (catálogo/código), hipótesis, pendiente.

## Verificado sin problema
- Todas las tablas de `public` tienen RLS y `anon` no tiene ningún privilegio sobre ellas. Todas las políticas referencian empresa, membresía o permiso (ninguna `using (true)`).
- 0 funciones ejecutables por `authenticated` sin control de permiso, salvo las que lo delegan a helpers `private.*` (revisados: `price_require_admin` = rol admin + `sales:update` [+ `finance:read` si toca costos]; `price_require_cost_view` = admin + `finance:read` + `items:read` + `sales:read`; `can_see_production_costs` = admin + `finance:read`; `can_see_reference_cost` = admin o `purchases:read`; `prepare_item_import` exige `items:insert/update`) o que solo exigen sesión por diseño (`create_company`, `my_company_access`, `begin_support_session`, que valida operador).
- Escritura directa del cliente en `companies` y `profiles`: solo la columna `name`. `roles`, `role_permissions` y `company_users` solo se modifican por RPC.
- `set_company_member`: exige `users:update`, el rol debe ser de la misma empresa, solo un admin asigna o quita el rol admin, no se puede suspender la propia cuenta, debe quedar al menos un admin activo. `update_company_role`: el rol admin está protegido; rechaza permisos desconocidos. `roles` tiene `unique(company_id, code)`, así que un rol personalizado no puede duplicar el código `admin`.
- Gestión de archivados (`archived_records`, `cleanup_*`, `restore_archived_record`) verifica el permiso del módulo de cada recurso en el servidor.
- Ajustes: usuarios, roles, unidades, categorías, depósitos y documentos de producción tienen puerta por recurso en el frontend (`PermissionGate`).

## Hallazgos nuevos
### H-007 — P1 — abierto — Escalada por delegación (roles y usuarios)
- Evidencia (cuerpos en la base, 24/11): `create_company_role` exige solo `roles:insert` y admite cualquier combinación de permisos (incluidos `users` y `roles`); `update_company_role` exige solo `roles:update` y permite editar el PROPIO rol; `set_company_member` exige `users:update` y permite asignarse a uno mismo cualquier rol que no sea admin. No hay "techo": nadie queda limitado a conceder solo permisos que ya tiene.
- Actor: usuario no administrador al que el admin dio `roles:*` o `users:update` (por ejemplo un "jefe de RR. HH.").
- Impacto: puede darse a sí mismo todos los permisos operativos (stock, compras, producción, ventas, reportes…). No alcanza lo atado al código `admin` (costos, márgenes, listas de precios, rol admin), pero sí rompe el principio de mínimo privilegio. Confirma y amplía HI-004.
- Clasificación: confirmado por lectura de código; NO probado con usuarios.
- Corrección propuesta (Fase 4, migración 044 con revisión crítica): (a) gestionar roles y usuarios solo para el rol admin, o (b) impedir editar el propio rol y asignarse roles, y limitar a conceder permisos que el actor ya posee. Recomendado (a) para el piloto.
- Prueba de regresión: con un usuario `users:update` sin admin, asignarse un rol con más permisos debe fallar; editar su propio rol debe fallar.

### H-008 — P2 — abierto — Rutas sin puerta de permiso en el frontend
- `/inventory` (StockOverview), `/archivados`, `/ayuda`, `/mi-perfil`, `/actualizaciones` no tienen `PermissionGate`. Los datos están protegidos en el servidor y las pantallas filtran por `can()`, así que el riesgo es de interfaz (pantalla vacía o confusa), no de datos.
- Corrección: decidir qué rutas son libres para todo usuario autenticado (perfil, ayuda, novedades) y poner puerta a las demás; unificar con el catálogo de permisos finos (Fase 4).

### H-009 — P2 — abierto — Sin auditoría de cambios de roles, permisos y miembros
- Evidencia: no hay tabla de historial para `roles`, `role_permissions` ni `company_users` (las únicas tablas de historial/auditoría son de precios, producción, presupuestos y soporte). Quién cambió un permiso y cuándo no queda registrado.
- Corrección propuesta: tabla de eventos de acceso escrita por las RPC de roles/miembros (quién, qué cambió, antes/después), visible solo para admin. Va en la migración 044.

### H-010 — P2 — decisión de diseño — Costos y márgenes atados al código de rol `admin`
- Evidencia: `can_see_production_costs`, `price_require_*` exigen `get_user_role = 'admin'` además del permiso. Un rol personalizado (por ejemplo "gerente") con `finance:read` NO ve costos.
- Implicancia para Fase 4/5: si el administrador quiere que un gerente vea costos, hoy no puede; hace falta un permiso explícito "ver costos" (y la vista "ver como rol" debe respetarlo). Decisión del propietario.

### Reconfirmados
- H-004: `rls_auto_enable` (disparador de eventos) sigue ejecutable por `anon`; el resto de los disparadores observados antes no se re-listaron. Higiene, sin impacto observado.
- HI-002: `create_company` lo ejecuta cualquier usuario autenticado, sin cuota ni control (cada llamada crea una empresa nueva con el usuario como admin).
- HI-003: las funciones de invitación no son ejecutables por `authenticated`; la pantalla de usuarios no tiene alta. Falta definir cómo se incorpora un empleado (hoy: fuera de la app, desde Supabase Auth + asignación). Pendiente decidir el flujo de alta para el cliente.
- `role_permissions` y `roles` son legibles por cualquier miembro de la empresa (necesario para `can()`); expone qué permisos tiene cada rol a todo el personal. Riesgo bajo; anotado.

## Qué NO cubre esta auditoría
- Pruebas con 2 empresas y roles reales (Fase 2c), concurrencia (HI-001), `post_stock_operation` y funciones de dinero en profundidad, exportaciones/PDF con roles sin costos (C-013), HI-005 (esquema `private` en la API: se mira en el panel de Supabase).

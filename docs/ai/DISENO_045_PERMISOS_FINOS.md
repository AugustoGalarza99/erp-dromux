# Diseño 045 — Permisos finos por pantalla (borrador para decidir, 24/11/2026)

Estado: DISEÑO, nada implementado ni aplicado. Objetivo del propietario: que el administrador pueda dar, por ejemplo, solo "Pedidos internos de compra" a un empleado sin abrirle Resumen, Órdenes, Proveedores ni Cuentas, y lo mismo en cada módulo; y poder ver "como vería" ese empleado (vista "ver como rol", Fase 5).

## 1. Hoy (verificado 24/11)
- `role_permissions(role_id, resource, action)`: 16 recursos × 5 acciones. Un recurso = un módulo entero (`purchases` abre las 4 pestañas de Compras).
- Uso en el servidor: ~35 funciones chequean `purchases`, ~35 `production`, ~30 `sales`, ~28 `stock`, ~27 `finance`, 12 `items`; ~100 políticas RLS en 45 tablas. Varias funciones son compartidas entre módulos (tableros, reposición, importación de ítems).
- Excepción que ya funciona como modelo: `purchase_requests` (pedido interno) es un recurso propio.
- `can(resource, action)` en el frontend lee la lista de permisos del rol; el menú y las rutas usan un recurso por módulo (más `adminOnly` para Usuarios y Roles desde 044).

## 2. Principio de diseño (sin tocar `has_permission`, que es el camino más caliente)
1. Catálogo de permisos en una tabla `public.permission_catalog(resource, module, parent, label, help, sort)`: lista cerrada y legible para toda la empresa (no es dato sensible). Reemplaza la lista fija de recursos que hoy está escrita dentro de `create_company_role`/`update_company_role`.
2. Cada pantalla pasa a ser un recurso hijo de su módulo, con las mismas acciones de siempre (ver, crear, editar, eliminar). El recurso del módulo (`purchases`) pasa a significar "acceso total al módulo".
3. EXPANSIÓN AL GUARDAR, no al consultar: al guardar un rol, el servidor agrega las filas de todos los hijos cuando el rol tiene el padre. Así `has_permission` no cambia y las políticas siguen siendo una consulta simple. Una migración posterior que agregue una pantalla nueva también expande a los roles que tengan el padre.
4. Cada función y política pasa a exigir el recurso hijo de su pantalla (por lote, ver §5). Las compartidas (tableros) exigen el hijo "Resumen" del módulo correspondiente.
5. Compatibilidad: la migración inicial expande los roles actuales a todos sus hijos, así que NADIE gana ni pierde acceso al aplicarla; el administrador decide después qué quita.
6. Usuarios y Roles siguen siendo solo del administrador (044) y fuera del catálogo delegable.
7. El rol de soporte (solo lectura) incluye los recursos nuevos en su lista de lectura.

## 2b. Cómo lo usa el administrador (decidido 24/11: el administrador decide todo, nada viene "por diseño")
Al crear o editar un rol, la pantalla pregunta módulo por módulo, en el orden del menú:
1. "¿Este rol puede entrar al módulo **Compras**?" Sí / No. Si es No, el módulo no aparece en su menú y el servidor rechaza todo lo de ese módulo.
2. Si es Sí: lista de las pantallas del módulo (Resumen, Pedidos internos, Órdenes de compra, Proveedores, Cuentas…), cada una con **Acceso / Sin acceso**; si tiene acceso, qué puede hacer (ver, crear, editar, eliminar). Atajo "Acceso total al módulo".
3. Bloque aparte "Datos sensibles": ¿puede ver costos de materiales? ¿puede ver costos, márgenes y listas con costos? Sí / No, siempre decisión del administrador.
4. Resumen final en lenguaje claro ("Puede: … · No puede: …") antes de guardar, y el cambio queda en el historial de accesos. La misma lista se repite para Ventas, Producción, Stock y cada módulo futuro: un módulo nuevo se agrega al catálogo y aparece solo en la pantalla.
Plantillas opcionales (Encargado de compras, Operario, Vendedor…) solo precargan casillas que el administrador revisa y puede cambiar.

## 2c. Cómo se ve lo restringido (decidido 24/11)
Las secciones sin permiso NO se ocultan: se muestran bloqueadas, en gris y con candado ("Acceso restringido"), en el menú y en las pantallas. Al entrar a una pantalla bloqueada se ve el aviso "Acceso restringido" con la explicación y a quién pedir acceso; el servidor igual rechaza los datos. La misma presentación se usa en "ver como rol". HECHO en el menú y en la pantalla de aviso (ver evidencia 2026-11-24_menu_bloqueado.md); falta la búsqueda Ctrl+K (hoy solo lista lo permitido) y las tarjetas de Inicio.

## 3. Catálogo propuesto (primer alcance: Compras, Producción, Stock, Ajustes; Ventas y Finanzas después)
| Módulo (padre) | Pantalla (recurso hijo) | Qué abre |
| --- | --- | --- |
| Compras `purchases` | `purchases_overview` | Resumen de compras |
| | `purchases_orders` | Órdenes de compra y recepción |
| | `purchases_suppliers` | Proveedores y catálogo de precios |
| | `purchases_accounts` | "Compras y cuentas": cuentas y órdenes de pago a proveedores |
| | `purchase_requests` (ya existe) | Pedidos internos de compra |
| Producción `production` | `production_overview` | Resumen |
| | `production_orders` | Órdenes de fabricación (entrega, devolución, cierre) |
| | `production_formulas` | Fórmulas |
| | `production_planning` | Planificación |
| | `production_availability` | ¿Alcanza el stock? |
| | `production_replenishment` | Pronóstico y reposición |
| | `production_packaging` | Envases y presentaciones |
| | `production_stats` | Estadística de producción |
| | `production_documents` | Formato de documentos (PDF) |
| Stock `stock` | `stock_overview` | Resumen de stock |
| | `stock_levels` | Existencias e ingresos/egresos manuales |
| | `stock_movements` | Historial de movimientos |
| | `stock_delivery_notes` | Remitos |
| Ítems `items` | (sin cambios en esta ronda) | Ficha, alta, importación |
| Ajustes | `units`, `categories`, `warehouses` (ya existen); `users` y `roles` solo admin | |
| Costos (no son hijos de ningún módulo) | `costs_materials` | Ver costos de referencia de materiales |
| | `costs_production` | Ver costos, márgenes y listas con costos |

## 4. Costos y márgenes (resuelve H-010 y H-011; decidido 24/11)
- Dos permisos explícitos, independientes de los módulos y decididos por el administrador para cada rol: `costs_materials:read` (costo de referencia de materiales) y `costs_production:read` (costos de fórmula y órdenes, márgenes y listas con costos). El administrador siempre los ve.
- Regla del propietario: el encargado de compras normalmente ve costos y el vendedor solo el precio de venta de la lista establecida por el administrador; pero cada empresa decide rol por rol, por eso son casillas y no una regla fija. La plantilla "Encargado de compras" los trae tildados; "Vendedor" no.
- Migración 045: en la base de hoy el único rol no administrador es "Vendedor" (empresa Dromux ERP) y todos los demás son administradores, así que `costs_*` se otorga solo a los administradores: el vendedor deja de ver el costo de referencia de los materiales (H-011) y no se rompe ningún rol de compras porque no existe ninguno. Alta y edición de listas de precios sigue exigiendo administrador (dinero).
- El vendedor sigue viendo precios de venta de lista por las pantallas de Ventas (no por costos). Queda por verificar en el lote de Ventas que ninguna pantalla de Ventas devuelva costos a quien no tenga `costs_*`.
- API, PDF y exportaciones se revisan en cada lote (C-013).

## 5. Plan por lotes (cada uno: migración con deshacer + verificaciones + revisión crítica + script de pruebas + frontend)
- 045 (base, sin cambio de comportamiento): catálogo, expansión de roles actuales, `create/update_company_role` leen el catálogo y expanden padres, RPC `my_effective_permissions(company)` y `role_effective_permissions(company, role)` (admin) para la vista "ver como rol", permisos `costs_*`. Frontend: `PermissionsGrid` agrupado por módulo y pantalla ("Acceso total al módulo" + pantallas desplegables, resumen en lenguaje claro).
- 046 Compras: re-apuntar funciones y políticas a los hijos; `can_see_reference_cost` usa `costs_materials`; rutas y menú por pantalla. Prueba clave: rol con solo `purchase_requests` ve solo Pedidos internos y todo lo demás da 42501.
- 047 Producción (+ `can_see_production_costs` usa `costs_production`).
- 048 Stock y Ajustes (unidades, categorías, depósitos) + Ventas/Finanzas en una segunda ronda si hace falta.
- Fase 5 "ver como rol" (solo interfaz) sobre `role_effective_permissions`, en paralelo desde 045.
Método de reescritura: igual que 037 (lee la definición vigente con `pg_get_functiondef`, reemplaza el literal del recurso con un mapa explícito función→recurso y aborta si el conteo de apariciones no coincide); políticas por tabla con mapa explícito. Sin reescribir cuerpos desde archivos.

## 6. Riesgos y controles
- Un hijo mal mapeado deja a un rol sin acceso (falla "segura") o con más acceso del debido (falla de seguridad): por eso cada lote lleva pruebas positivas y negativas por rol con el script de suplantación y revisión crítica.
- Funciones compartidas (tableros, reposición, importación de ítems): se aclara a mano qué sección exige qué hijo; si falta permiso devuelven la sección vacía, no error.
- Catálogo y frontend deben coincidir: el frontend lee el catálogo del servidor (no una copia).
- Expansión y futuro: cada pantalla nueva se agrega con migración que expande a los roles con el padre.
- Auditoría: los cambios de roles ya quedan en el historial de accesos (044).

## 7. Decisiones
1. Costos: RESUELTA (§4): permisos explícitos que decide el administrador; compras con costos y vendedor sin costos como plantillas.
2. Catálogo: CONFIRMADO 24/11. Compras, Ventas, Producción y Stock son módulos; dentro de Compras: Resumen de compras, Pedidos internos, Órdenes de compra, Proveedores y Compras y cuentas. "Comercial" es el grupo del menú que contiene Ventas y Compras.
3. Acciones por pantalla: se mantienen ver / crear / editar / eliminar (igual que hoy), salvo que pidas otra cosa.
4. Orden de lotes: Compras primero (046), luego Producción (047) y Stock/Ajustes (048); Ventas y Finanzas después.

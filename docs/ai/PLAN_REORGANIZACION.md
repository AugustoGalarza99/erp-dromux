# Plan de reorganización (D-008, D-009)

El cliente NO usa el sistema hasta el visto bueno del propietario. Opus analiza y planifica; Sonnet ejecuta.

## Etapas
| # | Qué | Estado (26/11/2026) |
|---|---|---|
| 0 | Carpetas por módulo y submódulo (`MAPA_CARPETAS.md`) | HECHA y verificada |
| 2 | Base nueva en español, tablas unificadas (`MAPA_BASE.md`, `supabase/base_nueva/`) | APLICADA y verificada en Supabase |
| 3 | Módulos activos por empresa | HECHO en servidor y menú (27/11); falta probar con sesión |
| A | Adaptar la aplicación a la base nueva | Código HECHO (27/11, `PLAN_ADAPTACION.md`); falta recorrido con sesión |
| B | Pruebas, revisión crítica y publicación | Después de A |
| 1 | Archivos, componentes y variables del frontend en español | Después de B |
| 4 | Importar desde Excel: fórmulas, stock inicial, proveedores y precios (ítems ya existe) | Después de B |
| 5 | Botones para eliminar: categorías, unidades, depósitos, envases, proveedores, pedidos, clientes y listas sin historial | Después de B |

## Próxima sesión: etapa A (adaptar la aplicación)
Medido el 26/11: 58 lecturas directas `.from()`, 168 usos de `can()`, unos 68 archivos afectados. Detalle de nombres y valores: `supabase/base_nueva/mapa.json`. Funciones, parámetros `p_*` y claves devueltas NO cambiaron.

1. Planificar con Opus y fijar un archivo compartido de valores (`src/compartido/valores.js`).
2. Acceso y permisos (primero, sin esto no abre ninguna pantalla): `my_company_access` (rol `administrador`/`soporte`, `company_modules`), `can('recurso','accion')`, navConfig (candado «No incluido en tu plan»), PermissionsGrid, DEPENDENCIES, roleTemplates, Usuarios y Roles.
3. Stock: tablas y columnas en `.from()` (alias de PostgREST para conservar claves), tipos de ítem, movimientos, remitos, catálogos, importación Excel y su plantilla, archivar/eliminar (`items, tipos_cambio, formulas, ordenes, fabricaciones, planes, remitos`), avisos (claves de alerta).
4. Producción: fórmulas, órdenes (estados, entregas/devoluciones, ajustes que se envían como `entrega`/`devolucion`), planificación, reposición, envases, estadística, PDF y copias guardadas (claves en inglés con valores en español).
5. Compras, Ventas, Finanzas, Reportes (lista de precios del cliente = `ventas_clientes.lista_precio_id`; sin invitaciones; borrar `AcceptInvite.jsx`).
6. Controlar que no quede ningún nombre ni valor viejo en `src` (búsqueda por cada valor del mapa) y compilar.

Criterio de aceptación: `npm run build` OK y recorrido de todas las rutas con `npm run dev:nueva`, con alta de ítems, stock, fórmula, orden completa y remito por pantalla.

## Etapa B: pruebas y salida
1. Usuario de prueba (lo crea el propietario en el panel nuevo) y empresas de prueba (al menos 2); activar módulos.
2. Traducir y correr `supabase/verificaciones/pruebas_roles_empresas.sql`; probar operario, vendedor y una sola pantalla; sin costos en pantallas y PDF.
3. Pendientes anteriores: concurrencia (HI-001), corte de red real en el cierre, 200+ filas, tablet y móvil.
4. Revisión crítica con Opus: permisos, bloqueo de módulos (hoy no cubre funciones que solo miran el rol administrador) y aislamiento.
5. En Supabase nuevo: `private` no expuesto en la API (HI-005), URL del sitio, respaldos.
6. Publicar apuntando a la base nueva; el propietario borra la vieja y pasa el proyecto nuevo a la organización paga.
7. Al borrar la base vieja: mover `supabase/0xx`, `reparacion`, `linea_base` a una carpeta de historial y sacar el conector viejo.

## Anotado: baja completa de una empresa (después de las pruebas; pedido del propietario 27/11)
- Debe borrar TODO lo asociado. Hoy solo se puede borrar una empresa recién creada: 10 claves sin cascada y 30 tablas con protección de historial.
- Factible (probado el 27/11 en la base local, con un dueño de tablas sin superusuario): apagar las protecciones dentro de una transacción, borrar por `empresa_id`, borrar la empresa y volver a encenderlas. 221 filas a 0, otra empresa intacta, 0 protecciones apagadas.
- Diseño propuesto: función en `private`, solo SQL Editor; empresa desactivada; nombre exacto como confirmación; todo o nada; resumen de lo borrado y constancia mínima; no borra cuentas de ingreso (lista las que queden sin empresa); respaldo previo. Como archivo en `cambios/` con deshacer y comprobaciones, prueba local y revisión Opus. Apagar protecciones bloquea esas tablas mientras corre: ejecutar sin usuarios trabajando.

## Reglas de la base (desde la línea base)
Cada cambio: archivo en `supabase/base_nueva/cambios/` con deshacer y comprobaciones, registro regenerado (`npm run base:registro`), huellas comparadas y anotación en `BITACORA.md`.

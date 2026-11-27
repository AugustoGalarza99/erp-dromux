# Adaptación de la aplicación a la base nueva (plan de Opus, 27/11/2026)

Detalle de nombres y valores: `supabase/base_nueva/mapa.json`. Columnas y CHECK: `sql/01_estructura.sql`. Permisos por columna y catálogo: `sql/03_permisos_y_datos.sql`.

## Método
- En cada `.select()`, alias `clave_vieja:columna_nueva` (también en embebidos): las pantallas siguen leyendo `row.status`. Solo cambian los **valores** comparados, `can()`, roles y clases CSS. Los nombres del frontend se traducen en la etapa 1.
- Constantes de valores guardados y etiquetas: `src/compartido/valores.js`.
- Funciones RPC, parámetros `p_*` y claves jsonb (enviadas y devueltas) siguen en inglés; los **valores** van en español. Excepción: `p_row`/`p_rows` de ítems ya usaban claves en español.
- No hay `.from()` en `.jsx`, ni Realtime, ni Storage. La escritura y la lectura de `stock_items` tienen permisos por columna: no agregar columnas al `select`.
- El chequeo de módulo contratado va dentro de `can()`.

## Orden
1. `valores.js` y controles automáticos. 2. Acceso y permisos (todos los `can()`, recursos y roles). 3. Stock. 4. Producción. 5. Inicio, Ajustes, Compras, Ventas, Finanzas, Reportes; borrar `AcceptInvite.jsx`.

## Trampas (no reemplazar a ciegas)
- `issue`: `egreso` (stock) / `entrega` (evento de orden). `FinishJobDialog` y el remito de producción envían evento.
- `cash`: `efectivo` (medio de pago) / `caja` (tipo de cuenta). `other`: `otro` / `otra`.
- `cancelled`: `cancelada` (orden) / `cancelado` (plan, pedido, pago, presupuesto). `completed`: `terminada` (orden) / `terminado` (plan).
- `open`: `abierta` (orden de compra) / `abierto` (presupuesto).
- Quedan en inglés: respuesta de limpieza `delete/archive/blocked`, `p_status='all'` y `p_filter`, `day/week/month`, `own/derived/...`, `critical/warning/ok`, claves de `erp_production_dashboard`, niveles de interfaz `urgent/attention/info`, claves de React Query, rutas, ids de módulo y tokens CSS `--mod-*`.
- Copias guardadas (`formula_copia`, `documento_copia`, `opciones_trabajo`): claves en inglés.

## Controles (`npm run base:frontend`)
- `pruebas/frontend.mjs`: contra la base local, comprueba tablas, columnas, relaciones, permisos por columna, RPC y parámetros, `can()` y que `valores.js` coincida con las restricciones.
- `pruebas/viejos.mjs`: busca nombres y valores viejos en `src`, con lista de excepciones justificadas.
- Límite: no prueba PostgREST; los embebidos se confirman recorriendo la app con `npm run dev:nueva`.

## Decisiones tomadas por defecto (el propietario puede cambiarlas)
- Se mantienen los textos visibles actuales (p. ej. orden `pendiente` se muestra «En cola»).
- Plantilla de Excel nueva con códigos en español.

## Observaciones del servidor (no bloquean; revisar en etapa B)
- `archived_records` rotula «OF n» y el código de documento por defecto es `OP`.
- `create_company` guarda el UUID como nombre de perfil (venía igual).
- Alertas con zona horaria fija; `empresas.zona_horaria` y `moneda` sin uso.
- Funciones de precios que solo miran el rol administrador no consultan el módulo.

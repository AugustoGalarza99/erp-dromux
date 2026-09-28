# Dromux ERP · panel, roles y precios (versión 018)

## Instalación en tu proyecto local

1. Hacé una copia de seguridad del proyecto y de la base de datos antes de actualizar. Descomprimí este ZIP y copiá **el contenido de `erp-dromux/`** sobre la carpeta de tu proyecto (`D:/Planos/turnero/erp-dromux/` si sigue en esa ruta). Conservá tu `.env.local`: no se incluye en la entrega ni tenés que cambiar tus claves.
2. En el editor SQL de tu proyecto ejecutá **`supabase/018_panel_precios_roles.sql`** una sola vez, después de las migraciones anteriores. Deben estar instaladas las funciones de costos de la versión 016 y la configuración de usuarios de la 017. Si aparece “function ... does not exist”, detenete y revisá la migración pendiente; no saltees pasos.
3. En la terminal, dentro de `erp-dromux/`, ejecutá `npm install` y `npm run dev`. Reiniciá Vite si estaba abierto y recargá el navegador.

## Qué cambia

| Sección | Resultado |
| --- | --- |
| Inicio | Ventas y facturación de 30 días, cuentas por cobrar, compras abiertas, fabricación planificada, stock bajo mínimo y accesos directos según permisos. Ganancia estimada solo para administrador. |
| Configuración → Usuarios | Quien tenga permiso para editar usuarios puede cambiar el rol; asignar o quitar el rol de administrador requiere ser administrador y siempre debe quedar al menos uno activo. |
| Ventas → Lista de precios | Consulta de productos finales y precio vigente; sin edición en esta pantalla, visible para quien tenga Ventas → Ver. |
| Finanzas → Costos y márgenes | Solo administrador. Muestra costo calculado, permite fijar precio de productos finales y muestra margen y resumen de ganancias estimadas. |
| Navegación | Sidebar desplazable con pie fijo, ajustes visuales de botones, campos y enlaces, tablas desplazables en pantallas pequeñas. |

## Prueba sugerida

1. Entrá como administrador. En **Finanzas → Costos y márgenes** colocá un precio final en un producto terminado que tenga fórmula y costos completos. Comprobá que se actualiza el margen.
2. En **Ventas → Lista de precios** buscá ese producto: debe mostrar el precio actualizado sin controles de edición.
3. En **Configuración → Usuarios** asigná un rol de vendedor a una cuenta de prueba. Iniciá sesión con esa cuenta: debe poder consultar la lista con Ventas → Ver, sin acceso a la vista de costos. El cambio de permisos puede tardar hasta un minuto en una sesión ya abierta; cerrar y volver a entrar lo actualiza de inmediato.
4. Abrí el menú, expandí todos los grupos y desplazate hasta Cerrar sesión. Repetí en un teléfono o con el navegador estrecho; recorré tablas, formularios y enlaces.
5. Realizá una venta de prueba y recargá Inicio para comprobar los indicadores. Validá también una compra pendiente, una planificación y una cuenta por cobrar si tenés ejemplos.

## Alcance de la verificación

`npm run build` compiló correctamente. No se ejecutó la migración contra tu base ni se probó visualmente en dispositivos reales; hacé la prueba anterior antes de publicar. El costo mostrado es estimado: margen bruto por unidad, sin impuestos ni gastos indirectos. La tabla general de ítems del diseño anterior sigue incluyendo columnas de costo para usuarios con permiso de lectura de ítems; si necesitás ocultar el costo a todo vendedor incluso al consultar directamente la API, hay que separar esos datos con permisos específicos en otra migración antes de dar acceso a Inventario.

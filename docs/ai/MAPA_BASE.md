# Mapa de la base nueva (D-009) — APROBADO y aplicado el 26/11/2026

Estado actual de cada tabla: `supabase/base_nueva/registro/`.

Detalle completo (columnas y valores): `supabase/base_nueva/mapa.json`. De 86 tablas pasan a 76; las 13 copias viejas de seguridad no se copian.

## Se unen o se quitan
| Hoy | En la base nueva |
|---|---|
| company_modules | columna `modulos` en `empresas` (con bloqueo real) |
| company_settings | columnas `moneda` y `zona_horaria` en `empresas` |
| customer_price_lists | columna `lista_precio_id` en `ventas_clientes` |
| 7 tablas de numeración | `empresas_numeradores` |
| company_invitations | no se copia (ninguna pantalla la usa) |
| copias `*_pre0*` (13) | no se copian |

## Nombres por módulo
| Módulo | Tablas nuevas |
|---|---|
| Empresas | empresas, empresas_perfil, empresas_usuarios, empresas_numeradores |
| Ajustes | ajustes_perfiles, ajustes_roles, ajustes_roles_permisos, ajustes_permisos_catalogo, ajustes_auditoria_accesos |
| Inicio | inicio_alertas_leidas |
| Stock | stock_items, stock_categorias, stock_unidades, stock_depositos, stock_operaciones, stock_movimientos, stock_saldos, stock_lotes, stock_lotes_saldos, stock_lotes_aperturas, stock_remitos, stock_remitos_lineas, stock_remitos_reversiones |
| Producción | produccion_formulas, produccion_formulas_lineas, produccion_ordenes, produccion_ordenes_eventos, produccion_ordenes_reservas, produccion_reservas_ubicaciones, produccion_fabricaciones, produccion_fabricaciones_lineas, produccion_fabricaciones_antiduplicado, produccion_planes, produccion_tipos_envase, produccion_documentos_config |
| Compras | compras_proveedores, compras_proveedores_items, compras_proveedores_ajustes_precio, compras_ordenes, compras_ordenes_lineas, compras_ordenes_antiduplicado, compras_recepciones, compras_recepciones_lineas, compras_pedidos, compras_pedidos_lineas, compras_pedidos_antiduplicado, compras_pagos, compras_pagos_lineas |
| Ventas | ventas, ventas_lineas, ventas_clientes, ventas_cobros, ventas_cobros_reversiones, ventas_cobros_antiduplicado, ventas_reintegros, ventas_ajustes, ventas_ajustes_lineas, ventas_presupuestos, ventas_presupuestos_lineas, ventas_presupuestos_estados, ventas_listas_precios, ventas_listas_items, ventas_listas_items_metodo, ventas_listas_items_historial, ventas_precios_antiduplicado, ventas_precios_config, ventas_items_config |
| Finanzas | finanzas_tipos_cambio, finanzas_cotizaciones, finanzas_cuentas, finanzas_movimientos, finanzas_cobros_cuentas |
| Internas (`private`) | produccion_solicitudes_eliminadas, soporte_operadores, soporte_sesiones, soporte_accesos |

Las tablas `..._antiduplicado` evitan que una acción se registre dos veces si se reintenta.

## Ejemplos de columnas y valores
`company_id` → `empresa_id` · `name` → `nombre` · `item_type` → `tipo_item` · `created_at` → `creado_en` · `raw_material` → `materia_prima` · `in_progress` → `en_proceso` · rol `admin` → `administrador` · permiso `read` → `ver`.

## Riesgos principales (Opus)
1. Textos ambiguos dentro de funciones (`issue`, `open`, `paid`…) mal traducidos fallan sin avisar: revisar uno por uno.
2. Funciones de borrar/restaurar arman consultas como texto: probarlas en ejecución.
3. Siete funciones devuelven filas completas: cambiarían sus claves.
4. Permisos y rol administrador: un error deja acceso de más o de menos.
5. No perder los permisos que ocultan costos ni el `search_path` de funciones privilegiadas.
6. Comparaciones de estados en la aplicación que fallan sin error.

Validación prevista: extensión `plpgsql_check` (0 errores), comparación de conteos con el origen, `pruebas_roles_empresas.sql` traducido y recorrido de pantallas.

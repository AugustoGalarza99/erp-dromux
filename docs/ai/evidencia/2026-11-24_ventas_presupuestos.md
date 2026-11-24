# Ventas — Presupuestos (041) — 24/11/2026 (noche)

Método: build OK y arnés local temporal (ya eliminado) con Supabase simulado; el PDF se abrió en el visor del navegador. La 041 NO se aplicó ni se ejecutó en ninguna base.

- 040 aplicada por el propietario y verificada por catálogo: columna `max_discount_percent`, 4 funciones (anon sin EXECUTE), post_sale con 1 uso del resolvedor y 0 usos del precio fijo, lectura de columnas nuevas de sale_lines y `estimated_unit_cost` sin lectura. Incidente: el primer intento abortó (chequeo de fragmentos) por saltos de línea CRLF; se hizo la 040 inmune a CR y nada quedó a medias.
- 041 revisada con erp-revisor-critico: sin P0. P1 corregidos: historial de estados (tabla de eventos) y aceptar presupuesto vencido solo admin. P2 corregidos: idempotencia antes de validar vigencia, precio cero, desborde y coherencia bruto = neto + IVA, item_id inválido, validación del logo (bytes iniciales, padding, nulo = conservar), deshacer con guarda de logo, comprobaciones (columnas, políticas, Realtime). Pendiente: columna line_count para rendimiento con muchos presupuestos, trigger de TRUNCATE (sin grant, riesgo bajo).
- PDF: membrete con logo y datos de la empresa, bloque del cliente, tabla (código, descripción, cantidad, precio de lista y descuento solo si hay, precio unitario, importe), IVA por alícuota, total, condiciones, pie con paginación. 3 líneas (1 hoja) y 120 líneas (7 hojas, encabezado repetido).
- Interfaz probada en 360 y 1280 px sin desborde; lista paginada, filtros, editor con búsqueda de productos y vista previa de totales. Corregido en el arnés: campos sin estilo de alto/borde en el editor.
- No probado: comportamiento real contra la base (2 empresas, 3 roles, idempotencia, estados), descarga del PDF desde un presupuesto creado por el servidor, impresión real en papel.

## Ajustes posteriores (noche) — 042
- 041 aplicada por el propietario; verificada por catálogo: 5 tablas (RLS; legibles solo quotes por columna, quote_lines y quote_status_events), columnas sin lectura (created_by, request_id, request_payload, status_changed_by), 6 funciones con SECURITY DEFINER y search_path vacío, 3 disparadores, 3 políticas, 0 tablas en Realtime.
- Pedido del propietario: ocultar un identificador largo, vista previa antes de generar y "sumar IVA sin mostrarlo". Causa del identificador: 3 perfiles guardan un UUID como nombre y aparecía como autor en la lista. Solución: la lista lo muestra como "Usuario" y la 042 hace que create_quote registre "Usuario".
- 042 revisada (erp-revisor-critico): sin P0. Aplicado: payload idéntico al de la 041 en el modo por defecto (reintentos entre versiones), notify pgrst reload schema, importe por línea desde el servidor (line_gross), bloqueo de tabla en el deshacer, control agregado de coherencia.
- Probado en arnés (eliminado): editor con dos productos, check de IVA, totales (3.500 neto + 525 IVA = 4.025), vista previa con marca de agua y precios con IVA incluido sin discriminar.
- No probado: la 042 contra una base real; impresión en papel; unitario con IVA vs importe de línea en cantidades fraccionarias (pueden diferir en centavos: el importe de línea manda).

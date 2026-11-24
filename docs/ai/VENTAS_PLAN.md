# Plan del módulo Ventas (L5) — para trabajar el 24/11/2026

Estado: BORRADOR. Parte de lo que hay hoy en el código y de lo que necesita un dueño de pyme para competir. Falta contrastarlo con el Excel de costos del propietario ("Costos AGOSTO 26 nuevoultimo", enlace de OneDrive): el visor no se pudo leer desde el navegador integrado. Ver "Excel" al final.

## 1. Lo que existe hoy (verificado 23/11/2026)
- Un solo precio de venta por ítem: `items.sale_unit_price` (RPC `erp_set_finished_product_price`, lectura pública `erp_public_price_list` = id, código, nombre, unidad, precio).
- Pantallas: `/sales/customers` (CustomersPage), `/sales/lista-precios` (PriceListPage, 61 líneas, solo consulta), `/sales/orders` (SalesOrdersPage: registrar venta con cliente, líneas, lote, cobro total/parcial, devoluciones/ajustes con `SaleAdjustmentPanel`).
- Costos y margen: `/finance/costs` (CostsPage, solo admin) con `erp_admin_product_costs` (item, costo, precio, margen, % margen, estado) y `erp_admin_sales_profit_*` (ganancia por venta). `sale_lines.estimated_unit_cost` guarda el costo al vender.
- NO hay: listas de precios múltiples, productos por lista, vigencia, descuentos, IVA/impuestos, redondeo, precio por unidad de medida/presentación, recargo vs margen configurable, historial de cambios de precio, presupuestos/cotizaciones, lista por cliente, importar/exportar planillas, alertas de margen bajo, comparación con la competencia.
- `post_sale` está limitado a 40 líneas (dinero, requiere auditoría antes de subirlo).

## 2. Objetivo
Que el dueño pueda armar, mantener y compartir listas de precios con costo, margen y ganancia a la vista, y vender con el precio correcto según el cliente, sin cargar dos veces, y sin que un operario o vendedor vea costos.

## 3. Funciones a construir (orden sugerido)
A. Listas de precios (maestro)
 1. Crear/editar/duplicar/archivar listas (nombre, moneda ARS/USD, vigencia desde/hasta, lista por defecto, nota). Ej.: Mayorista, Minorista, Distribuidor, Lista web.
 2. Agregar productos a una lista (buscador + importación masiva desde Excel con vista previa, formato argentino $16.500,50) con paginación y filtros (D-007).
 3. Por producto y lista: costo (solo admin), método de precio (margen % sobre venta, recargo % sobre costo o precio fijo), margen, ganancia por unidad, precio sin impuestos, IVA, precio final, redondeo, precio por unidad de medida y por presentación/envase (ej.: por kg y por bolsa de 25 kg).
 4. Edición masiva: subir/bajar % a toda la lista o a una selección; recalcular desde el costo vigente; vista previa del cambio antes de aplicar.
 5. Historial de cambios de precio y de costo (quién, cuándo, antes/después).
 6. Alertas: margen por debajo del mínimo configurable, costo que subió y precio desactualizado, productos sin precio en la lista.
B. Cálculo y análisis (solo admin / finance:read)
 7. Panel de rentabilidad por producto y por lista: costo, margen %, recargo %, ganancia unitaria, ganancia sobre la tanda/orden, punto de equilibrio simple.
 8. Simulador "¿a qué precio vendo?": entrada de margen deseado → precio; entrada de precio de la competencia → margen resultante.
 9. Referencia de precio de mercado/competencia por producto (campo opcional y fecha) para comparar.
C. Venta
 10. Cliente con lista asignada; al registrar la venta el precio sale de la lista del cliente (editable con permiso y con motivo si baja del mínimo).
 11. Descuentos por línea y por documento (con tope por rol), condición de pago.
 12. Presupuestos/cotizaciones imprimibles en PDF (sin costos), con vencimiento y conversión a venta.
 13. Compartir lista de precios en PDF/Excel para clientes (sin costos ni márgenes).
D. Interfaz (misma forma de trabajo)
 14. `SalesShell` + Resumen de ventas (ventas del período, por cobrar, productos con margen bajo, presupuestos por vencer), tema verde, pestañas: Resumen, Ventas, Clientes, Listas de precios, Presupuestos.
 15. Tablas compactas, paginación, tarjetas en móvil, confirmaciones, Sonner, ayuda corta.

## 4. Diseño de datos propuesto (migración 039, PREPARAR y REVISAR; NO aplicar sin autorización)
- `price_lists(id, company_id, name, currency, valid_from, valid_to, is_default, archived, note, created_at)`.
- `price_list_items(company_id, price_list_id, item_id, pricing_method, margin_percent|markup_percent|fixed_price, tax_percent, rounding, unit_price, pack_price, updated_at, updated_by)` con precio calculado guardado + historial `price_list_item_history`.
- `customers.price_list_id` (opcional). `sale_lines` guarda lista y precio base usados.
- Costos y márgenes SOLO por RPC con `admin` + `finance:read` (patrón D-004); el vendedor recibe precio final y nada más.
- Funciones SECURITY DEFINER con `search_path` vacío, idempotencia donde haya dinero, RLS por empresa, revoke a `public,anon,authenticated`, deshacer y comprobaciones. Revisión crítica con `erp-revisor-critico` (u Opus con `/model`) antes de aplicar.
- Impuestos: confirmar con el propietario el tratamiento de IVA (precio con/sin IVA, alícuotas) antes de modelarlo; no adivinar.

## 5. Reglas que siguen vigentes
- Multirrubro (D-006): sin vocabulario de un solo rubro; presentaciones, unidades e impuestos configurables.
- Volumen (D-007): listas de 200+ productos con paginación, búsqueda, filtros y edición masiva.
- Costos nunca al operario/vendedor (API, PDF, exportaciones). No tocar `post_sale` ni dinero sin revisión.
- Probar con arnés (360/768/1024/1440) y `npm run build`; documentar evidencia.

## 6. Excel de costos del propietario — pendiente de lectura
- Archivo: "Costos AGOSTO 26 nuevoultimo.xlsx" (OneDrive). El visor web no se renderiza en el navegador integrado, así que su contenido NO se leyó ni se asume.
- Para analizarlo: copiarlo a `docs/ai/referencias/` (ver `LEEME.md` ahí) o pegar las columnas y 5 filas de ejemplo. Qué extraer: columnas de costo, margen, recargos, IVA, precio por unidad/presentación, listas por tipo de cliente, fórmulas usadas, redondeos, moneda, y cómo agrupa productos. Con eso, ajustar las secciones 3 y 4 antes de diseñar la migración.
- Sanitizar: no copiar a Git datos de clientes ni costos reales sin acordarlo; la carpeta de referencias debe quedar fuera de commits (`.gitignore`) si contiene datos reales.

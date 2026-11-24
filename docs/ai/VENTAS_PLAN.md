# Plan del módulo Ventas (L5) — para trabajar el 24/11/2026

Estado: BORRADOR AJUSTADO (24/11/2026) con la lectura del Excel de costos del propietario (sección 6). IVA: decisión pendiente del propietario antes de modelarlo.

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

## 4. Diseño de datos — migración 039 (PREPARADA 24/11, revisada, NO aplicada)
Archivos: `supabase/039_listas_precios.sql`, `reparacion/0_deshacer_039.sql`, `verificaciones/039_comprobaciones.sql`.
- Decisión del propietario (IVA): todo se guarda SIN IVA; alícuota por producto (`item_sale_settings.tax_percent`) o general de la empresa (`price_settings.default_tax_percent`, 21); el precio con IVA se calcula al leer.
- Tablas: `price_lists` (moneda, vigencia, predeterminada, lista base + descuento %, redondeo), `price_list_items` (solo precio neto: lo único legible con sales:read), `price_list_item_pricing` (método margen/recargo/fijo y costo al fijar), `price_list_item_history` (inmutable), `price_settings` (IVA, margen mínimo, comisión, estructura), `price_change_requests` (idempotencia), `item_sale_settings` (IVA y contenido por unidad), `customer_price_lists`. Las 4 con datos de costo/margen no tienen permisos de tabla: solo por funciones de administrador con finance:read.
- 13 funciones SECURITY DEFINER (search_path vacío). Costos por `private.price_costs` (por ids, sin el tope de 100 de `erp_product_costs`).
- Revisión crítica (erp-revisor-critico): sin fugas ni huecos multiempresa; 4 P1 (tope de 100 costos, desborde de method_value, guarda del deshacer, moneda en resolve) y varios P2 CORREGIDOS en el archivo. Sin ejecutar: la revisión fue de lectura y la migración no se probó contra una base.
- Fuera de 039: `post_sale_with_payment` no se toca (sigue usando `items.sale_unit_price`); `erp_resolve_sale_price` solo consulta. Descuentos, presupuestos, ofertas y kits quedan para 040.
- Decisión abierta: una lista derivada sigue usando la base aunque la base esté vencida por fechas.

## 5. Reglas que siguen vigentes
- Multirrubro (D-006): sin vocabulario de un solo rubro; presentaciones, unidades e impuestos configurables.
- Volumen (D-007): listas de 200+ productos con paginación, búsqueda, filtros y edición masiva.
- Costos nunca al operario/vendedor (API, PDF, exportaciones). No tocar `post_sale` ni dinero sin revisión.
- Probar con arnés (360/768/1024/1440) y `npm run build`; documentar evidencia.

## 6. Excel de costos del propietario — LEÍDO el 24/11/2026 (verificado: estructura y valores; hipótesis: reglas de cálculo)
Archivo local `docs/ai/referencias/Costos AGOSTO 26 nuevoultimo.xlsx` (fuera de Git). 16 hojas, **todas con valores pegados, sin fórmulas**: las reglas hay que inferirlas y confirmarlas con el propietario.

| Hoja | Qué contiene |
|---|---|
| Parametros | Descuento a Distribuidor 43 %, Mayoristas 40 %, Reventa 36 %; dólar 1540; kilos mensuales; sueldos de producción; comisión vendedores 7 %; estructura 20 % |
| Formulas / Listas | ~2300 filas fórmula→materia prima→cantidad→precio→costo; materias primas con costo, precio ref. USD y proveedor; envases con costo y USD; tiempos de envasado y factores; marca, unidad de negocio, tipos de oferta (unidades a facturar vs a dar) |
| Articulos | ~880 productos: código, producto base, envase, kilos que entran, costo, $/kg, mano de obra, factor, costo de envase, orden interno |
| Rentabilidades | por producto: costo (materia prima + mano de obra + recargo 20 %), precio lista sin IVA, precio sugerido (margen 25 %), precio y ganancia para distribuidor y revendedor tras comisiones, margen (sobre precio) y rentabilidad (sobre costo), precio por kilo nominal, dólar anterior/hoy y variación |
| Tabla_sistema_nueva | ~950 filas: código, costo sin IVA, precio sin IVA y 5 listas (Ofertas, Norte, Reventa, Mayorista, Distribuidor) |
| Lista_Colorear / _xls | lista imprimible para clientes (precio y "mi precio" con descuento) |
| Armado_Ofertas_* (Común, Norte, Distribuidor, Combinadas) | ofertas por cantidad (ej. 20 unidades = medio pallet, 10+2 bonificadas): precio unitario de oferta, costo total, ganancia y margen de la oferta, descuento vs lista, comisión 7 % |
| Ofertas_Extraordinarias_Norte, Kits, Formulas_Kit | ofertas puntuales y kits (producto compuesto con costo) |

Relaciones numéricas VERIFICADAS en los datos: precio Reventa = 64 %, Mayorista = 60 %, Distribuidor = 57 % del precio de lista (= 1 − descuento de Parametros). Margen se mide sobre el precio de venta y rentabilidad sobre el costo (dos medidas distintas). HIPÓTESIS sin confirmar: relación entre "Precio lista" de Rentabilidades y "Precio sin IVA" de Tabla_sistema_nueva (cociente 0,685), y cómo se llega a precios de lista (no hay fórmula).

### Lo que necesita el dueño para competir (ajusta las secciones 3 y 4)
1. **Listas por tipo de cliente derivadas de una lista base** por descuento % (Distribuidor, Mayorista, Reventa, Norte/zona, Ofertas), editables producto por producto y con vigencia. El modelo debe permitir "lista = base − X %" **y** precio fijo por producto.
2. **Costo compuesto** (materia prima + mano de obra + recargo %), por presentación; hoy el ERP solo tiene `reference_unit_cost` y el costo de producción: la lista usa el costo vigente que ya calcula el sistema (admin), sin duplicarlo.
3. **Comisión de vendedor y estructura (%)** como parámetros por empresa que bajan el margen real ("ganancia pagando comisiones").
4. **Dos medidas**: margen sobre precio y rentabilidad/recargo sobre costo, siempre juntas.
5. **Precio por unidad base y por presentación** (precio por kilo nominal vs por envase) y **precio por kilo** para comparar.
6. **Ofertas por cantidad** (pack de N unidades a precio especial, "10 + 2 bonificadas", medio pallet/pallet) con ganancia y margen de la oferta y alerta si es negativa (hay ofertas con margen −22 % en el Excel).
7. **Moneda/dólar**: costos de insumos en USD con tipo de cambio "ayer vs hoy" y variación; ya existen `exchange_rates` y `exchange_rate_types` (reutilizar).
8. **Aumento general** (% sobre toda la lista) con vista previa y variación.
9. **Kits/combos** (producto compuesto con costo) y **ofertas combinadas** de varios productos.
10. **Lista imprimible para clientes** sin costos ("Lista_Colorear"), con descuento del cliente.
Fuera de alcance de esta fase (documentar, no construir): fórmulas de producción (ya están en el módulo Producción), tiempos de envasado, órdenes internas.

### Datos reales
Contiene costos y listas reales: no copiar a Git ni a la memoria. La carpeta `referencias/` está en `.gitignore` (pendiente de confirmar que ese cambio esté commiteado).

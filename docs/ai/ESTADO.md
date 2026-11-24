# Estado — cierre de sesión 24/11/2026: Ventas L5 con migraciones 039–042 APLICADAS

## Resumen en una frase
Ventas (L5) quedó funcional de punta a punta: listas de precios múltiples, venta con precio de lista y descuento, presupuestos con PDF profesional (incluido consumidor final con IVA sumado sin discriminar) y vista previa. Las migraciones 039, 040, 041 y 042 las aplicó el propietario y están verificadas por catálogo. Falta probar con usuarios y roles reales, y construir la conversión presupuesto → venta.

## Evidencia y entorno
- Repo `main` HEAD `3d562bc` ("DromuxERP 1.0.4.2"). Todo el trabajo de Ventas está preparado en el área de preparación de Git (`git add`), SIN commit: lo sube el propietario (ver sección "Commit"). `docs/ai/referencias/` (Excel con datos reales) y `.env.local` están ignorados.
- Base: proyecto `drcexqsewiwfhiowrgtv`, conector de solo lectura. Migraciones aplicadas por el propietario: 035–042. Locales: `018`–`042`.
- VERIFICADO por catálogo (24/11): 039 (8 tablas con RLS, 13 funciones), 040 (columna de tope, 4 funciones, `post_sale` parcheada con el resolvedor, columnas nuevas de `sale_lines` legibles y `estimated_unit_cost` no), 041 (5 tablas, lectura por columna sin `request_payload`/`created_by`, 6 funciones, 3 disparadores, 0 tablas en Realtime), 042 (columna `tax_included`, restricción, `create_quote` de 13 parámetros, 0 incoherentes).
- VERIFICADO: `npm run build` OK; interfaz probada en arnés simulado (360/768/1024/1440, 260 productos; PDF de 1 y 7 hojas; vista previa). NO verificado: comportamiento con 2 empresas y 3 roles, idempotencia real, impresión en papel, tiempos con listas de 200–5000 productos.
- El propietario probó con datos reales: listas, costos, márgenes, cambio de precio (OK, 24/11). Excel de costos leído (16 hojas, valores sin fórmulas): ver `VENTAS_PLAN.md` §6.

## Terminado (evidencia en `docs/ai/evidencia/2026-11-24_ventas_*.md`)
- H-001 costos por API (035/036). L0 shell, L1 Inicio, L2 Stock, L3 Producción, L4 Compras (+pedidos internos 038).
- Ventas L5: `SalesShell` (tema verde) + Resumen; Clientes con lista asignada; Listas de precios (paginación en servidor, filtros Sin precio/Margen bajo/Costo cambió, edición con vista previa, cambio masivo e importación con vista previa y confirmación, historial, simulador, parámetros, tarjetas en móvil); Registrar venta con precio por cliente y descuento por línea (tope general; admin lo supera con motivo); IVA sin guardar con IVA, alícuota por producto o general.
- Presupuestos: pestaña con lista paginada y estados con historial; editor (cliente o interesado, hasta 200 líneas, descuento con tope); diálogo Datos de la empresa (CUIT, domicilio, logo); PDF con membrete, cliente, tabla con encabezado repetido, condiciones y paginación; vista previa con marca de agua; tres modos de IVA (discriminado / sumado sin discriminar para consumidor final / no incluido). No mueven stock ni dinero y no se editan.

## Incompleto o sin hacer
- Ventas: presupuesto aceptado → venta con un clic (migración propia, revisión crítica y autorización); ofertas por cantidad y kits (Excel); lista imprimible para clientes sin costos (PDF/Excel); duplicar presupuesto; presupuestos por vencer en el Resumen; importar .xlsx nativo (hoy se pega o se carga CSV); costo compuesto con comisión/estructura y dólar "ayer vs hoy"; descuento de documento y condición de pago.
- Decisiones abiertas: lista derivada cuya base venció por fechas (hoy sigue usando la base); cómo llega el propietario a los precios de lista (el Excel no trae fórmulas).
- Limpiezas: 3 perfiles de la base tienen un identificador como nombre (se ven como "Usuario"); `*.sql text eol=lf` en `.gitattributes` (las migraciones que parchean texto ya ignoran CRLF); columna `line_count` en presupuestos y medición de rendimiento; trigger de TRUNCATE en presupuestos (riesgo bajo).
- Otros módulos: pedidos internos (probar con 2 empresas y 3 roles; dar `purchase_requests` a operarios), Compras L4c, Producción (PDF de 200 líneas), Stock (`ItemImport`, filtro bajo mínimo, lote inicial), Finanzas (L6), Reportes (L7), Ajustes (L8), auditoría final y base de pruebas.

## Commit (preparado, lo sube el propietario)
- Incluye: `src/modules/sales/*` (SalesShell, SalesOverview, PriceListsPage + diálogos, PriceSimulator, QuotesPage, QuoteEditor, CompanyProfileDialog, quotePdf, salesModule.css; CustomersPage/SalesOrdersPage/PriceListPage modificados), `src/lib/pricing.js`, `src/lib/logo.js`, `src/services/priceLists.js`, `src/services/quotes.js`, `src/services/sales.js`, `src/app/App.jsx`, `src/components/navConfig.js`, `supabase/039`–`042` + `reparacion/0_deshacer_039`–`042` + `verificaciones/039`–`042`, y `docs/ai/` (ESTADO, PLAN, VENTAS_PLAN, PROMPT_PROXIMA_SESION, evidencia de L5a, L5b y presupuestos).
- Mensaje sugerido: "Ventas: listas de precios, venta con lista y descuento, presupuestos en PDF (migraciones 039–042)".
- Verificado antes de preparar: sin secretos en el código ni en los documentos; `npm run build` OK; sin carpeta de arnés.

## Riesgos
- Sin pruebas con usuarios y roles reales: los cierres son de catálogo y de interfaz simulada.
- Rendimiento de costos (`private.price_costs` recursivo) sin medir con 200–5000 productos y fórmulas de 200 componentes; filtros Margen bajo/Costo cambió limitados a 1000 productos con precio.
- Ventas toca dinero: no tocar `post_sale` ni cobros sin revisión crítica y autorización. Toda migración que cree tablas revoca a `public,anon,authenticated`.
- Un presupuesto con IVA sumado y una futura conversión a venta podrían diferir en centavos (la venta guarda neto; el IVA es informativo): revisar al diseñar la conversión.

## Decisiones vigentes
- Costos: referencia admin o `purchases:read`; producción y márgenes solo admin + `finance:read`, por RPC (D-004). El operario/vendedor nunca recibe costos (API, PDF, exportaciones).
- D-005 paleta por módulo, D-006 multirrubro, D-007 volumen. IVA: precios guardados sin IVA; en la venta el total y los cobros son netos y el IVA es informativo; tope general de descuento por empresa; listas USD ignoradas al vender (24/11). No tocar base/permisos/RPC sin autorización.

## Próximo paso concreto
1. Propietario: subir el commit preparado y probar con usuarios reales (presupuesto de consumidor final impreso, vendedor sin costos, venta con lista y descuento); corregir los 3 perfiles con identificador como nombre.
2. Diseñar y preparar la migración 043: presupuesto aceptado → venta (preguntar antes: reserva de precio, presupuesto vencido, falta de stock). No aplicar sin revisión crítica y autorización.
3. Luego ofertas por cantidad y kits, lista imprimible para clientes y pruebas de comportamiento con 2 empresas y 3 roles. Prompt de arranque en `docs/ai/PROMPT_PROXIMA_SESION.md`.

## Datos de sesión
- Verificación habitual: `npm run build` + arnés local temporal (login y supabase simulados, alias de Vite a mocks, siempre borrado) en 360/768/1024/1440 con 200+ filas. El visor de PDF del navegador permite revisar los PDF.
- No hay Python en la máquina: leer .xlsx con Node (`fflate` está en node_modules como dependencia transitiva; no es dependencia directa).
- Servidor de desarrollo del propietario en el puerto 5173; ante "Outdated Optimize Dep", reiniciar Vite.
- Las migraciones con parche de texto sobre una función (040) deben ignorar CRLF; las verificaciones por catálogo se hacen con el conector de solo lectura.

## Regla de mantenimiento
Reemplazar este resumen al avanzar; máximo 100 líneas. Preservar decisiones vigentes y próximo paso. No marcar algo resuelto sin evidencia.

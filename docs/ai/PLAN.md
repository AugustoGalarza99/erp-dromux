# Plan de rediseño y funciones por módulo (D-005)

Plazo: 15 días de pruebas del cliente + 15 de mejoras. Orden: un lote por módulo, luego auditoría final. Reglas: sin tocar lógica de negocio en lotes visuales; ayuda de 2–4 frases por pantalla; operario sin costos (también en API/PDF); validar en 360, 768, 1024 y 1440 px. Estado de cada lote: pendiente salvo indicación.

## L0 — Shell y navegación (fundación) — en curso
- UX: sidebar agrupado (Operación, Comercial, Finanzas, Análisis, Administración), color del módulo activo, migas, Ctrl+K con atajos, guía "Cómo usar este módulo".
- Doble carga: ninguna en el shell. Quitar duplicación de rutas Configuración vs. documentos de producción si el cliente la señala.
- Faltantes: favoritos/recientes en la búsqueda; ayuda por pantalla (no solo por módulo).
- Ayuda: componente `ModuleGuide` reutilizable (3–5 pasos, recuerda si se cerró).
- Terminado cuando: build OK, 4 anchos sin desborde global, navegación solo con teclado, contraste AA, sin `!important` nuevo.

## L1 — Inicio — implementado 23/11/2026, falta probar con datos y roles reales
- Hecho: "Decisiones de hoy" (fuera de plazo, materiales que se agotan, por cobrar, compras por recibir, planes sin lanzar, cola sin fabricar), KPI de ventas/por cobrar/tesorería/ganancia bruta (admin), panel de producción, avisos y acciones rápidas. Sin migraciones: usa `erp_operational_dashboard`, `erp_production_dashboard`, `erp_replenishment_forecast`, `treasury_balances` y las alertas existentes.
- Doble carga: ninguna; los números salen de lo ya registrado.
- Faltantes (requieren RPC nueva = migración, pedir autorización): actividad del equipo (quién hizo qué hoy, usuarios activos), cobros vencidos por antigüedad, ventas de hoy vs. ayer, comparación con el mes anterior, facturas de proveedor por vencer.
- Ayuda: pendiente de textos por indicador (el Inicio no tiene guía de módulo).
- Terminado cuando: probado con admin, operario y compras en base real; confirmar que operario no recibe importes (la pantalla ya no los muestra; la API lo decide `erp_operational_dashboard`).

## L2 — Stock
- UX: ítems con búsqueda y filtros junto a la tabla, tarjetas en móvil, importación guiada.
- Doble carga: costo en ficha y en importación; remito vs. movimiento manual.
- Faltantes: conteo de inventario/ajustes con motivo; etiquetas de lote.
- Ayuda: crear unidad → depósito → ítem → ingreso.
- Terminado: ajustes con confirmación, Sonner y protección contra doble envío.
- Avance 23/11/2026 (L2a): `StockShell` (cabecera + pestañas), `StockOverview` (ruta `/inventory`), enlaces cruzados ítem ↔ stock ↔ movimientos, pestañas por tipo en Ítems, rangos rápidos en Movimientos, confirmación de salidas/transferencias, tema con color de módulo. Evidencia: `evidencia/2026-11-23_stock_L2.md`.
- Avance 23/11/2026 (L2b): `ItemEditor` rehecho (secciones, tipo en tarjetas, cambios sin guardar, confirmación al desactivar, existencias en el lateral), colores sutiles por tipo (`--type-*` en `uiFoundation.css`, catálogo en `itemTypes.js`), remitero con filtros y resumen previo a emitir. Evidencia: `evidencia/2026-11-23_stock_L2b.md`.
- Pendiente L2b restante: `ItemImport` (asistente de importación), aviso Sonner al archivar/restaurar desde Archivados, ítems bajo mínimo como filtro del servidor en Stock (hoy solo hay conteo; filtrar exige parámetro nuevo en `stock_summary` = migración), desglose de stock por ítem en Ítems (RPC nueva), tarjetas en móvil para Movimientos, ayuda por pantalla, pruebas con roles reales y base de prueba.

## L3 — Producción
- Avance 23/11/2026 (L3a): `components/ModuleShell.jsx` + `moduleShell.css` (estructura genérica para los módulos que siguen), `ProductionShell`, `ProductionOverview` (`/production`), cabecera común en las 6 pantallas, tema naranja y estados de orden en `production.css`, orden de menú igual al de pestañas, `?new=1` para abrir "Nueva orden", "Envases y presentaciones" con texto neutro. Evidencia: `evidencia/2026-11-23_produccion_L3a.md`.
- Avance L3b (23/11/2026, D-007 volumen): `ListPager`/`usePagedList`, tabla `.mod-table` con tarjetas en móvil, Reposición compacta con filtros y paginación, `JobComponentsTable` (insumos de la orden), `FormulaLinesEditor` (fórmulas), Envases y presentaciones rehecho, historial de la orden paginado. Evidencia: `evidencia/2026-11-23_produccion_L3b.md`. Bloqueo H-006: tope de 40 líneas en la base.
- Pendiente L3b restante (resto de la lista original, ya sin lo hecho): planificación y simulador "¿Alcanza el stock?" con muchos componentes (paginar/tabla), diálogos de la orden, PDF con 200 líneas, migrar Stock a `ModuleShell`, aplicar el mismo patrón a Compras (órdenes con muchas líneas) y Stock (remitos grandes).
- Lista original L3b: tarjeta de orden y sus 5 diálogos (entrega de insumos, devolución, finalización, detalles de trabajo, cancelación) para lenguaje y pasos más claros y confirmación al iniciar/terminar; editor de fórmulas (costo solo admin, vista previa de insumos, versión visible); planificación (convertir plan en orden en un clic, estados); simulador y reposición (tablas a tarjetas en móvil); hoja PDF sin costos y con texto neutro; migrar Stock a `ModuleShell` para eliminar el CSS duplicado; hover del resto de módulos.
- Regla D-006: revisar textos/ejemplos de rubro en cada pantalla (campos de densidad/rendimiento deben ser opcionales y con ayuda neutra).
- UX: orden → retiro → cierre en un flujo claro; hoja del operario sin costos.
- Doble carga: fórmula vs. envasado; retiro vs. remito de insumos.
- Faltantes: avisos de faltantes antes de iniciar; reposición sugerida accionable.
- Ayuda: 5 pasos de la guía de Producción.
- Terminado: sin doble descuento; PDF operario sin costos.

## L4 — Compras
- Avance L4a (23/11/2026): `PurchasesShell`, Resumen (`/purchases`), órdenes rehechas (lista con avance, `PurchaseLinesEditor`, reposición sugerida por proveedor, resumen antes de crear), recepción con "marcar todo", búsqueda, paginación y confirmación, Proveedores (nueva orden desde el proveedor, confirmar al desactivar) y Cuentas con cabecera común, guía actualizada. Evidencia: `evidencia/2026-11-23_compras_L4.md`.
- Avance L4b (23/11/2026): pedidos de compra internos (operario pide, Compras convierte o rechaza) con migración 038 PREPARADA y revisada, NO aplicada; interfaz, permisos y navegación listos. PDF de orden de 200 líneas verificado (13 páginas). Evidencia: `evidencia/2026-11-23_compras_L4b_pedidos.md`.
- Pendiente L4c: aplicar 038 (autorización, respaldo, pruebas con roles), asignar el permiso `purchase_requests` a los roles de operario; catálogo y comparación de precios de Proveedores y su CSS interno; estadísticas/cuenta corriente/órdenes de pago con volumen (ya paginan en servidor); fecha prevista de entrega en la orden con alerta de atraso (columna nueva = migración); pagos en lote; avisar al operario cuando su pedido se resuelve (notificación); pruebas con datos y roles reales.
- UX: orden de compra a recepción en pocos clics; cuentas de proveedor legibles.
- Doble carga: precio del proveedor vs. costo del ítem.
- Faltantes: recepción parcial visible; comparación de precios.
- Ayuda: crear orden no suma stock; recibirla sí.
- Terminado: recepción idempotente verificada.

## L5 — Ventas
- HECHO 24/11 (L5a–L5c): SalesShell + Resumen; Clientes con lista asignada; Listas de precios (039: múltiples listas con vigencia, derivadas por descuento, historial, cambio masivo e importación con vista previa, simulador, IVA por producto); Registrar venta con precio por cliente y descuento por línea con tope (040); Presupuestos con numeración, estados con historial, datos de la empresa y PDF profesional con vista previa (041); presupuesto con IVA sumado sin discriminar para consumidor final (042). Evidencia: `evidencia/2026-11-24_ventas_*.md`. Migraciones 039–042 aplicadas y verificadas por catálogo.
- PENDIENTE: presupuesto aceptado → venta con un clic (toca stock y dinero: migración propia con revisión crítica); ofertas por cantidad y kits (Excel del propietario); lista imprimible para clientes sin costos; duplicar presupuesto; presupuestos por vencer en el Resumen; importar .xlsx nativo; costo compuesto con comisión/estructura y dólar "ayer vs hoy"; descuento de documento y condición de pago; pruebas de comportamiento (2 empresas × 3 roles) de 039–042.
- UX: registrar venta con cliente, lista de precios y cobro en una pantalla (hecho); Doble carga: cobro al confirmar vs. Cuentas por cobrar (sin cambios).
- Terminado cuando: sin doble descuento de stock ni doble cobro (verificar con pruebas reales).

## L6 — Tesorería / Finanzas
- UX: saldos por cuenta, cobros y pagos con comprobante, rentabilidad solo admin.
- Doble carga: pagos de compras vs. movimientos de tesorería.
- Faltantes: conciliación simple; vencimientos.
- Ayuda: qué es ganancia bruta.
- Terminado: costos y márgenes solo para roles autorizados.

## L7 — Reportes
- UX: filtros de período arriba, exportación clara.
- Doble carga: ninguna.
- Faltantes: exportaciones con permiso verificado.
- Ayuda: alcance del resultado bruto.
- Terminado: exportaciones sin costos para roles sin acceso.

## L8 — Ajustes
- UX: usuarios, roles y permisos con resumen en lenguaje claro.
- Doble carga: roles vs. permisos por usuario.
- Faltantes: auditoría legible de cambios de permisos.
- Ayuda: asignar el rol mínimo necesario.
- Terminado: cambios de permisos confirmados y auditados.

## Final — Auditoría
Funciones de dinero y stock, concurrencia/idempotencia, costos en PDF/exportaciones, pruebas con roles y dos empresas (ver ESTADO.md).

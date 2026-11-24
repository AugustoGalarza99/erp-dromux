# Prompt para arrancar la próxima sesión (copiar y pegar)

```
/erp-retomar Hoy trabajamos el módulo VENTAS (L5), con la misma forma de trabajo de las sesiones anteriores.

Contexto: leé docs/ai/ESTADO.md y docs/ai/VENTAS_PLAN.md. Reglas permanentes: CLAUDE.md (multirrubro D-006, volumen D-007), costos solo para admin/finance:read (D-004) y nada de tocar base, permisos ni dinero sin mi autorización. Las migraciones 035 a 038 ya están aplicadas.

Paso 1 — Excel de costos y listas de precios: dejé (o voy a dejar) el archivo "Costos AGOSTO 26 nuevoultimo.xlsx" en docs/ai/referencias/. Leelo con herramientas locales, resumime sus hojas y columnas (costo, margen, recargo, IVA, precio por unidad y por presentación, listas por tipo de cliente, redondeos, moneda) y ajustá VENTAS_PLAN.md con lo que realmente necesita el dueño para competir. Si no encontrás el archivo, pedime que pegue encabezados y 5 filas.

Paso 2 — Relevamiento: revisá el módulo actual (SalesOrdersPage, CustomersPage, PriceListPage, CostsPage, services/sales.js, services/costing.js, erp_admin_product_costs, items.sale_unit_price) y decime qué conviene reutilizar.

Paso 3 — Diseño: listas de precios múltiples con vigencia, productos por lista, costo, margen %, recargo %, ganancia, precio sin/con IVA, precio por unidad y por presentación, redondeo, edición masiva con vista previa, historial, alertas de margen, lista por cliente, descuentos, presupuestos en PDF sin costos. Preparame la migración 039 (con deshacer y comprobaciones), pasala por el subagente erp-revisor-critico y NO la apliques: yo la aplico después de revisarla. Antes de modelar el IVA preguntame cómo lo manejamos.

Paso 4 — Interfaz: SalesShell + Resumen de ventas (tema verde), listas de precios con tabla compacta y paginación (200+ productos), importación desde Excel con vista previa, simulador de precio, tarjetas en móvil, confirmaciones y Sonner. Probá con el arnés local (360/768/1024/1440, borrarlo al terminar) y npm run build.

Al cerrar: guardá evidencia en docs/ai/evidencia, actualizá ESTADO.md, PLAN.md y la memoria. Pedime confirmación antes de cualquier commit.
```

## Antes de empezar mañana (checklist del propietario)
1. Copiar el Excel a `docs/ai/referencias/` (o tener a mano encabezados y 5 filas).
2. Levantar el servidor de desarrollo; si falla con "Outdated Optimize Dep", reiniciar Vite.
3. Decidir cómo tratar el IVA (precio con o sin IVA, alícuotas) y el margen mínimo aceptable.
4. Commit: el del 23/11 ("DromuxERP 1.0.4.1", `dfd3e46`) solo incluyó 29 archivos del trabajo de costos. El rediseño L0–L4, las migraciones 037/038 y los documentos nuevos (44 modificados + 34 nuevos) siguen sin commit. Pedirle a Claude al arrancar que proponga la lista de archivos y hacer un segundo commit; no usar `git add -A` sin antes confirmar el `.gitignore` de `docs/ai/referencias/` (datos reales).


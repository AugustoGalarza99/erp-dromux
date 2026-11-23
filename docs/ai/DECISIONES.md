# Decisiones vigentes

## D-001 — Preservar el ERP existente
Mejorar por lotes sobre el código vigente. Evitar reescrituras generales. Agregar migraciones nuevas con pruebas; no editar migraciones históricas ya aplicadas. Verificar convención y numeración actuales antes de generar otra.

## D-002 — Memoria compacta y evidencia separada
CLAUDE.md guarda reglas; ESTADO.md, avance actual; PRODUCTO.md, requisitos; COBERTURA.md y HALLAZGOS.md, evidencia. No importar todos con @ desde CLAUDE.md. La memoria automática de Claude es complementaria y local, no la única fuente compartida.

## D-003 — Datos e historial
Identidad por ID; autorizaciones en backend; registrar reversión/archivo para operaciones con historial. Confirmar método de valuación, monedas, redondeos y unidades antes de modificar costos.

Agregar decisiones nuevas con fecha, problema, decisión y consecuencia; conservar solo las vigentes y enlazar detalle cuando haga falta.v

## D-004 — 20/11/2026 — Costos servidos solo por RPC con permiso
Problema: costos de producción y de referencia legibles por API con permisos no financieros (H-001). Decisión: costo de referencia del ítem para admin o `purchases:read`; costos de producción solo admin + `finance:read`; lecturas por RPC (`list_production_*`, `get_item_detail`) y revocación de SELECT por columna en `036`. Consecuencia: orden de despliegue 035 → frontend → 036; sin acceso a costos no se crean materias primas; toda tabla o columna con costos nueva debe seguir este patrón.

# Decisiones vigentes

## D-001 — Preservar el ERP existente
Mejorar por lotes sobre el código vigente. Evitar reescrituras generales. Agregar migraciones nuevas con pruebas; no editar migraciones históricas ya aplicadas. Verificar convención y numeración actuales antes de generar otra.

## D-002 — Memoria compacta y evidencia separada
CLAUDE.md guarda reglas; ESTADO.md, avance actual; PRODUCTO.md, requisitos; COBERTURA.md y HALLAZGOS.md, evidencia. No importar todos con @ desde CLAUDE.md. La memoria automática de Claude es complementaria y local, no la única fuente compartida.

## D-003 — Datos e historial
Identidad por ID; autorizaciones en backend; registrar reversión/archivo para operaciones con historial. Confirmar método de valuación, monedas, redondeos y unidades antes de modificar costos.

Agregar decisiones nuevas con fecha, problema, decisión y consecuencia; conservar solo las vigentes y enlazar detalle cuando haga falta.v

## D-005 — 23/11/2026 — Plazo, orden de trabajo y paleta por módulo
Problema: hay que cerrar la prueba del cliente y mejorar la experiencia sin perder control de la auditoría. Decisión: 15 días para pruebas del cliente y 15 más para mejoras. Orden: rediseño y funciones por módulo (ver `PLAN.md`), luego auditoría final. Paleta ampliada: fondo blanco y un acento propio por módulo, sobrio y con contraste WCAG AA (texto sobre blanco ≥ 4,5:1): Inicio índigo, Stock azul, Producción naranja, Compras violeta, Ventas verde, Tesorería/Finanzas verde azulado, Reportes gris azulado, Ajustes pizarra. El color nunca es la única señal: siempre va con ícono, texto o forma. Consecuencia: los tokens viven solo en `src/uiFoundation.css` (`--mod-*`); los módulos usan `var(--module-accent)` y no definen colores propios de acento.

## D-006 — 23/11/2026 — Producto multirrubro (no dirigido a una sola empresa)
Problema: el diseño y los ejemplos tendían a un rubro (pinturería). Decisión: el ERP debe adaptarse a cualquier pyme fabricante (metalúrgica, jabones, alimentos, textil, pinturería, etc.). Vocabulario neutro en toda la interfaz (material, insumo, producto, fórmula/receta, orden de fabricación, envase/presentación); ejemplos y datos de prueba genéricos o de rubros distintos; lo específico de cada empresa se resuelve con datos configurables (unidades, categorías, tipos de envasado, campos opcionales), nunca con código o textos fijos de un rubro. Consecuencia: cada lote de UX revisa textos y ejemplos con `rg` de términos de un rubro; los módulos que hoy asumen un caso (p. ej. densidad/rendimiento, envasados) deben ser opcionales y configurables.

## D-007 — 23/11/2026 — Diseño para volumen (fábricas grandes)
Problema: una fábrica grande puede tener fórmulas de 200 componentes o 200+ ítems con faltante; las tarjetas apiladas se vuelven interminables. Decisión: toda lista o detalle que pueda crecer usa resumen arriba, tabla compacta (tarjetas solo en móvil), urgentes/pendientes primero, búsqueda, filtros por estado, paginación y detalle plegable; componentes comunes en `src/components/ListPager.jsx`. Consecuencia: cada lote se prueba con 200+ filas simuladas; las pantallas de Producción (orden, fórmula, reposición, simulador) y luego Compras/Ventas/Stock se ajustan a esta regla.

## D-004 — 20/11/2026 — Costos servidos solo por RPC con permiso
Problema: costos de producción y de referencia legibles por API con permisos no financieros (H-001). Decisión: costo de referencia del ítem para admin o `purchases:read`; costos de producción solo admin + `finance:read`; lecturas por RPC (`list_production_*`, `get_item_detail`) y revocación de SELECT por columna en `036`. Consecuencia: orden de despliegue 035 → frontend → 036; sin acceso a costos no se crean materias primas; toda tabla o columna con costos nueva debe seguir este patrón.

## 24/11/2026 — Alta de empleados, cuentas y empresas (HI-003 / HI-002)
Decisión del propietario: hasta el lanzamiento comercial el alta de empleados, cuentas y empresas se hace manualmente. La automatización (alta de cuentas, creación de empresas, invitaciones de empleados, cuota de `create_company`) se hará junto con la publicación de la página web y la integración de Stripe (pagos y suscripciones). Mientras tanto HI-002 y HI-003 quedan ACEPTADOS como riesgo conocido (proceso manual del propietario) y diferidos a esa etapa.

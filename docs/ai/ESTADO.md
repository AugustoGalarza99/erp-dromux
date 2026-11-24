# Estado — cierre de sesión 23/11/2026: L0–L4 hechos, mañana Ventas (L5)

## Resumen en una frase
Rediseño UI hecho para shell, Inicio, Stock, Producción y Compras (con pedidos de compra internos). Migraciones 035, 036, 037 y 038 aplicadas por el propietario y verificadas por catálogo. Mañana: módulo Ventas con listas de precios, costos y márgenes (plan en `VENTAS_PLAN.md`; falta contrastarlo con el Excel de costos del propietario).

## Evidencia y entorno (verificada salvo lo indicado)
- Repo `main` HEAD `dfd3e46` ("DromuxERP 1.0.4.1", hecho por el propietario el 23/11): incluye 29 archivos del trabajo de costos (035/036, línea base, reparación, verificaciones y cambios tempranos). VERIFICADO tras ese commit: siguen SIN commit 44 archivos modificados y 34 nuevos (todo el rediseño L0–L4: `components/*`, módulos, `uiFoundation.css`, `lib/*`, servicios, migraciones 037 y 038, verificaciones, `docs/ai/PLAN.md`, `VENTAS_PLAN.md`, `PROMPT_PROXIMA_SESION.md`, `evidencia/`, `referencias/LEEME.md`, `.gitignore` y `CLAUDE.md`). Pendiente: segundo commit con autorización del propietario. React 18 + Vite 6, supabase-js 2, TanStack Query 5, Sonner, jsPDF. Migraciones locales `018`–`038`; las 001–017 no están en el repo.
- Base: proyecto `drcexqsewiwfhiowrgtv`, conector de solo lectura. Solo catálogos; no se leyeron datos de clientes ni se ejecutó negocio. Las migraciones las aplica el propietario.
- 038 verificada por catálogo (23/11): RLS activa en las 4 tablas, `anon` sin acceso, `authenticated` solo SELECT en pedidos y líneas, 5 funciones SECURITY DEFINER con `search_path` vacío y EXECUTE solo para `authenticated`, recurso `purchase_requests` en las 3 listas blancas, 5 permisos en cada rol administrador. NO se probó comportamiento (2 empresas, 3 roles).

## Mapa breve
- Frontend `src/`: `app`, `components` (`AdminLayout`, `navConfig`, `ModuleShell`+`moduleShell.css`, `ListPager`, `CommandPalette`, `ModuleGuide`), `modules/*` (cada módulo con su `*Shell` y Resumen), `services/*`, `lib/` (`display.js` sin IDs, `limits.js` topes de líneas).
- Base: 65 tablas `public` con RLS y `company_id`; escrituras por funciones `SECURITY DEFINER`; historial inmutable. `anon` sin acceso.

## Terminado (evidencia en `docs/ai/evidencia/`)
- H-001 costos por API (035/036). L0 shell, L1 Inicio, L2 Stock (+ficha de ítem, tipos con color, remitero), L3 Producción (+volumen 200+), L4 Compras (+orden desde reposición, recepción masiva, pedidos internos).
- 037 topes de líneas 500/200 (H-006); 038 pedidos de compra internos (revisión crítica sin P0, correcciones aplicadas).
- Reglas permanentes: D-005 paleta por módulo, D-006 multirrubro, D-007 volumen (fábricas grandes). Memoria del proyecto al día.

## Incompleto o sin hacer
- VENTAS (L5): plan completo en `docs/ai/VENTAS_PLAN.md`. Hoy hay UN solo precio por ítem (`items.sale_unit_price`) y una pantalla "Lista de precios" mínima; no hay listas múltiples, descuentos, IVA, presupuestos ni historial. El Excel "Costos AGOSTO 26 nuevoultimo" NO se pudo leer (el visor de OneDrive no renderiza en el navegador integrado): hace falta copiarlo a `docs/ai/referencias/` o pegar sus columnas.
- Pedidos internos: probar comportamiento con 2 empresas y 3 roles; dar `purchase_requests` a los roles de operario; avisar al operario al resolverse.
- Compras L4c: catálogo/comparación de Proveedores (CSS interno), fecha prevista de entrega con alerta (migración), pagos en lote.
- Producción: diálogos de la orden y PDF de 200 líneas (remitos/fabricación) sin revisar en pantalla; probar fórmula de 200 componentes y remito de 200 líneas con 037 aplicada.
- Stock: `ItemImport`; filtro "bajo mínimo" (RPC); código de lote inicial con UUID (migración); migrar a `ModuleShell`.
- Finanzas (L6), Reportes (L7), Ajustes (L8) sin rediseño; auditoría final (dinero/stock/concurrencia/PDF con costos); base de pruebas inexistente.

## Riesgos
- Sin pruebas con usuarios y roles reales: los cierres son de catálogo y de interfaz simulada.
- Rediseño L0–L4 todavía sin commit (el commit `dfd3e46` no lo incluye): riesgo de pérdida o mezcla. Antes de commitear: el `.gitignore` nuevo (carpeta `docs/ai/referencias/`, con datos reales del Excel) también está sin commit, así que no usar `git add -A` hasta confirmarlo; no incluir `supabase/.temp/cli-latest`. Los avisos "LF will be replaced by CRLF" son solo de finales de línea de Windows.
- Toda migración que cree tablas debe revocar a `public,anon,authenticated`.
- Ventas toca dinero: cualquier función nueva exige revisión crítica (Opus o subagente `erp-revisor-critico`) y autorización antes de aplicar.

## Decisiones vigentes
- Costos: costo de referencia admin o `purchases:read`; costos de producción y márgenes solo admin + `finance:read`, servidos por RPC (D-004). El operario nunca recibe costos (API, PDF, exportaciones).
- D-005 (plazo 15+15, paleta), D-006 (multirrubro), D-007 (volumen). No tocar base/permisos/RPC sin autorización.

## Próximo paso concreto
0. Commit pendiente del rediseño (ver Evidencia y entorno): proponer qué archivos incluir y esperar autorización; el commit `dfd3e46` no lo contiene.
1. Leer `docs/ai/PROMPT_PROXIMA_SESION.md` y arrancar con ese prompt.
2. Obtener el Excel (carpeta `docs/ai/referencias/`), analizarlo y ajustar `VENTAS_PLAN.md`.
3. Ventas: relevar módulo actual, diseñar listas de precios y migración 039 (preparar, revisar, NO aplicar sin autorización), construir interfaz.

## Datos de sesión
- Verificación habitual: `npm run build` + arnés local temporal (login y supabase simulados, siempre borrado) en 360/768/1024/1440 con 200+ filas.
- Servidor de desarrollo del propietario en el puerto 5173; ante "Outdated Optimize Dep", reiniciar Vite.

## Regla de mantenimiento
Reemplazar este resumen al avanzar; máximo 100 líneas. Preservar decisiones vigentes y próximo paso. No marcar algo resuelto sin evidencia.

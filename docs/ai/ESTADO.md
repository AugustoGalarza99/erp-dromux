# Estado — H-001 cerrado a nivel de esquema, 23/11/2026

## Resumen en una frase
035 y 036 están aplicadas en Supabase (el propietario reportó comprobaciones OK; yo las corroboré por catálogo en solo lectura). H-001 queda cerrado a nivel de esquema; faltan pruebas con roles reales y dos empresas.

## Evidencia y entorno (verificada salvo lo indicado)
- Repo `main` HEAD `74786d5` ("DromuxERP 1.0.4"). React 18 + Vite 6, supabase-js 2, TanStack Query 5, Sonner, jsPDF. Migraciones locales `018`–`036`; las 001–017 no están en el repo.
- Base: proyecto `drcexqsewiwfhiowrgtv`, conector "Supabase Dromux — lectura" (`read_only=true`). Solo catálogos; no se leyeron datos de clientes ni se ejecutó ninguna función de negocio.
- Registro/Auth: el propietario crea las cuentas a mano. Falta confirmar en el panel que el alta libre esté desactivada (no observable desde la base).

## Mapa breve
- Frontend `src/`: `app`, `modules/*`, `services/*` (84 RPC; 27 tablas leídas directo), `contexts/AuthContext`, `lib/`.
- Base: 61 tablas `public` con RLS y `company_id`; lecturas por `private.has_permission`; escrituras por ~100 funciones `SECURITY DEFINER`; escritura directa solo en 10 tablas de catálogo; historial inmutable por triggers; soporte autorizado/auditado. `anon` sin acceso. Sin Storage ni Realtime.

## Terminado
- Diagnóstico inicial: `COBERTURA.md` (17 superficies) y `HALLAZGOS.md`.
- H-001 (costos legibles por API): 035 (5 RPC, helpers privados, envoltorios de `save_item_with_cost`/`import_items`, `production_formula_cost` solo admin + `finance:read`) y 036 (revoca SELECT por columna de costos y escritura directa de `reference_unit_cost`) aplicadas por el propietario.
- Verificado por catálogo 23/11/2026: SELECT de `authenticated` = false en las 9 columnas de costo; 5 RPC nuevas con EXECUTE solo para `authenticated`; núcleos en `private` sin EXECUTE para `authenticated`/`anon`. Detalle en H-001.
- Frontend adaptado (`services/production.js`, `services/items.js`, `FormulasPage.jsx`, `ItemEditor.jsx`); `npm run build` OK.

## Incompleto o sin hacer
- Confirmar con el propietario si el frontend nuevo está publicado y las pestañas recargadas; si no, producción y ficha de ítem fallan con "permission denied".
- Probar con roles reales (admin, compras, operario) y dos empresas; crear ítem sin costo como rol sin compras; comparar filtros/límites de `list_production_*` con el frontend anterior. Sin evidencia de pruebas funcionales aún.
- Auditoría pendiente: cuerpo completo de funciones de dinero y stock (ventas, cobros, devoluciones, remitos, recepciones, fabricación); concurrencia/idempotencia; costos en PDF/exportaciones/informes; cotejar cuerpos locales vs remotos; índices FK (H-003); higiene `private`/EXECUTE (H-004); decisiones HI-002 a HI-004.
- Base de pruebas inexistente (sin Docker ni `psql`): elegir Supabase local o proyecto de pruebas.
- Sin commit de 035/036, verificaciones, reparación, línea base ni cambios de frontend.

## Riesgos
- Falta de pruebas con roles reales: el cierre es de privilegios en catálogo, no de comportamiento.
- Los privilegios por defecto de `public` dan acceso total a tablas nuevas: toda migración que cree tablas debe revocar a `public,anon,authenticated`.
- `supabase/linea_base/001_...sql` se generó desde catálogos y no está validado en ninguna base.

## Decisiones vigentes
- Costo de referencia del ítem: admin o `purchases:read`. Costos de producción: solo admin + `finance:read`. Costos servidos por RPC (D-004).
- Sin acceso a costos no se crean materias primas (el servidor exige costo).
- Prioridad del propietario: cerrar la auditoría antes de nuevas ideas; las que no toquen stock ni dinero pueden ir en paralelo.

## Próximo paso concreto
1. Propietario: confirmar frontend publicado; probar login con un rol operario y uno de compras (producción, ficha de ítem, fórmulas) y reportar errores.
2. Siguiente lote de auditoría (Opus vía `/model`): leer completas las funciones de dinero y stock de COBERTURA C-006 y diseñar pruebas de doble envío.
3. Después: ideas nuevas.

## Datos de sesión
- Git: `main`, sin commit de este lote; no incluir `supabase/.temp/cli-latest` en commits. Varios archivos modificados ajenos a este lote.
- Comandos: una consulta de catálogo en solo lectura (grants de columnas y funciones). Ninguna escritura remota.

## Regla de mantenimiento
Reemplazar este resumen al avanzar; máximo 100 líneas. Preservar decisiones vigentes y próximo paso. No marcar algo resuelto sin evidencia.

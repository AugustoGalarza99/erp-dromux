# Estado — cierre 26/11/2026: carpetas por módulo y base nueva en español aplicadas; falta adaptar la aplicación

## Resumen en una frase
Reorganización (D-008/D-009): la base nueva está aplicada, verificada y registrada; la aplicación TODAVÍA usa la base vieja. Siguiente: adaptarla (`PLAN_REORGANIZACION.md`, «Próxima sesión»). El cliente NO usa el sistema hasta el visto bueno del propietario.

## Evidencia y entorno
- Repo `main`; el propietario hace el commit al cierre del 26/11 (comprobar con `git log` al retomar). Incluye: reglas en CLAUDE.md, D-008/D-009, 160 archivos movidos, `supabase/base_nueva/`, `@electric-sql/pglite` 0.3.16 (desarrollo), scripts `dev:nueva`, `base:probar`, `base:registro`, documentos y el manual de `docs/cliente` (de la sesión del 25/11).
- Base VIEJA `drcexqsewiwfhiowrgtv` (conector solo lectura, intacta, la usa la app y `.env.local`). NUEVA `nummzswhycklmzbgacnl` (segundo conector solo lectura; `.env.nueva.local`, ignorado por Git).
- VERIFICADO carpetas: compilado idéntico antes y después (también tras agregar PGlite); 38 rutas cargan con sesión (Espacio Demo) contra la base vieja, sin alertas; aviso menor en Categorías (input no controlado -> controlado).
- VERIFICADO base nueva en Supabase (solo lectura): 76 tablas, 200 funciones, 79 políticas, 60 disparadores, 34 permisos, `ensure_rls` activo, 0 tablas sin RLS, anónimo sin lectura de tablas, `plpgsql_check` 0 errores (14 avisos), registro público cerrado, 0 empresas y 0 usuarios; 9 huellas iguales a `registro/huella.json`.
- VERIFICADO en local (`npm run base:probar`): carga completa, 684 consultas internas (9 avisos falsos), flujo 66/66.
- NO verificado: la aplicación contra la base nueva, script de roles y empresas, Ventas a fondo, revisión crítica de permisos.

## Próximo paso
1. Comprobar el commit y planificar con Opus la adaptación (acceso/permisos, Stock, Producción, resto).
2. Adaptar y probar con `npm run dev:nueva`; el propietario crea su usuario cuando haga falta.
3. Etapa B (pruebas, revisión crítica, publicar). Luego etapas 1, 4 y 5.

## Pendiente anterior (sigue vigente)
- Concurrencia (HI-001), corte de red real en el cierre, «Asignado» como operario con una orden activa.
- H-UX4 (ayuda inicial a 360 px) y tablas de Roles en 360.
- `post_stock_operation` a fondo; H-011b (precios en órdenes de compra: decide el propietario); HI-005; H-008, H-010, H-012, H-003, H-002; P2 de la 047 y 048.
- Lista de lanzamiento (erp-validar). Manual y presentación de `docs/cliente` (actualizar tras la adaptación).
- Lote de Ventas (revisión crítica obligatoria), luego Finanzas y Reportes.

## Decisiones vigentes
- D-008/D-009: español en tablas, columnas y valores; funciones en inglés; base desde cero sin datos. Cambios de base solo como archivo en `cambios/` y registrados. Reglas en CLAUDE.md. Opus analiza y planifica; Sonnet ejecuta.
- El propietario aplica los SQL (conectores solo lectura); ofreció permisos extra hasta producción si se piden.
- Empresa nueva: módulos `stock` y `produccion` activos; se cambian solo desde el SQL Editor. Sin invitaciones.
- Costos: `costos_materiales` y `costos_produccion` = administrador o permiso explícito. Márgenes/listas: administrador + finanzas hasta su lote.
- Roles y usuarios solo del administrador; sin permiso se ve con candado; «Gestionar» solo en Pedidos internos.
- Reposición, ¿Alcanza? y existencias en órdenes exigen «Stock por depósito». Stock: ver por pantalla; crear/editar/eliminar = módulo completo.
- Estadística cuenta órdenes terminadas aunque estén archivadas; las canceladas no.
- Alta de empleados, cuentas y empresas MANUAL hasta el lanzamiento comercial.
- D-005 paleta, D-006 multirrubro, D-007 volumen. IVA: precios sin IVA, informativo en la venta.

## Datos de sesión
- Nunca pasar contraseñas. Campos React: setter nativo + evento, o teclado.
- En el shell NO usar heredocs ni `cat >` sin entrada (se cuelga): usar la herramienta de archivos y `timeout`.

## Regla de mantenimiento
Reemplazar este resumen al avanzar; máximo 100 líneas. No marcar algo resuelto sin evidencia.

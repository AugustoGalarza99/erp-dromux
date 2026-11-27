# Estado — 27/11/2026: aplicación adaptada y probada en Stock y Producción; sin commit

## Resumen en una frase
La aplicación (`src/`) usa la base nueva en español; Stock, Producción y roles se probaron por pantalla con el administrador. Falta Compras/Ventas/Finanzas/Reportes, un usuario no administrador y dos empresas. El cliente NO usa el sistema hasta el visto bueno del propietario.

## Evidencia y entorno
- Commits del propietario: `cb3c66f` + `7a96ce0` = reorganización y base nueva, en GitHub. La adaptación del 27/11 está SIN commit.
- Base VIEJA `drcexqsewiwfhiowrgtv` (intacta; `.env.local`). El código adaptado ya NO funciona contra ella: usar `npm run dev:nueva`. No publicar hasta la etapa B.
- Base NUEVA `nummzswhycklmzbgacnl` (`.env.nueva.local`). Sin cambios de SQL. Datos de prueba en «Empresa de prueba» (módulos `stock` y `produccion`).
- VERIFICADO local: `npm run build`; `npm run base:frontend` sin errores ni restos viejos.
- VERIFICADO con sesión (administrador, 27/11): 38 rutas; unidades, categorías, depósitos; ítems de los 4 tipos; ingreso, egreso, transferencia y rechazo por stock insuficiente; fórmula y costo; envase y formato de documento; orden en cola, inicio, entrega, devolución, cierre con ajustes, fabricación en un paso, plan, cancelación; saldos y costos cuadran; remitos (materiales, productos, fabricación), anular, archivar, recuperar; eliminar ítem sin uso y bloqueo con stock; avisos leídos; importación Excel; rol con plantilla, historial y «ver como rol» sin costos. PDF de orden y remito se generan (contenido no revisado a la vista).
- Corregido durante la prueba: aviso claro al importar precios sin Ventas; historial de accesos se actualiza al guardar; textos de módulo no contratado en Inicio; aviso de consola en catálogos.
- NO verificado: Compras, Ventas, Finanzas, Reportes; permisos reales de un no administrador; aislamiento entre empresas; tablet/móvil; 200+ filas; concurrencia.

## Hecho el 27/11 (plan: `PLAN_ADAPTACION.md`)
- `src/compartido/valores.js`; consultas con alias; valores, permisos y roles en español; candado «No incluido en tu plan»; plantilla Excel; controles `pruebas/frontend.mjs` y `viejos.mjs`; `dev-nueva` en `.claude/launch.json`.
- Quitados: `AcceptInvite.jsx`, grilla de permisos anterior, `completeProductionPlan`.

## Próximo paso
1. Commit (con confirmación del propietario).
2. El propietario activa los demás módulos en «Empresa de prueba» (SQL en `base_nueva/LEEME.md`) y se recorren Compras, Ventas, Finanzas y Reportes.
3. Etapa B: usuario operario y segunda empresa (los crea el propietario), `pruebas_roles_empresas.sql` traducido, revisión crítica Opus, publicar.
4. Baja completa de empresa (pedido del propietario; diseño en `PLAN_REORGANIZACION.md`). Luego etapas 1, 4 y 5.

## Observaciones abiertas (no bloquean)
- Inicio puede tardar ~1 min (o «Actualizar») en reflejar órdenes nuevas en «Decisiones de hoy».
- Plantilla Excel con ejemplos de un solo rubro (contra D-006): corregir en la etapa 4.
- Avisos muestran «10.000000 kg»; la grilla de permisos no indica módulos no contratados.
- Servidor: «OF n» vs código `OP`; `create_company` guarda UUID como nombre de perfil; zona horaria fija en alertas; precios de Ventas no consultan el módulo.

## Pendiente anterior (sigue vigente)
- Concurrencia (HI-001), corte de red real en el cierre, «Asignado» como operario con una orden activa.
- H-UX4 (ayuda inicial a 360 px) y tablas de Roles en 360.
- `post_stock_operation` a fondo; H-011b (precios en órdenes de compra: decide el propietario); HI-005; H-008, H-010, H-012, H-003, H-002; P2 de la 047 y 048.
- Lista de lanzamiento (erp-validar). Manual y presentación de `docs/cliente`.
- Lote de Ventas (revisión crítica obligatoria), luego Finanzas y Reportes.

## Decisiones vigentes
- D-008/D-009: español en tablas, columnas y valores; funciones en inglés; base desde cero. Cambios de base solo como archivo en `cambios/` y registrados. Opus analiza y planifica; Sonnet ejecuta.
- Textos visibles sin cambios; los nombres del frontend se traducen en la etapa 1.
- El propietario aplica los SQL (conectores solo lectura); ofreció permisos extra si se piden.
- Empresa nueva: módulos `stock` y `produccion`; se cambian solo desde el SQL Editor. Sin invitaciones.
- Costos: `costos_materiales` y `costos_produccion` = administrador o permiso explícito. Márgenes/listas: administrador + finanzas hasta su lote.
- Roles y usuarios solo del administrador; sin permiso se ve con candado; «Gestionar» solo en Pedidos internos.
- Reposición, ¿Alcanza? y existencias en órdenes exigen «Stock por depósito». Stock: ver por pantalla; crear/editar/eliminar = módulo completo.
- Estadística cuenta órdenes terminadas aunque estén archivadas; las canceladas no.
- Alta de empleados, cuentas y empresas MANUAL hasta el lanzamiento comercial.
- D-005 paleta, D-006 multirrubro, D-007 volumen. IVA: precios sin IVA, informativo en la venta.

## Datos de sesión
- Nunca pasar contraseñas. Campos React: setter nativo + evento, o teclado.
- En el shell NO usar heredocs, `cat >` sin entrada ni `node -e` largos con comillas anidadas (se cuelga).

## Regla de mantenimiento
Reemplazar este resumen al avanzar; máximo 100 líneas. No marcar algo resuelto sin evidencia.

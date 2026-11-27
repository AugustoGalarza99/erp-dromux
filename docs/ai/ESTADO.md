# Estado — cierre 27/11/2026: base nueva funcionando y probada; faltan pruebas de volumen y revisión crítica

## Resumen en una frase
La aplicación usa la base nueva en español; los seis módulos, un operario real y el aislamiento entre dos empresas se probaron por pantalla o contra el servidor. NO está publicada ni lista para producción. El cliente NO usa el sistema hasta el visto bueno del propietario.

## Evidencia y entorno
- Git: `0ead273` («1.0.4.9») = adaptación. Lo posterior del 27/11 queda para el commit de cierre del propietario (nombre sugerido «DromuxERP 1.0.5.0»): comprobar con `git log` al retomar. El propietario publica el sitio a mano (no está vinculado a GitHub).
- Base VIEJA `drcexqsewiwfhiowrgtv` (intacta; `.env.local`). El código ya NO funciona contra ella: usar `npm run dev:nueva` (o `dev-nueva` en el panel). No publicar todavía.
- Base NUEVA `nummzswhycklmzbgacnl` (`.env.nueva.local`; conector de solo lectura `mcp__fb7e0e4d…`). `cambios/001`, `002` y `003` aplicados por el propietario, en bitácora, 9 huellas iguales (202 funciones, 81 políticas).
- Datos de prueba: «Empresa de prueba» (seis módulos; usuarios administrador y operario, rol «Operario de prueba 2») y «Empresa de prueba B» (su administrador; stock y producción; vacía).
- Local (27/11): `npm run build`, `npm run base:frontend` (sin errores ni restos viejos; detecta nombres sin declarar) y `npm run base:probar` (flujo 66/66, cambios 61/61).

## Verificado por pantalla (administrador)
- Stock: catálogos, ítems, ingreso/egreso/transferencia, rechazo sin stock, remitos (materiales, productos, producción, venta), anular, archivar, recuperar, eliminar sin uso, avisos, importación Excel.
- Producción: fórmula y costo, envases, formato, orden completa, devolución, cierre con ajustes, un paso, plan, cancelación, disponibilidad, reposición, estadística.
- Compras, Finanzas, Ventas, Reportes: proveedor y precios ARS/USD, pedido, orden, recepción parcial y total, pagos, tesorería, clientes, listas, presupuestos, ventas, cobros, devolución, reintegro, rentabilidad. Saldos y stock revisados cuadran.
- Roles con plantilla, historial, «ver como rol»; 35 pantallas a 375 px sin desborde. PDF se generan (contenido no revisado a la vista).

## Verificado de seguridad
- Operario real: pantallas según rol; sin costos en pantallas ni respuestas probadas; tablas y funciones sensibles rechazadas; escrituras y escaladas rechazadas.
- Operario tras 003: entrega (solo fórmula), devuelve y termina; cancelar, mover stock, remitos, crear órdenes, fijar la marca y leer costos rechazados.
- Aislamiento A→B (18 intentos) y B→A (64 tablas sin filas ajenas; 206 llamadas: 197 rechazadas, 9 vacías, 0 con datos de A; datos idénticos).

## NO verificado
- Botones de una orden activa con sesión de administrador después del 003 (cambió `ProductionJobCard`).
- Listas de 200+ filas, concurrencia (HI-001), corte de red en el cierre, tablet, contenido de los PDF, rol vendedor y rol compras reales, soporte.

## Próximo paso
1. Comprobar el commit. Con sesión de administrador: crear una orden y revisar remito, entregar, terminar y cancelar.
2. Pruebas de volumen (200+ filas), dos sesiones a la vez, tablet y PDF.
3. Revisión crítica Opus (permisos, 003, módulos, aislamiento) y lista `erp-validar`; recién entonces publicar con confirmación.
4. Baja completa de empresa (`PLAN_REORGANIZACION.md`). Luego etapas 1, 4 y 5.

## Para la revisión crítica
- Marca de transacción `dromux.production_job` (alternativa: tabla privada); `private.issue_production_material` sin uso.
- `create_company` lo puede llamar cualquier usuario autenticado; quien ve producción lee fórmulas por tabla; el operario lee permisos de otros roles de su empresa.
- HI-005 (`private` no expuesto), URL del sitio y respaldos en Supabase nuevo.

## Observaciones abiertas (no bloquean)
- Sin tope a la cantidad fabricada que declara un operario (decide el propietario).
- Cuentas por cobrar avisa «cobros anteriores a la devolución» aunque ya se reintegró.
- Porcentajes con punto decimal; avisos con «10.000000 kg»; la grilla de permisos no indica módulos no contratados.
- Inicio puede tardar ~1 min en reflejar órdenes nuevas («Actualizar» lo resuelve).
- Plantilla Excel con ejemplos de un solo rubro (D-006): etapa 4.
- «OF n» vs código `OP`; zona horaria fija en alertas; precios de Ventas no consultan el módulo.

## Pendiente anterior (sigue vigente)
- H-UX4 y Roles en 360 px; `post_stock_operation` a fondo; H-011b (precios en órdenes de compra: decide el propietario); H-008, H-010, H-012, H-003, H-002; P2 de la 047 y 048.
- Manual y presentación de `docs/cliente` (actualizar). Revisión crítica de Ventas.

## Decisiones vigentes
- D-008/D-009: español en tablas, columnas y valores; funciones en inglés. Cambios de base solo como archivo en `cambios/` y registrados. Opus analiza y planifica; Sonnet ejecuta.
- D-010: operario entrega y termina desde la orden; cancelar exige «Gestionar» (órdenes). «Gestionar» además en Pedidos internos.
- Textos visibles sin cambios; nombres del frontend se traducen en la etapa 1.
- El propietario aplica los SQL (conectores solo lectura) y hace o confirma los commits.
- Empresa nueva: módulos `stock` y `produccion`; se cambian solo desde el SQL Editor. Sin invitaciones. Altas de usuarios y empresas MANUALES.
- Costos solo administrador o permiso explícito. Stock: ver por pantalla; crear/editar/eliminar = módulo completo (excepción D-010).
- Reposición, ¿Alcanza? y existencias en órdenes exigen «Stock por depósito». Estadística cuenta terminadas aunque estén archivadas.
- D-005 paleta, D-006 multirrubro, D-007 volumen. IVA: precios sin IVA, informativo en la venta.

## Datos de sesión
- Nunca pasar contraseñas: el propietario inicia sesión en el panel del navegador. Campos React: setter nativo + evento.
- En el shell NO usar heredocs, `cat >` sin entrada, `awk` con `exit` ni `node -e` largos con comillas anidadas (se cuelga).

## Regla de mantenimiento
Reemplazar este resumen al avanzar; máximo 100 líneas. No marcar algo resuelto sin evidencia.

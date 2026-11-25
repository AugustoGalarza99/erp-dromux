# Estado — cierre de sesión 25/11/2026: 047b y 048 aplicadas y verificadas; operario y vendedor reales probados; Stock simplificado

## Resumen en una frase
Foco: dejar PRODUCCIÓN, costos, stock y Ajustes listos para que el primer cliente empiece a probar (sin ventas ni clientes). Migraciones 035–048 + 046b + 046c + 047b APLICADAS por el propietario. Seguimiento: `docs/ai/AVANCE_FASES.md` (leer primero) y `PROMPT_PROXIMA_SESION.md`.

## Evidencia y entorno
- Repo `main`; cambios de esta sesión SIN commit (el propietario confirma el commit). Base: proyecto `drcexqsewiwfhiowrgtv` (conector de solo lectura). App local en `localhost:5174` (el puerto puede variar). Empresas de prueba: Dromux ERP, Espacio Demo, Metalurgica Cerquatti (ids en AVANCE_FASES).
- VERIFICADO 25/11 (evidencia/2026-11-25_operario_real.md): usuario OPERARIO y VENDEDOR reales en Espacio Demo (menú con candados, Inicio restringido, rutas directas bloqueadas, sin costos en pantalla); PDF de la orden sin costos (contenido decodificado y descarga confirmada por el propietario); cierre con stock insuficiente falla completo; reintento tras corte simulado no duplica; rol de una sola pantalla ("User": solo Inicio) e historial de accesos OK; sin desborde horizontal a 360/720/768 px (script).
- VERIFICADO 25/11: script `pruebas_roles_empresas.sql` completo tras 047b y 048: 0 FALLA; caso 336 = PASA; grupo 13 todo PASA (INFO: 352, 354, 361, 369 con filas). `048_comprobaciones` replicadas en la base (solo lectura): sin políticas de lectura con el módulo `stock`; solo `issue_sale_delivery_note` conserva stock/read (lote de Ventas); seguridad de funciones intacta; `cleanup_target` por pantalla y no ejecutable por la API; 9 pantallas exigidas; copias de deshacer 12/11/34; 0 roles con `inventory:read` sin stock.
- Frontend (build OK): aviso de dependencias en Roles (¿Alcanza?, Reposición y Órdenes piden «Stock por depósito»; botón para agregarlo) y regla de Stock en Roles probados en pantalla; cambio de rol con diálogo propio probado; navConfig/Inicio/Archivados con permisos por pantalla de Stock.

## Hecho al cierre de la sesión
- Decisión Stock (25/11): VER = por pantalla; CREAR/EDITAR/ELIMINAR en Stock = acceso COMPLETO al módulo (todos los movimientos comparten control y quedan con `actor_id`). Roles lo explica y lo aplica solo (marcar Crear/Editar/Eliminar en una pantalla de Stock da todo el módulo; desmarcar quita las escrituras). LA 048b YA NO HACE FALTA.
- Interfaz: el error del cierre de orden se ve DENTRO del diálogo (verificado solo por código, no en pantalla); mensaje de pérdida de conexión claro ("reintentar no la repite"); cambio de rol con diálogo propio (sin `window.confirm`).
- C-013 (revisión de código): productionJobPdf, deliveryNotePdf y quotePdf (solo precios finales) sin costos; orderPdf (orden de compra) imprime el precio unitario del proveedor = costo de materiales: ligado a H-011b (decisión pendiente del propietario: ¿quién puede ver/descargar precios de órdenes de compra?). "Deposito | Deposito" en el PDF del operario = no puede leer Depósitos (dar «Depósitos: ver» si debe verse); no es defecto.
- Guardia 8 (funciones sin chequeo visible): lista conocida = precios e importación (helpers `private.price_require_*`, `prepare_item_import`), soporte (`begin_support_session`), `rls_auto_enable`.

## Pendiente (en este orden; el prompt de la próxima sesión lo reproduce)
1. PROPIETARIO: publicar frontend y commit. (HECHO esta sesión: operario real tras la 048 verificado en pantalla — «Stock por depósito» visible con saldos 50/68/37/145, «¿Alcanza?» funciona, Movimientos y Remitos con candado; para eso hubo que cambiar el frontend que seguía pidiendo `can('stock','read')` de módulo: rutas, Órdenes, Alcanza, Reposición, Planificación, ficha de ítem, Resumen de stock, Compras (pronóstico) y remitos ahora usan `stock_levels`. Quedan con módulo completo a propósito: recibir mercadería (stock insert+read) y Ventas.) Pendiente de ver con una orden ACTIVA que el operario ve «Asignado» (no había órdenes activas; lo cubre el caso 361 del script).
2. HECHO por el propietario: orden de 200 insumos, listas 200+ y revisión visual a 1024/1440. Pendiente: concurrencia (HI-001) y corte de red REAL.
3. La ayuda inicial ocupa casi toda la pantalla a 360 px (H-UX4); tablas de Roles en 360 sin revisar a ojo.
4b. Entregable al cliente: `docs/cliente/Dromux_ERP_Presentacion.pdf` (6 páginas: qué incluye hoy, cómo empezar, qué no está, hoja de ruta corto/mediano/largo plazo; fuente editable `presentacion.html`, se regenera con Edge `--headless=new --print-to-pdf`). Compras figura "en validación" y Ventas/Finanzas como "corto plazo": actualizar el PDF cuando cambie el alcance.
4. Fase 2a restante: leer a fondo `post_stock_operation`; H-011b (precios en purchase_order_lines / orderPdf); HI-005 (esquema `private` expuesto, confirmar en el panel de Supabase); H-008 (rutas sin puerta); H-010, H-012, H-003, H-002; P2 de la 047 (production_formula_cost sin pantalla, recalculate_production_reservations, erp_company_profile) y de la 048 (deshacer sin comparar cambios posteriores).
5. Lista de lanzamiento (erp-validar): guía corta en lenguaje simple, respaldo, usuarios/roles reales a mano, qué NO está listo (Ventas, Clientes, Finanzas, Reportes) y cómo ocultarlo.
6. Lote de Ventas (sesión aparte, revisión crítica obligatoria): precios y márgenes con costs_production, price_require_*, erp_admin_*, remito de venta; luego Finanzas L6 y Reportes L7.

## Decisiones vigentes
- Costos: `costs_materials` y `costs_production` = admin o permiso explícito por rol; el Vendedor no los tiene. Márgenes/listas de Ventas: admin + finanzas hasta su lote.
- Roles y usuarios solo del administrador; módulos y pantallas sin permiso se ven bloqueados (candado); "Gestionar" solo en Pedidos internos. Cada dueño de empresa arma los accesos de sus empleados desde Roles (sin roles a medida del soporte): la interfaz avisa las dependencias.
- Reposición, ¿Alcanza? y ver existencias en órdenes exigen «Stock por depósito» (servidor + aviso en Roles).
- Stock: ver por pantalla; crear/editar/eliminar = módulo completo (Roles lo aplica solo). No habrá 048b.
- Estadística de producción cuenta órdenes terminadas aunque estén archivadas; las canceladas no.
- Alta de empleados, cuentas y empresas MANUAL hasta el lanzamiento comercial (HI-002/HI-003 diferidos).
- Pruebas en el MISMO proyecto con 3 empresas de prueba, sin datos reales; Claude opera por pantalla solo en Espacio Demo con la sesión del propietario; los scripts con suplantación los corre el propietario. Nunca aplicar migraciones sin autorización; aplicar con la app CERRADA (la 048 dio deadlock con la app abierta; ahora toma bloqueos ordenados con lock_timeout).
- D-005 paleta por módulo, D-006 multirrubro, D-007 volumen. IVA: precios sin IVA, informativo en la venta.

## Riesgos
- Cierre de órdenes con muchos ajustes toma el bloqueo de reservas de la empresa (tope 300 ajustes): medir con volumen.
- Ventas toca dinero: no tocar `post_sale` ni cobros sin revisión crítica.

## Datos de sesión
- Arnés: app local con la sesión del propietario en el panel; para sesiones de otros usuarios el propietario cierra e inicia sesión en el panel (nunca pasar contraseñas). Los campos controlados por React no responden a `value=` por script: usar el setter nativo + evento `input`/`change`, o escribir con el teclado.
- El conector de la base es de solo lectura. En el shell evitar heredocs/comillas complejas y backticks: usar la herramienta de archivos.

## Regla de mantenimiento
Reemplazar este resumen al avanzar; máximo 100 líneas. Preservar decisiones vigentes y próximo paso. No marcar algo resuelto sin evidencia.

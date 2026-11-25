# Fase 1 — recorrido ejecutado por Claude en Espacio Demo (24/11/2026, en curso)
Entorno: app local (localhost:5173) contra el proyecto de Supabase del propietario, empresa Espacio Demo, usuario admin Demo (sesión iniciada por el propietario). Datos de prueba genéricos; sin capturas guardadas en archivo (verificado por pantalla y texto de página).

| Paso | Resultado | Detalle |
| --- | --- | --- |
| 1 Unidades, depósitos, categorías | OK | kg/l/un; Central y Secundario; Materias primas, Envases, Productos terminados |
| 2 Ítems M1 (con costo, sin lote), M2 (lote), E1 (insumo/envase), P1 (producto) | OK | Código repetido M1 se rechaza ("Fila 2: el código M1 ya existe o está repetido") |
| 4/5 Ingreso manual de stock | OK | M1 +100 kg (doble clic = 1 solo movimiento, saldo 100), E1 +200 u, M2 +50 l (lotes activados con saldo inicial) y +30 l con lote LOTE-A1 y vencimiento |
| 3 Operario sin costo | PENDIENTE | requiere usuario operario (no disponible en esta sesión) |
| Resto (fórmula, órdenes, cierre, estadística, cancelación) | PENDIENTE | |

## Defectos y mejoras detectados
- D1 Unidades: el código rechaza mayúsculas con el mensaje genérico del navegador ("Utiliza un formato que coincida con el solicitado") y sin ayuda visible; conviene aclarar "solo minúsculas, números y guion bajo" o convertir a minúsculas.
- D2 Unidades: tras crear, el campo Código conserva el valor hasta que termina de guardar; mientras guarda (varios segundos) los campos siguen editables.
- D3 Texto "Nueva depósito" (concordancia) en Depósitos.
- D4 Alta de ítem: el error de código repetido dice "Fila 2" aunque es un solo formulario.
- D5 (D-006 multirrubro) El placeholder del nombre del ítem es "Ej.: Dióxido de titanio rutilo" (rubro pinturas); usar un ejemplo neutro.
- D6 Guardar es lento (3-5 s) en altas de catálogo; revisar tiempos de respuesta.

## Avance (2da parte, misma sesión)
| Paso | Resultado | Detalle |
| --- | --- | --- |
| 6 Fórmula P1 (base 100 l: M1 20 kg, M2 30 l, E1 100 u) | OK | Versión 1; costo estimado por unidad $400,00 = (20×1000 + 30×500 + 100×50)/100, coincide con el cálculo a mano |
| 7 ¿Alcanza el stock? | OK | 100: "hay stock libre suficiente" (la tabla de componentes queda sin filas, ver D8); 1000: falta E1 800 u y M2 220 l, M1 también (3 componentes) |
| 11 Crear orden (en cola, sin envasado) | OK | OF 1 · Producto 1 · 100 l; reserva 100 u/30 l/20 kg asignada, insumos pendientes 3 de 3 |

Nuevos defectos
- D7 (importante, tablet): con el contenido en ~750 px (ventana angosta con menú lateral abierto) el buscador "Agregar componente" de Fórmulas se comprime a ~20 px y el texto se parte letra por letra; la barra "Tenés cambios sin guardar" tapa el formulario. A 1440 px funciona.
- D8: "¿Alcanza el stock?" con stock suficiente muestra los encabezados de la tabla de componentes sin filas.

## Avance (3ra parte): orden de fabricación OF 1
| Paso | Resultado | Detalle |
| --- | --- | --- |
| 11 Iniciar orden | OK | "Fabricación iniciada" |
| 12 Remito de entrega para fabricación (3 insumos, 20 kg / 30 l / 100 u) | OK con 1 DEFECTO | Con el lote LOTE-A1 (reservado por la propia orden) el servidor responde 400 "Stock libre insuficiente en el depósito y lote elegidos" aunque la pantalla muestra "LOTE-A1 · 30 disponibles". Con el lote "Inicial" se confirmó: 3 salidas (E1 −100 u, M2 −30 l lote Inicial, M1 −20 kg), saldos E1 100, M2 50, M1 80 |
| 12/16 Doble confirmación (dos clics seguidos por programa) | OK | solo se registraron 3 movimientos, sin duplicados |

DEFECTO H-E1 (importante, P1 funcional): no se puede entregar a la orden el insumo que ella misma tiene reservado en un lote cuando ese lote queda 100% reservado; la lista de lotes dice que hay disponibles y el servidor lo rechaza. Esperado: la entrega para una orden descuenta primero su propia reserva. Reproducir: M2 con lote LOTE-A1 (30 l) y lote Inicial (50 l); OF de 100 con M2 30 l; la reserva toma LOTE-A1; entregar 30 l de LOTE-A1 → error. A revisar en `issue_delivery_note` (cálculo de stock libre que no excluye la reserva de la propia orden) con el revisor crítico, sin tocar la base sin autorización.
Nota de la prueba: el error 400 no se muestra al operario como mensaje visible en el diálogo (no se vio aviso al fallar; el diálogo quedó abierto) — verificar (D10).

## Avance (4ta parte): cierre de OF 1 (INTERRUMPIDO)
| Paso | Resultado | Detalle |
| --- | --- | --- |
| 14 Cierre (b)+(d): salió 95 de 100 l, Material A usó 22 kg (de más), Material B usó 28 l (de menos), lote FAB-001 | PARCIAL | La pantalla calcula bien las diferencias: "Salió de menos: 5 l (5,0 %)", resumen de confirmación "Ingresa 95 l de Producto 1 (Central, lote FAB-001) · Descuenta 2 kg de Material A · Devuelve 2 l de Material B al stock", motivo de la diferencia obligatorio |
| 14 Confirmar y mover stock | RECHAZO correcto del servidor | P1 no usa lotes: "Este producto no usa lotes; dejá lote y vencimiento vacíos" (aviso visible en pantalla). No se movió stock |
| 15-19 | PENDIENTE | OF 1 sigue "En proceso" con los 3 insumos entregados (stock M1 80 kg, M2 50 l, E1 100 u); falta cerrar sin lote, reintentos, estadística, cancelación y archivado |

Defectos nuevos
- D9: en el remito de entrega el cartel "Disponible" muestra "0" un instante antes de cargar (parpadeo engañoso).
- D10: el campo "Lote del producto (no aplica)" del cierre queda editable aunque el producto no use lotes; debería estar deshabilitado o no mostrarse.
- D11: tras el rechazo del servidor el diálogo de cierre se cerró y se perdieron las cantidades cargadas (a confirmar: puede haberse cerrado por la prueba); debería quedar abierto con los datos.
- Limitación de la prueba: con la ventana emulada a 1440 px los clics por coordenadas no acertaban; se operó con referencias y eventos de entrada. No se probó impresión de PDF ni el usuario operario/vendedor.

## Correcciones aplicadas en el código (misma jornada, sin commit)
- H-E1: causa verificada (post_stock_operation solo descuenta la reserva propia si existe la variable `dromux.production_job`, y ninguna función la fija). Corrección preparada: `supabase/046c_entrega_con_reserva_propia.sql` (+ deshacer + comprobaciones). NO aplicada; en revisión crítica.
- D1 código de catálogos: se escribe en minúsculas solo, con ayuda visible y título explicativo. D2: el formulario se deshabilita mientras guarda. D3: "Nuevo depósito". D4: se oculta "Fila N" en el alta de un solo ítem. D5: ejemplo neutro de nombre de ítem. D7: el buscador de componentes de Fórmulas ya no se comprime en columnas angostas. D8: ¿Alcanza el stock? sin tabla vacía y con botón "Ver el detalle de los N componentes". D9: "Calculando disponible…" en vez de 0. D10 era falso (el campo ya está deshabilitado en productos sin lotes; yo lo había escrito por script).
- Pruebas: los 2 FALLA del grupo 11 (237 y 243). 237 era consecuencia esperada de la 046b (el precio de proveedor exige costs_materials): la prueba se separó en "con costs_materials" (permitido) y "sin" (denegado). 243 (crear orden con crear/editar) queda por diagnosticar: el ayudante ahora devuelve el mensaje real del servidor.

## Avance (5ta parte): cierre de OF 1 y estadística
| Paso | Resultado | Detalle |
| --- | --- | --- |
| 14/15 Cierre con diferencias (95 de 100 l, M1 22 kg, M2 28 l, sin lote en P1) | OK | RPC finish_production_job_adjusted 200; movimientos: P1 +95 l (Central), M2 +2 l devolución al lote Inicial, M1 −2 kg. Saldos finales M1 78, M2 52, E1 100, P1 95 = cálculo a mano |
| 18 Estadística (mes en curso) | OK | 1 orden terminada, producido 95 l, previsto 100 l, diferencia −5,0 %, promedio 3,96/día, aparece en la tabla por día y por producto |
Pendiente de la Fase 1: reintento con corte de red, cierre con stock insuficiente (paso 17), cancelación con insumos entregados, archivar/recuperar, devolución de sobrante aparte, envasado, PDF, orden de 200 insumos, usuarios operario/vendedor.
Revisión crítica de 046c: "aplicar" sin P0/P1; P2-b (guarda del deshacer) incorporado; P2-a (limpia a vacío) documentado.

## Avance (6ta parte): verificación de 046c y cancelación
- 046c aplicada por el propietario (comprobación: 2 copias). Prueba funcional en pantalla: OF 2 (100 l) reservó LOTE-A1 (30 l) al 100 %; el remito de entrega con ese lote ahora responde 200 (antes 400 "Stock libre insuficiente"). Doble confirmación seguida: 2 respuestas 200 pero SOLO 3 movimientos (E1 −100, M2 −30 lote LOTE-A1, M1 −20); saldos E1 0, M2 22, M1 58. **H-E1 CERRADO y verificado.**
- Paso 19 (parte 1): cancelar OF 2 con insumos entregados se rechaza con mensaje claro "Devolvé todos los insumos pendientes antes de cancelar la orden" y aviso visible. Falta: devolver los insumos y cancelar, archivar/recuperar.
- Script de pruebas (rerun tras 046/046b/046c): único FALLA = caso 244 "crear orden con crear/editar" → "permission denied for function create_purchase_order": esa función NO tiene EXECUTE para la API (correcto; la app usa create_purchase_order_once). Era un error de la prueba: ahora usa `create_purchase_order_once` (los casos "denegado" que usaban la otra función eran falsos positivos; ya no). Hay que re-correr el script. INFO: fila 271 (Vendedor lee supplier_items) = 0 filas → precio de proveedor cerrado también por tabla.
- Estado de la OF 2: En proceso, con insumos entregados (no cancelada).

## Avance (7ma parte): devolución y cancelación (paso 19)
- Devolución de los 3 insumos de la OF 2 (100 u, 30 l, 20 kg): return_production_material 200 ×3. Cancelación con motivo: cancel_production_job 204; la orden pasó a "Órdenes finalizadas o canceladas (2)".
- Saldos tras cancelar = saldos antes de crear la OF 2: E1 100 u, M1 78 kg, M2 52 l, P1 95 l. **Paso 19 OK** (parte rechazo + parte devolución/cancelación).
- Re-corrida del script de pruebas del propietario: seguía el FALLA del caso 244 con el mismo mensaje porque se ejecutó una copia anterior del archivo; el archivo del repositorio ya usa create_purchase_order_once. Hay que copiar el archivo de nuevo.

## Avance (8va parte): script de pruebas, archivado y envasado
- Script de pruebas (copia nueva, tras 046/046b/046c): 0 FALLA. El caso 244 ahora PASA (create_purchase_order_once). Solo INFO: 149/150/264 (los costos de ítems los ve quien tiene el permiso: esperado), 159/160 (H-007: ahora rechazado con error), 271 (Vendedor lee 0 filas de supplier_items).
- Archivar/recuperar (paso 19, segunda parte): OF 2 cancelada se archivó con confirmación ("Podés recuperarlo en Archivados") -> cleanup_record 200; en Ajustes > Archivados (pantalla rediseñada) apareció "OF 2 · Producto 1" y "Recuperar" -> restore_archived_record 204; volvió al listado. OK.
- Devolución al lote de origen: la devolución de M2 volvió a LOTE-A1 (30 l) y la del cierre al lote Inicial. OK (paso 13).
- Envasado: se crearon 2 presentaciones neutras (Bidón 1 l, Caja 10 l: save_production_packaging_type 200); OF 3 (50 l) creada con envasado previsto 30 bidones + 2 cajas (create_production_work_order 200); "Envasado y controles" muestra ambas presentaciones con lo previsto. OK. OF 3 queda EN COLA (reserva E1 50, M2 15, M1 10) para seguir probando.
- Lo único de la Fase 1 que NO se pudo probar sin intervención humana: PDF (descarga de archivo), usuarios operario/vendedor (pasos 3, 8, 10), corte de red real (paso 16), orden con 200 insumos (paso 11).

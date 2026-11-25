# Evidencia — usuario OPERARIO real (Espacio Demo, 25/11/2026)
Entorno: app local (localhost:5174), sesión iniciada por el propietario como operario@ (rol "Operario", plantilla Operario de planta). Datos de prueba.

| Prueba | Resultado |
| --- | --- |
| Menú: Ventas, Finanzas, Reportes y Ajustes con candado; Stock, Producción y Compras abiertos | OK |
| Inicio: tarjetas de ventas, cobros, tesorería y ganancia con "Acceso restringido" | OK |
| Rutas directas /settings/roles, /finance/costs, /production/formulas, /purchases/orders, /inventory/stock, /inventory/movements | OK: "Acceso restringido" |
| /production/orders, /inventory/items, /purchases/requests | Abren; sin "$", costo, margen ni ganancia en el texto de pantalla |
| Ficha de ítem (Material A): sin costo; el bloque "Costo de referencia" solo informa quién lo gestiona | OK |
| PDF de la orden (OF 3), capturado y decodificado: material, previsto, unidad, envasado, controles | OK: SIN costos ni precios |

## Hallazgos
- H-O1 (P1, hipótesis fuerte): con Stock parcial (Ítems + Stock por depósito) el servidor aún exige el módulo Stock completo (falta la 048). Consecuencias vistas: en la ficha "Tu rol no consulta existencias"; en la orden OF 3 "Insumos de la fórmula · 0 de 3 cubiertos", "Asignado 0" y "Falta 50 u / 15 l / 10 kg" aunque hay stock (E1 100, M2 52, M1 78 según la Fase 1). Un operario vería faltantes falsos. Confirmar como admin que OF 3 muestra asignado y cerrarlo con la 048.
- H-O2 (P3): el PDF imprime "Deposito | Deposito" (nombre del depósito); verificar como admin si es dato o falla de lectura.
- H-O3 (P3): el cambio de rol en Usuarios usa window.confirm (no funciona en el panel del navegador); reemplazar por diálogo propio.

# Usuario VENDEDOR real (vendedordemo@, rol "Vendedor" = plantilla Vendedor: Inicio, Ítems, Stock por depósito, Ventas)
| Prueba | Resultado |
| --- | --- |
| Menú: Producción, Compras, Finanzas, Reportes y Ajustes con candado; Stock y Ventas abiertos | OK |
| Inicio: Producción "Acceso restringido"; cobros, tesorería y ganancia restringidos; acciones rápidas de producción con candado | OK |
| Rutas directas /production/orders, /production/formulas, /purchases/requests, /finance/costs, /settings/users | OK: "Acceso restringido" |
| /inventory/items, /sales, /sales/lista-precios: sin "costo", "margen" ni "ganancia" en el texto (no hay listas de precios cargadas: prueba con datos pendiente) | OK sin datos |
Pendiente: ver Ventas con listas de precios y presupuestos cargados (el PDF de presupuesto, quotePdf.js, no se probó) y el efecto de H-O1 (Stock parcial) en este rol.

# Admin Demo (25/11): confirmación H-O1, cierre con stock insuficiente y reintento tras corte
- H-O1 CONFIRMADO: el admin ve en OF 3 "Asignado 50 u / 15 l / 10 kg"; el operario veía "Asignado 0" (lectura de reservas bloqueada por Stock parcial). Cierra con la 048.
- Paso 17 OK: cierre de OF 3 con Material A usado = 1000 kg (stock 78): el servidor responde "Stock libre insuficiente en el depósito y lote elegidos"; saldos E1 100 / M1 78 / M2 52 / P1 95 y 16 movimientos antes y después; la orden sigue en proceso; el diálogo conserva los datos al "Volver a editar" (D11 resuelto).
  - Defecto UX (P2): el mensaje de error aparece DETRÁS del diálogo de confirmación (el aviso queda tapado por la capa); debería mostrarse dentro del diálogo.
- Paso 16 OK (corte simulado: se interceptó la respuesta de la llamada de cierre tras llegar al servidor): 1er intento aplicado en servidor (+4 movimientos: P1 +50, E1 −50, M1 −10, M2 −15; saldos 50/68/37/145), la pantalla mostró "No pudimos completar la operación. Comprobá tu acceso…" (engañoso: la operación SÍ se aplicó). Reintento con el mismo botón: 200 y 0 movimientos nuevos (20 en total); diálogo cerrado. No duplica.
  - Defecto UX (P2): el mensaje ante pérdida de conexión debería decir "Revisá tu conexión; si ya se aplicó, no se repite", no "Comprobá tu acceso".
  - Limitación: el corte se simuló con un interceptor en la página, no con red real.
- OF 3 quedó COMPLETADA (50 l). Estado de prueba: E1 50, M1 68, M2 37, P1 145.

# Rol de una sola pantalla (revisión en base, solo lectura) y verificación visual automática
- Rol "User" (Espacio Demo): único permiso `dashboard:read` (solo Inicio), 0 personas hoy (el propietario lo probó entrando con él antes de pasarle Operario/Vendedor). El historial de accesos registró creación, renombre y cambios de rol (role_created, role_updated, member_updated con before/after): OK.
- Operario: dashboard, items, production_overview/orders(read, update)/availability, purchase_requests(insert, read), stock_levels:read; sin costs_*. Vendedor: dashboard, items, sales(insert/read/update), stock_levels:read; sin costs_*. Coinciden con lo probado en pantalla.
- Limitación: "Inicio" solo prueba la puerta del menú; las pantallas únicas de Producción (p. ej. solo Estadística) se prueban a nivel servidor en el grupo 12 del script (casos 310–313, PASA), no con usuario real.
- PDF de la orden descargado por el propietario: sin costos (confirmado).
- Verificación visual por script (sin captura fina) a 360, 720 (≈ 1440 con zoom 200 %) y 768: 21 rutas a 360 (Inicio, Ajustes, Producción, Stock) y 9 a 768 y 5 a 720 sin desborde horizontal de página ni controles aplastados (el único campo angosto es el selector 12/24/48 de paginación). Pendiente: revisión humana de aspecto a 1024/1440 y de las tablas de Roles en 360.

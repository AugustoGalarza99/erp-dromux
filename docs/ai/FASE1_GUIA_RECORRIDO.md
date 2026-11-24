# Fase 1 — Guía del recorrido completo (para ejecutar en la app real)

Cómo usarla: marcá cada paso con OK / FALLA y anotá lo que viste. Si algo falla, pegame el mensaje exacto y la pantalla. Se prueba en este mismo proyecto (sin producción todavía). Usar nombres genéricos y datos inventados; no cargar datos de clientes reales.

## Preparación (una vez)
- Cuentas: 1 admin (la tuya), 1 usuario "operario" y 1 usuario "compras" (emails de prueba tuyos). Crearlos en Supabase Auth y asignarles rol desde Ajustes → Usuarios (si la pantalla no permite el alta, decime: es HI-003).
- Empresa A (la actual) y Empresa B (segunda empresa de prueba, con otro usuario admin). Sirve para la Fase 2c.
- Roles de prueba en Empresa A: "Operario" (producción: ver/crear órdenes, stock: ver/ingresar; SIN finanzas, SIN compras), "Compras" (compras, pedidos internos, ítems; SIN producción).
- Antes de empezar: anotar saldos iniciales de cada ítem que vayas a usar.

## A. Catálogos y alta de ítems
1. Unidades (kg, l, u, caja), depósito "Central" y "Secundario", categorías (OK / FALLA).
2. Materia prima M1 (con costo, sin lote), M2 (con lote y vencimiento), consumible/envase E1 (con stock), y producto terminado P1. Verificar: código único (repetir código debe fallar), ficha, costo visible solo para admin y compras.
3. Con el usuario operario: abrir la ficha de M1 → no debe ver costo; crear un ítem con costo debe fallar.

## B. Ingreso de stock
4. Orden de compra a un proveedor → recibir parcial y total (compras); o ingreso manual con confirmación. Verificar saldo y movimiento (stock → movimientos).
5. Recepción repetida (doble clic / recargar y reenviar): no duplica.

## C. Fórmula y disponibilidad
6. Fórmula de P1 (lote de 100) con M1, M2 y E1; versión; con rendimiento opcional.
7. "¿Alcanza el stock?" para 100 y para una cantidad que no alcanza (debe marcar faltantes).
8. Costo de la fórmula: admin lo ve; operario no (ni en pantalla ni en PDF).

## D. Precios, márgenes y listas
9. Costo → margen → precio de venta de P1; lista de precios general y una derivada con descuento; simulador.
10. Cambio masivo con vista previa; historial del cambio. Con el rol operario/compras: no hay acceso a costos ni márgenes (pantalla y datos).

## E. Orden de trabajo
11. Crear orden de P1 (con envasado: 2 tipos de envase), iniciar, descargar PDF (sin costos). Probar también con una fórmula de 200 componentes.
12. Entrega de insumos por remito y un insumo "sin remito": confirmación visible, el stock baja una sola vez, saldo y movimientos coinciden.
13. Devolver un sobrante: confirmación; el stock sube en el depósito y lote de origen.

## F. Cierre
14. Terminar: (a) igual a lo previsto; (b) salió de menos; (c) salió de más; (d) usó insumo de más y de menos; con envases y resto sin envasar. Ver la alerta de confirmación y el resumen de movimientos.
15. Verificar: producto terminado ingresó con el lote; insumos ajustados; la orden figura terminada; stock final = cálculo a mano.
16. Reintentos: doble clic en "Confirmar y mover stock"; cortar la red y reintentar. No debe duplicar.
17. Cierre con stock insuficiente para un insumo adicional: debe fallar completo y la orden seguir "en proceso" sin movimientos nuevos.

## G. Estadística
18. Producción → Estadística: la orden aparece en mes, semana y en un rango personalizado; el total coincide con lo producido.

## H. Cancelación y archivado
19. Cancelar una orden con insumos entregados (debe pedir devolverlos); archivar y recuperar un registro (Ajustes → Archivados).

## Entregable
`docs/ai/evidencia/2026-11-XX_flujo_completo.md` con OK/FALLA por paso y los defectos encontrados (yo lo armo con lo que me cuentes). Criterio de cierre: los 19 pasos en OK dos veces seguidas y los saldos finales coinciden.

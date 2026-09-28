# Dromux Producción · hoja de ruta

**Objetivo:** operar una fábrica pequeña o mediana desde demanda, inventario y abastecimiento hasta orden, consumos reales, lote y costo final. Las ventas y los cobros permanecen como soporte comercial básico.

## Punto de partida: versión 023

Ya están implementados inventario y depósitos, compras, proveedores, fórmulas, semielaborados, fabricación y consumos reales, entregas parciales y devoluciones, remitos, venta básica, roles, guías, tablero operativo, avisos dinámicos de mínimo de stock y fechas de órdenes, y perfil personal.

Los avisos de stock de esta versión se calculan a partir de **stock físico total frente al mínimo configurado**; todavía no reservan existencias, proyectan consumo ni calculan días de cobertura. Las órdenes próximas son aquellas que vencen dentro de tres días; las atrasadas muestran prioridad crítica.

## Fase 1 · reservas y disponibilidad verdadera

- Definir los estados de stock: físico, reservado para órdenes abiertas, disponible libre y pendiente de ingreso de compras. La reserva nunca mueve stock físico; la entrega/consumo sí.
- Crear y liberar reservas en transacciones atómicas al confirmar, modificar o cancelar una orden. Evitar que dos órdenes reserven el mismo saldo.
- Añadir pantalla «¿Puedo fabricar X unidades para esta fecha?» con explosión de fórmula multinivel, semielaborados, depósitos, lotes y asignación a órdenes ya confirmadas.
- Mostrar por componente requerido, libre, reservado, faltante y fecha comprometida. Permitir un escenario de prueba sin modificar saldos.
- **Criterio de aceptación:** dos órdenes simultáneas no pueden reservar el mismo ítem. Cancelar una libera su reserva; una entrega parcial reduce reserva y físico sin contarlos dos veces.

## Fase 2 · proyección y alertas accionables

- Configurar por ítem plazo del proveedor, stock de seguridad, reposición y criterio de demanda: órdenes confirmadas y, cuando exista historial confiable, consumo promedio.
- Calcular cobertura: stock libre / consumo diario estimado. Si el consumo es cero o la muestra es insuficiente, mostrar «Sin estimación», nunca inventar días.
- Detectar riesgo por fecha cuando un pedido o una orden de fabricación necesita material antes de la entrega comprometida de compras.
- Avisos por material, lote y orden con detalle del cálculo, gravedad y vínculo a compra o reprogramación. Evitar avisos repetidos por el mismo estado.
- **Criterio de aceptación:** una compra recibida, una reserva, una devolución y una modificación de fórmula recalculan alertas y explican el resultado.

## Fase 3 · órdenes de trabajo dentro de la planta

- Definir etapas, responsables, estados, prioridad, tiempos previstos y reales, registro de detenciones y motivos.
- Registrar cantidad conforme, rechazo, merma y retrabajo por etapa; evaluar si el primer rubro requiere máquina, mantenimiento o control de calidad.
- Pantalla de operario sin precios ni datos administrativos; cierre supervisado y trazabilidad de ajustes.
- **Criterio de aceptación:** cada producto entregado puede relacionarse con orden, materiales, lote, etapa y responsable.

## Fase 4 · costos de fabricación y mejora continua

- Versionar fórmula; separar costo previsto, materiales realmente consumidos, mano de obra y costos indirectos. No reescribir el costo histórico de órdenes cerradas.
- Reporte por orden: rendimiento, desvío de cantidades, causa de merma, duración y costo real por unidad.
- Análisis de proveedores y demoras de abastecimiento; exportación de datos para el área contable.
- **Criterio de aceptación:** un aumento de insumos o caída de rendimiento se refleja en el costo de esa fabricación, con explicación y fecha.

## Fase 5 · comercialización a varios clientes

- Repetir pruebas con tres rubros productivos; definir una configuración inicial por rubro sin copiar lógica específica en cada empresa.
- Restauración real de backup, monitoreo, registro de auditoría, validación RLS entre empresas, procedimientos de soporte, importación inicial y salida de datos.
- Estandarizar capacitación, contrato, niveles de servicio y precio de implementación. Integrar facturación externa si el cliente necesita emitir comprobantes sin doble carga.

**Orden recomendado:** pilotear versión 023 con un fabricante, desarrollar fases 1 y 2 con sus datos reales, y recién después diseñar las etapas de la fase 3 según cómo trabaje la planta. Ser «el mejor» requerirá medir uso diario, errores, tiempos y valor ahorrado, además de sumar módulos.

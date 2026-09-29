# Dromux Producción · qué falta para lanzar

## Ya implementado

Compras, proveedores, stock físico por depósito y lote, fórmulas, semielaborados, fabricación con consumos y rendimiento reales, remitos, venta básica, costo de producto, perfiles, permisos, tablero, avisos de mínimos, simulación «¿Tengo stock?» y reservas por orden. En 025, las salidas independientes respetan la cantidad comprometida y los faltantes de órdenes generan avisos.

## Etapas restantes, en orden de dependencia

1. **Ubicación y trazabilidad de la reserva.** Reservar cantidades específicas por depósito y lote; verificar vencimiento y disponibilidad real antes de confirmar una orden. Permitir traslados propuestos y liberar/cambiar asignaciones sin romper movimientos históricos.
2. **Abastecimiento y cobertura.** Plazos de proveedor, compras pendientes y fechas reales de recepción; demanda confirmada y consumo histórico. Calcular «hasta cuándo alcanza» con muestra suficiente y mostrar «sin estimación» cuando no la haya. Generar sugerencias de compra y avisos por fecha.
3. **Órdenes de trabajo en planta.** Etapas, responsables, prioridad, tiempos reales, paradas, mermas, rechazo/retrabajo y controles de calidad. Vista de operario sin costos.
4. **Costos completos y reportes.** Mano de obra e indirectos, versiones de fórmula, costo teórico vs. real y causas de desvío, trazabilidad de insumos hasta lote entregado.
5. **Preparación comercial.** Piloto real con un rubro definido, pruebas de concurrencia y RLS, respaldo y restauración, importación/exportación, monitoreo, soporte y documentación. Integración con facturación del cliente cuando sea necesaria para evitar doble carga.

**Próximo desarrollo recomendado:** etapa 1 por depósito y lote. Requiere definir cuándo se elige el origen: al planificar, al confirmar la orden o al retirar materiales. Para el primer piloto se puede permitir sugerencia automática y ajuste manual antes de entregar.

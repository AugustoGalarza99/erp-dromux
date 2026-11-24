# Producción: cierre con ajustes, estadística e índices (migración 043 PREPARADA, NO aplicada)

## Hecho (local)
- `supabase/043_produccion_cierre_estadistica_indices.sql` + `reparacion/0_deshacer_043.sql` + `verificaciones/043_comprobaciones.sql` (incluye lista de pruebas de comportamiento).
- RPC nuevas: `production_output_summary` (día/semana/mes, rango libre, por unidad), `production_output_by_product` (paginada en servidor, búsqueda), `finish_production_job_adjusted` (cierre + entrega adicional/devolución de insumos + recuento de envases, una transacción, idempotente por request_id derivado). Reutiliza las funciones existentes sin modificarlas. Sin columnas de costo.
- 8 índices (H-003 parcial): jobs completadas, jobs por producto, events por issue_id y por componente, runs por producto, run_lines y formula_lines por componente, lotes por vencimiento. Base casi vacía: no se pudo medir con EXPLAIN; se justifican por patrón de consulta.
- Revisión crítica (subagente erp-revisor-critico, solo lectura): corregidos kind nulo, casts sin control, permiso de devolver previo, envases > fabricado, tope 300 ajustes. Pendiente (hipótesis): bloqueo de reservas por empresa durante cierres con muchos ajustes; reserva propia de la orden en un 'issue' (anterior a 043); `save_production_work_details` borra `unpackaged_quantity` y se puede llamar en órdenes terminadas; decidir si la estadística incluye órdenes archivadas (hoy sí).
- Frontend: pestaña Estadística (`/production/stats`: presets, rango personalizado, agrupar, comparación con período anterior, gráfico, tabla paginada, por producto con "ver evolución"); `FinishJobDialog` (real vs previsto, envases y resto sin envasar, insumos usados vs entregado paginados con efecto en stock, paso de confirmación con alerta); confirmación antes de entregar/devolver insumo.
- `npm run build` OK.

## NO verificado
- Migración no aplicada ni probada en base. UI NO probada en navegador (360/768/1024/1440, 200+ insumos): falta el arnés.
- Sin pruebas con 2 empresas y 3 roles; sin concurrencia real.

## Prueba de interfaz con arnés simulado (24/11, arnés borrado)
- Supabase simulado (Vite alias): 1 empresa admin, 220 insumos, orden en proceso con 220 líneas, 230 productos para la estadística. Anchos 360/768/1024/1440 sin desborde horizontal global.
- Estadística: presets, rango personalizado (agrupa por mes automáticamente), comparación con período anterior, gráfico, tabla paginada, por producto con paginación en servidor (230 → 10 páginas) y búsqueda. Corregido: promedio con 6 decimales (ahora 2) y etiquetas del gráfico encimadas en móvil.
- Cierre: 220 insumos paginados de a 10; "Igualar todo a lo previsto" y "Dar por usado lo entregado"; motivo obligatorio ante diferencias; resto sin envasar (100 − 50×1 − 9×5 = 5 kg); paso de confirmación con alerta; payload correcto a `finish_production_job_adjusted` (1 ajuste `issue`, envases 50 y 9). Agregado: bloqueo si hay más de 300 ajustes.
- NO probado: la RPC real (043 sin aplicar), lotes (insumo con lote en ajuste), diálogo de confirmación de entrega/devolución en navegador, impresión.

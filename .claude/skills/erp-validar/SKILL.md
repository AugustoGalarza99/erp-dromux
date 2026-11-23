---
name: erp-validar
description: Probar flujos productivos, permisos y condiciones de lanzamiento con evidencia reproducible.
---

Alcance: $ARGUMENTS. Usar Sonnet; escalar a Opus problemas de concurrencia/privilegios. Los comandos deterministas no necesitan un modelo más potente.
1. Leer scripts y pruebas existentes. Ejecutar build/lint/tests pertinentes; no inventar comandos npm ni instalar suites completas sin verificar necesidad. Datos sintéticos aislados en local/pruebas.
2. Matriz de negocio: proveedor/costo ARS-USD → OC/recepción parcial → stock/lotes → fórmula/plan/reserva → consumos/retornos/adicionales → salida real → remito → venta/cobro → devolución/anulación. Probar únicamente lo existente y registrar huecos.
3. Casos críticos: mínimo decimal, stock infinito, unidades kg/L/m/unidad, cotización histórica, importación con miles/centavos y duplicados, fabricación con faltante/lote, sobrantes y doble clic/reintento. No consumir dos veces al cerrar producción/remito.
4. Roles anon/admin/operario/vendedor/sin permiso, compañías A/B y suspendida: validar servidor, UI, PDF/exportaciones y Realtime. No simular RLS solo con mocks.
5. Concurrencia: dos usuarios consumen la última existencia o pagan el mismo saldo. Verificar atomicidad, ausencia de duplicados y respuesta recuperable ante conflicto/timeout.
6. UX: anchos definidos por erp-diseno, teclado, iPad, búsquedas por fila, modales y errores. E2E requiere navegador; guardar qué realmente se ejecutó.
7. Antes del piloto: probar instalación de migraciones desde cero y actualización con datos sintéticos; ensayo de backup/restauración, despliegue/reversión, monitoreo sin secretos y responsables del piloto.
Reporte: comando, entorno/commit, fecha, resultado, evidencia acotada, exclusiones y bloqueos. Puerta de salida: cero P0 confirmados abiertos; flujos/permisos críticos probados; recuperación ensayada; pendientes P1 aceptados explícitamente por responsable. "No probado" nunca significa "pasa".
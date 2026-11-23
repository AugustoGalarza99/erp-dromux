---
name: erp-feature
description: Implementar funciones industriales integradas sin duplicar stock, precios ni operaciones.
---

Petición: $ARGUMENTS. Leer requisitos pertinentes en PRODUCTO.md y decisiones vigentes.
1. Trazar flujo existente y fuente única de cada dato; definir aceptación, unidades, roles, estados, histórico y comportamiento al reintentar.
2. Resolver ambigüedades materiales; avanzar en lo independiente. Decidir migración compatible, autorización backend, interfaz y validaciones; no inventar columnas/RPC sin inspeccionar esquema.
3. Implementar una porción completa: persistencia, servicio, UI, Sonner, errores, empty/loading, ayuda breve y exportación si aplica. Mantener formato multilínea.
4. Proteger IDs, fórmulas versionadas, consumos netos, reservas, lotes y costos históricos. Densidad requiere unidades; no tratarla como rendimiento sin explicitar fórmula.
5. Migración nueva y verificable, nunca reescribir la aplicada. Preparar diagnóstico, validación y reversión o plan de recuperación; no aplicar automáticamente en remoto.
6. Verificar ruta feliz + permiso denegado + otra empresa + reintento + casos límite pertinentes. Concurrencia cuando afecta stock/dinero.
7. Actualizar instrucciones funcionales del módulo, tests y memoria. Usar erp-validar para el alcance afectado; no declarar listo todo el ERP por completar una función.
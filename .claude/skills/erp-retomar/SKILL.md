---
name: erp-retomar
description: Retomar Dromux y reconocer el repositorio sin repetir auditorías anteriores.
disable-model-invocation: true
---

Leer CLAUDE.md y docs/ai/ESTADO.md. Objetivo adicional: $ARGUMENTS.
1. Examinar estado del árbol de trabajo, scripts y rutas relevantes sin descartar cambios. Identificar entorno y permisos disponibles.
2. Primera sesión: leer PRODUCTO.md; inventariar módulos, fuentes de datos, migraciones, funciones, policies, grants y pruebas. Registrar versiones y comandos realmente disponibles.
3. Comparar historial SQL local con el esquema vigente si hay acceso de lectura autorizado. Inventariar todas las firmas/sobrecargas, triggers, vistas y tablas; usar consultas de catálogo paginadas. Documentar cobertura faltante.
4. Sesiones posteriores: leer diff y el próximo paso guardado; consultar cobertura solo del área afectada. No repetir inventario completo si no cambió.
5. Seleccionar un lote concreto de máximo tres problemas relacionados, por riesgo. Avanzar con trabajo local autorizado, no detenerse solo con una propuesta.
6. Primer arranque sin acceso suficiente: entregar inventario y consultas de diagnóstico preparadas, declarar el bloqueo y avanzar en evidencia local disponible.
Actualizar ESTADO.md al terminar. No leer dumps completos ni credenciales.
---
name: erp-optimizar
description: Reducir consumo de Supabase, consultas, cache y Realtime con medidas antes y después.
---

Alcance: $ARGUMENTS. Leer solo servicios y pantallas afectados; usar Sonnet.
1. Medir solicitudes por acción/tiempo, filas/columnas/bytes, duración y frecuencia; identificar refetches, N+1, listas ilimitadas, joins y conteos caros. No afirmar ahorro sin datos.
2. Proyectar columnas; paginar con orden estable y desempate ID. Para listas grandes evaluar cursor; mantener filtros/búsqueda en servidor e índices acordes. No sustituir paginación por descargar todo al navegador.
3. Revisar enabled, debounce, deduplicación, staleTime/refetch y claves por usuario/empresa/permisos. Invalidar lo afectado después de mutaciones. No usar Infinity ni cache persistente para esconder datos obsoletos; documentar invalidación/expiración.
4. Usar EXPLAIN y métricas sanitizadas; EXPLAIN ANALYZE ejecuta la consulta: solo entorno de pruebas para operaciones costosas o mutaciones. Índices con evidencia del plan y costo de escritura; no indexar cada columna.
5. Realtime solo donde la frescura lo exige: canal por alcance, cleanup y reconexión, coalescer invalidaciones; evitar suscripciones duplicadas y refetch global por cada evento. Comparar costo con refetch al foco o polling acotado.
6. Separar costo: compute/DB, conexiones, egress, Storage, Auth y mensajes Realtime. Estimar con volumen supuesto explícito; verificar cuotas/precios vigentes, no inferirlos del código.
Entregar antes/después, cambios, prueba de aislamiento/cache y riesgo de obsolescencia. Mantener consistencia de stock y costos por encima de reducir una petición.
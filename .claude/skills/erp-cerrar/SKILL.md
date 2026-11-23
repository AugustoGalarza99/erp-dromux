---
name: erp-cerrar
description: Guardar un resumen breve verificable y el siguiente paso antes de cerrar o compactar sesión.
disable-model-invocation: true
---

Guardar avance de la sesión; contexto adicional: $ARGUMENTS.
1. Revisar diff y resultados ya obtenidos, sin repetir toda la suite.
2. Actualizar docs/ai/ESTADO.md (máximo 100 líneas): objetivo, rama/commit si hay, cambios reales/rutas, pruebas ejecutadas/resultados, hallazgos abiertos, bloqueos, entorno autorizado y próximo comando/paso.
3. Actualizar COBERTURA/HALLAZGOS solo del área tocada. Registrar decisiones duraderas en DECISIONES sin duplicar todo el estado. No escribir razonamiento interno ni transcribir logs.
4. Separar realizado/verificado/propuesto/pendiente. No incluir credenciales, datos de clientes ni rutas personales innecesarias.
5. Entregar un prompt para la próxima sesión de hasta seis líneas. No crear commits, pushes, migraciones remotas ni despliegues por cerrar la sesión.
Si la sesión se interrumpe, la memoria puede quedar atrasada: al retomar contrastar con diff y pruebas, no confiar ciegamente en el resumen.
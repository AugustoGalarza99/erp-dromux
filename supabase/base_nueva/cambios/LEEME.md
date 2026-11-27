# Cambios a la base (desde el 26/11/2026)

La línea base (`../sql/`) ya está aplicada y no se edita. Todo agregado o corrección va acá como archivo nuevo.

## Archivos de cada cambio
| Archivo | Contenido |
|---|---|
| `NNN_modulo_descripcion.sql` | El cambio, entre `begin;` y `commit;` |
| `deshacer/NNN_modulo_descripcion.sql` | Cómo volver atrás |
| `comprobaciones/NNN_modulo_descripcion.sql` | Consultas de solo lectura y resultado esperado |

Ejemplo de nombre: `001_stock_importar_saldos.sql`. El número no se repite ni se reutiliza, y un archivo ya aplicado no se modifica: se corrige con otro.

## Pasos
1. Preparar los tres archivos, con nombres en español.
2. Probar en la base local (`pruebas/`).
3. El propietario lo aplica en el SQL Editor del proyecto nuevo, con respaldo si hay datos reales.
4. Verificar: comprobaciones y `sql/05_comprobaciones.sql` (ajustando los conteos esperados).
5. Regenerar el registro (`registro/documentar.mjs`), agregar las tablas nuevas a `registro/descripciones.json` y comparar `registro/huella.sql` en la base real con `registro/huella.json`.
6. Anotarlo en `registro/BITACORA.md`.

Si las huellas no coinciden, alguien cambió la base sin dejar archivo (o falta aplicar uno): resolverlo antes de seguir.

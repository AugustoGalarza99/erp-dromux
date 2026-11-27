# Base nueva en español (D-008, D-009)

Proyecto nuevo: `nummzswhycklmzbgacnl`. La base vieja (`drcexqsewiwfhiowrgtv`) no se toca.

## Carpetas
| Carpeta | Qué es |
|---|---|
| `registro/` | **Empezar acá.** Tablas por módulo, funciones, bitácora y huellas |
| `cambios/` | Todo agregado o corrección posterior (ver su LEEME) |
| `sql/` | Línea base, aplicada el 26/11/2026. No editar |
| `pruebas/` | Pruebas en la base local |
| `generador/`, `mapa.json`, `origen.csv` | Cómo se armó la línea base desde la base vieja |

## Cómo se aplicó la línea base (SQL Editor del proyecto NUEVO, en este orden)
1. `sql/01_estructura.sql`
2. `sql/02a_funciones.sql`
3. `sql/02b_funciones.sql`
4. `sql/03_permisos_y_datos.sql`
5. `sql/04_proteccion_rls.sql`
6. `sql/05_comprobaciones.sql` (solo lectura)

Cada archivo 01–03 es una transacción: si falla no queda a medias. Ante un error, parar y guardar el mensaje. Se aplica una sola vez sobre un proyecto vacío.

## Esperado en 05
76 tablas, 200 funciones, 79 políticas, 60 disparadores, 34 permisos, 0 tablas sin seguridad por filas, 1 función ejecutable por anónimo (`rls_auto_enable`, igual que antes) y 0 errores en funciones.

## Módulos por empresa
Una empresa nueva nace con `stock` y `produccion` activos. Para cambiarlo (solo el propietario del sistema, desde el SQL Editor):
```sql
update public.empresas
set modulos = jsonb_set(modulos, '{compras}', 'true')
where nombre = 'Nombre de la empresa';
```
El bloqueo actúa sobre los permisos (`private.has_permission`). No dependen de ningún módulo: inicio, ajustes, costos, ítems, unidades, categorías y depósitos. Las funciones que solo miran el rol administrador (precios de Ventas) todavía no consultan el módulo.

## Cambios de comportamiento respecto de la base vieja
- Valores en español (`materia_prima`, `en_proceso`, rol `administrador`, permisos `ver/crear/editar/eliminar`). Recursos de eliminar/archivar: `items, tipos_cambio, formulas, ordenes, fabricaciones, planes, remitos`.
- `my_company_access` devuelve además `company_modules`; el rol de soporte se llama `soporte`.
- Numeración de documentos en `empresas_numeradores`. La lista de precios de cada cliente es `ventas_clientes.lista_precio_id`.
- Sin invitaciones. `empresas` no se puede editar desde la aplicación.
- Funciones, parámetros `p_*` y claves devueltas siguen en inglés.

## Regenerar
`node supabase/base_nueva/generador/generar.mjs` (lee `origen.csv`, `mapa.json`, `generador/decisiones.json` y `generador/manual/`). No editar `sql/01–04` a mano. `generador/informe.json` debe quedar vacío.

## Pruebas locales (26/11)
Usan `@electric-sql/pglite` (dependencia de desarrollo; no toca Supabase ni se publica con la aplicación).
```powershell
npm run base:probar
```
```powershell
npm run base:registro
```
`cargar.mjs`: carga completa y 16 funciones SQL sin fallas. `revisar.mjs`: 684 consultas de funciones preparadas; 9 avisos revisados como falsos (valores NULL de la propia prueba, `tg_table_name`, operadores `~*`, alias implícitos). `flujo.mjs`: 66 de 66 pasos (empresa, stock, fórmula, orden, remito, borrar/archivar, compras, venta, presupuesto, rol sin costos, módulo apagado).

## Pendiente
- Adaptar la aplicación a la base nueva (todavía apunta y funciona solo con la vieja).
- Traducir y correr `verificaciones/pruebas_roles_empresas.sql`; revisión crítica (Opus) de permisos y módulos antes de producción.
- Usuario y empresa de prueba; plan con respaldos antes del uso real.

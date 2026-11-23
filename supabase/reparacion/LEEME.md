# Reparación de seguridad: qué ejecutar y en qué orden

Resultado de la auditoría de la base (20/11/2026) y los dos scripts que la corrigen. Todo se ejecuta en el SQL Editor de Supabase, cada archivo completo y de una sola vez. Cada script abre su propia transacción: si algo falla, no queda nada a medias.

## Antes de empezar
1. Confirmá que tenés un respaldo reciente (Supabase, Database, Backups) o descargá uno.
2. Hacelo en un horario con poco uso: los pasos son rápidos pero cambian funciones que el ERP usa al guardar ítems.

## PASO 1 — ejecutar ahora: `supabase/035_costos_funciones.sql`
Compatible con la versión actual del ERP publicada. Qué corrige:
- Un usuario sin acceso a costos podía **cambiar el costo de referencia** de un ítem (guardando o importando) y así alterar los costos de producción. Ahora solo admin o quien tenga permiso de Compras puede.
- `production_formula_cost` devolvía el **costo de fabricación** a cualquiera con permiso de producción. Ahora solo admin con permiso de Finanzas.
- Agrega funciones nuevas (`list_production_*`, `get_item_detail`) que usa la versión nueva del ERP. La versión actual no las usa.

Después de ejecutarlo, comprobá:
1. Corré `supabase/verificaciones/035_036_comprobaciones.sql` (solo lectura): las 8 funciones nuevas deben aparecer, con `anon_exec = false`.
2. En el ERP, como admin: abrí un ítem, cambiá la descripción y guardá. Después importá un Excel de prueba con 1 ítem.
3. Como usuario de producción sin Compras: abrí un ítem y guardá un cambio de nombre. Debe guardar y el costo debe seguir igual.
4. Si algo falla: ejecutá `supabase/reparacion/0_deshacer_paso_1.sql` y avisame.

## PASO 2 — ejecutar DESPUÉS de publicar la versión nueva del ERP: `supabase/036_costos_revocar.sql`
Cierra la lectura directa de costos por la API. Si lo ejecutás antes de publicar el frontend nuevo, las pantallas de producción y la ficha de ítem dejan de funcionar. Orden obligatorio: paso 1 → publicar el ERP nuevo (con tu procedimiento habitual de publicación) → recargar pestañas abiertas → paso 2 → `035_036_comprobaciones.sql`.

## Lo que NO se ejecutó ni se probó
- Ninguno de estos scripts se corrió en ninguna base todavía. Se escribieron a partir de la base observada, con transacción y cómo deshacer, pero sin una prueba previa. Por eso el respaldo y las comprobaciones.
- Este paso no cambia datos de clientes.

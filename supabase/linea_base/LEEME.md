# Línea base del esquema observado

`001_esquema_observado_2026-11-20.sql` reproduce la estructura de los esquemas `public` y `private` del proyecto remoto el 20/11/2026: 67 tablas, 144 funciones, restricciones, índices, RLS, 74 políticas, 51 triggers y permisos de `anon` y `authenticated`. No contiene datos ni credenciales. Se generó con consultas de solo lectura sobre los catálogos.

## Qué NO es
- No es una migración para aplicar en el proyecto real: ese proyecto ya tiene todo esto.
- No incluye el event trigger `rls_auto_enable` (requiere superusuario) ni los esquemas de Supabase (`auth`, `storage`, `extensions`): hay que cargarlo en un proyecto Supabase vacío o en Supabase local.
- No se probó que cargue sin errores: no había Docker ni `psql` en esta máquina. Puede requerir ajustes menores en el primer intento.
- No incluye 035 ni 036; el orden en la base de pruebas es: línea base → 035 → pruebas → frontend → 036.

## Cómo armar la base de pruebas (elegir una)
### A. Supabase local (recomendado; necesita Docker Desktop)
1. Instalar Docker Desktop y comprobar que `docker info` responde.
2. En la raíz del repo: `npx supabase init` (crea `supabase/config.toml`) y `npx supabase start`.
3. Cargar la línea base en el contenedor local (nombre del contenedor en `docker ps`, normalmente `supabase_db_<proyecto>`):
   `docker exec -i supabase_db_erp-dromux psql -U postgres -v ON_ERROR_STOP=1 < supabase/linea_base/001_esquema_observado_2026-11-20.sql`
4. Aplicar `supabase/035_costos_funciones.sql` de la misma manera.

### B. Segundo proyecto en Supabase Cloud (vacío, solo para pruebas)
1. Crearlo desde el panel (lo hace el propietario; puede tener costo según el plan).
2. Cargar la línea base y luego 035 con `psql` y la cadena de conexión de ese proyecto de pruebas, o pegándolos en el SQL Editor.
3. No usar nunca la cadena de conexión del proyecto real.

## Pruebas mínimas después de cargar (con datos sintéticos)
1. Crear dos empresas con `create_company`, y tres usuarios en la primera: admin, compras (`purchases:read`) y operario (`production:read`, `items:read`).
2. Con cada usuario, llamar `list_production_jobs`, `list_production_plans`, `list_production_runs`, `list_production_items` y `get_item_detail`: solo admin ve `unit_cost` y `estimated_cost`; admin y compras ven el costo de referencia.
3. Operario: `save_item_with_cost` y `import_items` no cambian costos; crear un ítem que no sea materia prima sin costo debe funcionar; una materia prima debe fallar con mensaje claro.
4. Un usuario de la segunda empresa no ve nada de la primera.
5. Aplicar 036 y repetir `supabase/verificaciones/035_036_comprobaciones.sql`.
6. Doble envío con el mismo `request_id` en ventas, cobros, recepciones y fabricación (lote P0 de concurrencia).

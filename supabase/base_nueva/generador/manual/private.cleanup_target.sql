-- Qué se puede eliminar o archivar: tabla, columna que identifica y permiso.
create or replace function private.cleanup_target(p_resource text)
returns table(table_name text, id_field text, permission text)
language sql
immutable
set search_path to ''
as $function$
  select t.table_name, t.id_field, t.permission from (values
    ('items', 'stock_items', 'id', 'items'),
    ('tipos_cambio', 'finanzas_tipos_cambio', 'id', 'compras_proveedores'),
    ('formulas', 'produccion_formulas', 'producto_id', 'produccion_formulas'),
    ('ordenes', 'produccion_ordenes', 'id', 'produccion_ordenes'),
    ('fabricaciones', 'produccion_fabricaciones', 'id', 'produccion_ordenes'),
    ('planes', 'produccion_planes', 'id', 'produccion_planificacion'),
    ('remitos', 'stock_remitos', 'id', 'stock_remitos')
  ) t(resource, table_name, id_field, permission) where t.resource = p_resource
$function$

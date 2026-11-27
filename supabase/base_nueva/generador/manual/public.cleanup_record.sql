create or replace function public.cleanup_record(p_company uuid, p_resource text, p_id uuid, p_action text)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare v_target record; v_preview jsonb; v_row jsonb; v_cost numeric;
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if auth.uid() is null or not private.has_permission(p_company,v_target.permission,'eliminar') then
    raise exception 'Sin permiso para retirar el registro' using errcode='42501'; end if;
  perform 1 from public.empresas where id=p_company and activo for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  execute format('select to_jsonb(t) from public.%I t where empresa_id=$1 and %I=$2 for update',v_target.table_name,v_target.id_field)
    into v_row using p_company,p_id;
  if v_row is null then raise exception 'El registro ya no existe'; end if;
  v_preview:=public.cleanup_preview(p_company,p_resource,p_id);
  if v_preview->>'action'='blocked' then raise exception '%',v_preview->>'message'; end if;
  if p_action is null or p_action<>v_preview->>'action' then raise exception 'Cambió el uso del registro. Reabrí la confirmación para revisar la acción'; end if;
  if p_action='archive' then
    if p_resource in ('items','tipos_cambio') then
      execute format('update public.%I set activo_antes_de_archivar=activo,activo=false,archivado=true where empresa_id=$1 and %I=$2',v_target.table_name,v_target.id_field)
        using p_company,p_id;
    else
      execute format('update public.%I set archivado=true where empresa_id=$1 and %I=$2',v_target.table_name,v_target.id_field) using p_company,p_id;
    end if;
    return 'archive';
  end if;
  if p_resource='items' then
    update public.compras_proveedores_items set preferido=false where empresa_id=p_company and item_id=p_id and preferido;
    delete from public.compras_proveedores_items where empresa_id=p_company and item_id=p_id;
  elsif p_resource='formulas' then
    v_cost:=private.production_unit_cost(p_company,p_id);
    update public.stock_items set costo_unitario_referencia=v_cost where empresa_id=p_company and id=p_id
      and costo_referencia_usd is null and not exists(select 1 from public.compras_proveedores_items where empresa_id=p_company and item_id=p_id and preferido);
    delete from public.produccion_formulas_lineas where empresa_id=p_company and producto_id=p_id;
  elsif p_resource='ordenes' then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('production-reservations:'||p_company::text,0));
    delete from public.produccion_reservas_ubicaciones where empresa_id=p_company and orden_id=p_id;
    delete from public.produccion_ordenes_reservas where empresa_id=p_company and orden_id=p_id;
  end if;
  if p_resource in ('ordenes','planes') then
    insert into private.produccion_solicitudes_eliminadas(empresa_id,recurso,solicitud_id,autor_id)
      values(p_company,p_resource,(v_row->>'solicitud_id')::uuid,auth.uid()) on conflict do nothing;
  end if;
  execute format('delete from public.%I where empresa_id=$1 and %I=$2',v_target.table_name,v_target.id_field) using p_company,p_id;
  if p_resource='ordenes' then perform private.rebalance_production_reservations(p_company); end if;
  return 'delete';
exception when foreign_key_violation then
  raise exception 'El registro tiene nuevos vínculos. Reabrí la confirmación para revisar la acción';
end
$function$

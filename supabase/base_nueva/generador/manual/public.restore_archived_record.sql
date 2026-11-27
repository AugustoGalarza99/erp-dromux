create or replace function public.restore_archived_record(p_company uuid, p_resource text, p_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare v_target record; v_row jsonb;
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if auth.uid() is null or not private.has_permission(p_company,v_target.permission,'eliminar') then
    raise exception 'Sin permiso para recuperar el registro' using errcode='42501'; end if;
  execute format('select to_jsonb(t) from public.%I t where empresa_id=$1 and %I=$2 and archivado for update',v_target.table_name,v_target.id_field)
    into v_row using p_company,p_id;
  if v_row is null then raise exception 'No se encontró el registro archivado'; end if;
  if p_resource='items' and coalesce((v_row->>'activo_antes_de_archivar')::boolean,true) then
    perform 1 from public.finanzas_tipos_cambio t where t.empresa_id=p_company and (
      t.id=(v_row->>'tipo_cambio_referencia_id')::uuid or exists(
        select 1 from public.compras_proveedores_items q where q.empresa_id=p_company and q.item_id=p_id and q.tipo_cambio_id=t.id)) for share;
    if exists(select 1 from public.finanzas_tipos_cambio t where t.empresa_id=p_company and not t.activo and (
      t.id=(v_row->>'tipo_cambio_referencia_id')::uuid or exists(
        select 1 from public.compras_proveedores_items q where q.empresa_id=p_company and q.item_id=p_id and q.tipo_cambio_id=t.id))) then
      raise exception 'Recuperá primero los tipos de dólar que usa este ítem'; end if;
  elsif p_resource='formulas' then
    perform 1 from public.stock_items i where i.empresa_id=p_company and (i.id=p_id or exists(
      select 1 from public.produccion_formulas_lineas l where l.empresa_id=p_company and l.producto_id=p_id and l.componente_id=i.id)) for share;
    if exists(select 1 from public.stock_items i where i.empresa_id=p_company and not i.activo and (i.id=p_id or exists(
      select 1 from public.produccion_formulas_lineas l where l.empresa_id=p_company and l.producto_id=p_id and l.componente_id=i.id))) then
      raise exception 'Recuperá o activá primero el producto y sus componentes'; end if;
  end if;
  if p_resource in ('items','tipos_cambio') then
    execute format('update public.%I set archivado=false,activo=coalesce(activo_antes_de_archivar,true),activo_antes_de_archivar=null where empresa_id=$1 and %I=$2',v_target.table_name,v_target.id_field)
      using p_company,p_id;
  else
    execute format('update public.%I set archivado=false where empresa_id=$1 and %I=$2',v_target.table_name,v_target.id_field) using p_company,p_id;
  end if;
end
$function$

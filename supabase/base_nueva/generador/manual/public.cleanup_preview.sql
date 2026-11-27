create or replace function public.cleanup_preview(p_company uuid, p_resource text, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_target record; v_row jsonb; v_action text:='delete'; v_message text;
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if auth.uid() is null or not private.has_permission(p_company,v_target.permission,'eliminar') then
    raise exception 'Necesitás permiso de eliminar en este módulo' using errcode='42501'; end if;
  execute format('select to_jsonb(t) from public.%I t where empresa_id=$1 and %I=$2',v_target.table_name,v_target.id_field)
    into v_row using p_company,p_id;
  if v_row is null then raise exception 'El registro no existe en esta empresa'; end if;
  if (v_row->>'archivado')::boolean then raise exception 'El registro ya está archivado'; end if;
  if p_resource='items' then
    if exists(select 1 from public.stock_saldos where empresa_id=p_company and item_id=p_id and cantidad<>0) then
      v_action:='blocked'; v_message:='El ítem todavía tiene stock. Regularizá sus existencias antes de retirarlo.';
    elsif exists(select 1 from public.produccion_formulas_lineas l join public.produccion_formulas f
      on f.empresa_id=l.empresa_id and f.producto_id=l.producto_id where l.empresa_id=p_company
        and (l.componente_id=p_id or l.producto_id=p_id) and not f.archivado) then
      v_action:='blocked'; v_message:='El ítem forma parte de una fórmula activa. Modificá o archivá esa fórmula primero.';
    elsif exists(select 1 from public.produccion_ordenes j where j.empresa_id=p_company and j.estado in ('pendiente','en_proceso')
      and (j.producto_id=p_id or exists(select 1 from jsonb_array_elements(j.formula_copia) x where x->>'component_id'=p_id::text)))
      or exists(select 1 from public.produccion_planes p where p.empresa_id=p_company and p.estado='planificado'
        and (p.producto_id=p_id or exists(select 1 from jsonb_array_elements(p.componentes_copia) x where x->>'component_id'=p_id::text)))
      or exists(select 1 from public.compras_ordenes_lineas l join public.compras_ordenes o on o.empresa_id=l.empresa_id and o.id=l.orden_compra_id
        where l.empresa_id=p_company and l.item_id=p_id and o.estado in ('abierta','parcial') and l.cantidad_recibida<l.cantidad) then
      v_action:='blocked'; v_message:='El ítem tiene fabricación, planificación o compras pendientes. Resolvé esas operaciones primero.';
    end if;
  elsif p_resource='tipos_cambio' then
    if exists(select 1 from public.stock_items where empresa_id=p_company and activo and tipo_cambio_referencia_id=p_id)
      or exists(select 1 from public.compras_proveedores_items q join public.stock_items i on i.empresa_id=q.empresa_id and i.id=q.item_id
        join public.compras_proveedores s on s.empresa_id=q.empresa_id and s.id=q.proveedor_id
        where q.empresa_id=p_company and q.tipo_cambio_id=p_id and i.activo and s.activo) then
      v_action:='blocked'; v_message:='Este dólar se usa en costos actuales. Cambiá primero el tipo de dólar de esos ítems o proveedores.';
    end if;
  elsif p_resource='formulas' then
    if exists(select 1 from public.produccion_ordenes where empresa_id=p_company and producto_id=p_id and estado in ('pendiente','en_proceso'))
      or exists(select 1 from public.produccion_planes where empresa_id=p_company and producto_id=p_id and estado='planificado') then
      v_action:='blocked'; v_message:='Hay órdenes o planes pendientes de este producto. Terminá o cancelá el trabajo primero.';
    end if;
  elsif p_resource='ordenes' then
    if v_row->>'estado'='en_proceso' or (v_row->>'estado'='pendiente' and exists(
      select 1 from public.produccion_ordenes_eventos where empresa_id=p_company and orden_id=p_id)) then
      v_action:='blocked'; v_message:='La orden está en proceso o tiene entregas. Completala o devolvé los materiales y cancelala antes de retirarla.';
    end if;
  elsif p_resource='fabricaciones' then v_action:='archive';
  elsif p_resource='planes' and v_row->>'estado'='planificado' and exists(
    select 1 from public.produccion_ordenes where empresa_id=p_company and plan_id=p_id) then
    v_action:='blocked'; v_message:='El plan tiene una orden vinculada. Gestioná primero esa orden.';
  elsif p_resource='remitos' then v_action:='archive';
  end if;
  if v_action='delete' and private.cleanup_has_references(p_company,p_resource,p_id) then v_action:='archive'; end if;
  if v_action='delete' then v_message:='Se eliminará definitivamente este registro sin uso. La acción no se puede deshacer.'; end if;
  if v_action='archive' then v_message:=case when p_resource='remitos'
    then 'El remito saldrá del listado, conservando la entrega y su historial. Archivar NO devuelve mercadería al stock. Para devolverla usá Anular entrega.'
    else 'El registro tiene información relacionada. Saldrá del listado y conservará sus movimientos, costos y vínculos. Podés recuperarlo en Archivados.' end; end if;
  return jsonb_build_object('action',v_action,'message',v_message);
end
$function$

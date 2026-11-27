create or replace function public.archived_records(p_company uuid, p_resource text, p_search text default ''::text, p_page integer default 0)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare v_target record; v_label text; v_date text; v_count bigint; v_rows jsonb; v_filter text;
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if auth.uid() is null or not private.has_permission(p_company,v_target.permission,'ver') then
    raise exception 'Sin acceso a este archivo' using errcode='42501'; end if;
  if p_page is null or p_page<0 or p_page>100000 or length(coalesce(p_search,''))>100 then raise exception 'Búsqueda o página inválida'; end if;
  v_label:=case p_resource
    when 'items' then 't.codigo||'' · ''||t.nombre'
    when 'tipos_cambio' then 't.nombre'
    when 'formulas' then '(select i.nombre from public.stock_items i where i.empresa_id=t.empresa_id and i.id=t.producto_id)'
    when 'ordenes' then '''OF ''||t.numero::text||'' · ''||(select i.nombre from public.stock_items i where i.empresa_id=t.empresa_id and i.id=t.producto_id)'
    when 'remitos' then '''Remito ''||t.numero::text||'' · ''||t.destinatario'
    else '(select i.nombre from public.stock_items i where i.empresa_id=t.empresa_id and i.id=t.producto_id)' end;
  v_date:=case when p_resource='formulas' then 't.actualizado_en'
    when p_resource='tipos_cambio' then '(select max(e.creado_en) from public.finanzas_cotizaciones e where e.empresa_id=t.empresa_id and e.tipo_cambio_id=t.id)'
    else 't.creado_en' end;
  v_filter:='t.empresa_id=$1 and t.archivado and ('||v_label||') ilike ''%''||$2||''%''';
  execute format('select count(*) from public.%I t where %s',v_target.table_name,v_filter) into v_count using p_company,coalesce(p_search,'');
  execute format('select coalesce(jsonb_agg(x),''[]''::jsonb) from (select t.%I id,%s label,%s created_at from public.%I t where %s order by %s desc,t.%I limit 25 offset $3) x',
    v_target.id_field,v_label,v_date,v_target.table_name,v_filter,v_date,v_target.id_field)
    into v_rows using p_company,coalesce(p_search,''),p_page*25;
  return jsonb_build_object('rows',v_rows,'count',v_count);
end
$function$

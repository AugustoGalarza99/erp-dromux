-- 007 · Guardar controles de una orden ya no borra otros datos de envasado (p. ej. lo que quedó
-- sin envasar). Antes reemplazaba todo el bloque.
begin;

CREATE OR REPLACE FUNCTION public.save_production_work_details(p_company uuid, p_job uuid, p_counts jsonb, p_observations jsonb, p_expected timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.produccion_ordenes%rowtype; v_pack jsonb; v_result jsonb:='[]'; v_count numeric;
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_ordenes','editar') then
    raise exception 'Sin permiso para actualizar la orden' using errcode='42501'; end if;
  perform 1 from public.empresas where id=p_company and activo for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  select * into v_job from public.produccion_ordenes where empresa_id=p_company and id=p_job for update;
  if not found or v_job.estado='cancelada' then raise exception 'Orden inexistente o cancelada'; end if;
  if p_expected is null or v_job.detalles_actualizado_en<>p_expected then raise exception 'Los controles cambiaron. Reabrí el formulario'; end if;
  if jsonb_typeof(p_counts) is distinct from 'object' or jsonb_typeof(p_observations) is distinct from 'object'
    or length(p_observations::text)>10000 or length(p_counts::text)>5000 then raise exception 'Datos de controles inválidos'; end if;
  if exists(select 1 from jsonb_each(p_observations) e where jsonb_typeof(e.value)<>'string'
    or length(e.value#>>'{}')>500 or not (coalesce(v_job.documento_copia->'labels','[]') ? e.key)) then
    raise exception 'Usá los campos originales de la orden'; end if;
  if exists(select 1 from jsonb_each(p_counts) e where not exists(
    select 1 from jsonb_array_elements(coalesce(v_job.opciones_trabajo->'packaging','[]')) x where x->>'id'=e.key)) then
    raise exception 'Envasado no asociado a esta orden'; end if;
  for v_pack in select value from jsonb_array_elements(coalesce(v_job.opciones_trabajo->'packaging','[]')) loop
    v_count:=nullif(p_counts->>(v_pack->>'id'),'')::numeric;
    if v_count is not null and (v_count<0 or v_count>=1000000000 or v_count<>trunc(v_count)) then
      raise exception 'La cantidad real de envases debe ser entera y no negativa'; end if;
    v_result:=v_result||jsonb_build_array(v_pack||jsonb_build_object('actual_count',v_count));
  end loop;
  update public.produccion_ordenes set opciones_trabajo=coalesce(v_job.opciones_trabajo,'{}'::jsonb)
      ||jsonb_build_object('packaging',v_result,'observations',p_observations),
    detalles_actualizado_en=clock_timestamp() where empresa_id=p_company and id=p_job;
end; $function$;

commit;

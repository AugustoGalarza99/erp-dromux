create or replace function private.cleanup_has_references(p_company uuid, p_resource text, p_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare v_target record; v_fk record; v_join text; v_found boolean; v_skip text[]:='{}';
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if p_resource='items' then v_skip:=array['compras_proveedores_items']; end if;
  if p_resource='formulas' then v_skip:=array['produccion_formulas_lineas']; end if;
  if p_resource='ordenes' then v_skip:=array['produccion_ordenes_reservas']; end if;
  for v_fk in
    select c.conrelid,c.conkey,c.confkey,n.nspname,cl.relname
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_class cl on cl.oid=c.conrelid
    join pg_catalog.pg_namespace n on n.oid=cl.relnamespace
    where c.contype='f' and c.confrelid=pg_catalog.to_regclass('public.'||v_target.table_name)
      and not (cl.relname=any(v_skip))
  loop
    select string_agg(format('c.%I=p.%I',ca.attname,pa.attname),' and ' order by keys.ordinality)
      into v_join from unnest(v_fk.conkey,v_fk.confkey) with ordinality keys(child_key,parent_key,ordinality)
      join pg_catalog.pg_attribute ca on ca.attrelid=v_fk.conrelid and ca.attnum=keys.child_key
      join pg_catalog.pg_attribute pa on pa.attrelid=pg_catalog.to_regclass('public.'||v_target.table_name)
        and pa.attnum=keys.parent_key;
    execute format('select exists(select 1 from %I.%I c join public.%I p on %s where p.empresa_id=$1 and p.%I=$2)',
      v_fk.nspname,v_fk.relname,v_target.table_name,v_join,v_target.id_field)
      into v_found using p_company,p_id;
    if v_found then return true; end if;
  end loop;
  -- Las copias guardadas (jsonb) conservan sus claves en inglés.
  if p_resource='items' and (exists(
    select 1 from public.produccion_ordenes j cross join lateral jsonb_array_elements(j.formula_copia) x
      where j.empresa_id=p_company and x->>'component_id'=p_id::text)
    or exists(select 1 from public.produccion_planes p cross join lateral jsonb_array_elements(p.componentes_copia) x
      where p.empresa_id=p_company and x->>'component_id'=p_id::text)) then return true; end if;
  if p_resource='formulas' and (exists(select 1 from public.produccion_ordenes where empresa_id=p_company and producto_id=p_id)
    or exists(select 1 from public.produccion_fabricaciones where empresa_id=p_company and producto_id=p_id)
    or exists(select 1 from public.produccion_planes where empresa_id=p_company and producto_id=p_id)
    or exists(select 1 from public.produccion_formulas_lineas where empresa_id=p_company and componente_id=p_id)) then return true; end if;
  return false;
end
$function$

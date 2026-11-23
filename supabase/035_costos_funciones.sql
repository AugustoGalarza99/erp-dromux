-- Fase 1 de 2 para ocultar costos a roles sin permiso. Aplicar DESPUÉS de 034.
-- Agrega funciones nuevas, mueve save_item_with_cost e import_items a private detrás de envoltorios con la
-- misma firma y restringe production_formula_cost a admin + finance:read. No cambia datos ni revoca
-- columnas; el frontend anterior sigue funcionando (salvo que un rol sin costos intente cambiar costos).
-- La fase 2 (036_costos_revocar.sql) se aplica únicamente cuando el frontend nuevo ya está publicado.
--
-- Reglas:
--   * Costos de producción (estimated_cost, unit_cost y unit_cost dentro de los JSON de snapshot):
--     solo rol admin con permiso finance:read.
--   * Costo de referencia del ítem: rol admin o permiso purchases:read.
-- Las funciones devuelven la misma forma que las consultas anteriores; sin permiso, los costos vienen en null
-- o se quitan del JSON. No se leen ni modifican datos fuera de la empresa indicada.
begin;

create function private.can_see_production_costs(p_company uuid)
returns boolean
language sql stable security definer set search_path='' as $$
  select private.get_user_role(p_company)='admin'
    and private.has_permission(p_company,'finance','read');
$$;

create function private.can_see_reference_cost(p_company uuid)
returns boolean
language sql stable security definer set search_path='' as $$
  select private.get_user_role(p_company)='admin'
    or private.has_permission(p_company,'purchases','read');
$$;

-- Quita unit_cost de cada elemento de un snapshot (arreglo JSON) conservando el orden.
create function private.strip_snapshot_cost(p_snapshot jsonb)
returns jsonb
language sql immutable set search_path='' as $$
  select coalesce(jsonb_agg(x.value-'unit_cost' order by x.ord),'[]'::jsonb)
  from jsonb_array_elements(case when jsonb_typeof(p_snapshot)='array' then p_snapshot else '[]'::jsonb end)
    with ordinality as x(value,ord);
$$;

revoke all on function private.can_see_production_costs(uuid),private.can_see_reference_cost(uuid),
  private.strip_snapshot_cost(jsonb) from public,anon,authenticated;

create function public.list_production_jobs(p_company uuid)
returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_costs boolean;
begin
  if auth.uid() is null then raise exception 'Iniciá sesión' using errcode='42501'; end if;
  -- Sin permiso devuelve lista vacía, igual que la consulta anterior bajo RLS.
  if not private.has_permission(p_company,'production','read') then return '[]'::jsonb; end if;
  v_costs:=private.can_see_production_costs(p_company);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',j.id,'number',j.number,'yield_factor',j.yield_factor,'expected_output',j.expected_output,
      'document_snapshot',j.document_snapshot,'work_options',j.work_options,
      'details_updated_at',j.details_updated_at,'product_id',j.product_id,'plan_id',j.plan_id,
      'planned_quantity',j.planned_quantity,'actual_quantity',j.actual_quantity,
      'warehouse_id',j.warehouse_id,'due_on',j.due_on,'formula_version',j.formula_version,
      'formula_snapshot',case when v_costs then j.formula_snapshot
        else private.strip_snapshot_cost(j.formula_snapshot) end,
      'status',j.status,'note',j.note,'cancel_reason',j.cancel_reason,'variance_note',j.variance_note,
      'output_lot',j.output_lot,'output_expiry',j.output_expiry,'run_id',j.run_id,
      'created_at',j.created_at,'started_at',j.started_at,'completed_at',j.completed_at,
      'production_job_events',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',e.id,'kind',e.kind,'issue_id',e.issue_id,'component_id',e.component_id,
          'warehouse_id',e.warehouse_id,'lot_code',e.lot_code,'quantity',e.quantity,
          'unit_cost',case when v_costs then e.unit_cost end,'note',e.note,'created_at',e.created_at)
          order by e.created_at,e.id)
        from public.production_job_events e where e.company_id=j.company_id and e.job_id=j.id),'[]'::jsonb)
    ) order by j.created_at desc,j.id)
    from (select * from public.production_jobs
      where company_id=p_company and not archived
      order by created_at desc,id limit 70) j),'[]'::jsonb);
end;
$$;

create function public.list_production_plans(p_company uuid)
returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_costs boolean;
begin
  if auth.uid() is null then raise exception 'Iniciá sesión' using errcode='42501'; end if;
  -- Sin permiso devuelve lista vacía, igual que la consulta anterior bajo RLS.
  if not private.has_permission(p_company,'production','read') then return '[]'::jsonb; end if;
  v_costs:=private.can_see_production_costs(p_company);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',p.id,'product_id',p.product_id,'warehouse_id',p.warehouse_id,'quantity',p.quantity,
      'formula_version',p.formula_version,'estimated_cost',case when v_costs then p.estimated_cost end,
      'component_snapshot',case when v_costs then p.component_snapshot
        else private.strip_snapshot_cost(p.component_snapshot) end,
      'due_on',p.due_on,'note',p.note,'status',p.status,'run_id',p.run_id,'created_at',p.created_at
    ) order by p.created_at desc,p.id)
    from (select * from public.production_plans
      where company_id=p_company and not archived
      order by created_at desc,id limit 100) p),'[]'::jsonb);
end;
$$;

create function public.list_production_runs(p_company uuid)
returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_costs boolean;
begin
  if auth.uid() is null then raise exception 'Iniciá sesión' using errcode='42501'; end if;
  -- Sin permiso devuelve lista vacía, igual que la consulta anterior bajo RLS.
  if not private.has_permission(p_company,'production','read') then return '[]'::jsonb; end if;
  v_costs:=private.can_see_production_costs(p_company);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',r.id,'product_id',r.product_id,'quantity',r.quantity,'formula_version',r.formula_version,
      'estimated_cost',case when v_costs then r.estimated_cost end,'created_at',r.created_at,
      'warehouse_id',r.warehouse_id,
      'production_run_lines',coalesce((
        select jsonb_agg(jsonb_build_object(
          'component_id',l.component_id,'quantity',l.quantity,'lot_code',l.lot_code,
          'warehouse_id',l.warehouse_id,'unit_cost',case when v_costs then l.unit_cost end)
          order by l.component_id)
        from public.production_run_lines l where l.company_id=r.company_id and l.run_id=r.id),'[]'::jsonb)
    ) order by r.created_at desc,r.id)
    from (select * from public.production_runs
      where company_id=p_company and not archived
      order by created_at desc,id limit 30) r),'[]'::jsonb);
end;
$$;

-- Ítems para producción. El costo de referencia solo se informa a admin y compras;
-- has_reference_cost permite a la pantalla de fórmulas validar sin conocer el valor.
create function public.list_production_items(p_company uuid,p_include_inactive boolean default false)
returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_cost boolean;
begin
  if auth.uid() is null then raise exception 'Iniciá sesión' using errcode='42501'; end if;
  if not private.has_permission(p_company,'items','read') then return '[]'::jsonb; end if;
  v_cost:=private.can_see_reference_cost(p_company);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',i.id,'code',i.code,'name',i.name,'active',i.active,'item_type',i.item_type,
      'track_lots',i.track_lots,'infinite_stock',i.infinite_stock,'yield_enabled',i.yield_enabled,
      'yield_factor',i.yield_factor,
      'reference_unit_cost',case when v_cost then i.reference_unit_cost end,
      'has_reference_cost',i.reference_unit_cost is not null,
      'units',jsonb_build_object('symbol',u.symbol)
    ) order by i.name,i.id)
    from (select * from public.items
      where company_id=p_company and (coalesce(p_include_inactive,false) or active)
        and item_type in ('raw_material','semi_finished','finished_product','consumable')
      order by name,id limit 500) i
    join public.units u on u.company_id=i.company_id and u.id=i.unit_id),'[]'::jsonb);
end;
$$;

-- Ficha de ítem. Costos de referencia solo para admin y compras (cost_visible indica si se ven).
create function public.get_item_detail(p_company uuid,p_item uuid)
returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_cost boolean; v_result jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'items','read') then
    raise exception 'Sin permiso para consultar ítems' using errcode='42501'; end if;
  v_cost:=private.can_see_reference_cost(p_company);
  select jsonb_build_object(
    'id',i.id,'company_id',i.company_id,'code',i.code,'name',i.name,'item_type',i.item_type,
    'category_id',i.category_id,'unit_id',i.unit_id,'barcode',i.barcode,'description',i.description,
    'minimum_stock',i.minimum_stock,'track_lots',i.track_lots,'infinite_stock',i.infinite_stock,
    'active',i.active,'archived',i.archived,
    'reference_unit_cost',case when v_cost then i.reference_unit_cost end,
    'reference_cost_usd',case when v_cost then i.reference_cost_usd end,
    'reference_exchange_rate_type_id',case when v_cost then i.reference_exchange_rate_type_id end,
    'cost_visible',v_cost,'created_at',i.created_at,'updated_at',i.updated_at,
    'category',case when c.id is null then null
      else jsonb_build_object('id',c.id,'name',c.name,'active',c.active) end,
    'unit',jsonb_build_object('id',u.id,'name',u.name,'symbol',u.symbol,'active',u.active))
  into v_result
  from public.items i
  join public.units u on u.company_id=i.company_id and u.id=i.unit_id
  left join public.item_categories c on c.company_id=i.company_id and c.id=i.category_id
  where i.company_id=p_company and i.id=p_item;
  if v_result is null then raise exception 'El ítem no existe en esta empresa'; end if;
  return v_result;
end;
$$;

revoke all on function public.list_production_jobs(uuid),public.list_production_plans(uuid),
  public.list_production_runs(uuid),public.list_production_items(uuid,boolean),
  public.get_item_detail(uuid,uuid) from public,anon,authenticated;
grant execute on function public.list_production_jobs(uuid),public.list_production_plans(uuid),
  public.list_production_runs(uuid),public.list_production_items(uuid,boolean),
  public.get_item_detail(uuid,uuid) to authenticated;

-- Escritura del costo de referencia: save_item_with_cost e import_items solo pedían items:insert/update,
-- y p_preserve_cost lo decide el cliente. Se mueven al esquema private (sin cambios) y se publican
-- envoltorios con la misma firma que exigen admin o purchases:read para definir o cambiar costos.
create function private.row_has_cost(p_row jsonb)
returns boolean
language sql immutable set search_path='' as $$
  select exists(select 1 from (values ('costo_referencia_ars'),('costo_usd'),('tipo_dolar'),
      ('proveedor'),('supplier_id'),('exchange_type_id')) k(key)
    where nullif(btrim(coalesce(p_row->>k.key,'')),'') is not null);
$$;
revoke all on function private.row_has_cost(jsonb) from public,anon,authenticated;

alter function public.save_item_with_cost(uuid,uuid,jsonb,timestamp with time zone,boolean) set schema private;
alter function public.import_items(uuid,jsonb) set schema private;
revoke all on function private.save_item_with_cost(uuid,uuid,jsonb,timestamp with time zone,boolean),
  private.import_items(uuid,jsonb) from public,anon,authenticated;

create function public.save_item_with_cost(p_company uuid,p_item uuid,p_row jsonb,
  p_expected_updated_at timestamp with time zone,p_preserve_cost boolean)
returns uuid
language plpgsql security definer set search_path='' as $$
declare v_row jsonb:=p_row; v_preserve boolean:=p_preserve_cost;
begin
  if auth.uid() is null then raise exception 'Iniciá sesión' using errcode='42501'; end if;
  if jsonb_typeof(p_row) is distinct from 'object' then raise exception 'Datos del ítem inválidos'; end if;
  if not private.can_see_reference_cost(p_company) then
    if p_item is null then
      if private.row_has_cost(p_row) then
        raise exception 'Solo Administración o Compras pueden definir costos' using errcode='42501'; end if;
    else
      -- Quien no gestiona costos puede editar la ficha, pero el costo vigente se conserva.
      v_preserve:=true;
      v_row:=p_row-'costo_referencia_ars'-'costo_usd'-'tipo_dolar'-'supplier_id'-'exchange_type_id'-'proveedor';
    end if;
  end if;
  return private.save_item_with_cost(p_company,p_item,v_row,p_expected_updated_at,v_preserve);
end;
$$;

create function public.import_items(p_company uuid,p_rows jsonb)
returns integer
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'Iniciá sesión' using errcode='42501'; end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'Datos de importación inválidos'; end if;
  if not private.can_see_reference_cost(p_company) and exists(
    select 1 from jsonb_array_elements(p_rows) r
    where jsonb_typeof(r.value)='object' and private.row_has_cost(r.value)) then
    raise exception 'Solo Administración o Compras pueden importar costos' using errcode='42501'; end if;
  return private.import_items(p_company,p_rows);
end;
$$;

revoke all on function public.save_item_with_cost(uuid,uuid,jsonb,timestamp with time zone,boolean),
  public.import_items(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.save_item_with_cost(uuid,uuid,jsonb,timestamp with time zone,boolean),
  public.import_items(uuid,jsonb) to authenticated;

-- production_formula_cost solo pedía production:read pero devuelve el costo de fabricación.
create or replace function public.production_formula_cost(p_company uuid,p_product uuid)
returns numeric
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.can_see_production_costs(p_company) then
    raise exception 'Solo un administrador con acceso a finanzas puede consultar costos' using errcode='42501'; end if;
  return private.production_unit_cost(p_company,p_product);
end;
$$;

commit;

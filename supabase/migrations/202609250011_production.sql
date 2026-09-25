-- ERP Dromux · fórmulas y fabricación atómica. Aplicar luego de 010.
create table public.production_formulas (
  company_id uuid not null,
  product_id uuid not null,
  batch_quantity numeric(18,6) not null check (batch_quantity > 0),
  version integer not null default 1,
  updated_at timestamptz not null default now(),
  primary key (company_id, product_id),
  foreign key (company_id, product_id) references public.items(company_id,id)
);

create table public.production_formula_lines (
  company_id uuid not null,
  product_id uuid not null,
  component_id uuid not null,
  quantity numeric(18,6) not null check (quantity > 0),
  primary key (company_id, product_id, component_id),
  foreign key (company_id, product_id) references public.production_formulas(company_id,product_id),
  foreign key (company_id, component_id) references public.items(company_id,id),
  check (product_id <> component_id)
);

create table public.production_runs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  product_id uuid not null,
  formula_version integer not null,
  quantity numeric(18,6) not null check (quantity > 0),
  warehouse_id uuid not null,
  output_operation_id uuid not null,
  estimated_cost numeric(18,2) not null,
  request_id uuid not null,
  request_payload jsonb not null,
  note text not null,
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  unique(company_id,id),
  unique(company_id,request_id),
  foreign key (company_id,product_id) references public.items(company_id,id),
  foreign key (company_id,warehouse_id) references public.warehouses(company_id,id),
  foreign key (company_id,output_operation_id) references public.stock_operations(company_id,id)
);

create table public.production_run_lines (
  company_id uuid not null,
  run_id uuid not null,
  component_id uuid not null,
  warehouse_id uuid not null,
  quantity numeric(18,6) not null check (quantity > 0),
  lot_code text,
  unit_cost numeric(18,2) not null,
  stock_operation_id uuid not null,
  primary key (company_id,run_id,component_id),
  foreign key (company_id,run_id) references public.production_runs(company_id,id),
  foreign key (company_id,component_id) references public.items(company_id,id),
  foreign key (company_id,warehouse_id) references public.warehouses(company_id,id),
  foreign key (company_id,stock_operation_id) references public.stock_operations(company_id,id)
);

create index production_runs_recent on public.production_runs(company_id,created_at desc);

alter table public.production_formulas enable row level security;
alter table public.production_formula_lines enable row level security;
alter table public.production_runs enable row level security;
alter table public.production_run_lines enable row level security;

create policy production_formulas_read on public.production_formulas for select to authenticated
  using ((select private.has_permission(company_id,'production','read')));
create policy production_formula_lines_read on public.production_formula_lines for select to authenticated
  using ((select private.has_permission(company_id,'production','read')));
create policy production_runs_read on public.production_runs for select to authenticated
  using ((select private.has_permission(company_id,'production','read')));
create policy production_run_lines_read on public.production_run_lines for select to authenticated
  using ((select private.has_permission(company_id,'production','read')));

revoke all on public.production_formulas, public.production_formula_lines,
  public.production_runs, public.production_run_lines from anon,authenticated;
grant select on public.production_formulas, public.production_formula_lines,
  public.production_runs, public.production_run_lines to authenticated;

create trigger production_runs_immutable before update or delete on public.production_runs
  for each row execute function private.reject_stock_history_mutation();
create trigger production_run_lines_immutable before update or delete on public.production_run_lines
  for each row execute function private.reject_stock_history_mutation();

create function private.production_unit_cost(p_company uuid,p_item uuid,p_path uuid[] default '{}')
returns numeric language plpgsql security definer set search_path = '' as $$
declare
  v_cost numeric;
  v_batch numeric;
  v_line record;
  v_total numeric := 0;
begin
  if p_item = any(p_path) or array_length(p_path,1) >= 15 then
    raise exception 'Se detectó un ciclo o demasiados niveles en la fórmula';
  end if;
  select f.batch_quantity into v_batch from public.production_formulas f
  where f.company_id=p_company and f.product_id=p_item;
  if v_batch is null then
    select i.reference_unit_cost into v_cost from public.items i
    where i.company_id=p_company and i.id=p_item;
    if v_cost is null then raise exception 'Falta el costo de referencia de un componente sin fórmula'; end if;
    return v_cost;
  end if;
  for v_line in select component_id,quantity from public.production_formula_lines
    where company_id=p_company and product_id=p_item loop
    v_total := v_total + v_line.quantity * private.production_unit_cost(
      p_company,v_line.component_id,array_append(p_path,p_item));
  end loop;
  return round(v_total/v_batch,2);
end;
$$;

create function public.save_production_formula(
  p_company uuid,p_product uuid,p_batch_quantity numeric,p_lines jsonb
) returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_line jsonb;
  v_component uuid;
  v_quantity numeric;
  v_version integer;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','update') then
    raise exception 'Sin permiso para editar fórmulas' using errcode='42501';
  end if;
  if p_batch_quantity is null or p_batch_quantity <= 0 or p_batch_quantity >= 1000000000000
    or p_batch_quantity <> round(p_batch_quantity,6)
    or p_lines is null or jsonb_typeof(p_lines) <> 'array'
    or jsonb_array_length(p_lines) not between 1 and 40 then
    raise exception 'Indicá rendimiento y componentes válidos';
  end if;
  -- Una sola edición de fórmulas por empresa evita ciclos por escrituras simultáneas.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('formula:'||p_company::text,0));
  perform 1 from public.items i where i.company_id=p_company and i.id=p_product
    and i.active and i.item_type in ('finished_product','semi_finished') for share;
  if not found then raise exception 'Elegí un producto terminado o semielaborado activo'; end if;
  insert into public.production_formulas(company_id,product_id,batch_quantity)
  values(p_company,p_product,p_batch_quantity)
  on conflict(company_id,product_id) do update set
    batch_quantity=excluded.batch_quantity,version=production_formulas.version+1,updated_at=now()
  returning version into v_version;
  delete from public.production_formula_lines where company_id=p_company and product_id=p_product;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_component := (v_line->>'component_id')::uuid;
    v_quantity := (v_line->>'quantity')::numeric;
    if v_quantity is null or v_quantity <= 0 or v_quantity >= 1000000000000
      or v_quantity <> round(v_quantity,6) then raise exception 'Cantidad de componente inválida'; end if;
    perform 1 from public.items i where i.company_id=p_company and i.id=v_component
      and i.active and i.item_type in ('raw_material','semi_finished') for share;
    if not found then raise exception 'Sólo podés usar materias primas o semielaborados activos'; end if;
    insert into public.production_formula_lines(company_id,product_id,component_id,quantity)
    values(p_company,p_product,v_component,v_quantity);
  end loop;
  -- Calcula recursivamente y revierte la transacción si aparece un ciclo o falta un costo.
  perform private.production_unit_cost(p_company,p_product);
  return v_version;
end;
$$;

create function public.production_formula_cost(p_company uuid,p_product uuid)
returns numeric language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','read') then
    raise exception 'Sin permiso para consultar costos' using errcode='42501';
  end if;
  return private.production_unit_cost(p_company,p_product);
end;
$$;

create function public.post_production_run(
  p_company uuid,p_product uuid,p_request_id uuid,p_quantity numeric,
  p_warehouse uuid,p_output_lot text,p_expires_on date,p_note text,p_inputs jsonb
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_payload jsonb;
  v_existing public.production_runs%rowtype;
  v_formula public.production_formulas%rowtype;
  v_line record;
  v_input jsonb;
  v_required numeric;
  v_cost numeric;
  v_run uuid;
  v_operation uuid;
  v_output uuid;
  v_wh uuid;
  v_lot text;
  v_posted jsonb := '[]'::jsonb;
  v_post jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert')
    or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Necesitás permisos de producción y movimientos de stock' using errcode='42501';
  end if;
  if p_request_id is null or p_quantity is null or p_quantity <= 0
    or p_quantity >= 1000000000000 or p_quantity <> round(p_quantity,6)
    or p_product is null or p_warehouse is null or p_inputs is null
    or jsonb_typeof(p_inputs) <> 'array' or length(btrim(p_note)) not between 3 and 400 then
    raise exception 'Datos de producción inválidos';
  end if;
  v_payload := jsonb_build_object('product',p_product,'quantity',p_quantity,
    'warehouse',p_warehouse,'lot',nullif(btrim(p_output_lot),''),
    'expiry',p_expires_on,'note',btrim(p_note),'inputs',p_inputs);
  select * into v_existing from public.production_runs
  where company_id=p_company and request_id=p_request_id;
  if found then
    if v_existing.request_payload <> v_payload or v_existing.actor_id <> auth.uid() then
      raise exception 'Esta solicitud ya se usó con otros datos';
    end if;
    return v_existing.id;
  end if;
  select * into v_formula from public.production_formulas
  where company_id=p_company and product_id=p_product for share;
  if not found then raise exception 'El producto no tiene fórmula'; end if;
  perform 1 from public.items where company_id=p_company and id=p_product and active for share;
  if not found then raise exception 'El producto está inactivo'; end if;
  if jsonb_array_length(p_inputs) <> (select count(*) from public.production_formula_lines
    where company_id=p_company and product_id=p_product) then
    raise exception 'Seleccioná depósito y lote para cada componente';
  end if;
  v_cost := private.production_unit_cost(p_company,p_product);
  -- Se registra todo dentro de la misma transacción de PostgreSQL.
  v_run := gen_random_uuid();
  for v_line in select l.component_id,l.quantity,i.track_lots
    from public.production_formula_lines l join public.items i
      on i.company_id=l.company_id and i.id=l.component_id
    where l.company_id=p_company and l.product_id=p_product order by l.component_id loop
    select value into v_input from jsonb_array_elements(p_inputs) value
    where value->>'component_id'=v_line.component_id::text;
    if not found or (select count(*) from jsonb_array_elements(p_inputs) value
      where value->>'component_id'=v_line.component_id::text) <> 1 then
      raise exception 'Cada componente debe figurar una sola vez';
    end if;
    v_wh := (v_input->>'warehouse_id')::uuid;
    v_lot := nullif(btrim(v_input->>'lot_code'),'');
    v_required := v_line.quantity*p_quantity/v_formula.batch_quantity;
    if v_required <= 0 or v_required >= 1000000000000 or v_required <> round(v_required,6) then
      raise exception 'La cantidad requerida no admite más de seis decimales';
    end if;
    v_operation := public.post_stock_operation(p_company,v_line.component_id,v_wh,null,
      'issue',v_required,'Producción '||v_run::text,gen_random_uuid(),v_lot,null);
    v_posted := v_posted || jsonb_build_array(jsonb_build_object(
      'component',v_line.component_id,'warehouse',v_wh,'quantity',v_required,
      'lot',v_lot,'cost',private.production_unit_cost(p_company,v_line.component_id),
      'operation',v_operation));
  end loop;
  v_output := public.post_stock_operation(p_company,p_product,p_warehouse,null,
    'receipt',p_quantity,'Producción '||v_run::text,gen_random_uuid(),
    nullif(btrim(p_output_lot),''),p_expires_on);
  insert into public.production_runs(id,company_id,product_id,formula_version,quantity,
    warehouse_id,output_operation_id,estimated_cost,request_id,request_payload,note,actor_id)
  values(v_run,p_company,p_product,v_formula.version,p_quantity,p_warehouse,
    v_output,round(v_cost*p_quantity,2),p_request_id,v_payload,btrim(p_note),auth.uid());
  for v_post in select value from jsonb_array_elements(v_posted) loop
    insert into public.production_run_lines(company_id,run_id,component_id,warehouse_id,
      quantity,lot_code,unit_cost,stock_operation_id)
    values(p_company,v_run,(v_post->>'component')::uuid,(v_post->>'warehouse')::uuid,
      (v_post->>'quantity')::numeric,v_post->>'lot',(v_post->>'cost')::numeric,
      (v_post->>'operation')::uuid);
  end loop;
  return v_run;
end;
$$;

revoke execute on function private.production_unit_cost(uuid,uuid,uuid[]) from public,anon,authenticated;
revoke execute on function public.save_production_formula(uuid,uuid,numeric,jsonb),
  public.production_formula_cost(uuid,uuid),
  public.post_production_run(uuid,uuid,uuid,numeric,uuid,text,date,text,jsonb)
  from public,anon;
grant execute on function public.save_production_formula(uuid,uuid,numeric,jsonb),
  public.production_formula_cost(uuid,uuid),
  public.post_production_run(uuid,uuid,uuid,numeric,uuid,text,date,text,jsonb)
  to authenticated;

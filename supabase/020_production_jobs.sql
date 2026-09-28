-- Dromux ERP · órdenes de fabricación con consumos reales y rendimiento.
-- Ejecutar una vez después de 019. No modifica órdenes históricas.

create table public.production_jobs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  request_id uuid not null,
  request_payload jsonb not null,
  product_id uuid not null,
  plan_id uuid,
  planned_quantity numeric(18,6) not null check(planned_quantity>0),
  actual_quantity numeric(18,6) check(actual_quantity>0),
  warehouse_id uuid not null,
  due_on date,
  formula_version integer not null,
  formula_snapshot jsonb not null,
  status text not null default 'queued'
    check(status in ('queued','in_progress','completed','cancelled')),
  note text not null check(length(btrim(note)) between 3 and 400),
  cancel_reason text,
  variance_note text,
  output_lot text,
  output_expiry date,
  run_id uuid,
  completion_request_id uuid,
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  unique(company_id,id),
  unique(company_id,request_id),
  unique(company_id,plan_id),
  foreign key(company_id,product_id) references public.items(company_id,id),
  foreign key(company_id,warehouse_id) references public.warehouses(company_id,id),
  foreign key(company_id,plan_id) references public.production_plans(company_id,id),
  foreign key(company_id,run_id) references public.production_runs(company_id,id),
  check((status='completed')=(run_id is not null and completed_at is not null
    and actual_quantity is not null and completion_request_id is not null)),
  check((status='cancelled')=(cancelled_at is not null))
);
create index production_jobs_queue on public.production_jobs(company_id,status,due_on,created_at);

create table public.production_job_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  job_id uuid not null,
  request_id uuid not null,
  kind text not null check(kind in ('issue','return')),
  issue_id uuid,
  component_id uuid not null,
  warehouse_id uuid not null,
  lot_code text,
  quantity numeric(18,6) not null check(quantity>0),
  unit_cost numeric(18,2) not null check(unit_cost>=0),
  stock_operation_id uuid not null,
  note text not null check(length(btrim(note)) between 3 and 300),
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  unique(company_id,id),
  unique(company_id,request_id),
  foreign key(company_id,job_id) references public.production_jobs(company_id,id),
  foreign key(company_id,issue_id) references public.production_job_events(company_id,id),
  foreign key(company_id,component_id) references public.items(company_id,id),
  foreign key(company_id,warehouse_id) references public.warehouses(company_id,id),
  foreign key(company_id,stock_operation_id) references public.stock_operations(company_id,id),
  check((kind='return')=(issue_id is not null))
);
create index production_job_events_list on public.production_job_events(company_id,job_id,created_at,id);

alter table public.production_jobs enable row level security;
alter table public.production_job_events enable row level security;
create policy production_jobs_read on public.production_jobs for select to authenticated
  using((select private.has_permission(company_id,'production','read')));
create policy production_job_events_read on public.production_job_events for select to authenticated
  using((select private.has_permission(company_id,'production','read')));
revoke all on public.production_jobs,public.production_job_events from public,anon,authenticated;
grant select on public.production_jobs,public.production_job_events to authenticated;
create trigger production_job_events_immutable before update or delete on public.production_job_events
  for each row execute function private.reject_stock_history_mutation();

create function public.create_production_job(p_company uuid,p_product uuid,
  p_quantity numeric,p_warehouse uuid,p_due_on date,p_note text,
  p_request_id uuid,p_plan uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_formula public.production_formulas%rowtype;
  v_plan public.production_plans%rowtype; v_previous public.production_jobs%rowtype;
  v_payload jsonb; v_snapshot jsonb; v_job uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert') then
    raise exception 'Sin permiso para crear órdenes de fabricación' using errcode='42501'; end if;
  if p_product is null or p_warehouse is null or p_request_id is null
    or p_quantity is null or p_quantity<=0 or p_quantity>=1000000000000
    or p_quantity<>round(p_quantity,6)
    or length(btrim(coalesce(p_note,''))) not between 3 and 400 then
    raise exception 'Revisá producto, cantidad, depósito y nota'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('job-create:'||p_company::text||':'||p_request_id::text,0));
  v_payload:=jsonb_build_object('product',p_product,'quantity',p_quantity,
    'warehouse',p_warehouse,'date',p_due_on,'note',btrim(p_note),'plan',p_plan);
  select * into v_previous from public.production_jobs
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_previous.actor_id<>auth.uid() or v_previous.request_payload<>v_payload then
      raise exception 'La solicitud ya se usó con otros datos'; end if;
    return v_previous.id;
  end if;
  select * into v_formula from public.production_formulas
    where company_id=p_company and product_id=p_product for share;
  if not found then raise exception 'El producto no tiene fórmula'; end if;
  perform 1 from public.items i where i.company_id=p_company and i.id=p_product
    and i.active and i.item_type in ('semi_finished','finished_product') for share;
  if not found then raise exception 'Producto inactivo o no fabricable'; end if;
  perform 1 from public.warehouses w where w.company_id=p_company
    and w.id=p_warehouse and w.active for share;
  if not found then raise exception 'Depósito de destino inactivo'; end if;
  if p_plan is not null then
    select * into v_plan from public.production_plans
      where company_id=p_company and id=p_plan for update;
    if not found or v_plan.status<>'planned' or v_plan.product_id<>p_product
      or v_plan.warehouse_id<>p_warehouse or v_plan.quantity<>p_quantity
      or v_plan.formula_version<>v_formula.version then
      raise exception 'La planificación cambió. Revisá su fórmula y cantidades'; end if;
    if exists(select 1 from public.production_jobs
      where company_id=p_company and plan_id=p_plan) then
      raise exception 'La planificación ya tiene una orden de fabricación'; end if;
    v_snapshot:=v_plan.component_snapshot;
  else
    select jsonb_agg(jsonb_build_object('component_id',l.component_id,
      'quantity',l.quantity*p_quantity/v_formula.batch_quantity,
      'unit_cost',private.production_unit_cost(p_company,l.component_id))
      order by l.component_id) into v_snapshot
    from public.production_formula_lines l
    where l.company_id=p_company and l.product_id=p_product;
  end if;
  if v_snapshot is null or jsonb_array_length(v_snapshot)=0
    or exists(select 1 from jsonb_array_elements(v_snapshot) entry
      where (entry->>'quantity')::numeric<=0
        or (entry->>'quantity')::numeric<>round((entry->>'quantity')::numeric,6)) then
    raise exception 'La fórmula necesita componentes con hasta seis decimales'; end if;
  insert into public.production_jobs(company_id,request_id,request_payload,
    product_id,plan_id,planned_quantity,warehouse_id,due_on,
    formula_version,formula_snapshot,note,actor_id)
  values(p_company,p_request_id,v_payload,p_product,p_plan,p_quantity,p_warehouse,
    p_due_on,v_formula.version,v_snapshot,btrim(p_note),auth.uid())
  returning id into v_job;
  return v_job;
end;
$$;

create function public.start_production_job(p_company uuid,p_job uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','update') then
    raise exception 'Sin permiso para iniciar fabricación' using errcode='42501'; end if;
  update public.production_jobs set status='in_progress',started_at=clock_timestamp()
    where company_id=p_company and id=p_job and status='queued';
  if not found and not exists(select 1 from public.production_jobs
    where company_id=p_company and id=p_job and status='in_progress') then
    raise exception 'La orden no está pendiente'; end if;
end;
$$;

create function public.issue_production_material(p_company uuid,p_job uuid,
  p_component uuid,p_warehouse uuid,p_lot text,p_quantity numeric,
  p_note text,p_request_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_job public.production_jobs%rowtype;
  v_previous public.production_job_events%rowtype;
  v_cost numeric; v_operation uuid; v_event uuid;
  v_lot text:=nullif(btrim(p_lot),'');
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert')
    or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Necesitás permiso de producción y stock' using errcode='42501'; end if;
  if p_request_id is null or p_component is null or p_warehouse is null
    or p_quantity is null or p_quantity<=0 or p_quantity>=1000000000000
    or p_quantity<>round(p_quantity,6)
    or length(btrim(coalesce(p_note,''))) not between 3 and 300 then
    raise exception 'Revisá el insumo, cantidad, depósito y motivo'; end if;
  select * into v_job from public.production_jobs
    where company_id=p_company and id=p_job for update;
  if not found then raise exception 'Orden inexistente'; end if;
  select * into v_previous from public.production_job_events
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_previous.actor_id<>auth.uid() or v_previous.kind<>'issue'
      or v_previous.job_id<>p_job or v_previous.component_id<>p_component
      or v_previous.warehouse_id<>p_warehouse or v_previous.quantity<>p_quantity
      or v_previous.lot_code is distinct from v_lot
      or v_previous.note<>btrim(p_note) then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_previous.id;
  end if;
  if v_job.status not in ('queued','in_progress') then
    raise exception 'La orden ya no admite insumos'; end if;
  if p_component=v_job.product_id then
    raise exception 'El producto fabricado no puede consumirse a sí mismo'; end if;
  perform 1 from public.items i where i.company_id=p_company and i.id=p_component
    and i.active and i.item_type in ('raw_material','semi_finished') for share;
  if not found then raise exception 'Elegí una materia prima o un semielaborado activo'; end if;
  select round(r.estimated_cost/r.quantity,2) into v_cost
    from public.production_runs r
    where r.company_id=p_company and r.product_id=p_component
    order by r.created_at desc limit 1;
  v_cost:=coalesce(v_cost,private.production_unit_cost(p_company,p_component));
  v_operation:=public.post_stock_operation(p_company,p_component,p_warehouse,
    null,'issue',p_quantity,'Orden producción '||p_job::text,
    gen_random_uuid(),v_lot,null);
  insert into public.production_job_events(company_id,job_id,request_id,kind,
    component_id,warehouse_id,lot_code,quantity,unit_cost,stock_operation_id,
    note,actor_id)
  values(p_company,p_job,p_request_id,'issue',p_component,p_warehouse,
    v_lot,p_quantity,v_cost,v_operation,btrim(p_note),auth.uid())
  returning id into v_event;
  if v_job.status='queued' then
    update public.production_jobs set status='in_progress',started_at=clock_timestamp()
      where company_id=p_company and id=p_job;
  end if;
  return v_event;
end;
$$;

create function public.return_production_material(p_company uuid,p_job uuid,
  p_issue uuid,p_quantity numeric,p_note text,p_request_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_job public.production_jobs%rowtype;
  v_issue public.production_job_events%rowtype;
  v_previous public.production_job_events%rowtype;
  v_open numeric; v_expiry date; v_operation uuid; v_event uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','update')
    or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Necesitás permiso para devolver insumos al stock' using errcode='42501'; end if;
  if p_request_id is null or p_quantity is null or p_quantity<=0
    or p_quantity>=1000000000000 or p_quantity<>round(p_quantity,6)
    or length(btrim(coalesce(p_note,''))) not between 3 and 300 then
    raise exception 'Revisá cantidad y motivo de devolución'; end if;
  select * into v_job from public.production_jobs
    where company_id=p_company and id=p_job for update;
  if not found then raise exception 'Orden inexistente'; end if;
  select * into v_previous from public.production_job_events
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_previous.actor_id<>auth.uid() or v_previous.kind<>'return'
      or v_previous.job_id<>p_job or v_previous.issue_id<>p_issue
      or v_previous.quantity<>p_quantity or v_previous.note<>btrim(p_note) then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_previous.id;
  end if;
  if v_job.status<>'in_progress' then raise exception 'La orden ya no admite devoluciones'; end if;
  select * into v_issue from public.production_job_events
    where company_id=p_company and job_id=p_job and id=p_issue and kind='issue';
  if not found then raise exception 'Elegí una salida de insumo de esta orden'; end if;
  select v_issue.quantity-coalesce(sum(e.quantity),0) into v_open
    from public.production_job_events e
    where e.company_id=p_company and e.issue_id=p_issue and e.kind='return';
  if p_quantity>v_open then raise exception 'La devolución supera el saldo de esa salida'; end if;
  if v_issue.lot_code is not null then
    select l.expires_on into v_expiry from public.stock_lots l
      where l.company_id=p_company and l.item_id=v_issue.component_id
        and lower(l.code)=lower(v_issue.lot_code);
    if not found then raise exception 'No se encuentra el lote de origen'; end if;
  end if;
  v_operation:=public.post_stock_operation(p_company,v_issue.component_id,
    v_issue.warehouse_id,null,'receipt',p_quantity,
    'Devolución orden '||p_job::text,gen_random_uuid(),v_issue.lot_code,v_expiry);
  insert into public.production_job_events(company_id,job_id,request_id,kind,
    issue_id,component_id,warehouse_id,lot_code,quantity,unit_cost,
    stock_operation_id,note,actor_id)
  values(p_company,p_job,p_request_id,'return',p_issue,v_issue.component_id,
    v_issue.warehouse_id,v_issue.lot_code,p_quantity,v_issue.unit_cost,
    v_operation,btrim(p_note),auth.uid()) returning id into v_event;
  return v_event;
end;
$$;

create function public.finish_production_job(p_company uuid,p_job uuid,
  p_actual_quantity numeric,p_output_lot text,p_expires_on date,
  p_variance_note text,p_request_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_job public.production_jobs%rowtype;
  v_track_lots boolean; v_expected record; v_cost numeric; v_output uuid;
  v_run uuid; v_mismatch boolean:=false; v_lot text:=nullif(btrim(p_output_lot),'');
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert')
    or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Necesitás permiso de producción y stock' using errcode='42501'; end if;
  if p_request_id is null or p_actual_quantity is null or p_actual_quantity<=0
    or p_actual_quantity>=1000000000000
    or p_actual_quantity<>round(p_actual_quantity,6)
    or length(coalesce(p_variance_note,''))>400 then
    raise exception 'Indicá el rendimiento real con hasta seis decimales'; end if;
  select * into v_job from public.production_jobs
    where company_id=p_company and id=p_job for update;
  if not found then raise exception 'Orden inexistente'; end if;
  if v_job.status='completed' then
    if v_job.completion_request_id<>p_request_id
      or v_job.actual_quantity<>p_actual_quantity
      or v_job.output_lot is distinct from v_lot
      or v_job.output_expiry is distinct from p_expires_on
      or v_job.variance_note is distinct from nullif(btrim(p_variance_note),'') then
      raise exception 'Esta orden ya fue completada con otros datos'; end if;
    return v_job.run_id;
  end if;
  if v_job.status<>'in_progress' then
    raise exception 'Iniciá la orden y registrá sus insumos antes de terminar'; end if;
  select i.track_lots into v_track_lots from public.items i
    where i.company_id=p_company and i.id=v_job.product_id and i.active for share;
  if not found then raise exception 'El producto está inactivo'; end if;
  if v_track_lots and v_lot is null then
    raise exception 'Indicá el lote del producto que vas a ingresar'; end if;
  if not v_track_lots and (v_lot is not null or p_expires_on is not null) then
    raise exception 'Este producto no usa lotes; dejá lote y vencimiento vacíos'; end if;
  if p_actual_quantity<>v_job.planned_quantity then v_mismatch:=true; end if;
  for v_expected in select (x->>'component_id')::uuid component_id,
    (x->>'quantity')::numeric quantity
    from jsonb_array_elements(v_job.formula_snapshot) x loop
    if (select coalesce(sum(case when e.kind='issue' then e.quantity else -e.quantity end),0)
      from public.production_job_events e where e.company_id=p_company and e.job_id=p_job
        and e.component_id=v_expected.component_id)<>v_expected.quantity then
      v_mismatch:=true; end if;
  end loop;
  if exists(select 1 from public.production_job_events e
    where e.company_id=p_company and e.job_id=p_job
      and not exists(select 1 from jsonb_array_elements(v_job.formula_snapshot) x
        where x->>'component_id'=e.component_id::text)
    group by e.component_id
    having sum(case when e.kind='issue' then e.quantity else -e.quantity end)>0) then
    v_mismatch:=true; end if;
  if v_mismatch and length(btrim(coalesce(p_variance_note,'')))<5 then
    raise exception 'Explicá la diferencia entre lo previsto y lo fabricado'; end if;
  select round(coalesce(sum(case when e.kind='issue' then 1 else -1 end
    *e.quantity*e.unit_cost),0),2) into v_cost
    from public.production_job_events e where e.company_id=p_company and e.job_id=p_job;
  if v_cost<0 then raise exception 'Los consumos de la orden son inconsistentes'; end if;
  if not exists(select 1 from public.production_job_events e
    where e.company_id=p_company and e.job_id=p_job and e.kind='issue'
      and e.quantity>(select coalesce(sum(r.quantity),0)
        from public.production_job_events r where r.company_id=e.company_id
          and r.issue_id=e.id)) then
    raise exception 'No quedan insumos consumidos para fabricar el producto'; end if;
  v_run:=gen_random_uuid();
  v_output:=public.post_stock_operation(p_company,v_job.product_id,
    v_job.warehouse_id,null,'receipt',p_actual_quantity,
    'Fabricación orden '||p_job::text,gen_random_uuid(),v_lot,p_expires_on);
  insert into public.production_runs(id,company_id,product_id,formula_version,
    quantity,warehouse_id,output_operation_id,estimated_cost,request_id,
    request_payload,note,actor_id)
  values(v_run,p_company,v_job.product_id,v_job.formula_version,
    p_actual_quantity,v_job.warehouse_id,v_output,v_cost,p_request_id,
    jsonb_build_object('job',p_job,'actual_quantity',p_actual_quantity,
      'output_lot',v_lot,'expiry',p_expires_on),v_job.note,auth.uid());
  update public.production_jobs set status='completed',actual_quantity=p_actual_quantity,
    output_lot=v_lot,output_expiry=p_expires_on,
    variance_note=nullif(btrim(p_variance_note),''),run_id=v_run,
    completion_request_id=p_request_id,completed_at=clock_timestamp()
    where company_id=p_company and id=p_job;
  if v_job.plan_id is not null then
    update public.production_plans set status='completed',run_id=v_run,
      completion_request_id=p_request_id,completed_at=clock_timestamp()
      where company_id=p_company and id=v_job.plan_id and status='planned';
    if not found then raise exception 'La planificación fue modificada'; end if;
  end if;
  return v_run;
end;
$$;

create function public.cancel_production_job(p_company uuid,p_job uuid,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare v_job public.production_jobs%rowtype; v_open numeric;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','update') then
    raise exception 'Sin permiso para cancelar órdenes' using errcode='42501'; end if;
  if length(btrim(coalesce(p_reason,''))) not between 5 and 300 then
    raise exception 'Indicá un motivo de al menos cinco caracteres'; end if;
  select * into v_job from public.production_jobs
    where company_id=p_company and id=p_job for update;
  if not found or v_job.status not in ('queued','in_progress') then
    raise exception 'La orden no se puede cancelar'; end if;
  select coalesce(sum(case when e.kind='issue' then e.quantity else -e.quantity end),0)
    into v_open from public.production_job_events e
    where e.company_id=p_company and e.job_id=p_job;
  if v_open<>0 then
    raise exception 'Devolvé todos los insumos pendientes antes de cancelar la orden'; end if;
  update public.production_jobs set status='cancelled',cancelled_at=clock_timestamp(),
    cancel_reason=btrim(p_reason) where company_id=p_company and id=p_job;
  if v_job.plan_id is not null then
    update public.production_plans set status='cancelled',cancelled_at=clock_timestamp()
      where company_id=p_company and id=v_job.plan_id and status='planned';
    if not found then raise exception 'La planificación fue modificada'; end if;
  end if;
end;
$$;

create table public.production_one_step_requests (
  company_id uuid not null,
  request_id uuid not null,
  request_payload jsonb not null,
  job_id uuid not null,
  run_id uuid not null,
  actor_id uuid not null references auth.users(id),
  primary key(company_id,request_id),
  foreign key(company_id,job_id) references public.production_jobs(company_id,id),
  foreign key(company_id,run_id) references public.production_runs(company_id,id)
);
revoke all on public.production_one_step_requests from public,anon,authenticated;

create function public.complete_production_now(p_company uuid,p_product uuid,
  p_planned_quantity numeric,p_actual_quantity numeric,p_warehouse uuid,
  p_output_lot text,p_expires_on date,p_note text,p_variance_note text,
  p_inputs jsonb,p_request_id uuid,p_finish_request_id uuid,p_plan uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_previous public.production_one_step_requests%rowtype;
  v_payload jsonb; v_job uuid; v_run uuid; v_input jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert')
    or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Necesitás permisos de producción y stock' using errcode='42501'; end if;
  if p_request_id is null or p_finish_request_id is null
    or jsonb_typeof(p_inputs) is distinct from 'array'
    or jsonb_array_length(p_inputs) not between 1 and 40 then
    raise exception 'Revisá los insumos de la fabricación'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('job-create:'||p_company::text||':'||p_request_id::text,0));
  v_payload:=jsonb_build_object('product',p_product,'planned',p_planned_quantity,
    'actual',p_actual_quantity,'warehouse',p_warehouse,
    'lot',nullif(btrim(p_output_lot),''),'expires',p_expires_on,
    'note',btrim(p_note),'variance',nullif(btrim(p_variance_note),''),
    'inputs',p_inputs,'plan',p_plan,'finish',p_finish_request_id);
  select * into v_previous from public.production_one_step_requests
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_previous.actor_id<>auth.uid() or v_previous.request_payload<>v_payload then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_previous.run_id;
  end if;
  v_job:=public.create_production_job(p_company,p_product,p_planned_quantity,
    p_warehouse,null,p_note,p_request_id,p_plan);
  for v_input in select value from jsonb_array_elements(p_inputs) x(value) loop
    perform public.issue_production_material(p_company,v_job,
      (v_input->>'component_id')::uuid,(v_input->>'warehouse_id')::uuid,
      v_input->>'lot_code',(v_input->>'quantity')::numeric,
      'Fabricación completada',gen_random_uuid());
  end loop;
  v_run:=public.finish_production_job(p_company,v_job,p_actual_quantity,
    p_output_lot,p_expires_on,p_variance_note,p_finish_request_id);
  insert into public.production_one_step_requests(company_id,request_id,
    request_payload,job_id,run_id,actor_id)
  values(p_company,p_request_id,v_payload,v_job,v_run,auth.uid());
  return v_run;
end;
$$;

-- Evita que una planificación vinculada se complete o cancele por el flujo antiguo.
create or replace function public.cancel_production_plan(p_company uuid,p_plan uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_plan public.production_plans%rowtype;
begin
  if not private.has_permission(p_company,'production','update') then
    raise exception 'Sin permiso para cancelar planes' using errcode='42501'; end if;
  select * into v_plan from public.production_plans
    where company_id=p_company and id=p_plan for update;
  if not found then raise exception 'Plan inexistente'; end if;
  if exists(select 1 from public.production_jobs j
    where j.company_id=p_company and j.plan_id=p_plan) then
    raise exception 'Este plan tiene una orden. Gestioná su estado desde Fabricación'; end if;
  if v_plan.status='completed' then
    raise exception 'Una fabricación registrada no se puede cancelar'; end if;
  if v_plan.status='planned' then
    update public.production_plans set status='cancelled',cancelled_at=clock_timestamp()
      where company_id=p_company and id=p_plan;
  end if;
  return p_plan;
end;
$$;
revoke execute on function public.complete_production_plan(uuid,uuid,uuid,jsonb,text,date)
  from public,anon,authenticated;

revoke execute on function public.create_production_job(uuid,uuid,numeric,uuid,date,text,uuid,uuid),
  public.start_production_job(uuid,uuid),
  public.issue_production_material(uuid,uuid,uuid,uuid,text,numeric,text,uuid),
  public.return_production_material(uuid,uuid,uuid,numeric,text,uuid),
  public.finish_production_job(uuid,uuid,numeric,text,date,text,uuid),
  public.cancel_production_job(uuid,uuid,text),
  public.complete_production_now(uuid,uuid,numeric,numeric,uuid,text,date,text,text,jsonb,uuid,uuid,uuid)
  from public,anon;
grant execute on function public.create_production_job(uuid,uuid,numeric,uuid,date,text,uuid,uuid),
  public.start_production_job(uuid,uuid),
  public.issue_production_material(uuid,uuid,uuid,uuid,text,numeric,text,uuid),
  public.return_production_material(uuid,uuid,uuid,numeric,text,uuid),
  public.finish_production_job(uuid,uuid,numeric,text,date,text,uuid),
  public.cancel_production_job(uuid,uuid,text),
  public.complete_production_now(uuid,uuid,numeric,numeric,uuid,text,date,text,text,jsonb,uuid,uuid,uuid)
  to authenticated;

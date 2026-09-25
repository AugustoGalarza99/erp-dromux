-- ERP Dromux · planificación de fabricación. Ejecutar luego de 011.
-- La planificación no reserva stock; la ejecución reutiliza post_production_run.
create table public.production_plans (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  request_id uuid not null,
  product_id uuid not null,
  warehouse_id uuid not null,
  quantity numeric(18,6) not null check (quantity > 0),
  formula_version integer not null,
  estimated_cost numeric(18,2) not null check (estimated_cost >= 0),
  component_snapshot jsonb not null,
  due_on date,
  note text not null check (length(btrim(note)) between 3 and 400),
  status text not null default 'planned' check (status in ('planned','completed','cancelled')),
  run_id uuid,
  completion_request_id uuid,
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  cancelled_at timestamptz,
  unique(company_id,id),
  unique(company_id,request_id),
  unique(company_id,run_id),
  foreign key(company_id,product_id) references public.items(company_id,id),
  foreign key(company_id,warehouse_id) references public.warehouses(company_id,id),
  foreign key(company_id,run_id) references public.production_runs(company_id,id),
  check ((status='completed' and run_id is not null and completed_at is not null
    and completion_request_id is not null) or
    (status<>'completed' and run_id is null and completed_at is null
      and completion_request_id is null)),
  check ((status='cancelled')=(cancelled_at is not null))
);

create index production_plans_queue on public.production_plans(company_id,status,due_on,created_at);

alter table public.production_plans enable row level security;
create policy production_plans_read on public.production_plans for select to authenticated
  using ((select private.has_permission(company_id,'production','read')));
revoke all on public.production_plans from anon,authenticated;
grant select on public.production_plans to authenticated;

create function public.create_production_plan(
  p_company uuid,p_product uuid,p_quantity numeric,p_warehouse uuid,
  p_due_on date,p_note text,p_request_id uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_formula public.production_formulas%rowtype;
  v_previous public.production_plans%rowtype;
  v_snapshot jsonb;
  v_cost numeric;
  v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert') then
    raise exception 'Sin permiso para planificar producción' using errcode='42501';
  end if;
  if p_request_id is null or p_product is null or p_warehouse is null
    or p_quantity is null or p_quantity <= 0 or p_quantity >= 1000000000000
    or p_quantity <> round(p_quantity,6)
    or p_note is null or length(btrim(p_note)) not between 3 and 400 then
    raise exception 'Revisá producto, cantidad, depósito y nota';
  end if;
  select * into v_previous from public.production_plans
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_previous.actor_id <> auth.uid() or v_previous.product_id <> p_product
      or v_previous.quantity <> p_quantity or v_previous.warehouse_id <> p_warehouse
      or v_previous.due_on is distinct from p_due_on or v_previous.note <> btrim(p_note) then
      raise exception 'Esta solicitud ya se utilizó con otros datos';
    end if;
    return v_previous.id;
  end if;
  select * into v_formula from public.production_formulas
    where company_id=p_company and product_id=p_product for share;
  if not found then raise exception 'El producto no tiene fórmula'; end if;
  perform 1 from public.items where company_id=p_company and id=p_product
    and active and item_type in ('semi_finished','finished_product') for share;
  if not found then raise exception 'El producto está inactivo'; end if;
  perform 1 from public.warehouses where company_id=p_company
    and id=p_warehouse and active for share;
  if not found then raise exception 'El depósito está inactivo'; end if;
  select jsonb_agg(jsonb_build_object('component_id',l.component_id,
    'quantity',l.quantity*p_quantity/v_formula.batch_quantity,
    'unit_cost',private.production_unit_cost(p_company,l.component_id))
    order by l.component_id)
  into v_snapshot from public.production_formula_lines l
  where l.company_id=p_company and l.product_id=p_product;
  if v_snapshot is null then raise exception 'La fórmula no tiene componentes'; end if;
  if exists (select 1 from jsonb_array_elements(v_snapshot) component
    where (component->>'quantity')::numeric <= 0
      or (component->>'quantity')::numeric >= 1000000000000
      or (component->>'quantity')::numeric <> round((component->>'quantity')::numeric,6)) then
    raise exception 'Esta cantidad genera consumos con más de seis decimales';
  end if;
  v_cost := round(private.production_unit_cost(p_company,p_product)*p_quantity,2);
  insert into public.production_plans(company_id,request_id,product_id,warehouse_id,
    quantity,formula_version,estimated_cost,component_snapshot,due_on,note,actor_id)
  values(p_company,p_request_id,p_product,p_warehouse,p_quantity,
    v_formula.version,v_cost,v_snapshot,p_due_on,btrim(p_note),auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

create function public.complete_production_plan(
  p_company uuid,p_plan uuid,p_request_id uuid,
  p_inputs jsonb,p_output_lot text,p_expires_on date
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_plan public.production_plans%rowtype;
  v_run uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert')
    or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Necesitás permiso de producción y stock' using errcode='42501';
  end if;
  if p_request_id is null then raise exception 'Solicitud inválida'; end if;
  select * into v_plan from public.production_plans
  where company_id=p_company and id=p_plan for update;
  if not found then raise exception 'Plan inexistente'; end if;
  if v_plan.status='completed' then
    if v_plan.completion_request_id <> p_request_id then
      raise exception 'Esta planificación ya fue completada';
    end if;
    return v_plan.run_id;
  end if;
  if v_plan.status<>'planned' then raise exception 'Esta planificación fue cancelada'; end if;
  perform 1 from public.production_formulas f
    where f.company_id=p_company and f.product_id=v_plan.product_id
      and f.version=v_plan.formula_version for share;
  if not found then
    raise exception 'La fórmula cambió. Creá un plan nuevo para revisar los insumos';
  end if;
  v_run := public.post_production_run(p_company,v_plan.product_id,p_request_id,
    v_plan.quantity,v_plan.warehouse_id,p_output_lot,p_expires_on,
    v_plan.note,p_inputs);
  update public.production_plans set status='completed',run_id=v_run,
    completion_request_id=p_request_id,completed_at=clock_timestamp()
  where company_id=p_company and id=p_plan;
  return v_run;
end;
$$;

create function public.cancel_production_plan(p_company uuid,p_plan uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_plan public.production_plans%rowtype;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','update') then
    raise exception 'Sin permiso para cancelar planes' using errcode='42501';
  end if;
  select * into v_plan from public.production_plans
    where company_id=p_company and id=p_plan for update;
  if not found then raise exception 'Plan inexistente'; end if;
  if v_plan.status='completed' then raise exception 'Una fabricación registrada no se puede cancelar'; end if;
  if v_plan.status='planned' then
    update public.production_plans set status='cancelled',cancelled_at=clock_timestamp()
    where company_id=p_company and id=p_plan;
  end if;
  return p_plan;
end;
$$;

revoke execute on function public.create_production_plan(uuid,uuid,numeric,uuid,date,text,uuid),
  public.complete_production_plan(uuid,uuid,uuid,jsonb,text,date),
  public.cancel_production_plan(uuid,uuid) from public,anon;
grant execute on function public.create_production_plan(uuid,uuid,numeric,uuid,date,text,uuid),
  public.complete_production_plan(uuid,uuid,uuid,jsonb,text,date),
  public.cancel_production_plan(uuid,uuid) to authenticated;

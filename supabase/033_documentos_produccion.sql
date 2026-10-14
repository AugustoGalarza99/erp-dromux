-- Ejecutar una vez después de 032. Formatos por empresa y envasado.
begin;
alter table public.items
  add column yield_enabled boolean not null default false,
  add column yield_factor numeric(12,6) not null default 1 check(yield_factor>0 and yield_factor<=1000);
create table public.production_document_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  logo_data text not null default '', document_code text not null default 'OP',
  revision text not null default '01', observation_labels jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default clock_timestamp()
);
create table public.production_packaging_types (
  id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
  name text not null check(length(btrim(name)) between 2 and 100),
  capacity numeric(18,6) not null check(capacity>0), unit_id uuid not null,
  active boolean not null default true, unique(company_id,id),
  foreign key(company_id,unit_id) references public.units(company_id,id)
);
create unique index packaging_names on public.production_packaging_types(company_id,lower(name));
alter table public.production_document_settings enable row level security;
alter table public.production_packaging_types enable row level security;
create policy document_settings_read on public.production_document_settings for select to authenticated
  using(private.has_permission(company_id,'production','read') or (private.get_user_role(company_id)='admin' and private.has_permission(company_id,'dashboard','read')));
create policy packaging_types_read on public.production_packaging_types for select to authenticated
  using(private.has_permission(company_id,'production','read'));
revoke all on public.production_document_settings,public.production_packaging_types from public,anon,authenticated;
grant select on public.production_document_settings,public.production_packaging_types to authenticated;

create function public.save_production_document_settings(p_company uuid,p_logo text,p_code text,p_revision text,p_labels jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare v_label jsonb;
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'admin' then
    raise exception 'Solo el administrador configura el formato' using errcode='42501'; end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  if p_logo is null or length(p_logo)>120000 or length(btrim(coalesce(p_code,''))) not between 1 and 40
    or length(btrim(coalesce(p_revision,''))) not between 1 and 20
    or p_labels is null or jsonb_typeof(p_labels)<>'array' or jsonb_array_length(p_labels)>12 then
    raise exception 'Revisá logo, código, revisión y hasta doce campos'; end if;
  if p_logo<>'' and p_logo !~ '^data:image/png;base64,[A-Za-z0-9+/]+={0,2}$' then
    raise exception 'El logo debe ser PNG'; end if;
  if p_logo<>'' and encode(substring(decode(split_part(p_logo,',',2),'base64') from 1 for 8),'hex')<>'89504e470d0a1a0a' then
    raise exception 'El archivo no es un logo PNG válido'; end if;
  for v_label in select value from jsonb_array_elements(p_labels) loop
    if jsonb_typeof(v_label)<>'string' or length(btrim(v_label#>>'{}')) not between 2 and 80 then
      raise exception 'Cada título debe tener entre 2 y 80 caracteres'; end if;
  end loop;
  if (select count(distinct lower(btrim(value))) from jsonb_array_elements_text(p_labels))<>jsonb_array_length(p_labels) then
    raise exception 'No repitas títulos de observaciones'; end if;
  insert into public.production_document_settings(company_id,logo_data,document_code,revision,observation_labels)
    values(p_company,p_logo,btrim(p_code),btrim(p_revision),p_labels)
  on conflict(company_id) do update set logo_data=excluded.logo_data,document_code=excluded.document_code,
    revision=excluded.revision,observation_labels=excluded.observation_labels,updated_at=clock_timestamp();
end; $$;

create function public.save_production_packaging_type(p_company uuid,p_id uuid,p_name text,p_capacity numeric,p_unit uuid,p_active boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','update') then
    raise exception 'Sin permiso para gestionar envasados' using errcode='42501'; end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  if length(btrim(coalesce(p_name,''))) not between 2 and 100 or p_capacity is null or p_capacity<=0
    or p_capacity>=1000000000000 or p_capacity<>round(p_capacity,6) or p_active is null then
    raise exception 'Nombre y capacidad inválidos'; end if;
  perform 1 from public.units where company_id=p_company and id=p_unit and active;
  if not found then raise exception 'Elegí una unidad activa'; end if;
  if p_id is null then
    insert into public.production_packaging_types(company_id,name,capacity,unit_id,active)
      values(p_company,btrim(p_name),p_capacity,p_unit,p_active) returning id into v_id;
  else
    update public.production_packaging_types set name=btrim(p_name),capacity=p_capacity,unit_id=p_unit,active=p_active
      where company_id=p_company and id=p_id returning id into v_id;
    if v_id is null then raise exception 'Envasado inexistente'; end if;
  end if;
  return v_id;
end; $$;

create function public.save_production_formula_v2(p_company uuid,p_product uuid,p_batch_quantity numeric,
  p_lines jsonb,p_yield_enabled boolean,p_yield_factor numeric)
returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','update') then
    raise exception 'Sin permiso para editar fórmulas' using errcode='42501'; end if;
  if p_yield_enabled is null or p_yield_factor is null or p_yield_factor<=0 or p_yield_factor>1000
    or p_yield_factor<>round(p_yield_factor,6) then raise exception 'Factor de rendimiento inválido'; end if;
  perform public.save_production_formula(p_company,p_product,p_batch_quantity,p_lines);
  update public.items set yield_enabled=p_yield_enabled,
    yield_factor=case when p_yield_enabled then p_yield_factor else 1 end
    where company_id=p_company and id=p_product;
end; $$;

alter table public.production_jobs
  add column number bigint,
  add column yield_factor numeric(12,6) not null default 1,
  add column expected_output numeric(18,6),
  add column document_snapshot jsonb not null default '{}'::jsonb,
  add column work_options jsonb not null default '{}'::jsonb,
  add column work_request_options jsonb not null default '{}'::jsonb;
with numbered as (select id,company_id,row_number() over(partition by company_id order by created_at,id) n from public.production_jobs)
update public.production_jobs j set number=n.n,expected_output=j.planned_quantity
  from numbered n where n.company_id=j.company_id and n.id=j.id;
alter table public.production_jobs alter column number set not null;
alter table public.production_jobs alter column expected_output set not null;
alter table public.production_jobs add constraint production_job_number_unique unique(company_id,number);
create table private.production_job_numbers(company_id uuid primary key references public.companies(id) on delete cascade,next_number bigint not null);
insert into private.production_job_numbers select company_id,max(number)+1 from public.production_jobs group by company_id;
revoke all on private.production_job_numbers from public,anon,authenticated;

create function private.snapshot_work_options(p_company uuid,p_options jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_pack jsonb; v_count numeric; v_type record; v_result jsonb:='[]'; v_obs jsonb; v_labels jsonb;
begin
  if p_options is null or jsonb_typeof(p_options)<>'object'
    or jsonb_typeof(coalesce(p_options->'packaging','[]'))<>'array'
    or jsonb_array_length(coalesce(p_options->'packaging','[]'))>40
    or jsonb_typeof(coalesce(p_options->'observations','{}'))<>'object'
    or length(coalesce(p_options->>'observations',''))>10000 then raise exception 'Datos de trabajo inválidos'; end if;
  for v_pack in select value from jsonb_array_elements(coalesce(p_options->'packaging','[]')) loop
    v_count:=(v_pack->>'count')::numeric;
    if v_count is null or v_count<1 or v_count>=1000000000 or v_count<>trunc(v_count) then
      raise exception 'Indicá una cantidad entera de envases'; end if;
    select t.*,u.symbol into v_type from public.production_packaging_types t
      join public.units u on u.company_id=t.company_id and u.id=t.unit_id
      where t.company_id=p_company and t.id=(v_pack->>'id')::uuid and t.active;
    if not found then raise exception 'Elegí un envasado activo de esta empresa'; end if;
    if exists(select 1 from jsonb_array_elements(v_result) x where x->>'id'=v_type.id::text) then
      raise exception 'No repitas el tipo de envasado'; end if;
    v_result:=v_result||jsonb_build_array(jsonb_build_object('id',v_type.id,'name',v_type.name,
      'capacity',v_type.capacity,'unit',v_type.symbol,'count',v_count));
  end loop;
  v_obs:=coalesce(p_options->'observations','{}');
  select observation_labels into v_labels from public.production_document_settings where company_id=p_company;
  if exists(select 1 from jsonb_each(v_obs) e where jsonb_typeof(e.value)<>'string'
    or length(e.value#>>'{}')>500 or not (coalesce(v_labels,'[]') ? e.key)) then
    raise exception 'Las observaciones deben corresponder a los campos configurados'; end if;
  return jsonb_build_object('packaging',v_result,'observations',v_obs);
end; $$;
revoke all on function private.snapshot_work_options(uuid,jsonb) from public,anon,authenticated;

create function private.prepare_production_document() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_factor numeric; v_options jsonb;
begin
  insert into private.production_job_numbers(company_id,next_number) values(new.company_id,2)
    on conflict(company_id) do update set next_number=private.production_job_numbers.next_number+1
    returning next_number-1 into new.number;
  select case when yield_enabled then yield_factor else 1 end into v_factor
    from public.items where company_id=new.company_id and id=new.product_id;
  new.yield_factor:=coalesce(v_factor,1);
  new.expected_output:=round(new.planned_quantity*new.yield_factor,6);
  if new.expected_output<=0 or new.expected_output>=1000000000000 then raise exception 'Salida esperada fuera de rango'; end if;
  select jsonb_build_object('code',document_code,'revision',revision,'labels',observation_labels)
    into new.document_snapshot from public.production_document_settings where company_id=new.company_id;
  new.document_snapshot:=coalesce(new.document_snapshot,'{}');
  v_options:=nullif(pg_catalog.current_setting('dromux.work_options',true),'')::jsonb;
  new.work_request_options:=coalesce(v_options,'{}');
  new.work_options:=private.snapshot_work_options(new.company_id,coalesce(v_options,'{}'));
  return new;
end; $$;
create trigger production_job_document before insert on public.production_jobs
  for each row execute function private.prepare_production_document();
revoke all on function private.prepare_production_document() from public,anon,authenticated;

create function public.create_production_work_order(p_company uuid,p_product uuid,p_quantity numeric,
  p_warehouse uuid,p_due date,p_note text,p_request uuid,p_plan uuid,p_options jsonb,p_finish jsonb default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.production_jobs%rowtype; v_snapshot jsonb; v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert') then
    raise exception 'Sin permiso para crear órdenes' using errcode='42501'; end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('work-order:'||p_company::text||':'||p_request::text,0));
  select * into v_old from public.production_jobs where company_id=p_company and request_id=p_request;
  if found then
    if v_old.work_request_options is distinct from p_options then raise exception 'Solicitud usada con otro envasado u observaciones'; end if;
  else
    v_snapshot:=private.snapshot_work_options(p_company,p_options);
  end if;
  perform pg_catalog.set_config('dromux.work_options',p_options::text,true);
  if p_finish is null then
    v_id:=public.create_production_job(p_company,p_product,p_quantity,p_warehouse,p_due,p_note,p_request,p_plan);
  else
    v_id:=public.complete_production_now(p_company,p_product,p_quantity,(p_finish->>'actual')::numeric,
      p_warehouse,nullif(p_finish->>'lot',''),nullif(p_finish->>'expiry','')::date,p_note,
      nullif(p_finish->>'variance',''),p_finish->'inputs',p_request,(p_finish->>'request')::uuid,p_plan);
    -- La función de fabricación inmediata devuelve la orden según la versión 020.
    select id into v_id from public.production_jobs where company_id=p_company and request_id=p_request;
  end if;
  perform pg_catalog.set_config('dromux.work_options','',true);
  return v_id;
end; $$;

revoke all on function public.save_production_document_settings(uuid,text,text,text,jsonb),
  public.save_production_packaging_type(uuid,uuid,text,numeric,uuid,boolean),
  public.save_production_formula_v2(uuid,uuid,numeric,jsonb,boolean,numeric),
  public.create_production_work_order(uuid,uuid,numeric,uuid,date,text,uuid,uuid,jsonb,jsonb) from public,anon;
grant execute on function public.save_production_document_settings(uuid,text,text,text,jsonb),
  public.save_production_packaging_type(uuid,uuid,text,numeric,uuid,boolean),
  public.save_production_formula_v2(uuid,uuid,numeric,jsonb,boolean,numeric),
  public.create_production_work_order(uuid,uuid,numeric,uuid,date,text,uuid,uuid,jsonb,jsonb) to authenticated;

-- La cantidad REAL sigue siendo la única que ingresa al stock.
create or replace function public.finish_production_job(p_company uuid,p_job uuid,
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
  if p_actual_quantity<>v_job.expected_output then v_mismatch:=true; end if;
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


create or replace function private.production_unit_cost(p_company uuid,p_item uuid,p_path uuid[] default '{}')
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
  select f.batch_quantity * case when i.yield_enabled then i.yield_factor else 1 end into v_batch
  from public.production_formulas f join public.items i on i.company_id=f.company_id and i.id=f.product_id
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


alter table public.production_jobs add column details_updated_at timestamptz not null default clock_timestamp();
create function public.save_production_work_details(p_company uuid,p_job uuid,p_counts jsonb,p_observations jsonb,p_expected timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare v_job public.production_jobs%rowtype; v_pack jsonb; v_result jsonb:='[]'; v_count numeric;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','update') then
    raise exception 'Sin permiso para actualizar la orden' using errcode='42501'; end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  select * into v_job from public.production_jobs where company_id=p_company and id=p_job for update;
  if not found or v_job.status='cancelled' then raise exception 'Orden inexistente o cancelada'; end if;
  if p_expected is null or v_job.details_updated_at<>p_expected then raise exception 'Los controles cambiaron. Reabrí el formulario'; end if;
  if jsonb_typeof(p_counts) is distinct from 'object' or jsonb_typeof(p_observations) is distinct from 'object'
    or length(p_observations::text)>10000 or length(p_counts::text)>5000 then raise exception 'Datos de controles inválidos'; end if;
  if exists(select 1 from jsonb_each(p_observations) e where jsonb_typeof(e.value)<>'string'
    or length(e.value#>>'{}')>500 or not (coalesce(v_job.document_snapshot->'labels','[]') ? e.key)) then
    raise exception 'Usá los campos originales de la orden'; end if;
  if exists(select 1 from jsonb_each(p_counts) e where not exists(
    select 1 from jsonb_array_elements(coalesce(v_job.work_options->'packaging','[]')) x where x->>'id'=e.key)) then
    raise exception 'Envasado no asociado a esta orden'; end if;
  for v_pack in select value from jsonb_array_elements(coalesce(v_job.work_options->'packaging','[]')) loop
    v_count:=nullif(p_counts->>(v_pack->>'id'),'')::numeric;
    if v_count is not null and (v_count<0 or v_count>=1000000000 or v_count<>trunc(v_count)) then
      raise exception 'La cantidad real de envases debe ser entera y no negativa'; end if;
    v_result:=v_result||jsonb_build_array(v_pack||jsonb_build_object('actual_count',v_count));
  end loop;
  update public.production_jobs set work_options=jsonb_build_object('packaging',v_result,'observations',p_observations),
    details_updated_at=clock_timestamp() where company_id=p_company and id=p_job;
end; $$;
revoke all on function public.save_production_work_details(uuid,uuid,jsonb,jsonb,timestamptz) from public,anon;
grant execute on function public.save_production_work_details(uuid,uuid,jsonb,jsonb,timestamptz) to authenticated;

-- Los envases con stock pueden registrarse como insumos de la fórmula y del proceso.
create or replace function public.save_production_formula(
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
      and i.active and i.item_type in ('raw_material','semi_finished','consumable') for share;
    if not found then raise exception 'Elegí materias primas, semielaborados o insumos activos'; end if;
    insert into public.production_formula_lines(company_id,product_id,component_id,quantity)
    values(p_company,p_product,v_component,v_quantity);
  end loop;
  -- Calcula recursivamente y revierte la transacción si aparece un ciclo o falta un costo.
  perform private.production_unit_cost(p_company,p_product);
  return v_version;
end;
$$;

create or replace function public.issue_production_material(p_company uuid,p_job uuid,
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
    and i.active and i.item_type in ('raw_material','semi_finished','consumable') for share;
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


create or replace function public.issue_delivery_note(
  p_company uuid, p_kind text, p_job uuid, p_recipient text,
  p_note text, p_lines jsonb, p_request uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_payload jsonb;
  v_existing public.delivery_notes%rowtype;
  v_job public.production_jobs%rowtype;
  v_line jsonb;
  v_item public.items%rowtype;
  v_warehouse text;
  v_symbol text;
  v_id uuid;
  v_number bigint;
  v_line_no integer := 0;
  v_quantity numeric;
  v_warehouse_id uuid;
  v_lot text;
  v_operation uuid;
  v_event uuid;
begin
  if auth.uid() is null
    or not private.has_permission(p_company, 'stock', 'insert')
    or (p_kind = 'production' and
      not private.has_permission(p_company, 'production', 'insert')) then
    raise exception 'Necesitás permiso para entregar stock y registrar fabricación'
      using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('production','materials','products')
    or (p_kind = 'production') is distinct from (p_job is not null)
    or p_request is null
    or length(btrim(coalesce(p_recipient, ''))) not between 3 and 120
    or length(btrim(coalesce(p_note, ''))) not between 3 and 300
    or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) not between 1 and 40 then
    raise exception 'Revisá tipo de remito, destinatario e insumos';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('delivery:' || p_company::text || ':' || p_request::text, 0));
  v_payload := jsonb_build_object('kind', p_kind, 'job', p_job,
    'recipient', btrim(p_recipient), 'note', btrim(p_note), 'lines', p_lines);
  select * into v_existing from public.delivery_notes
    where company_id = p_company and request_id = p_request;
  if found then
    if v_existing.actor_id <> auth.uid() or v_existing.request_payload <> v_payload then
      raise exception 'Esta solicitud ya se usó con otros datos';
    end if;
    return v_existing.id;
  end if;
  if p_job is not null then
    select * into v_job from public.production_jobs
      where company_id = p_company and id = p_job for update;
    if not found or v_job.status not in ('queued', 'in_progress') then
      raise exception 'La orden de fabricación no admite más entregas';
    end if;
  end if;
  perform 1 from public.companies where id = p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  insert into public.delivery_note_counters(company_id) values (p_company)
    on conflict do nothing;
  update public.delivery_note_counters set next_number = next_number + 1
    where company_id = p_company returning next_number - 1 into v_number;
  insert into public.delivery_notes(company_id, number, request_id,
    request_payload, kind, job_id, recipient, note, actor_id)
  values (p_company, v_number, p_request, v_payload,
    p_kind, p_job, btrim(p_recipient), btrim(p_note), auth.uid())
  returning id into v_id;

  for v_line in select value from jsonb_array_elements(p_lines) x(value) loop
    v_line_no := v_line_no + 1;
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'Cada renglón debe contener un ítem'; end if;
    v_quantity := (v_line ->> 'quantity')::numeric;
    v_warehouse_id := (v_line ->> 'warehouse_id')::uuid;
    v_lot := nullif(btrim(v_line ->> 'lot_code'), '');
    if (v_line ->> 'item_id') is null or v_warehouse_id is null
      or v_quantity is null or v_quantity <= 0 or v_quantity >= 1000000000000
      or v_quantity <> round(v_quantity, 6) or length(coalesce(v_lot, '')) > 80 then
      raise exception 'Revisá ítem, cantidad, depósito y lote de cada renglón';
    end if;
    select * into v_item from public.items
      where company_id = p_company and id = (v_line ->> 'item_id')::uuid
        and active for share;
    if not found then raise exception 'El ítem está inactivo o no existe'; end if;
    if (p_kind = 'production'
        and v_item.item_type not in ('raw_material', 'semi_finished', 'consumable'))
      or (p_kind = 'materials'
        and v_item.item_type not in ('raw_material', 'semi_finished', 'consumable'))
      or (p_kind = 'products'
        and v_item.item_type not in ('semi_finished', 'finished_product')) then
      raise exception 'El tipo de ítem no corresponde a este remito';
    end if;
    select w.name into v_warehouse from public.warehouses w
      where w.company_id = p_company and w.id = v_warehouse_id and w.active for share;
    if not found then raise exception 'Elegí un depósito de origen activo'; end if;
    select u.symbol into v_symbol from public.units u
      where u.company_id = p_company and u.id = v_item.unit_id;
    if p_kind = 'production' then
      v_event := public.issue_production_material(p_company, p_job,
        v_item.id, v_warehouse_id, v_lot, v_quantity,
        'Remito Nº ' || v_number || ' · ' || left(btrim(p_note), 250),
        gen_random_uuid());
      select stock_operation_id into v_operation from public.production_job_events
        where company_id = p_company and id = v_event;
    else
      v_event := null;
      v_operation := public.post_stock_operation(p_company, v_item.id,
        v_warehouse_id, null, 'issue', v_quantity,
        'Remito Nº ' || v_number || ' · ' || left(btrim(p_note), 250),
        gen_random_uuid(), v_lot, null);
    end if;
    insert into public.delivery_note_lines(company_id, note_id, line_no,
      item_id, item_code, item_name, unit_symbol, warehouse_id,
      warehouse_name, lot_code, quantity, stock_operation_id, production_event_id)
    values (p_company, v_id, v_line_no, v_item.id, v_item.code, v_item.name,
      coalesce(v_symbol, ''), v_warehouse_id, v_warehouse, v_lot,
      v_quantity, v_operation, v_event);
  end loop;
  return v_id;
end;
$$;


commit;

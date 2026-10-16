-- Aplicar una vez después de 033. No elimina movimientos ni registros financieros.
begin;
alter table public.items add column archived boolean not null default false,
  add column archive_previous_active boolean;
alter table public.exchange_rate_types add column archived boolean not null default false,
  add column archive_previous_active boolean;
alter table public.production_formulas add column archived boolean not null default false;
alter table public.production_jobs add column archived boolean not null default false;
alter table public.production_runs add column archived boolean not null default false;
alter table public.production_plans add column archived boolean not null default false;
alter table public.delivery_notes add column archived boolean not null default false;
create table private.deleted_production_requests (
  company_id uuid not null references public.companies(id) on delete cascade,
  resource text not null, request_id uuid not null, actor_id uuid not null references auth.users(id),
  deleted_at timestamptz not null default clock_timestamp(),
  primary key(company_id,resource,request_id)
);
revoke all on private.deleted_production_requests from public,anon,authenticated;

create function private.cleanup_target(p_resource text)
returns table(table_name text,id_field text,permission text)
language sql immutable set search_path='' as $$
  select t.table_name,t.id_field,t.permission from (values
    ('items','items','id','items'),
    ('exchange_types','exchange_rate_types','id','purchases'),
    ('formulas','production_formulas','product_id','production'),
    ('jobs','production_jobs','id','production'),
    ('runs','production_runs','id','production'),
    ('plans','production_plans','id','production'),
    ('delivery_notes','delivery_notes','id','stock')
  ) t(resource,table_name,id_field,permission) where resource=p_resource
$$;
revoke all on function private.cleanup_target(text) from public,anon,authenticated;

-- Inspeccionar TODAS las FK, no solo las que conoce la pantalla.
create function private.cleanup_has_references(p_company uuid,p_resource text,p_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_target record; v_fk record; v_join text; v_found boolean; v_skip text[]:='{}';
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if p_resource='items' then v_skip:=array['supplier_items']; end if;
  if p_resource='formulas' then v_skip:=array['production_formula_lines']; end if;
  if p_resource='jobs' then v_skip:=array['production_job_reservations']; end if;
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
    execute format('select exists(select 1 from %I.%I c join public.%I p on %s where p.company_id=$1 and p.%I=$2)',
      v_fk.nspname,v_fk.relname,v_target.table_name,v_join,v_target.id_field)
      into v_found using p_company,p_id;
    if v_found then return true; end if;
  end loop;
  if p_resource='items' and (exists(
    select 1 from public.production_jobs j cross join lateral jsonb_array_elements(j.formula_snapshot) x
      where j.company_id=p_company and x->>'component_id'=p_id::text)
    or exists(select 1 from public.production_plans p cross join lateral jsonb_array_elements(p.component_snapshot) x
      where p.company_id=p_company and x->>'component_id'=p_id::text)) then return true; end if;
  if p_resource='formulas' and (exists(select 1 from public.production_jobs where company_id=p_company and product_id=p_id)
    or exists(select 1 from public.production_runs where company_id=p_company and product_id=p_id)
    or exists(select 1 from public.production_plans where company_id=p_company and product_id=p_id)
    or exists(select 1 from public.production_formula_lines where company_id=p_company and component_id=p_id)) then return true; end if;
  return false;
end; $$;
revoke all on function private.cleanup_has_references(uuid,text,uuid) from public,anon,authenticated;

create function public.cleanup_preview(p_company uuid,p_resource text,p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_target record; v_row jsonb; v_action text:='delete'; v_message text;
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if auth.uid() is null or not private.has_permission(p_company,v_target.permission,'delete') then
    raise exception 'Necesitás permiso de eliminar en este módulo' using errcode='42501'; end if;
  execute format('select to_jsonb(t) from public.%I t where company_id=$1 and %I=$2',v_target.table_name,v_target.id_field)
    into v_row using p_company,p_id;
  if v_row is null then raise exception 'El registro no existe en esta empresa'; end if;
  if (v_row->>'archived')::boolean then raise exception 'El registro ya está archivado'; end if;
  if p_resource='items' then
    if exists(select 1 from public.stock_balances where company_id=p_company and item_id=p_id and quantity<>0) then
      v_action:='blocked'; v_message:='El ítem todavía tiene stock. Regularizá sus existencias antes de retirarlo.';
    elsif exists(select 1 from public.production_formula_lines l join public.production_formulas f
      on f.company_id=l.company_id and f.product_id=l.product_id where l.company_id=p_company
        and (l.component_id=p_id or l.product_id=p_id) and not f.archived) then
      v_action:='blocked'; v_message:='El ítem forma parte de una fórmula activa. Modificá o archivá esa fórmula primero.';
    elsif exists(select 1 from public.production_jobs j where j.company_id=p_company and j.status in ('queued','in_progress')
      and (j.product_id=p_id or exists(select 1 from jsonb_array_elements(j.formula_snapshot) x where x->>'component_id'=p_id::text)))
      or exists(select 1 from public.production_plans p where p.company_id=p_company and p.status='planned'
        and (p.product_id=p_id or exists(select 1 from jsonb_array_elements(p.component_snapshot) x where x->>'component_id'=p_id::text)))
      or exists(select 1 from public.purchase_order_lines l join public.purchase_orders o on o.company_id=l.company_id and o.id=l.order_id
        where l.company_id=p_company and l.item_id=p_id and o.status in ('open','partial') and l.received_quantity<l.quantity) then
      v_action:='blocked'; v_message:='El ítem tiene fabricación, planificación o compras pendientes. Resolvé esas operaciones primero.';
    end if;
  elsif p_resource='exchange_types' then
    if exists(select 1 from public.items where company_id=p_company and active and reference_exchange_rate_type_id=p_id)
      or exists(select 1 from public.supplier_items q join public.items i on i.company_id=q.company_id and i.id=q.item_id
        join public.suppliers s on s.company_id=q.company_id and s.id=q.supplier_id
        where q.company_id=p_company and q.exchange_rate_type_id=p_id and i.active and s.active) then
      v_action:='blocked'; v_message:='Este dólar se usa en costos actuales. Cambiá primero el tipo de dólar de esos ítems o proveedores.';
    end if;
  elsif p_resource='formulas' then
    if exists(select 1 from public.production_jobs where company_id=p_company and product_id=p_id and status in ('queued','in_progress'))
      or exists(select 1 from public.production_plans where company_id=p_company and product_id=p_id and status='planned') then
      v_action:='blocked'; v_message:='Hay órdenes o planes pendientes de este producto. Terminá o cancelá el trabajo primero.';
    end if;
  elsif p_resource='jobs' then
    if v_row->>'status'='in_progress' or (v_row->>'status'='queued' and exists(
      select 1 from public.production_job_events where company_id=p_company and job_id=p_id)) then
      v_action:='blocked'; v_message:='La orden está en proceso o tiene entregas. Completala o devolvé los materiales y cancelala antes de retirarla.';
    end if;
  elsif p_resource='runs' then v_action:='archive';
  elsif p_resource='plans' and v_row->>'status'='planned' and exists(
    select 1 from public.production_jobs where company_id=p_company and plan_id=p_id) then
    v_action:='blocked'; v_message:='El plan tiene una orden vinculada. Gestioná primero esa orden.';
  elsif p_resource='delivery_notes' then v_action:='archive';
  end if;
  if v_action='delete' and private.cleanup_has_references(p_company,p_resource,p_id) then v_action:='archive'; end if;
  if v_action='delete' then v_message:='Se eliminará definitivamente este registro sin uso. La acción no se puede deshacer.'; end if;
  if v_action='archive' then v_message:=case when p_resource='delivery_notes'
    then 'El remito saldrá del listado, conservando la entrega y su historial. Archivar NO devuelve mercadería al stock. Para devolverla usá Anular entrega.'
    else 'El registro tiene información relacionada. Saldrá del listado y conservará sus movimientos, costos y vínculos. Podés recuperarlo en Archivados.' end; end if;
  return jsonb_build_object('action',v_action,'message',v_message);
end; $$;

create function public.cleanup_record(p_company uuid,p_resource text,p_id uuid,p_action text)
returns text language plpgsql security definer set search_path='' as $$
declare v_target record; v_preview jsonb; v_row jsonb; v_cost numeric;
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if auth.uid() is null or not private.has_permission(p_company,v_target.permission,'delete') then
    raise exception 'Sin permiso para retirar el registro' using errcode='42501'; end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  execute format('select to_jsonb(t) from public.%I t where company_id=$1 and %I=$2 for update',v_target.table_name,v_target.id_field)
    into v_row using p_company,p_id;
  if v_row is null then raise exception 'El registro ya no existe'; end if;
  v_preview:=public.cleanup_preview(p_company,p_resource,p_id);
  if v_preview->>'action'='blocked' then raise exception '%',v_preview->>'message'; end if;
  if p_action is null or p_action<>v_preview->>'action' then raise exception 'Cambió el uso del registro. Reabrí la confirmación para revisar la acción'; end if;
  if p_action='archive' then
    if p_resource in ('items','exchange_types') then
      execute format('update public.%I set archive_previous_active=active,active=false,archived=true where company_id=$1 and %I=$2',v_target.table_name,v_target.id_field)
        using p_company,p_id;
    else
      execute format('update public.%I set archived=true where company_id=$1 and %I=$2',v_target.table_name,v_target.id_field) using p_company,p_id;
    end if;
    return 'archive';
  end if;
  if p_resource='items' then
    update public.supplier_items set preferred=false where company_id=p_company and item_id=p_id and preferred;
    delete from public.supplier_items where company_id=p_company and item_id=p_id;
  elsif p_resource='formulas' then
    v_cost:=private.production_unit_cost(p_company,p_id);
    update public.items set reference_unit_cost=v_cost where company_id=p_company and id=p_id
      and reference_cost_usd is null and not exists(select 1 from public.supplier_items where company_id=p_company and item_id=p_id and preferred);
    delete from public.production_formula_lines where company_id=p_company and product_id=p_id;
  elsif p_resource='jobs' then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('production-reservations:'||p_company::text,0));
    delete from public.production_reservation_locations where company_id=p_company and job_id=p_id;
    delete from public.production_job_reservations where company_id=p_company and job_id=p_id;
  end if;
  if p_resource in ('jobs','plans') then
    insert into private.deleted_production_requests(company_id,resource,request_id,actor_id)
      values(p_company,p_resource,(v_row->>'request_id')::uuid,auth.uid()) on conflict do nothing;
  end if;
  execute format('delete from public.%I where company_id=$1 and %I=$2',v_target.table_name,v_target.id_field) using p_company,p_id;
  if p_resource='jobs' then perform private.rebalance_production_reservations(p_company); end if;
  return 'delete';
exception when foreign_key_violation then
  raise exception 'El registro tiene nuevos vínculos. Reabrí la confirmación para revisar la acción';
end; $$;

create function public.restore_archived_record(p_company uuid,p_resource text,p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_target record; v_row jsonb;
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if auth.uid() is null or not private.has_permission(p_company,v_target.permission,'delete') then
    raise exception 'Sin permiso para recuperar el registro' using errcode='42501'; end if;
  execute format('select to_jsonb(t) from public.%I t where company_id=$1 and %I=$2 and archived for update',v_target.table_name,v_target.id_field)
    into v_row using p_company,p_id;
  if v_row is null then raise exception 'No se encontró el registro archivado'; end if;
  if p_resource='items' and coalesce((v_row->>'archive_previous_active')::boolean,true) then
    perform 1 from public.exchange_rate_types t where t.company_id=p_company and (
      t.id=(v_row->>'reference_exchange_rate_type_id')::uuid or exists(
        select 1 from public.supplier_items q where q.company_id=p_company and q.item_id=p_id and q.exchange_rate_type_id=t.id)) for share;
    if exists(select 1 from public.exchange_rate_types t where t.company_id=p_company and not t.active and (
      t.id=(v_row->>'reference_exchange_rate_type_id')::uuid or exists(
        select 1 from public.supplier_items q where q.company_id=p_company and q.item_id=p_id and q.exchange_rate_type_id=t.id))) then
      raise exception 'Recuperá primero los tipos de dólar que usa este ítem'; end if;
  elsif p_resource='formulas' then
    perform 1 from public.items i where i.company_id=p_company and (i.id=p_id or exists(
      select 1 from public.production_formula_lines l where l.company_id=p_company and l.product_id=p_id and l.component_id=i.id)) for share;
    if exists(select 1 from public.items i where i.company_id=p_company and not i.active and (i.id=p_id or exists(
      select 1 from public.production_formula_lines l where l.company_id=p_company and l.product_id=p_id and l.component_id=i.id))) then
      raise exception 'Recuperá o activá primero el producto y sus componentes'; end if;
  end if;
  if p_resource in ('items','exchange_types') then
    execute format('update public.%I set archived=false,active=coalesce(archive_previous_active,true),archive_previous_active=null where company_id=$1 and %I=$2',v_target.table_name,v_target.id_field)
      using p_company,p_id;
  else
    execute format('update public.%I set archived=false where company_id=$1 and %I=$2',v_target.table_name,v_target.id_field) using p_company,p_id;
  end if;
end; $$;

create function public.archived_records(p_company uuid,p_resource text,p_search text default '',p_page integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_target record; v_label text; v_date text; v_count bigint; v_rows jsonb; v_filter text;
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if auth.uid() is null or not private.has_permission(p_company,v_target.permission,'read') then
    raise exception 'Sin acceso a este archivo' using errcode='42501'; end if;
  if p_page is null or p_page<0 or p_page>100000 or length(coalesce(p_search,''))>100 then raise exception 'Búsqueda o página inválida'; end if;
  v_label:=case p_resource
    when 'items' then 't.code||'' · ''||t.name'
    when 'exchange_types' then 't.name'
    when 'formulas' then '(select i.name from public.items i where i.company_id=t.company_id and i.id=t.product_id)'
    when 'jobs' then '''OF ''||t.number::text||'' · ''||(select i.name from public.items i where i.company_id=t.company_id and i.id=t.product_id)'
    when 'delivery_notes' then '''Remito ''||t.number::text||'' · ''||t.recipient'
    else '(select i.name from public.items i where i.company_id=t.company_id and i.id=t.product_id)' end;
  v_date:=case when p_resource='formulas' then 't.updated_at' when p_resource='exchange_types' then '(select max(e.created_at) from public.exchange_rates e where e.company_id=t.company_id and e.type_id=t.id)' else 't.created_at' end;
  v_filter:='t.company_id=$1 and t.archived and ('||v_label||') ilike ''%''||$2||''%''';
  execute format('select count(*) from public.%I t where %s',v_target.table_name,v_filter) into v_count using p_company,coalesce(p_search,'');
  execute format('select coalesce(jsonb_agg(x),''[]''::jsonb) from (select t.%I id,%s label,%s created_at from public.%I t where %s order by %s desc,t.%I limit 25 offset $3) x',
    v_target.id_field,v_label,v_date,v_target.table_name,v_filter,v_date,v_target.id_field)
    into v_rows using p_company,coalesce(p_search,''),p_page*25;
  return jsonb_build_object('rows',v_rows,'count',v_count);
end; $$;

-- No convertir un registro archivado en activo desde el formulario antiguo.
create function private.protect_archived_activity() returns trigger
language plpgsql set search_path='' as $$ begin
  if new.archived and new.active then raise exception 'Recuperá el registro desde Archivados antes de activarlo'; end if;
  return new;
end; $$;
create trigger item_archived_activity before insert or update of active,archived on public.items
  for each row execute function private.protect_archived_activity();
create trigger exchange_archived_activity before insert or update of active,archived on public.exchange_rate_types
  for each row execute function private.protect_archived_activity();
revoke all on function private.protect_archived_activity() from public,anon,authenticated;

create function private.guard_archived_recipe() returns trigger
language plpgsql security definer set search_path='' as $$ begin
  if exists(select 1 from public.production_formulas where company_id=new.company_id and product_id=new.product_id and archived) then
    raise exception 'La fórmula está archivada. Recuperala antes de fabricar o planificar'; end if;
  if exists(select 1 from private.deleted_production_requests where company_id=new.company_id
    and request_id=new.request_id and resource=case tg_table_name when 'production_jobs' then 'jobs' when 'production_plans' then 'plans' else 'runs' end) then
    raise exception 'Esta solicitud corresponde a un registro eliminado. Generá una nueva orden'; end if;
  return new;
end; $$;
create trigger guard_archived_job_recipe before insert on public.production_jobs
  for each row execute function private.guard_archived_recipe();
create trigger guard_archived_plan_recipe before insert on public.production_plans
  for each row execute function private.guard_archived_recipe();
create trigger guard_archived_run_recipe before insert on public.production_runs
  for each row execute function private.guard_archived_recipe();
revoke all on function private.guard_archived_recipe() from public,anon,authenticated;

revoke all on function public.cleanup_preview(uuid,text,uuid),public.cleanup_record(uuid,text,uuid,text),
  public.restore_archived_record(uuid,text,uuid),public.archived_records(uuid,text,text,integer) from public,anon;
grant execute on function public.cleanup_preview(uuid,text,uuid),public.cleanup_record(uuid,text,uuid,text),
  public.restore_archived_record(uuid,text,uuid),public.archived_records(uuid,text,text,integer) to authenticated;
create or replace function public.exchange_rate_overview(p_company uuid)
returns table(id uuid,name text,active boolean,current_rate numeric,effective_on date)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','read') then
    raise exception 'Sin acceso a cotizaciones' using errcode='42501'; end if;
  return query select t.id,t.name,t.active,r.ars_per_usd,r.effective_on
    from public.exchange_rate_types t left join lateral (
      select e.ars_per_usd,e.effective_on from public.exchange_rates e
      where e.company_id=t.company_id and e.type_id=t.id
        and e.effective_on<=(now() at time zone 'America/Argentina/Buenos_Aires')::date
      order by e.effective_on desc,e.created_at desc,e.id desc limit 1
    ) r on true where t.company_id=p_company and not t.archived order by t.name;
end; $$;

create function private.guard_archived_formula_edit() returns trigger
language plpgsql set search_path='' as $$ begin
  if old.archived then raise exception 'La fórmula está archivada. Recuperala antes de editarla'; end if;
  return new;
end; $$;
create trigger guard_archived_formula_edit before update of batch_quantity,version on public.production_formulas
  for each row execute function private.guard_archived_formula_edit();
revoke all on function private.guard_archived_formula_edit() from public,anon,authenticated;

commit;

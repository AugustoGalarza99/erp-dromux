-- Dromux Producción · reservas parciales y simulador, versión 024.
-- Ejecutar una vez después de 023. Las reservas no mueven stock físico.

create table public.production_job_reservations (
  company_id uuid not null,
  job_id uuid not null,
  component_id uuid not null,
  required_quantity numeric(18,6) not null check (required_quantity > 0),
  reserved_quantity numeric(18,6) not null default 0 check (reserved_quantity >= 0),
  updated_at timestamptz not null default now(),
  primary key (company_id, job_id, component_id),
  foreign key (company_id, job_id) references public.production_jobs(company_id,id),
  foreign key (company_id, component_id) references public.items(company_id,id)
);
create index production_reservation_component on public.production_job_reservations(company_id,component_id);
alter table public.production_job_reservations enable row level security;
create policy production_reservations_read on public.production_job_reservations
  for select to authenticated using (
    (select private.has_permission(company_id,'production','read'))
    and (select private.has_permission(company_id,'stock','read'))
  );
revoke all on public.production_job_reservations from public,anon,authenticated;
grant select on public.production_job_reservations to authenticated;

-- Un único bloqueo por empresa serializa la asignación entre órdenes.
-- Las reservas se asignan por fecha comprometida y, luego, fecha de alta.
create function private.rebalance_production_reservations(p_company uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_row record; v_physical numeric; v_assigned numeric := 0;
  v_component uuid := null; v_needed numeric; v_balance numeric;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('production-reservations:'||p_company::text,0));
  for v_row in
    select r.company_id,r.job_id,r.component_id,r.required_quantity,
      j.status,j.due_on,j.created_at
    from public.production_job_reservations r
    join public.production_jobs j on j.company_id=r.company_id and j.id=r.job_id
    where r.company_id=p_company
    order by r.component_id,j.due_on asc nulls last,j.created_at,j.id
  loop
    if v_component is distinct from v_row.component_id then
      v_component:=v_row.component_id;
      select coalesce(sum(b.quantity),0) into v_physical
        from public.stock_balances b
        where b.company_id=p_company and b.item_id=v_component;
      v_assigned:=0;
    end if;
    if v_row.status not in ('queued','in_progress') then
      v_balance:=0;
    else
      select coalesce(sum(case when e.kind='issue' then e.quantity else -e.quantity end),0)
        into v_needed
        from public.production_job_events e
        where e.company_id=p_company and e.job_id=v_row.job_id
          and e.component_id=v_component;
      v_balance:=least(greatest(0,v_row.required_quantity-v_needed),
        greatest(0,v_physical-v_assigned));
      v_assigned:=v_assigned+v_balance;
    end if;
    update public.production_job_reservations
      set reserved_quantity=v_balance,updated_at=clock_timestamp()
      where company_id=p_company and job_id=v_row.job_id
        and component_id=v_component
        and reserved_quantity is distinct from v_balance;
  end loop;
end;
$$;
revoke all on function private.rebalance_production_reservations(uuid) from public,anon,authenticated;

-- La orden conserva su fórmula histórica, por eso se reserva al insertarla.
create function private.reserve_new_production_job()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.production_job_reservations
    (company_id,job_id,component_id,required_quantity)
  select new.company_id,new.id,(x->>'component_id')::uuid,
    sum((x->>'quantity')::numeric)
  from jsonb_array_elements(new.formula_snapshot) x
  group by (x->>'component_id')::uuid;
  perform private.rebalance_production_reservations(new.company_id);
  return new;
end;
$$;
create trigger reserve_production_job_after_insert
  after insert on public.production_jobs for each row
  execute function private.reserve_new_production_job();

create function private.rebalance_production_on_event()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.rebalance_production_reservations(new.company_id);
  return new;
end;
$$;
create trigger rebalance_production_after_event
  after insert on public.production_job_events for each row
  execute function private.rebalance_production_on_event();

create function private.release_closed_production_job()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status in ('completed','cancelled') and old.status <> new.status then
    perform private.rebalance_production_reservations(new.company_id);
  end if;
  return new;
end;
$$;
create trigger release_production_job_after_update
  after update of status on public.production_jobs for each row
  execute function private.release_closed_production_job();

-- Reservar en orden de fecha los trabajos abiertos existentes al instalar 024.
insert into public.production_job_reservations
  (company_id,job_id,component_id,required_quantity)
select j.company_id,j.id,(x->>'component_id')::uuid,
  sum((x->>'quantity')::numeric)
from public.production_jobs j
cross join lateral jsonb_array_elements(j.formula_snapshot) x
group by j.company_id,j.id,(x->>'component_id')::uuid;
do $$ declare v_company record; begin
  for v_company in select distinct company_id from public.production_job_reservations loop
    perform private.rebalance_production_reservations(v_company.company_id);
  end loop;
end $$;

-- Simula contra el stock libre total. Un semielaborado se considera un ítem
-- existente: fabricarlo previamente requiere una simulación independiente.
create function public.erp_can_manufacture(
  p_company uuid,p_product uuid,p_quantity numeric
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_formula public.production_formulas%rowtype; v_lines jsonb;
begin
  if auth.uid() is null
    or not private.has_permission(p_company,'production','read')
    or not private.has_permission(p_company,'stock','read') then
    raise exception 'Necesitás acceso a producción y stock' using errcode='42501';
  end if;
  if p_product is null or p_quantity is null or p_quantity <= 0
    or p_quantity >= 1000000000000 or p_quantity <> round(p_quantity,6) then
    raise exception 'Indicá una cantidad válida con hasta seis decimales';
  end if;
  select * into v_formula from public.production_formulas
    where company_id=p_company and product_id=p_product;
  if not found then raise exception 'El producto no tiene fórmula'; end if;
  select jsonb_agg(to_jsonb(v) order by v.item_name) into v_lines from (
    select i.id as item_id,i.code as item_code,i.name as item_name,
      i.item_type,u.symbol as unit_symbol,
      round(sum(l.quantity)*p_quantity/v_formula.batch_quantity,6) as required,
      coalesce((select sum(b.quantity) from public.stock_balances b
        where b.company_id=p_company and b.item_id=i.id),0) as physical,
      coalesce((select sum(r.reserved_quantity)
        from public.production_job_reservations r
        join public.production_jobs j on j.company_id=r.company_id and j.id=r.job_id
        where r.company_id=p_company and r.component_id=i.id
          and j.status in ('queued','in_progress')),0) as reserved,
      greatest(0,coalesce((select sum(b.quantity) from public.stock_balances b
        where b.company_id=p_company and b.item_id=i.id),0)
        -coalesce((select sum(r.reserved_quantity)
          from public.production_job_reservations r
          join public.production_jobs j on j.company_id=r.company_id and j.id=r.job_id
          where r.company_id=p_company and r.component_id=i.id
            and j.status in ('queued','in_progress')),0)) as free
    from public.production_formula_lines l
    join public.items i on i.company_id=l.company_id and i.id=l.component_id
    join public.units u on u.company_id=i.company_id and u.id=i.unit_id
    where l.company_id=p_company and l.product_id=p_product
    group by i.company_id,i.id,u.symbol
  ) v;
  return jsonb_build_object('product_id',p_product,'quantity',p_quantity,
    'formula_version',v_formula.version,'lines',coalesce(v_lines,'[]'::jsonb));
end;
$$;
revoke execute on function public.erp_can_manufacture(uuid,uuid,numeric) from public,anon;
grant execute on function public.erp_can_manufacture(uuid,uuid,numeric) to authenticated;

-- Reasigna reservas parciales tras compras, devoluciones u otros movimientos.
create function public.recalculate_production_reservations(p_company uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','read')
    or not private.has_permission(p_company,'stock','read') then
    raise exception 'Necesitás acceso a producción y stock' using errcode='42501';
  end if;
  perform private.rebalance_production_reservations(p_company);
end;
$$;
revoke execute on function public.recalculate_production_reservations(uuid) from public,anon;
grant execute on function public.recalculate_production_reservations(uuid) to authenticated;

-- Dromux Producción · proteger stock comprometido, versión 025.
-- Requiere 024; aplicar una sola vez. Los nombres previos se trasladan
-- a private y los llamados existentes continúan por los wrappers públicos.

alter function public.post_stock_operation(
  uuid,uuid,uuid,uuid,text,numeric,text,uuid,text,date
) set schema private;
revoke execute on function private.post_stock_operation(
  uuid,uuid,uuid,uuid,text,numeric,text,uuid,text,date
) from public,anon,authenticated;

-- La reserva de una orden sólo puede aplicarse a la salida de esa orden.
-- El contexto dura la llamada y nunca queda guardado en la conexión.
alter function public.issue_production_material(
  uuid,uuid,uuid,uuid,text,numeric,text,uuid
) set schema private;
revoke execute on function private.issue_production_material(
  uuid,uuid,uuid,uuid,text,numeric,text,uuid
) from public,anon,authenticated;

create function public.issue_production_material(
  p_company uuid,p_job uuid,p_component uuid,p_warehouse uuid,
  p_lot text,p_quantity numeric,p_note text,p_request_id uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_result uuid; v_previous text;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert')
    or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Necesitás permiso de producción y stock' using errcode='42501';
  end if;
  v_previous:=pg_catalog.current_setting('dromux.production_job',true);
  perform pg_catalog.set_config('dromux.production_job',coalesce(p_job::text,''),true);
  v_result:=private.issue_production_material(p_company,p_job,p_component,
    p_warehouse,p_lot,p_quantity,p_note,p_request_id);
  perform pg_catalog.set_config('dromux.production_job',coalesce(v_previous,''),true);
  return v_result;
end;
$$;
revoke execute on function public.issue_production_material(
  uuid,uuid,uuid,uuid,text,numeric,text,uuid
) from public,anon;
grant execute on function public.issue_production_material(
  uuid,uuid,uuid,uuid,text,numeric,text,uuid
) to authenticated;

create function public.post_stock_operation(
  p_company uuid,p_item uuid,p_warehouse uuid,p_to_warehouse uuid,
  p_kind text,p_quantity numeric,p_note text,p_request_id uuid,
  p_lot_code text,p_expires_on date
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_reserved numeric; v_own numeric; v_physical numeric;
  v_job uuid; v_operation uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Sin permiso para registrar movimientos' using errcode='42501';
  end if;
  -- Mismo bloqueo que usa la asignación de reservas. Protege la lectura,
  -- el chequeo de disponible, el movimiento y la reasignación final.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('production-reservations:'||p_company::text,0));
  -- La operación original verifica idempotencia y datos en detalle.
  if p_request_id is not null and exists (
    select 1 from public.stock_operations o
    where o.company_id=p_company and o.request_id=p_request_id
  ) then
    return private.post_stock_operation(p_company,p_item,p_warehouse,
      p_to_warehouse,p_kind,p_quantity,p_note,p_request_id,p_lot_code,p_expires_on);
  end if;
  if p_kind='issue' and p_item is not null and p_quantity is not null
    and p_quantity>0 then
    v_job:=nullif(pg_catalog.current_setting('dromux.production_job',true),'')::uuid;
    if v_job is not null then
      -- Un contexto de otra orden o componente no habilita reservas ajenas.
      perform 1 from public.production_jobs j
        where j.company_id=p_company and j.id=v_job
          and j.status in ('queued','in_progress');
      if not found then
        raise exception 'Orden de fabricación no activa';
      end if;
    end if;
    select coalesce(sum(b.quantity),0) into v_physical
      from public.stock_balances b
      where b.company_id=p_company and b.item_id=p_item;
    select coalesce(sum(r.reserved_quantity),0),
      coalesce(sum(r.reserved_quantity) filter (where r.job_id=v_job),0)
      into v_reserved,v_own
      from public.production_job_reservations r
      join public.production_jobs j
        on j.company_id=r.company_id and j.id=r.job_id
      where r.company_id=p_company and r.component_id=p_item
        and j.status in ('queued','in_progress');
    if p_quantity > greatest(0,v_physical-v_reserved+v_own) then
      raise exception 'Stock comprometido para fabricación: disponible libre %',
        greatest(0,v_physical-v_reserved+v_own);
    end if;
  end if;
  v_operation:=private.post_stock_operation(p_company,p_item,p_warehouse,
    p_to_warehouse,p_kind,p_quantity,p_note,p_request_id,p_lot_code,p_expires_on);
  if p_kind in ('receipt','issue') then
    perform private.rebalance_production_reservations(p_company);
  end if;
  return v_operation;
end;
$$;
revoke execute on function public.post_stock_operation(
  uuid,uuid,uuid,uuid,text,numeric,text,uuid,text,date
) from public,anon;
grant execute on function public.post_stock_operation(
  uuid,uuid,uuid,uuid,text,numeric,text,uuid,text,date
) to authenticated;

-- Los faltantes de una reserva parcial aparecen en el centro de avisos.
alter function public.erp_production_alerts(uuid) set schema private;
revoke execute on function private.erp_production_alerts(uuid)
  from public,anon,authenticated;
create function public.erp_production_alerts(p_company uuid)
returns table (
  alert_key text,fingerprint text,severity text,title text,
  detail text,destination text,occurred_on date
) language plpgsql stable security definer set search_path = '' as $$
declare v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null or not private.has_permission(p_company,'dashboard','read') then
    raise exception 'Sin acceso al centro operativo' using errcode='42501';
  end if;
  return query select base.alert_key,base.fingerprint,base.severity,
    base.title,base.detail,base.destination,base.occurred_on
    from private.erp_production_alerts(p_company) base;
  if private.has_permission(p_company,'production','read')
    and private.has_permission(p_company,'stock','read') then
    return query
    select 'reservation:'||j.id::text||':'||r.component_id::text,
      greatest(0,r.required_quantity-coalesce(e.consumed,0)-r.reserved_quantity)::text
        ||':'||coalesce(j.due_on::text,''),
      case when j.due_on <= v_today+3 then 'critical' else 'warning' end,
      'Faltan insumos para una orden',
      i.name||' · Faltan '||
        greatest(0,r.required_quantity-coalesce(e.consumed,0)-r.reserved_quantity)::text
        ||' '||u.symbol||' para '||p.name,
      '/production/orders?job='||j.id::text,
      coalesce(j.due_on,v_today)
    from public.production_job_reservations r
    join public.production_jobs j on j.company_id=r.company_id and j.id=r.job_id
    join public.items i on i.company_id=r.company_id and i.id=r.component_id
    join public.items p on p.company_id=j.company_id and p.id=j.product_id
    join public.units u on u.company_id=i.company_id and u.id=i.unit_id
    left join lateral (
      select sum(case when ev.kind='issue' then ev.quantity else -ev.quantity end) consumed
      from public.production_job_events ev
      where ev.company_id=r.company_id and ev.job_id=r.job_id
        and ev.component_id=r.component_id
    ) e on true
    where r.company_id=p_company and j.status in ('queued','in_progress')
      and r.required_quantity-coalesce(e.consumed,0)>r.reserved_quantity;
  end if;
end;
$$;
revoke execute on function public.erp_production_alerts(uuid) from public,anon;
grant execute on function public.erp_production_alerts(uuid) to authenticated;

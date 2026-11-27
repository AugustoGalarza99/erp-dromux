-- 005 · Reservas: al mover un material se recalculan solo sus reservas, no las de toda la empresa.
-- Motivo: cada movimiento recalculaba dos veces (tres si era de una orden) las reservas de todos
-- los materiales. Un remito de 110 ítems superaba el tiempo máximo de la base (8 segundos).
-- Cada material se reserva con sus propios datos, así que el resultado para el material movido es
-- el mismo. Crear, cerrar, cancelar una orden y «Recalcular» siguen recalculando todo.
begin;

-- Permite sumar lo ya entregado de un material sin recorrer todos los movimientos de la orden.
create index if not exists produccion_ordenes_eventos_componente_idx
  on public.produccion_ordenes_eventos (empresa_id, orden_id, componente_id);

-- Copia del recálculo completo, limitada a un material. Usa el mismo bloqueo por empresa.
CREATE OR REPLACE FUNCTION private.rebalance_production_reservations_item(p_company uuid, p_item uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row record; v_slot record;
  v_needed numeric; v_remaining numeric; v_reserved numeric;
  v_taken numeric; v_assign numeric;
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('production-reservations:'||p_company::text,0));
  delete from public.produccion_reservas_ubicaciones
    where empresa_id=p_company and componente_id=p_item;
  for v_row in
    select r.empresa_id,r.orden_id,r.componente_id,r.cantidad_requerida,j.estado
    from public.produccion_ordenes_reservas r
    join public.produccion_ordenes j on j.empresa_id=r.empresa_id and j.id=r.orden_id
    where r.empresa_id=p_company and r.componente_id=p_item
    order by r.componente_id,j.fecha_limite asc nulls last,j.creado_en,j.id
  loop
    v_reserved:=0;
    if v_row.estado in ('pendiente','en_proceso') and not exists (
      select 1 from public.stock_items i where i.empresa_id=p_company
        and i.id=v_row.componente_id and i.stock_infinito) then
      select coalesce(sum(case when e.tipo='entrega' then e.cantidad else -e.cantidad end),0)
        into v_needed from public.produccion_ordenes_eventos e
        where e.empresa_id=p_company and e.orden_id=v_row.orden_id
          and e.componente_id=v_row.componente_id;
      v_remaining:=greatest(0,v_row.cantidad_requerida-v_needed);
      for v_slot in
        select slots.deposito_id,slots.lote_id,slots.lote_codigo,slots.cantidad
        from (
          select b.deposito_id,null::uuid lote_id,null::text lote_codigo,
            null::date vencimiento,b.cantidad,w.nombre warehouse_name
          from public.stock_saldos b
          join public.stock_items i on i.empresa_id=b.empresa_id and i.id=b.item_id
          join public.stock_depositos w on w.empresa_id=b.empresa_id
            and w.id=b.deposito_id and w.activo
          where b.empresa_id=p_company and b.item_id=v_row.componente_id
            and not i.usa_lotes and b.cantidad>0
          union all
          select lb.deposito_id,lb.lote_id,l.codigo,l.vencimiento,
            lb.cantidad,w.nombre
          from public.stock_lotes_saldos lb
          join public.stock_items i on i.empresa_id=lb.empresa_id and i.id=lb.item_id
          join public.stock_lotes l on l.empresa_id=lb.empresa_id
            and l.item_id=lb.item_id and l.id=lb.lote_id
          join public.stock_depositos w on w.empresa_id=lb.empresa_id
            and w.id=lb.deposito_id and w.activo
          where lb.empresa_id=p_company and lb.item_id=v_row.componente_id
            and i.usa_lotes and lb.cantidad>0
            and (l.vencimiento is null or l.vencimiento>=v_today)
        ) slots
        order by slots.vencimiento asc nulls last,slots.warehouse_name,
          slots.deposito_id,slots.lote_codigo nulls last
      loop
        exit when v_remaining<=0;
        select coalesce(sum(a.cantidad),0) into v_taken
          from public.produccion_reservas_ubicaciones a
          where a.empresa_id=p_company and a.componente_id=v_row.componente_id
            and a.deposito_id=v_slot.deposito_id
            and a.lote_id is not distinct from v_slot.lote_id;
        v_assign:=least(v_remaining,greatest(0,v_slot.cantidad-v_taken));
        if v_assign>0 then
          insert into public.produccion_reservas_ubicaciones(
            empresa_id,orden_id,componente_id,deposito_id,lote_id,lote_codigo,cantidad)
          values(p_company,v_row.orden_id,v_row.componente_id,v_slot.deposito_id,
            v_slot.lote_id,v_slot.lote_codigo,v_assign);
          v_reserved:=v_reserved+v_assign;
          v_remaining:=v_remaining-v_assign;
        end if;
      end loop;
    end if;
    update public.produccion_ordenes_reservas
      set cantidad_reservada=v_reserved,actualizado_en=clock_timestamp()
      where empresa_id=p_company and orden_id=v_row.orden_id
        and componente_id=v_row.componente_id
        and cantidad_reservada is distinct from v_reserved;
  end loop;
end;
$function$;

revoke all on function private.rebalance_production_reservations_item(uuid, uuid)
  from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.rebalance_production_on_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.rebalance_production_reservations_item(new.empresa_id,new.componente_id);
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.post_stock_operation(p_company uuid, p_item uuid, p_warehouse uuid, p_to_warehouse uuid, p_kind text, p_quantity numeric, p_note text, p_request_id uuid, p_lot_code text, p_expires_on date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_reserved numeric; v_own numeric; v_usable numeric;
  v_slot_reserved numeric; v_slot_own numeric; v_slot_physical numeric;
  v_track boolean; v_lot uuid; v_expiry date;
  v_job uuid; v_operation uuid; v_infinite boolean; v_existing public.stock_operaciones%rowtype;
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null or not private.can_post_stock(p_company) then
    raise exception 'Sin permiso para registrar movimientos' using errcode='42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('production-reservations:'||p_company::text,0));
  if p_request_id is not null and exists (
    select 1 from public.stock_operaciones o
    where o.empresa_id=p_company and o.solicitud_id=p_request_id
  ) then
    return private.post_stock_operation(p_company,p_item,p_warehouse,
      p_to_warehouse,p_kind,p_quantity,p_note,p_request_id,p_lot_code,p_expires_on);
  end if;
  select i.stock_infinito into v_infinite from public.stock_items i
    where i.empresa_id=p_company and i.id=p_item and i.activo for share;
  if coalesce(v_infinite,false) then
    if p_request_id is null or p_warehouse is null or p_kind not in ('ingreso','egreso')
      or p_to_warehouse is not null or p_quantity is null or p_quantity<=0
      or p_quantity>=1000000000000 or p_quantity<>round(p_quantity,6)
      or length(btrim(coalesce(p_note,''))) not between 3 and 500
      or nullif(btrim(coalesce(p_lot_code,'')),'') is not null
      or p_expires_on is not null then
      raise exception 'Movimiento inválido para un ítem de stock infinito';
    end if;
    perform 1 from public.empresas c where c.id=p_company and c.activo for share;
    if not found then raise exception 'La empresa está suspendida'; end if;
    perform 1 from public.stock_depositos w where w.empresa_id=p_company
      and w.id=p_warehouse and w.activo for share;
    if not found then raise exception 'Elegí un depósito activo'; end if;
    v_job:=nullif(pg_catalog.current_setting('dromux.production_job',true),'')::uuid;
    if v_job is not null and p_kind='egreso' and not exists (
      select 1 from public.produccion_ordenes j where j.empresa_id=p_company
        and j.id=v_job and j.estado in ('pendiente','en_proceso')) then
      raise exception 'Orden de fabricación no activa';
    end if;
    insert into public.stock_operaciones(empresa_id,solicitud_id,item_id,deposito_id,
      tipo,cantidad,nota,autor_id)
    values(p_company,p_request_id,p_item,p_warehouse,p_kind,p_quantity,btrim(p_note),auth.uid())
    on conflict(empresa_id,solicitud_id) do nothing returning id into v_operation;
    if v_operation is null then
      select * into v_existing from public.stock_operaciones o
        where o.empresa_id=p_company and o.solicitud_id=p_request_id;
      if v_existing.item_id is distinct from p_item
        or v_existing.deposito_id is distinct from p_warehouse
        or v_existing.deposito_destino_id is not null or v_existing.tipo<>p_kind
        or v_existing.cantidad<>p_quantity or v_existing.nota<>btrim(p_note)
        or v_existing.autor_id<>auth.uid() then
        raise exception 'Esta solicitud ya se usó con otros datos';
      end if;
      return v_existing.id;
    end if;
    return v_operation;
  end if;
  perform private.rebalance_production_reservations_item(p_company,p_item);
  if p_kind in ('egreso','transferencia') and p_item is not null
    and p_warehouse is not null and p_quantity>0 then
    v_job:=nullif(pg_catalog.current_setting('dromux.production_job',true),'')::uuid;
    if v_job is not null and p_kind='egreso' then
      perform 1 from public.produccion_ordenes j where j.empresa_id=p_company
        and j.id=v_job and j.estado in ('pendiente','en_proceso');
      if not found then raise exception 'Orden de fabricación no activa'; end if;
    end if;
    select i.usa_lotes into v_track from public.stock_items i
      where i.empresa_id=p_company and i.id=p_item;
    if v_track then
      select l.id,l.vencimiento into v_lot,v_expiry from public.stock_lotes l
        where l.empresa_id=p_company and l.item_id=p_item
          and lower(l.codigo)=lower(btrim(p_lot_code));
      if v_lot is null then raise exception 'Elegí un lote existente'; end if;
      if p_kind='egreso' and v_expiry<v_today then
        raise exception 'El lote está vencido. Elegí uno vigente'; end if;
      select coalesce(b.cantidad,0) into v_slot_physical
        from public.stock_lotes_saldos b where b.empresa_id=p_company
          and b.item_id=p_item and b.deposito_id=p_warehouse and b.lote_id=v_lot;
    else
      select coalesce(b.cantidad,0) into v_slot_physical
        from public.stock_saldos b where b.empresa_id=p_company
          and b.item_id=p_item and b.deposito_id=p_warehouse;
    end if;
    v_slot_physical:=coalesce(v_slot_physical,0);
    select coalesce(sum(a.cantidad),0),
      coalesce(sum(a.cantidad) filter(where a.orden_id=v_job),0)
      into v_slot_reserved,v_slot_own
      from public.produccion_reservas_ubicaciones a
      join public.produccion_ordenes j on j.empresa_id=a.empresa_id and j.id=a.orden_id
      where a.empresa_id=p_company and a.componente_id=p_item
        and a.deposito_id=p_warehouse
        and a.lote_id is not distinct from v_lot
        and j.estado in ('pendiente','en_proceso');
    if p_quantity>greatest(0,v_slot_physical-v_slot_reserved
      +case when p_kind='egreso' then v_slot_own else 0 end) then
      raise exception 'Stock libre insuficiente en el depósito y lote elegidos';
    end if;
    if p_kind='egreso' then
      select coalesce(sum(a.cantidad),0),
        coalesce(sum(a.cantidad) filter(where a.orden_id=v_job),0)
        into v_reserved,v_own from public.produccion_reservas_ubicaciones a
        join public.produccion_ordenes j on j.empresa_id=a.empresa_id and j.id=a.orden_id
        where a.empresa_id=p_company and a.componente_id=p_item
          and j.estado in ('pendiente','en_proceso');
      if v_track then
        select coalesce(sum(lb.cantidad),0) into v_usable
          from public.stock_lotes_saldos lb
          join public.stock_depositos w on w.empresa_id=lb.empresa_id
            and w.id=lb.deposito_id and w.activo
          join public.stock_lotes l on l.empresa_id=lb.empresa_id
            and l.item_id=lb.item_id and l.id=lb.lote_id
          where lb.empresa_id=p_company and lb.item_id=p_item
            and (l.vencimiento is null or l.vencimiento>=v_today);
      else
        select coalesce(sum(b.cantidad),0) into v_usable
          from public.stock_saldos b
          join public.stock_depositos w on w.empresa_id=b.empresa_id
            and w.id=b.deposito_id and w.activo
          where b.empresa_id=p_company and b.item_id=p_item;
      end if;
      if p_quantity>greatest(0,v_usable-v_reserved+v_own) then
        raise exception 'Stock comprometido para fabricación: saldo libre insuficiente';
      end if;
    end if;
  end if;
  v_operation:=private.post_stock_operation(p_company,p_item,p_warehouse,
    p_to_warehouse,p_kind,p_quantity,p_note,p_request_id,p_lot_code,p_expires_on);
  if p_kind in ('ingreso','egreso','transferencia') then
    perform private.rebalance_production_reservations_item(p_company,p_item);
  end if;
  return v_operation;
end;
$function$;

commit;

-- 003 · Producción: quien opera órdenes (Órdenes: editar + Stock por depósito: ver) puede
-- iniciar, entregar, devolver, terminar y cargar controles sin permiso general de stock.
-- Cancelar una orden exige «Gestionar» en Órdenes de fabricación.
-- Los movimientos de stock se aceptan solo dentro de una orden activa de la misma empresa.
-- Las funciones son copia de la línea base con los cambios mínimos de permisos.
begin;

update public.ajustes_permisos_catalogo
set acciones = array['ver','crear','editar','eliminar','gestionar']::text[],
    ayuda = 'Crear, iniciar, entregar insumos, devolver y terminar órdenes. Gestionar: cancelar órdenes.'
where recurso = 'produccion_ordenes';

-- Los administradores y los roles que hoy crean y editan órdenes conservan la cancelación.
insert into public.ajustes_roles_permisos(empresa_id, rol_id, recurso, accion)
select r.empresa_id, r.id, 'produccion_ordenes', 'gestionar'
from public.ajustes_roles r where r.codigo = 'administrador'
on conflict do nothing;

insert into public.ajustes_roles_permisos(empresa_id, rol_id, recurso, accion)
select e.empresa_id, e.rol_id, 'produccion_ordenes', 'gestionar'
from public.ajustes_roles_permisos e
join public.ajustes_roles r on r.id = e.rol_id and r.empresa_id = e.empresa_id
where e.recurso = 'produccion_ordenes' and e.accion = 'editar'
  and r.codigo not in ('administrador', 'soporte')
  and exists (select 1 from public.ajustes_roles_permisos c
    where c.rol_id = e.rol_id and c.recurso = 'produccion_ordenes' and c.accion = 'crear')
on conflict do nothing;

create or replace function private.can_operate_production(p_company uuid)
returns boolean language sql stable security definer set search_path to ''
as $function$
  select private.has_permission(p_company, 'produccion_ordenes', 'editar')
     and private.has_permission(p_company, 'stock_saldos', 'ver')
$function$;

create or replace function private.can_post_stock(p_company uuid)
returns boolean language sql stable security definer set search_path to ''
as $function$
  select private.has_permission(p_company, 'stock', 'crear')
    or (private.can_operate_production(p_company)
      and exists (select 1 from public.produccion_ordenes j
        where j.empresa_id = p_company
          and j.id::text = nullif(pg_catalog.current_setting('dromux.production_job', true), '')
          and j.estado in ('pendiente', 'en_proceso')))
$function$;

revoke all on function private.can_operate_production(uuid) from public, anon, authenticated, service_role;
revoke all on function private.can_post_stock(uuid) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.post_stock_operation(p_company uuid, p_item uuid, p_warehouse uuid, p_to_warehouse uuid, p_kind text, p_quantity numeric, p_note text, p_request_id uuid, p_lot_code text, p_expires_on date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_note text := btrim(p_note);
  v_code text := nullif(btrim(p_lot_code), '');
  v_operation uuid;
  v_existing public.stock_operaciones%rowtype;
  v_item_code text;
  v_unit_symbol text;
  v_track_lots boolean;
  v_warehouse_code text;
  v_target_code text;
  v_source_balance numeric(18, 6);
  v_target_balance numeric(18, 6);
  v_source_version bigint;
  v_target_version bigint;
  v_lot_id uuid;
  v_lot_code text;
  v_lot_expiry date;
  v_lot_balance numeric(18, 6);
begin
  if v_actor is null or not private.can_post_stock(p_company) then
    raise exception 'Sin permiso para registrar movimientos' using errcode = '42501';
  end if;
  if p_request_id is null or p_item is null or p_warehouse is null
     or p_kind is null or p_kind not in ('ingreso', 'egreso', 'transferencia')
     or p_quantity is null or p_quantity <= 0 or p_quantity >= 1000000000000
     or round(p_quantity, 6) <> p_quantity
     or v_note is null or length(v_note) not between 3 and 500
     or (p_kind = 'transferencia' and (p_to_warehouse is null
       or p_to_warehouse = p_warehouse))
     or (p_kind <> 'transferencia' and p_to_warehouse is not null)
     or length(coalesce(p_lot_code, '')) > 80
     or (p_kind <> 'ingreso' and p_expires_on is not null) then
    raise exception 'Datos de movimiento inválidos';
  end if;

  perform 1 from public.empresas c
  where c.id = p_company and c.activo for share;
  if not found or not private.can_post_stock(p_company) then
    raise exception 'La empresa no está activa o no tenés permiso' using errcode = '42501';
  end if;

  -- Serializa todos los movimientos del mismo ítem y sus cambios de saldo.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_company::text || ':' || p_item::text, 0)
  );

  insert into public.stock_operaciones (
    empresa_id, solicitud_id, item_id, deposito_id, deposito_destino_id,
    tipo, cantidad, nota, autor_id, lote_codigo, lote_vencimiento
  ) values (
    p_company, p_request_id, p_item, p_warehouse, p_to_warehouse,
    p_kind, p_quantity, v_note, v_actor, v_code, p_expires_on
  ) on conflict (empresa_id, solicitud_id) do nothing
  returning id into v_operation;

  if v_operation is null then
    select * into v_existing from public.stock_operaciones
    where empresa_id = p_company and solicitud_id = p_request_id;
    if v_existing.item_id is distinct from p_item
       or v_existing.deposito_id is distinct from p_warehouse
       or v_existing.deposito_destino_id is distinct from p_to_warehouse
       or v_existing.tipo is distinct from p_kind
       or v_existing.cantidad is distinct from p_quantity
       or v_existing.nota is distinct from v_note
       or v_existing.autor_id is distinct from v_actor
       or v_existing.lote_codigo is distinct from v_code
       or v_existing.lote_vencimiento is distinct from p_expires_on then
      raise exception 'La solicitud ya se usó con otros datos';
    end if;
    return v_existing.id;
  end if;

  select i.codigo, u.simbolo, i.usa_lotes
  into v_item_code, v_unit_symbol, v_track_lots
  from public.stock_items i
  join public.stock_unidades u on u.id = i.unidad_id and u.empresa_id = i.empresa_id
  where i.id = p_item and i.empresa_id = p_company and i.activo
  for share of i;
  if not found then raise exception 'Ítem inactivo o inexistente'; end if;

  if v_track_lots then
    if v_code is null then raise exception 'Indicá el lote del ítem'; end if;
    if p_kind = 'ingreso' then
      insert into public.stock_lotes(empresa_id, item_id, codigo, vencimiento)
      values (p_company, p_item, v_code, p_expires_on)
      on conflict do nothing;
    end if;
    select l.id, l.codigo, l.vencimiento
    into v_lot_id, v_lot_code, v_lot_expiry
    from public.stock_lotes l
    where l.empresa_id = p_company and l.item_id = p_item
      and lower(l.codigo) = lower(v_code);
    if v_lot_id is null then raise exception 'Lote inexistente para este ítem'; end if;
    if p_kind = 'ingreso' and v_lot_expiry is distinct from p_expires_on then
      raise exception 'La fecha de vencimiento no coincide con la del lote existente';
    end if;
  elsif v_code is not null or p_expires_on is not null then
    raise exception 'El ítem no utiliza lotes';
  end if;

  select w.codigo into v_warehouse_code from public.stock_depositos w
  where w.id = p_warehouse and w.empresa_id = p_company and w.activo
  for share of w;
  if not found then raise exception 'Depósito inactivo o inexistente'; end if;
  if p_kind = 'transferencia' then
    select w.codigo into v_target_code from public.stock_depositos w
    where w.id = p_to_warehouse and w.empresa_id = p_company and w.activo
    for share of w;
    if not found then raise exception 'Depósito destino inactivo o inexistente'; end if;
  end if;

  insert into public.stock_saldos(empresa_id, item_id, deposito_id)
  values (p_company, p_item, p_warehouse)
  on conflict (empresa_id, item_id, deposito_id) do nothing;
  select b.cantidad into v_source_balance from public.stock_saldos b
  where b.empresa_id = p_company and b.item_id = p_item
    and b.deposito_id = p_warehouse for update;
  if p_kind in ('egreso', 'transferencia') and v_source_balance < p_quantity then
    raise exception 'Stock insuficiente en el depósito de origen';
  end if;

  if v_track_lots then
    insert into public.stock_lotes_saldos(empresa_id, item_id, deposito_id, lote_id)
    values (p_company, p_item, p_warehouse, v_lot_id)
    on conflict (empresa_id, item_id, deposito_id, lote_id) do nothing;
    select b.cantidad into v_lot_balance from public.stock_lotes_saldos b
    where b.empresa_id = p_company and b.item_id = p_item
      and b.deposito_id = p_warehouse and b.lote_id = v_lot_id for update;
    if p_kind in ('egreso', 'transferencia') and v_lot_balance < p_quantity then
      raise exception 'Stock insuficiente para el lote en el depósito de origen';
    end if;
    update public.stock_lotes_saldos b
    set cantidad = b.cantidad + case when p_kind = 'ingreso'
      then p_quantity else -p_quantity end
    where b.empresa_id = p_company and b.item_id = p_item
      and b.deposito_id = p_warehouse and b.lote_id = v_lot_id;
  end if;

  update public.stock_saldos b
  set cantidad = b.cantidad + case when p_kind = 'ingreso'
      then p_quantity else -p_quantity end,
      version = b.version + 1, actualizado_en = clock_timestamp()
  where b.empresa_id = p_company and b.item_id = p_item
    and b.deposito_id = p_warehouse
  returning b.cantidad, b.version into v_source_balance, v_source_version;

  insert into public.stock_movimientos (
    empresa_id, operacion_id, linea, item_id, deposito_id, tipo,
    variacion, saldo_posterior, saldo_version, item_codigo, deposito_codigo,
    unidad_simbolo, nota, autor_id, lote_id, lote_codigo, lote_vencimiento
  ) values (
    p_company, v_operation, 1, p_item, p_warehouse,
    case p_kind when 'ingreso' then 'ingreso'
      when 'egreso' then 'egreso' else 'transferencia_salida' end,
    case when p_kind = 'ingreso' then p_quantity else -p_quantity end,
    v_source_balance, v_source_version, v_item_code, v_warehouse_code,
    v_unit_symbol, v_note, v_actor, v_lot_id, v_lot_code, v_lot_expiry
  );

  if p_kind = 'transferencia' then
    insert into public.stock_saldos(empresa_id, item_id, deposito_id)
    values (p_company, p_item, p_to_warehouse)
    on conflict (empresa_id, item_id, deposito_id) do nothing;
    update public.stock_saldos b
    set cantidad = b.cantidad + p_quantity, version = b.version + 1,
        actualizado_en = clock_timestamp()
    where b.empresa_id = p_company and b.item_id = p_item
      and b.deposito_id = p_to_warehouse
    returning b.cantidad, b.version into v_target_balance, v_target_version;

    if v_track_lots then
      insert into public.stock_lotes_saldos(empresa_id, item_id, deposito_id, lote_id)
      values (p_company, p_item, p_to_warehouse, v_lot_id)
      on conflict (empresa_id, item_id, deposito_id, lote_id) do nothing;
      update public.stock_lotes_saldos b
      set cantidad = b.cantidad + p_quantity
      where b.empresa_id = p_company and b.item_id = p_item
        and b.deposito_id = p_to_warehouse and b.lote_id = v_lot_id;
    end if;

    insert into public.stock_movimientos (
      empresa_id, operacion_id, linea, item_id, deposito_id, tipo,
      variacion, saldo_posterior, saldo_version, item_codigo, deposito_codigo,
      unidad_simbolo, nota, autor_id, lote_id, lote_codigo, lote_vencimiento
    ) values (
      p_company, v_operation, 2, p_item, p_to_warehouse, 'transferencia_entrada',
      p_quantity, v_target_balance, v_target_version, v_item_code, v_target_code,
      v_unit_symbol, v_note, v_actor, v_lot_id, v_lot_code, v_lot_expiry
    );
  end if;

  if v_lot_id is not null then
    update public.stock_operaciones o set lote_id = v_lot_id
    where o.id = v_operation;
  end if;

  return v_operation;
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
  perform private.rebalance_production_reservations(p_company);
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
    perform private.rebalance_production_reservations(p_company);
  end if;
  return v_operation;
end;
$function$;

CREATE OR REPLACE FUNCTION public.issue_production_material(p_company uuid, p_job uuid, p_component uuid, p_warehouse uuid, p_lot text, p_quantity numeric, p_note text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.produccion_ordenes%rowtype; v_full boolean;
  v_previous public.produccion_ordenes_eventos%rowtype;
  v_cost numeric; v_operation uuid; v_event uuid;
  v_lot text:=nullif(btrim(p_lot),'');
begin
  v_full:=private.has_permission(p_company,'produccion_ordenes','crear')
      and private.has_permission(p_company,'stock','crear');
  if auth.uid() is null or not (v_full or private.can_operate_production(p_company)) then
    raise exception 'Necesitás permiso de producción y stock' using errcode='42501'; end if;
  if p_request_id is null or p_component is null or p_warehouse is null
    or p_quantity is null or p_quantity<=0 or p_quantity>=1000000000000
    or p_quantity<>round(p_quantity,6)
    or length(btrim(coalesce(p_note,''))) not between 3 and 300 then
    raise exception 'Revisá el insumo, cantidad, depósito y motivo'; end if;
  select * into v_job from public.produccion_ordenes
    where empresa_id=p_company and id=p_job for update;
  if not found then raise exception 'Orden inexistente'; end if;
  select * into v_previous from public.produccion_ordenes_eventos
    where empresa_id=p_company and solicitud_id=p_request_id;
  if found then
    if v_previous.autor_id<>auth.uid() or v_previous.tipo<>'entrega'
      or v_previous.orden_id<>p_job or v_previous.componente_id<>p_component
      or v_previous.deposito_id<>p_warehouse or v_previous.cantidad<>p_quantity
      or v_previous.lote_codigo is distinct from v_lot
      or v_previous.nota<>btrim(p_note) then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_previous.id;
  end if;
  if v_job.estado not in ('pendiente','en_proceso') then
    raise exception 'La orden ya no admite insumos'; end if;
  if p_component=v_job.producto_id then
    raise exception 'El producto fabricado no puede consumirse a sí mismo'; end if;
  perform 1 from public.stock_items i where i.empresa_id=p_company and i.id=p_component
    and i.activo and i.tipo_item in ('materia_prima','semielaborado','insumo') for share;
  if not found then raise exception 'Elegí una materia prima o un semielaborado activo'; end if;
  -- Sin permiso completo solo se entregan insumos de la fórmula o ya entregados a esta orden.
  if not v_full and not exists(select 1 from jsonb_array_elements(v_job.formula_copia) x
      where x->>'component_id'=p_component::text)
    and not exists(select 1 from public.produccion_ordenes_eventos e where e.empresa_id=p_company
      and e.orden_id=p_job and e.componente_id=p_component and e.tipo='entrega') then
    raise exception 'Solo podés entregar insumos de la fórmula de esta orden' using errcode='42501'; end if;
  select round(r.costo_estimado/r.cantidad,2) into v_cost
    from public.produccion_fabricaciones r
    where r.empresa_id=p_company and r.producto_id=p_component
    order by r.creado_en desc limit 1;
  v_cost:=coalesce(v_cost,private.production_unit_cost(p_company,p_component));
  perform pg_catalog.set_config('dromux.production_job',p_job::text,true);
  v_operation:=public.post_stock_operation(p_company,p_component,p_warehouse,
    null,'egreso',p_quantity,'Orden producción '||p_job::text,
    gen_random_uuid(),v_lot,null);
  perform pg_catalog.set_config('dromux.production_job','',true);
  insert into public.produccion_ordenes_eventos(empresa_id,orden_id,solicitud_id,tipo,
    componente_id,deposito_id,lote_codigo,cantidad,costo_unitario,operacion_stock_id,
    nota,autor_id)
  values(p_company,p_job,p_request_id,'entrega',p_component,p_warehouse,
    v_lot,p_quantity,v_cost,v_operation,btrim(p_note),auth.uid())
  returning id into v_event;
  if v_job.estado='pendiente' then
    update public.produccion_ordenes set estado='en_proceso',iniciado_en=clock_timestamp()
      where empresa_id=p_company and id=p_job;
  end if;
  return v_event;
end;
$function$;

CREATE OR REPLACE FUNCTION public.return_production_material(p_company uuid, p_job uuid, p_issue uuid, p_quantity numeric, p_note text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.produccion_ordenes%rowtype;
  v_issue public.produccion_ordenes_eventos%rowtype;
  v_previous public.produccion_ordenes_eventos%rowtype;
  v_open numeric; v_expiry date; v_operation uuid; v_event uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_ordenes','editar')
    or not (private.has_permission(p_company,'stock','crear')
      or private.can_operate_production(p_company)) then
    raise exception 'Necesitás permiso para devolver insumos al stock' using errcode='42501'; end if;
  if p_request_id is null or p_quantity is null or p_quantity<=0
    or p_quantity>=1000000000000 or p_quantity<>round(p_quantity,6)
    or length(btrim(coalesce(p_note,''))) not between 3 and 300 then
    raise exception 'Revisá cantidad y motivo de devolución'; end if;
  select * into v_job from public.produccion_ordenes
    where empresa_id=p_company and id=p_job for update;
  if not found then raise exception 'Orden inexistente'; end if;
  select * into v_previous from public.produccion_ordenes_eventos
    where empresa_id=p_company and solicitud_id=p_request_id;
  if found then
    if v_previous.autor_id<>auth.uid() or v_previous.tipo<>'devolucion'
      or v_previous.orden_id<>p_job or v_previous.entrega_id<>p_issue
      or v_previous.cantidad<>p_quantity or v_previous.nota<>btrim(p_note) then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_previous.id;
  end if;
  if v_job.estado<>'en_proceso' then raise exception 'La orden ya no admite devoluciones'; end if;
  select * into v_issue from public.produccion_ordenes_eventos
    where empresa_id=p_company and orden_id=p_job and id=p_issue and tipo='entrega';
  if not found then raise exception 'Elegí una salida de insumo de esta orden'; end if;
  select v_issue.cantidad-coalesce(sum(e.cantidad),0) into v_open
    from public.produccion_ordenes_eventos e
    where e.empresa_id=p_company and e.entrega_id=p_issue and e.tipo='devolucion';
  if p_quantity>v_open then raise exception 'La devolución supera el saldo de esa salida'; end if;
  if v_issue.lote_codigo is not null then
    select l.vencimiento into v_expiry from public.stock_lotes l
      where l.empresa_id=p_company and l.item_id=v_issue.componente_id
        and lower(l.codigo)=lower(v_issue.lote_codigo);
    if not found then raise exception 'No se encuentra el lote de origen'; end if;
  end if;
  perform pg_catalog.set_config('dromux.production_job',p_job::text,true);
  v_operation:=public.post_stock_operation(p_company,v_issue.componente_id,
    v_issue.deposito_id,null,'ingreso',p_quantity,
    'Devolución orden '||p_job::text,gen_random_uuid(),v_issue.lote_codigo,v_expiry);
  perform pg_catalog.set_config('dromux.production_job','',true);
  insert into public.produccion_ordenes_eventos(empresa_id,orden_id,solicitud_id,tipo,
    entrega_id,componente_id,deposito_id,lote_codigo,cantidad,costo_unitario,
    operacion_stock_id,nota,autor_id)
  values(p_company,p_job,p_request_id,'devolucion',p_issue,v_issue.componente_id,
    v_issue.deposito_id,v_issue.lote_codigo,p_quantity,v_issue.costo_unitario,
    v_operation,btrim(p_note),auth.uid()) returning id into v_event;
  return v_event;
end;
$function$;

CREATE OR REPLACE FUNCTION public.finish_production_job(p_company uuid, p_job uuid, p_actual_quantity numeric, p_output_lot text, p_expires_on date, p_variance_note text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.produccion_ordenes%rowtype;
  v_track_lots boolean; v_expected record; v_cost numeric; v_output uuid;
  v_run uuid; v_mismatch boolean:=false; v_lot text:=nullif(btrim(p_output_lot),'');
begin
  if auth.uid() is null or not ((private.has_permission(p_company,'produccion_ordenes','crear')
      and private.has_permission(p_company,'stock','crear'))
    or private.can_operate_production(p_company)) then
    raise exception 'Necesitás permiso de producción y stock' using errcode='42501'; end if;
  if p_request_id is null or p_actual_quantity is null or p_actual_quantity<=0
    or p_actual_quantity>=1000000000000
    or p_actual_quantity<>round(p_actual_quantity,6)
    or length(coalesce(p_variance_note,''))>400 then
    raise exception 'Indicá el rendimiento real con hasta seis decimales'; end if;
  select * into v_job from public.produccion_ordenes
    where empresa_id=p_company and id=p_job for update;
  if not found then raise exception 'Orden inexistente'; end if;
  if v_job.estado='terminada' then
    if v_job.solicitud_cierre_id<>p_request_id
      or v_job.cantidad_real<>p_actual_quantity
      or v_job.producto_lote is distinct from v_lot
      or v_job.producto_vencimiento is distinct from p_expires_on
      or v_job.nota_diferencia is distinct from nullif(btrim(p_variance_note),'') then
      raise exception 'Esta orden ya fue completada con otros datos'; end if;
    return v_job.fabricacion_id;
  end if;
  if v_job.estado<>'en_proceso' then
    raise exception 'Iniciá la orden y registrá sus insumos antes de terminar'; end if;
  select i.usa_lotes into v_track_lots from public.stock_items i
    where i.empresa_id=p_company and i.id=v_job.producto_id and i.activo for share;
  if not found then raise exception 'El producto está inactivo'; end if;
  if v_track_lots and v_lot is null then
    raise exception 'Indicá el lote del producto que vas a ingresar'; end if;
  if not v_track_lots and (v_lot is not null or p_expires_on is not null) then
    raise exception 'Este producto no usa lotes; dejá lote y vencimiento vacíos'; end if;
  if p_actual_quantity<>v_job.cantidad_esperada then v_mismatch:=true; end if;
  for v_expected in select (x->>'component_id')::uuid componente_id,
    (x->>'quantity')::numeric cantidad
    from jsonb_array_elements(v_job.formula_copia) x loop
    if (select coalesce(sum(case when e.tipo='entrega' then e.cantidad else -e.cantidad end),0)
      from public.produccion_ordenes_eventos e where e.empresa_id=p_company and e.orden_id=p_job
        and e.componente_id=v_expected.componente_id)<>v_expected.cantidad then
      v_mismatch:=true; end if;
  end loop;
  if exists(select 1 from public.produccion_ordenes_eventos e
    where e.empresa_id=p_company and e.orden_id=p_job
      and not exists(select 1 from jsonb_array_elements(v_job.formula_copia) x
        where x->>'component_id'=e.componente_id::text)
    group by e.componente_id
    having sum(case when e.tipo='entrega' then e.cantidad else -e.cantidad end)>0) then
    v_mismatch:=true; end if;
  if v_mismatch and length(btrim(coalesce(p_variance_note,'')))<5 then
    raise exception 'Explicá la diferencia entre lo previsto y lo fabricado'; end if;
  select round(coalesce(sum(case when e.tipo='entrega' then 1 else -1 end
    *e.cantidad*e.costo_unitario),0),2) into v_cost
    from public.produccion_ordenes_eventos e where e.empresa_id=p_company and e.orden_id=p_job;
  if v_cost<0 then raise exception 'Los consumos de la orden son inconsistentes'; end if;
  if not exists(select 1 from public.produccion_ordenes_eventos e
    where e.empresa_id=p_company and e.orden_id=p_job and e.tipo='entrega'
      and e.cantidad>(select coalesce(sum(r.cantidad),0)
        from public.produccion_ordenes_eventos r where r.empresa_id=e.empresa_id
          and r.entrega_id=e.id)) then
    raise exception 'No quedan insumos consumidos para fabricar el producto'; end if;
  v_run:=gen_random_uuid();
  perform pg_catalog.set_config('dromux.production_job',p_job::text,true);
  v_output:=public.post_stock_operation(p_company,v_job.producto_id,
    v_job.deposito_id,null,'ingreso',p_actual_quantity,
    'Fabricación orden '||p_job::text,gen_random_uuid(),v_lot,p_expires_on);
  perform pg_catalog.set_config('dromux.production_job','',true);
  insert into public.produccion_fabricaciones(id,empresa_id,producto_id,formula_version,
    cantidad,deposito_id,operacion_producto_id,costo_estimado,solicitud_id,
    solicitud_datos,nota,autor_id)
  values(v_run,p_company,v_job.producto_id,v_job.formula_version,
    p_actual_quantity,v_job.deposito_id,v_output,v_cost,p_request_id,
    jsonb_build_object('job',p_job,'actual_quantity',p_actual_quantity,
      'output_lot',v_lot,'expiry',p_expires_on),v_job.nota,auth.uid());
  update public.produccion_ordenes set estado='terminada',cantidad_real=p_actual_quantity,
    producto_lote=v_lot,producto_vencimiento=p_expires_on,
    nota_diferencia=nullif(btrim(p_variance_note),''),fabricacion_id=v_run,
    solicitud_cierre_id=p_request_id,terminado_en=clock_timestamp()
    where empresa_id=p_company and id=p_job;
  if v_job.plan_id is not null then
    update public.produccion_planes set estado='terminado',fabricacion_id=v_run,
      solicitud_cierre_id=p_request_id,terminado_en=clock_timestamp()
      where empresa_id=p_company and id=v_job.plan_id and estado='planificado';
    if not found then raise exception 'La planificación fue modificada'; end if;
  end if;
  return v_run;
end;
$function$;

CREATE OR REPLACE FUNCTION public.finish_production_job_adjusted(p_company uuid, p_job uuid, p_actual_quantity numeric, p_output_lot text, p_expires_on date, p_variance_note text, p_request_id uuid, p_adjustments jsonb DEFAULT '[]'::jsonb, p_packaging jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_job public.produccion_ordenes%rowtype;
  v_adj jsonb;
  v_index integer := 0;
  v_part integer;
  v_kind text;
  v_component uuid;
  v_warehouse uuid;
  v_lot text;
  v_quantity numeric;
  v_note text;
  v_left numeric;
  v_take numeric;
  v_event record;
  v_seen uuid[] := '{}';
  v_pack jsonb;
  v_packs jsonb := '[]'::jsonb;
  v_count numeric;
  v_unit text;
  v_total numeric := 0;
  v_complete boolean := true;
  v_options jsonb;
begin
  if auth.uid() is null or not ((private.has_permission(p_company,'produccion_ordenes','crear')
      and private.has_permission(p_company,'stock','crear'))
    or private.can_operate_production(p_company)) then
    raise exception 'Necesitás permiso de producción y stock' using errcode = '42501';
  end if;
  if p_request_id is null
    or p_adjustments is null or jsonb_typeof(p_adjustments) <> 'array'
    or jsonb_array_length(p_adjustments) > 300
    or p_packaging is null or jsonb_typeof(p_packaging) <> 'object' then
    raise exception 'Revisá los ajustes y el recuento de envases';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('finish-job:' || p_company::text || ':' || p_job::text, 0));
  select * into v_job from public.produccion_ordenes where empresa_id = p_company and id = p_job for update;
  if not found then raise exception 'Orden inexistente'; end if;

  -- Reintento de una orden ya terminada: no se repiten ajustes; la función original valida que sean los mismos datos.
  if v_job.estado = 'terminada' then
    return public.finish_production_job(p_company, p_job, p_actual_quantity, p_output_lot,
      p_expires_on, p_variance_note, p_request_id);
  end if;
  if v_job.estado <> 'en_proceso' then
    raise exception 'Iniciá la orden y registrá sus insumos antes de terminar';
  end if;

  -- Devolver exige además producción:update (lo valida return_production_material): avisar antes de mover nada.
  if exists (select 1 from jsonb_array_elements(p_adjustments) a where a.value->>'kind' = 'devolucion')
    and not private.has_permission(p_company,'produccion_ordenes','editar') then
    raise exception 'Necesitás permiso para devolver insumos al stock' using errcode = '42501';
  end if;

  -- Ajustes de insumos.
  for v_adj in select value from jsonb_array_elements(p_adjustments) loop
    v_index := v_index + 1;
    if jsonb_typeof(v_adj) <> 'object' then raise exception 'Ajuste inválido en la línea %', v_index; end if;
    v_kind := v_adj->>'kind';
    -- Validar formato antes de convertir: evita errores crudos de conversión.
    if coalesce(v_adj->>'component_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or coalesce(v_adj->>'quantity', '') !~ '^[0-9]{1,12}(\.[0-9]{1,6})?$'
      or (nullif(v_adj->>'warehouse_id', '') is not null
        and v_adj->>'warehouse_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
      raise exception 'Ajuste inválido en la línea %', v_index;
    end if;
    v_component := (v_adj->>'component_id')::uuid;
    v_quantity := (v_adj->>'quantity')::numeric;
    v_note := left('Ajuste al terminar: ' || coalesce(nullif(btrim(v_adj->>'note'), ''), 'diferencia de consumo'), 300);
    if coalesce(v_kind, '') not in ('entrega', 'devolucion') or v_component is null
      or v_quantity is null or v_quantity <= 0 or v_quantity >= 1000000000000
      or v_quantity <> round(v_quantity, 6) then
      raise exception 'Ajuste inválido en la línea %', v_index;
    end if;
    if v_component = any(v_seen) then
      raise exception 'Hay dos ajustes para el mismo insumo (línea %)', v_index;
    end if;
    v_seen := array_append(v_seen, v_component);

    if v_kind = 'entrega' then
      v_warehouse := (v_adj->>'warehouse_id')::uuid;
      v_lot := nullif(btrim(v_adj->>'lot_code'), '');
      if v_warehouse is null then raise exception 'Indicá el depósito del insumo adicional (línea %)', v_index; end if;
      perform public.issue_production_material(p_company, p_job, v_component, v_warehouse, v_lot,
        v_quantity, v_note, md5(p_request_id::text || ':adj:' || v_index::text)::uuid);
    else
      v_left := v_quantity;
      v_part := 0;
      for v_event in
        select e.id,
          e.cantidad - coalesce((select sum(r.cantidad) from public.produccion_ordenes_eventos r
            where r.empresa_id = e.empresa_id and r.entrega_id = e.id and r.tipo = 'devolucion'), 0) as open_quantity
        from public.produccion_ordenes_eventos e
        where e.empresa_id = p_company and e.orden_id = p_job
          and e.componente_id = v_component and e.tipo = 'entrega'
        order by e.creado_en desc, e.id desc
      loop
        exit when v_left <= 0;
        if v_event.open_quantity > 0 then
          v_take := least(v_event.open_quantity, v_left);
          v_part := v_part + 1;
          perform public.return_production_material(p_company, p_job, v_event.id, v_take, v_note,
            md5(p_request_id::text || ':ret:' || v_index::text || ':' || v_part::text)::uuid);
          v_left := v_left - v_take;
        end if;
      end loop;
      if v_left > 0 then
        raise exception 'La devolución supera lo entregado de ese insumo (línea %)', v_index;
      end if;
    end if;
  end loop;

  -- Recuento de envases (informativo: no mueve stock). El resto sin envasar se calcula si todos los envases
  -- tienen la misma unidad que el producto.
  if exists (select 1 from jsonb_object_keys(p_packaging)) then
    if exists (
      select 1 from jsonb_each(p_packaging) e
      where not exists (select 1 from jsonb_array_elements(coalesce(v_job.opciones_trabajo->'packaging', '[]')) x
          where x->>'id' = e.key)
        or (jsonb_typeof(e.value) not in ('number', 'null'))
        or (jsonb_typeof(e.value) = 'number'
          and ((e.value#>>'{}')::numeric < 0 or (e.value#>>'{}')::numeric >= 1000000000
            or (e.value#>>'{}')::numeric <> trunc((e.value#>>'{}')::numeric)))
    ) then
      raise exception 'El recuento de envases debe usar los envasados de la orden con cantidades enteras';
    end if;
    select u.simbolo into v_unit
      from public.stock_items i
      join public.stock_unidades u on u.empresa_id = i.empresa_id and u.id = i.unidad_id
      where i.empresa_id = p_company and i.id = v_job.producto_id;
    for v_pack in select value from jsonb_array_elements(coalesce(v_job.opciones_trabajo->'packaging', '[]')) loop
      v_count := case when p_packaging ? (v_pack->>'id')
        then nullif(p_packaging->>(v_pack->>'id'), '')::numeric
        else nullif(v_pack->>'actual_count', '')::numeric end;
      v_packs := v_packs || jsonb_build_array(v_pack || jsonb_build_object('actual_count', v_count));
      if v_count is null or (v_pack->>'unit') is distinct from v_unit then
        v_complete := false;
      else
        v_total := v_total + v_count * (v_pack->>'capacity')::numeric;
      end if;
    end loop;
    if v_complete and v_total > p_actual_quantity then
      raise exception 'Los envases contados suman más de lo fabricado: revisá los recuentos';
    end if;
    v_options := coalesce(v_job.opciones_trabajo, '{}'::jsonb)
      || jsonb_build_object('packaging', v_packs,
        'unpackaged_quantity', case when v_complete and jsonb_array_length(v_packs) > 0
          then to_jsonb(round(p_actual_quantity - v_total, 6)) else 'null'::jsonb end);
    update public.produccion_ordenes
      set opciones_trabajo = v_options, detalles_actualizado_en = clock_timestamp()
      where empresa_id = p_company and id = p_job;
  end if;

  return public.finish_production_job(p_company, p_job, p_actual_quantity, p_output_lot,
    p_expires_on, p_variance_note, p_request_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_production_job(p_company uuid, p_job uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.produccion_ordenes%rowtype; v_open numeric;
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_ordenes','gestionar') then
    raise exception 'Sin permiso para cancelar órdenes' using errcode='42501'; end if;
  if length(btrim(coalesce(p_reason,''))) not between 5 and 300 then
    raise exception 'Indicá un motivo de al menos cinco caracteres'; end if;
  select * into v_job from public.produccion_ordenes
    where empresa_id=p_company and id=p_job for update;
  if not found or v_job.estado not in ('pendiente','en_proceso') then
    raise exception 'La orden no se puede cancelar'; end if;
  select coalesce(sum(case when e.tipo='entrega' then e.cantidad else -e.cantidad end),0)
    into v_open from public.produccion_ordenes_eventos e
    where e.empresa_id=p_company and e.orden_id=p_job;
  if v_open<>0 then
    raise exception 'Devolvé todos los insumos pendientes antes de cancelar la orden'; end if;
  update public.produccion_ordenes set estado='cancelada',cancelado_en=clock_timestamp(),
    motivo_cancelacion=btrim(p_reason) where empresa_id=p_company and id=p_job;
  if v_job.plan_id is not null then
    update public.produccion_planes set estado='cancelado',cancelado_en=clock_timestamp()
      where empresa_id=p_company and id=v_job.plan_id and estado='planificado';
    if not found then raise exception 'La planificación fue modificada'; end if;
  end if;
end;
$function$;

commit;

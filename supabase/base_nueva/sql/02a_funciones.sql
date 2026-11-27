-- 02a. Funciones (primera parte).
begin;
set local check_function_bodies = off;

CREATE OR REPLACE FUNCTION private.access_audit_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  raise exception 'El historial de accesos no se modifica ni se borra';
end;
$function$;

CREATE OR REPLACE FUNCTION private.can_see_production_costs(p_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(private.get_user_role(p_company) = 'administrador', false)
      or private.has_permission(p_company, 'costos_produccion', 'ver');
$function$;

CREATE OR REPLACE FUNCTION private.can_see_reference_cost(p_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(private.get_user_role(p_company) = 'administrador', false)
      or private.has_permission(p_company, 'costos_materiales', 'ver');
$function$;

CREATE OR REPLACE FUNCTION private.check_infinite_stock_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.stock_infinito and (tg_op='INSERT' or not old.stock_infinito) then
    if exists (select 1 from public.stock_saldos b where b.empresa_id=new.empresa_id
      and b.item_id=new.id and b.cantidad<>0) then
      raise exception 'Dejá el saldo físico en cero antes de activar stock infinito';
    end if;
    if exists (select 1 from public.produccion_ordenes_reservas r
      join public.produccion_ordenes j on j.empresa_id=r.empresa_id and j.id=r.orden_id
      where r.empresa_id=new.empresa_id and r.componente_id=new.id
        and j.estado in ('pendiente','en_proceso')) then
      raise exception 'Terminá las órdenes pendientes antes de activar stock infinito';
    end if;
  end if;
  if tg_op='UPDATE' and old.stock_infinito and not new.stock_infinito then
    if exists (select 1 from public.produccion_ordenes_reservas r
      join public.produccion_ordenes j on j.empresa_id=r.empresa_id and j.id=r.orden_id
      where r.empresa_id=new.empresa_id and r.componente_id=new.id
        and j.estado in ('pendiente','en_proceso')) then
      raise exception 'Terminá las órdenes pendientes antes de cambiar el modo de stock';
    end if;
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION private.check_item_catalogs()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_check_unit boolean;
  v_check_category boolean;
begin
  if tg_op = 'INSERT' then
    v_check_unit := true;
    v_check_category := true;
  else
    v_check_unit := new.unidad_id is distinct from old.unidad_id;
    v_check_category := new.categoria_id is distinct from old.categoria_id;
  end if;

  if v_check_unit and not exists (
    select 1 from public.stock_unidades u
    where u.id = new.unidad_id and u.empresa_id = new.empresa_id and u.activo
  ) then
    raise exception 'Seleccioná una unidad activa de esta empresa';
  end if;

  if v_check_category and new.categoria_id is not null and not exists (
    select 1 from public.stock_categorias c
    where c.id = new.categoria_id and c.empresa_id = new.empresa_id and c.activo
  ) then
    raise exception 'Seleccioná una categoría activa de esta empresa';
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.check_reference_fx_cost()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rate numeric;
begin
  if new.costo_referencia_usd is not null then
    if not exists(select 1 from public.finanzas_tipos_cambio t where t.empresa_id=new.empresa_id
      and t.id=new.tipo_cambio_referencia_id and t.activo) then
      raise exception 'Elegí un tipo de dólar activo';
    end if;
    v_rate:=private.current_fx_rate(new.empresa_id,new.tipo_cambio_referencia_id);
    if v_rate is null then raise exception 'Cargá una cotización vigente para ese tipo de dólar'; end if;
    new.costo_unitario_referencia:=round(new.costo_referencia_usd*v_rate,2);
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION private.check_stock_catalog_deactivation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if old.activo and not new.activo then
    if tg_table_name = 'stock_items' and exists (
      select 1 from public.stock_saldos b
      where b.empresa_id = old.empresa_id
        and b.item_id = old.id and b.cantidad > 0
    ) then
      raise exception 'Trasladá o consumí el stock antes de desactivar el ítem';
    end if;
    if tg_table_name = 'stock_depositos' and exists (
      select 1 from public.stock_saldos b
      where b.empresa_id = old.empresa_id
        and b.deposito_id = old.id and b.cantidad > 0
    ) then
      raise exception 'Trasladá el stock antes de desactivar el depósito';
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.check_supplier_item()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op='INSERT' or new.precio_unitario is distinct from old.precio_unitario
    or new.proveedor_codigo is distinct from old.proveedor_codigo
    or new.moneda is distinct from old.moneda
    or new.tipo_cambio_id is distinct from old.tipo_cambio_id
    or new.ajuste_porcentaje is distinct from old.ajuste_porcentaje
    or (new.preferido and new.preferido is distinct from old.preferido) then
    if not exists(select 1 from public.stock_items i where i.empresa_id=new.empresa_id
      and i.id=new.item_id and i.activo) then
      raise exception 'Elegí un ítem activo'; end if;
    if not exists(select 1 from public.compras_proveedores s where s.empresa_id=new.empresa_id
      and s.id=new.proveedor_id and s.activo) then
      raise exception 'Elegí un proveedor activo'; end if;
    if new.moneda='USD' and not exists(select 1 from public.finanzas_tipos_cambio t
      where t.empresa_id=new.empresa_id and t.id=new.tipo_cambio_id and t.activo) then
      raise exception 'Elegí un tipo de dólar activo'; end if;
  end if;
  new.actualizado_en:=clock_timestamp();
  return new;
end; $function$;

create or replace function private.cleanup_has_references(p_company uuid, p_resource text, p_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare v_target record; v_fk record; v_join text; v_found boolean; v_skip text[]:='{}';
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if p_resource='items' then v_skip:=array['compras_proveedores_items']; end if;
  if p_resource='formulas' then v_skip:=array['produccion_formulas_lineas']; end if;
  if p_resource='ordenes' then v_skip:=array['produccion_ordenes_reservas']; end if;
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
    execute format('select exists(select 1 from %I.%I c join public.%I p on %s where p.empresa_id=$1 and p.%I=$2)',
      v_fk.nspname,v_fk.relname,v_target.table_name,v_join,v_target.id_field)
      into v_found using p_company,p_id;
    if v_found then return true; end if;
  end loop;
  -- Las copias guardadas (jsonb) conservan sus claves en inglés.
  if p_resource='items' and (exists(
    select 1 from public.produccion_ordenes j cross join lateral jsonb_array_elements(j.formula_copia) x
      where j.empresa_id=p_company and x->>'component_id'=p_id::text)
    or exists(select 1 from public.produccion_planes p cross join lateral jsonb_array_elements(p.componentes_copia) x
      where p.empresa_id=p_company and x->>'component_id'=p_id::text)) then return true; end if;
  if p_resource='formulas' and (exists(select 1 from public.produccion_ordenes where empresa_id=p_company and producto_id=p_id)
    or exists(select 1 from public.produccion_fabricaciones where empresa_id=p_company and producto_id=p_id)
    or exists(select 1 from public.produccion_planes where empresa_id=p_company and producto_id=p_id)
    or exists(select 1 from public.produccion_formulas_lineas where empresa_id=p_company and componente_id=p_id)) then return true; end if;
  return false;
end
$function$;

-- Qué se puede eliminar o archivar: tabla, columna que identifica y permiso.
create or replace function private.cleanup_target(p_resource text)
returns table(table_name text, id_field text, permission text)
language sql
immutable
set search_path to ''
as $function$
  select t.table_name, t.id_field, t.permission from (values
    ('items', 'stock_items', 'id', 'items'),
    ('tipos_cambio', 'finanzas_tipos_cambio', 'id', 'compras_proveedores'),
    ('formulas', 'produccion_formulas', 'producto_id', 'produccion_formulas'),
    ('ordenes', 'produccion_ordenes', 'id', 'produccion_ordenes'),
    ('fabricaciones', 'produccion_fabricaciones', 'id', 'produccion_ordenes'),
    ('planes', 'produccion_planes', 'id', 'produccion_planificacion'),
    ('remitos', 'stock_remitos', 'id', 'stock_remitos')
  ) t(resource, table_name, id_field, permission) where t.resource = p_resource
$function$;

CREATE OR REPLACE FUNCTION private.current_fx_rate(p_company uuid, p_type uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select r.ars_por_usd from public.finanzas_cotizaciones r
  where r.empresa_id=p_company and r.tipo_cambio_id=p_type and r.vigente_desde<=(now() at time zone 'America/Argentina/Buenos_Aires')::date
  order by r.vigente_desde desc,r.creado_en desc,r.id desc limit 1
$function$;

CREATE OR REPLACE FUNCTION private.erp_production_alerts(p_company uuid)
 RETURNS TABLE(alert_key text, fingerprint text, severity text, title text, detail text, destination text, occurred_on date)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'inicio', 'ver') then
    raise exception 'Sin acceso al centro operativo' using errcode = '42501';
  end if;

  if private.has_permission(p_company,'produccion_resumen','ver') then
    return query
    select 'job:' || j.id::text,
      j.estado || ':' || coalesce(j.fecha_limite::text, ''),
      case when j.fecha_limite < v_today then 'critical' else 'warning' end,
      case when j.fecha_limite < v_today then 'Fabricación fuera de plazo'
        else 'Fabricación próxima a vencer' end,
      i.nombre || ' · ' || j.cantidad_planificada::text || ' ' || u.simbolo ||
        ' · Fecha prevista: ' || to_char(j.fecha_limite, 'DD/MM/YYYY'),
      '/production/orders?job=' || j.id::text, j.fecha_limite
    from public.produccion_ordenes j
    join public.stock_items i on i.empresa_id = j.empresa_id and i.id = j.producto_id
    join public.stock_unidades u on u.empresa_id = i.empresa_id and u.id = i.unidad_id
    where j.empresa_id = p_company and j.estado in ('pendiente', 'en_proceso')
      and j.fecha_limite <= v_today + 3;
  end if;

  if private.has_permission(p_company,'stock_saldos','ver')
    and private.has_permission(p_company, 'items', 'ver') then
    return query
    select 'stock:' || i.id::text,
      i.stock_minimo::text || ':' || coalesce(b.total, 0)::text,
      case when coalesce(b.total, 0) <= 0 then 'critical' else 'warning' end,
      case when coalesce(b.total, 0) <= 0 then 'Ítem sin existencias'
        else 'Stock bajo el mínimo' end,
      i.nombre || ' · Disponible físico: ' || coalesce(b.total, 0)::text ||
        ' ' || u.simbolo || ' · Mínimo: ' || i.stock_minimo::text || ' ' || u.simbolo,
      '/inventory/stock', v_today
    from public.stock_items i
    join public.stock_unidades u on u.empresa_id = i.empresa_id and u.id = i.unidad_id
    left join lateral (
      select sum(sb.cantidad) as total from public.stock_saldos sb
      where sb.empresa_id = i.empresa_id and sb.item_id = i.id
    ) b on true
    where i.empresa_id = p_company and i.activo
      and i.tipo_item in ('materia_prima', 'semielaborado', 'insumo', 'producto_terminado')
      and i.stock_minimo > 0 and coalesce(b.total, 0) < i.stock_minimo;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION private.get_user_role(p_company uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((
    select r.codigo from public.empresas_usuarios cu
    join public.empresas c on c.id=cu.empresa_id
    join public.ajustes_roles r on r.id=cu.rol_id and r.empresa_id=cu.empresa_id
    where cu.empresa_id=p_company and cu.usuario_id=(select auth.uid())
      and cu.activo and c.activo limit 1
  ),case when private.support_session_active(p_company) then 'soporte' end);
$function$;

CREATE OR REPLACE FUNCTION private.guard_archived_formula_edit()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$ begin
  if old.archivado then raise exception 'La fórmula está archivada. Recuperala antes de editarla'; end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION private.guard_archived_recipe()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ begin
  if exists(select 1 from public.produccion_formulas where empresa_id=new.empresa_id and producto_id=new.producto_id and archivado) then
    raise exception 'La fórmula está archivada. Recuperala antes de fabricar o planificar'; end if;
  if exists(select 1 from private.produccion_solicitudes_eliminadas where empresa_id=new.empresa_id
    and solicitud_id=new.solicitud_id and recurso=case tg_table_name when 'produccion_ordenes' then 'ordenes' when 'produccion_planes' then 'planes' else 'fabricaciones' end) then
    raise exception 'Esta solicitud corresponde a un registro eliminado. Generá una nueva orden'; end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION private.guard_purchase_supplier_item()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_supplier uuid; v_currency text; v_exchange_type uuid;
begin
  select o.proveedor_id into v_supplier from public.compras_ordenes o
    where o.empresa_id=new.empresa_id and o.id=new.orden_compra_id;
  select si.moneda,si.tipo_cambio_id into v_currency,v_exchange_type
    from public.compras_proveedores_items si
    join public.stock_items i on i.empresa_id=si.empresa_id and i.id=si.item_id
    where si.empresa_id=new.empresa_id and si.proveedor_id=v_supplier
      and si.item_id=new.item_id and i.activo;
  if not found then
    raise exception 'El proveedor no tiene asociado este ítem. Cargá primero su cotización'; end if;
  if v_currency='USD' and private.current_fx_rate(new.empresa_id,v_exchange_type) is null then
    raise exception 'La cotización en dólares necesita un tipo de cambio vigente'; end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_reversal_after_refund()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_net numeric; v_paid numeric; v_refunded numeric; v_payment public.ventas_cobros%rowtype;
begin
  select * into v_payment from public.ventas_cobros
    where empresa_id=new.empresa_id and id=new.cobro_id;
  select greatest(0,s.total-coalesce(sum(a.credito_total),0)) into v_net
    from public.ventas s left join public.ventas_ajustes a
      on a.empresa_id=s.empresa_id and a.venta_id=s.id
    where s.empresa_id=new.empresa_id and s.id=v_payment.venta_id
    group by s.total;
  select coalesce(sum(p.importe),0) into v_paid from public.ventas_cobros p
    where p.empresa_id=new.empresa_id and p.venta_id=v_payment.venta_id
      and p.id<>new.cobro_id and not exists(
        select 1 from public.ventas_cobros_reversiones r
        where r.empresa_id=p.empresa_id and r.cobro_id=p.id);
  select coalesce(sum(f.importe),0) into v_refunded from public.ventas_reintegros f
    where f.empresa_id=new.empresa_id and f.venta_id=v_payment.venta_id;
  if v_refunded>greatest(0,v_paid-v_net) then
    raise exception 'El cobro ya tiene un reintegro: no puede anularse sin regularizarlo'; end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_sale_payment_net()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_net numeric; v_paid numeric;
begin
  select greatest(0,s.total-coalesce(sum(a.credito_total),0)) into v_net
  from public.ventas s left join public.ventas_ajustes a
    on a.empresa_id=s.empresa_id and a.venta_id=s.id
  where s.empresa_id=new.empresa_id and s.id=new.venta_id
  group by s.total;
  select coalesce(sum(p.importe),0) into v_paid from public.ventas_cobros p
    where p.empresa_id=new.empresa_id and p.venta_id=new.venta_id
      and not exists(select 1 from public.ventas_cobros_reversiones r
        where r.empresa_id=p.empresa_id and r.cobro_id=p.id);
  if v_net is null or v_paid+new.importe>v_net then
    raise exception 'El cobro supera el saldo neto después de las devoluciones'; end if;
  return new;
end;
$function$;

create or replace function private.has_permission(p_company uuid, p_resource text, p_action text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select (
    exists (
      select 1
      from public.empresas_usuarios cu
      join public.empresas c on c.id = cu.empresa_id
      join public.ajustes_roles_permisos rp on rp.rol_id = cu.rol_id and rp.empresa_id = cu.empresa_id
      where cu.empresa_id = p_company and cu.usuario_id = (select auth.uid()) and cu.activo and c.activo
        and rp.recurso = p_resource and rp.accion = p_action
    ) or (
      p_action = 'ver'
      and (
        p_resource in ('inicio', 'inventario', 'items', 'stock', 'depositos', 'unidades', 'categorias',
          'produccion', 'compras', 'ventas', 'finanzas', 'reportes', 'ajustes', 'usuarios', 'roles')
        or exists (select 1 from public.ajustes_permisos_catalogo pc where pc.recurso = p_resource and pc.modulo <> 'sensible')
      )
      and private.support_session_active(p_company)
    )
  ) and private.module_enabled(p_company, p_resource)
$function$;

CREATE OR REPLACE FUNCTION private.import_items(p_company uuid, p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rows jsonb; v_row jsonb; v_id uuid; v_supplier uuid; v_fx uuid; v_usd numeric;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('import-items:'||p_company::text,0));
  v_rows:=private.prepare_item_import(p_company,p_rows);
  for v_row in select value from jsonb_array_elements(v_rows) loop
    v_supplier:=nullif(v_row->>'supplier_id','')::uuid;
    v_fx:=nullif(v_row->>'exchange_type_id','')::uuid;
    v_usd:=nullif(v_row->>'cost_usd','')::numeric;
    insert into public.stock_items(empresa_id,codigo,nombre,tipo_item,categoria_id,unidad_id,codigo_barras,
      descripcion,stock_minimo,usa_lotes,stock_infinito,costo_unitario_referencia,precio_venta_unitario,
      activo,costo_referencia_usd,tipo_cambio_referencia_id)
    values(p_company,btrim(v_row->>'codigo'),btrim(v_row->>'nombre'),v_row->>'tipo',
      nullif(v_row->>'category_id','')::uuid,(v_row->>'unit_id')::uuid,
      nullif(btrim(v_row->>'codigo_barras'),''),btrim(v_row->>'descripcion'),
      (v_row->>'stock_minimo')::numeric,(v_row->>'seguir_lotes')::boolean,
      (v_row->>'stock_infinito')::boolean,nullif(v_row->>'cost_ars','')::numeric,
      nullif(v_row->>'precio_venta_ars','')::numeric,(v_row->>'activo')::boolean,
      case when v_supplier is null then v_usd end,
      case when v_supplier is null then v_fx end) returning id into v_id;
    if v_supplier is not null then
      perform public.save_supplier_quote(p_company,v_supplier,v_id,
        coalesce(v_usd,(v_row->>'cost_ars')::numeric),'',
        case when v_usd is null then 'ARS' else 'USD' end,v_fx,0,null,true);
      perform public.set_preferred_supplier(p_company,v_id,v_supplier);
    end if;
  end loop;
  return jsonb_array_length(v_rows);
end; $function$;

CREATE OR REPLACE FUNCTION private.is_company_member(p_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.empresas_usuarios cu
    join public.empresas c on c.id=cu.empresa_id
    where cu.empresa_id=p_company and cu.usuario_id=(select auth.uid())
      and cu.activo and c.activo
  ) or private.support_session_active(p_company);
$function$;

CREATE OR REPLACE FUNCTION private.issue_production_material(p_company uuid, p_job uuid, p_component uuid, p_warehouse uuid, p_lot text, p_quantity numeric, p_note text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.produccion_ordenes%rowtype;
  v_previous public.produccion_ordenes_eventos%rowtype;
  v_cost numeric; v_operation uuid; v_event uuid;
  v_lot text:=nullif(btrim(p_lot),'');
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_ordenes','crear')
    or not private.has_permission(p_company,'stock','crear') then
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
    and i.activo and i.tipo_item in ('materia_prima','semielaborado') for share;
  if not found then raise exception 'Elegí una materia prima o un semielaborado activo'; end if;
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

CREATE OR REPLACE FUNCTION private.log_access_event(p_company uuid, p_action text, p_user uuid, p_role uuid, p_detail jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  insert into public.ajustes_auditoria_accesos(empresa_id, autor_id, accion, usuario_destino_id, rol_destino_id, detalle)
  values (p_company, auth.uid(), p_action, p_user, p_role, coalesce(p_detail, '{}'::jsonb));
$function$;

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
  if v_actor is null or not private.has_permission(p_company, 'stock', 'crear') then
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
  if not found or not private.has_permission(p_company, 'stock', 'crear') then
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

CREATE OR REPLACE FUNCTION private.prepare_item_import(p_company uuid, p_rows jsonb, p_existing uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row jsonb; v_index integer:=0; v_unit uuid; v_category uuid;
  v_code text; v_name text; v_type text; v_barcode text;
  v_cost numeric; v_price numeric; v_min numeric; v_lots boolean;
  v_infinite boolean; v_active boolean; v_description text;
  v_supplier uuid; v_fx_type uuid; v_usd numeric; v_rate numeric; v_matches integer;
  v_supplier_name text; v_fx_name text;
  v_result jsonb := '[]'::jsonb; v_codes text[] := '{}'; v_barcodes text[] := '{}';
begin
  if auth.uid() is null or not private.has_permission(p_company,'items',case when p_existing is null then 'crear' else 'editar' end) then
    raise exception 'No tenés permiso para importar ítems' using errcode='42501';
  end if;
  perform 1 from public.empresas where id=p_company and activo for share;
  if not found then raise exception 'La empresa no está activa'; end if;
  if p_rows is null or jsonb_typeof(p_rows)<>'array'
    or jsonb_array_length(p_rows) not between 1 and 200 then
    raise exception 'Importá entre 1 y 200 ítems por archivo';
  end if;
  if p_existing is not null and jsonb_array_length(p_rows)<>1 then
    raise exception 'La edición debe contener un solo ítem';
  end if;
  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_index:=v_index+1;
    if jsonb_typeof(v_row)<>'object' then
      raise exception 'Fila %: formato inválido',v_index+1;
    end if;
    v_code:=btrim(coalesce(v_row->>'codigo',''));
    v_name:=btrim(coalesce(v_row->>'nombre',''));
    v_type:=btrim(coalesce(v_row->>'tipo',''));
    v_barcode:=nullif(btrim(coalesce(v_row->>'codigo_barras','')),'');
    v_description:=btrim(coalesce(v_row->>'descripcion',''));
    if v_code !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$'
      or length(v_name) not between 2 and 160
      or v_type not in ('materia_prima','semielaborado','producto_terminado','insumo')
      or length(v_description)>1500
      or (v_barcode is not null and length(v_barcode) not between 4 and 80) then
      raise exception 'Fila %: revisá código, nombre, tipo, descripción y código de barras',v_index+1;
    end if;
    if coalesce(v_row->>'stock_minimo','') !~ '^\d+(\.\d{1,6})?$'
      or coalesce(v_row->>'costo_referencia_ars','') !~ '^\d+(\.\d{1,2})?$'
      and nullif(v_row->>'costo_referencia_ars','') is not null
      or coalesce(v_row->>'precio_venta_ars','') !~ '^\d+(\.\d{1,2})?$'
      and nullif(v_row->>'precio_venta_ars','') is not null then
      raise exception 'Fila %: números inválidos (usá punto decimal)',v_index+1;
    end if;
    v_min:=(v_row->>'stock_minimo')::numeric;
    v_cost:=nullif(v_row->>'costo_referencia_ars','')::numeric;
    v_price:=nullif(v_row->>'precio_venta_ars','')::numeric;
    if v_min>=1000000000000 or coalesce(v_cost,0)>=1000000000000
      or coalesce(v_price,0)>=1000000000000 then
      raise exception 'Fila %: importe o cantidad fuera de rango',v_index+1;
    end if;
    if coalesce(v_row->>'seguir_lotes','') not in ('true','false')
      or coalesce(v_row->>'stock_infinito','') not in ('true','false')
      or coalesce(v_row->>'activo','') not in ('true','false') then
      raise exception 'Fila %: usá SI o NO en las columnas de opciones',v_index+1;
    end if;
    v_lots:=(v_row->>'seguir_lotes')::boolean;
    v_infinite:=(v_row->>'stock_infinito')::boolean;
    v_active:=(v_row->>'activo')::boolean;
    if v_infinite and (v_lots or v_min<>0) then
      raise exception 'Fila %: stock infinito requiere sin lotes y stock mínimo cero',v_index+1;
    end if;
    if v_price is not null and (v_type<>'producto_terminado'
      or private.get_user_role(p_company)<>'administrador'
      or not private.has_permission(p_company,'ventas','editar')) then
      raise exception 'Fila %: solo un administrador puede cargar precios de productos terminados',v_index+1;
    end if;
    v_supplier:=null; v_fx_type:=null; v_usd:=null; v_rate:=null;
    v_supplier_name:=nullif(btrim(coalesce(v_row->>'proveedor','')),'');
    v_fx_name:=nullif(btrim(coalesce(v_row->>'tipo_dolar','')),'');
    if nullif(btrim(coalesce(v_row->>'costo_usd','')),'') is not null then
      if btrim(v_row->>'costo_usd') !~ '^\d+(\.\d{1,2})?$' then
        raise exception 'Fila %: costo en dólares inválido, hasta dos decimales',v_index+1;
      end if;
      v_usd:=btrim(v_row->>'costo_usd')::numeric;
      if v_usd>=1000000000000 then raise exception 'Fila %: costo en dólares fuera de rango',v_index+1; end if;
      if v_fx_name is null then raise exception 'Fila %: indicá el tipo de dólar para el costo en dólares',v_index+1; end if;
    elsif v_fx_name is not null then
      raise exception 'Fila %: el tipo de dólar requiere un costo en dólares',v_index+1;
    end if;
    if v_fx_name is not null then
      select count(*), min(t.id::text)::uuid into v_matches,v_fx_type
        from public.finanzas_tipos_cambio t where t.empresa_id=p_company and t.activo
          and lower(btrim(t.nombre))=lower(v_fx_name);
      if v_matches<>1 then raise exception 'Fila %: el tipo de dólar no existe, está inactivo o su nombre es ambiguo',v_index+1; end if;
      v_rate:=private.current_fx_rate(p_company,v_fx_type);
      if v_rate is null then raise exception 'Fila %: cargá una cotización vigente para %',v_index+1,v_fx_name; end if;
      v_cost:=round(v_usd*v_rate,2);
      if v_cost>=1000000000000 then raise exception 'Fila %: costo convertido fuera de rango',v_index+1; end if;
    end if;
    if v_supplier_name is not null then
      if not private.has_permission(p_company,'compras_proveedores','editar') then
        raise exception 'Necesitás permiso para editar Compras para asociar proveedores' using errcode='42501';
      end if;
      select count(*),min(s.id::text)::uuid into v_matches,v_supplier from public.compras_proveedores s
        where s.empresa_id=p_company and s.activo and lower(btrim(s.nombre))=lower(v_supplier_name);
      if v_matches<>1 then raise exception 'Fila %: el proveedor no existe, está inactivo o su nombre es ambiguo',v_index+1; end if;
      if v_cost is null then raise exception 'Fila %: indicá un costo en pesos o dólares para asociar el proveedor',v_index+1; end if;
      if not v_active then raise exception 'Fila %: el ítem debe estar activo para asociar un proveedor',v_index+1; end if;
      if p_existing is not null and exists(select 1 from public.compras_proveedores_items q
        where q.empresa_id=p_company and q.item_id=p_existing and q.proveedor_id=v_supplier) then
        raise exception 'Este ítem ya está asociado al proveedor. Editá su precio en Compras';
      end if;
    end if;
    if v_type='materia_prima' and v_cost is null then
      raise exception 'Fila %: la materia prima necesita costo de referencia',v_index+1;
    end if;
    select u.id into v_unit from public.stock_unidades u
      where u.empresa_id=p_company and u.activo
        and lower(u.codigo)=lower(btrim(coalesce(v_row->>'unidad_codigo','')));
    if v_unit is null then
      raise exception 'Fila %: la unidad no existe o está inactiva',v_index+1;
    end if;
    v_category:=null;
    if nullif(btrim(coalesce(v_row->>'categoria_codigo','')),'') is not null then
      select c.id into v_category from public.stock_categorias c
        where c.empresa_id=p_company and c.activo
          and lower(c.codigo)=lower(btrim(v_row->>'categoria_codigo'));
      if v_category is null then
        raise exception 'Fila %: la categoría no existe o está inactiva',v_index+1;
      end if;
    end if;
    if exists (select 1 from public.stock_items i where i.empresa_id=p_company
      and i.id is distinct from p_existing and lower(i.codigo)=lower(v_code)) then
      raise exception 'Fila %: el código % ya existe o está repetido',v_index+1,v_code;
    end if;
    if v_barcode is not null and exists (select 1 from public.stock_items i
      where i.empresa_id=p_company and i.id is distinct from p_existing and i.codigo_barras=v_barcode) then
      raise exception 'Fila %: el código de barras % ya existe o está repetido',v_index+1,v_barcode;
    end if;
    if lower(v_code)=any(v_codes) or (v_barcode is not null and v_barcode=any(v_barcodes)) then
      raise exception 'Fila %: código o código de barras repetido en el archivo',v_index+1;
    end if;
    v_codes:=array_append(v_codes,lower(v_code));
    if v_barcode is not null then v_barcodes:=array_append(v_barcodes,v_barcode); end if;
    v_result:=v_result || jsonb_build_array(v_row || jsonb_build_object(
      'unit_id',v_unit,'category_id',v_category,'supplier_id',v_supplier,
      'exchange_type_id',v_fx_type,'cost_ars',v_cost,'cost_usd',v_usd,'exchange_rate',v_rate));
  end loop;
  return v_result;
end; $function$;

CREATE OR REPLACE FUNCTION private.prepare_production_document()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_factor numeric; v_options jsonb;
begin
  insert into public.empresas_numeradores(empresa_id,documento,proximo_numero) values(new.empresa_id,'orden_fabricacion',2)
    on conflict(empresa_id,documento) do update set proximo_numero=public.empresas_numeradores.proximo_numero+1
    returning proximo_numero-1 into new.numero;
  select case when usa_rendimiento then factor_rendimiento else 1 end into v_factor
    from public.stock_items where empresa_id=new.empresa_id and id=new.producto_id;
  new.factor_rendimiento:=coalesce(v_factor,1);
  new.cantidad_esperada:=round(new.cantidad_planificada*new.factor_rendimiento,6);
  if new.cantidad_esperada<=0 or new.cantidad_esperada>=1000000000000 then raise exception 'Salida esperada fuera de rango'; end if;
  select jsonb_build_object('code',documento_codigo,'revision',revision,'labels',observaciones_etiquetas)
    into new.documento_copia from public.produccion_documentos_config where empresa_id=new.empresa_id;
  new.documento_copia:=coalesce(new.documento_copia,'{}');
  v_options:=nullif(pg_catalog.current_setting('dromux.work_options',true),'')::jsonb;
  new.opciones_trabajo_solicitadas:=coalesce(v_options,'{}');
  new.opciones_trabajo:=private.snapshot_work_options(new.empresa_id,coalesce(v_options,'{}'));
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION private.prevent_infinite_physical_movement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_infinite boolean;
begin
  select i.stock_infinito into v_infinite from public.stock_items i
    where i.empresa_id=new.empresa_id and i.id=new.item_id for share;
  if coalesce(v_infinite,false) then
    raise exception 'El ítem tiene stock infinito; no registra movimientos físicos';
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION private.prevent_late_lot_tracking()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.usa_lotes and not old.usa_lotes and exists (
    select 1 from public.stock_saldos b
    where b.empresa_id = old.empresa_id and b.item_id = old.id
      and b.cantidad <> coalesce((
        select sum(lb.cantidad) from public.stock_lotes_saldos lb
        where lb.empresa_id = b.empresa_id and lb.item_id = b.item_id
          and lb.deposito_id = b.deposito_id
      ), 0)
  ) then
    raise exception 'El ítem tiene stock sin lotes: activá la trazabilidad desde la ficha';
  end if;

  if old.usa_lotes and not new.usa_lotes and exists (
    select 1 from public.stock_lotes l
    where l.empresa_id = old.empresa_id and l.item_id = old.id
  ) then
    raise exception 'No se puede desactivar lotes en un ítem que ya tiene lotes';
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.prevent_preferred_quote_deletion()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if old.preferido then
    raise exception 'Elegí otro proveedor principal antes de quitar esta cotización';
  end if;
  return old;
end;
$function$;

CREATE OR REPLACE FUNCTION private.prevent_stock_unit_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.unidad_id is distinct from old.unidad_id and exists (
    select 1 from public.stock_movimientos m
    where m.empresa_id = old.empresa_id and m.item_id = old.id
  ) then
    raise exception 'La unidad no puede cambiarse si el ítem tiene movimientos';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.prevent_supplier_price_unit_mismatch()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if (new.unidad_id is distinct from old.unidad_id
      or new.tipo_item is distinct from old.tipo_item)
    and exists (
      select 1 from public.compras_proveedores_items si
      where si.empresa_id = old.empresa_id and si.item_id = old.id
    ) then
    raise exception 'Quitá los precios de proveedores antes de cambiar la unidad o el tipo';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.price_compute(p_method text, p_value numeric, p_cost numeric, p_step numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v numeric;
begin
  if p_value is null or p_value < 0 then raise exception 'Indicá un valor válido'; end if;
  if p_method = 'fijo' then
    v := p_value;
  elsif p_method = 'margen' then
    if p_cost is null then raise exception 'El producto no tiene costo para calcular el precio'; end if;
    if p_value >= 100 then raise exception 'El margen debe ser menor a 100 %%'; end if;
    v := p_cost / (1 - p_value / 100);
  elsif p_method = 'recargo' then
    if p_cost is null then raise exception 'El producto no tiene costo para calcular el precio'; end if;
    if p_value > 10000 then raise exception 'El recargo es demasiado alto'; end if;
    v := p_cost * (1 + p_value / 100);
  else
    raise exception 'Método de precio inválido';
  end if;
  if v >= 10000000000000000 then raise exception 'Precio fuera de rango'; end if;
  return private.price_round(v, p_step);
end;
$function$;

CREATE OR REPLACE FUNCTION private.price_costs(p_company uuid, p_items uuid[])
 RETURNS TABLE(item_id uuid, cost numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v numeric;
begin
  if p_items is null then return; end if;
  for r in
    select i.id, i.costo_unitario_referencia, f.producto_id as has_formula
    from public.stock_items i
    left join public.produccion_formulas f on f.empresa_id = i.empresa_id and f.producto_id = i.id
    where i.empresa_id = p_company and i.id = any (p_items)
  loop
    v := null;
    if r.has_formula is not null then
      begin
        v := private.production_unit_cost(p_company, r.id);
      exception when raise_exception then v := null;
      end;
    else
      v := r.costo_unitario_referencia;
    end if;
    item_id := r.id; cost := v;
    return next;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION private.price_effective(p_company uuid, p_list uuid, p_term text)
 RETURNS TABLE(item_id uuid, code text, name text, unit_symbol text, net_price numeric, source text, method text, method_value numeric, cost_snapshot numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare v_list public.ventas_listas_precios%rowtype;
begin
  select * into v_list from public.ventas_listas_precios where empresa_id = p_company and id = p_list;
  if not found then raise exception 'Lista inexistente'; end if;
  return query
  select i.id, i.codigo, i.nombre, u.simbolo,
    coalesce(own.precio_neto, private.price_round(b.precio_neto * (1 - v_list.descuento_base_porcentaje / 100), v_list.redondeo)),
    case when own.precio_neto is not null then 'own' when b.precio_neto is not null then 'derived' else 'none' end,
    pp.metodo, pp.metodo_valor, pp.costo_copia
  from public.stock_items i
  join public.stock_unidades u on u.empresa_id = i.empresa_id and u.id = i.unidad_id
  left join public.ventas_listas_items own
    on own.empresa_id = i.empresa_id and own.lista_precio_id = p_list and own.item_id = i.id
  left join public.ventas_listas_items_metodo pp
    on pp.empresa_id = i.empresa_id and pp.lista_precio_id = p_list and pp.item_id = i.id
  left join public.ventas_listas_items b
    on b.empresa_id = i.empresa_id and b.lista_precio_id = v_list.lista_base_id and b.item_id = i.id
  where i.empresa_id = p_company and i.tipo_item = 'producto_terminado' and i.activo
    and (coalesce(p_term, '') = '' or position(p_term in lower(i.nombre)) > 0 or position(p_term in lower(i.codigo)) > 0);
end;
$function$;

CREATE OR REPLACE FUNCTION private.price_history_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  raise exception 'El historial de precios no se modifica ni se borra';
end;
$function$;

CREATE OR REPLACE FUNCTION private.price_item_cost(p_company uuid, p_item uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select c.cost from private.price_costs(p_company, array[p_item]) c limit 1;
$function$;

CREATE OR REPLACE FUNCTION private.price_lists_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_base public.ventas_listas_precios%rowtype;
begin
  if new.lista_base_id is not null then
    select * into v_base from public.ventas_listas_precios
    where empresa_id = new.empresa_id and id = new.lista_base_id;
    if v_base.lista_base_id is not null then
      raise exception 'La lista base no puede ser a su vez una lista derivada';
    end if;
    if v_base.moneda <> new.moneda then
      raise exception 'La lista derivada debe tener la misma moneda que su lista base';
    end if;
    if tg_op = 'UPDATE' and exists (
      select 1 from public.ventas_listas_precios d where d.empresa_id = new.empresa_id and d.lista_base_id = new.id) then
      raise exception 'Esta lista es base de otras listas y no puede volverse derivada';
    end if;
  end if;
  if tg_op = 'UPDATE' and new.moneda <> old.moneda and (
    exists (select 1 from public.ventas_listas_items i where i.empresa_id = new.empresa_id and i.lista_precio_id = new.id)
    or exists (select 1 from public.ventas_listas_precios d where d.empresa_id = new.empresa_id and d.lista_base_id = new.id)) then
    raise exception 'No se puede cambiar la moneda de una lista con precios o con listas derivadas';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.price_require_admin(p_company uuid, p_cost boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'administrador'
     or not private.has_permission(p_company, 'ventas', 'editar')
     or (p_cost and not private.has_permission(p_company, 'finanzas', 'ver')) then
    raise exception 'Solo un administrador con permiso puede gestionar listas de precios' using errcode = '42501';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION private.price_require_cost_view(p_company uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'administrador'
     or not private.has_permission(p_company, 'finanzas', 'ver')
     or not private.has_permission(p_company, 'items', 'ver')
     or not private.has_permission(p_company, 'ventas', 'ver') then
    raise exception 'Solo un administrador puede consultar costos y márgenes' using errcode = '42501';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION private.price_round(p numeric, p_step numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case when p is null then null
    when coalesce(p_step, 0) > 0 then round(round(p / p_step) * p_step, 2)
    else round(p, 2) end;
$function$;

CREATE OR REPLACE FUNCTION private.price_write(p_company uuid, p_list uuid, p_item uuid, p_new numeric, p_method text, p_value numeric, p_cost numeric, p_keep_cost boolean, p_source text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old numeric; v_old_cost numeric;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_list::text || p_item::text, 0));
  select precio_neto into v_old from public.ventas_listas_items
  where empresa_id = p_company and lista_precio_id = p_list and item_id = p_item for update;
  select costo_copia into v_old_cost from public.ventas_listas_items_metodo
  where empresa_id = p_company and lista_precio_id = p_list and item_id = p_item;
  insert into public.ventas_listas_items(empresa_id, lista_precio_id, item_id, precio_neto, actualizado_por)
  values (p_company, p_list, p_item, p_new, auth.uid())
  on conflict (empresa_id, lista_precio_id, item_id) do update
    set precio_neto = excluded.precio_neto, actualizado_en = clock_timestamp(), actualizado_por = auth.uid();
  insert into public.ventas_listas_items_metodo(empresa_id, lista_precio_id, item_id, metodo, metodo_valor, costo_copia)
  values (p_company, p_list, p_item, p_method, p_value, case when p_keep_cost then v_old_cost else p_cost end)
  on conflict (empresa_id, lista_precio_id, item_id) do update
    set metodo = excluded.metodo, metodo_valor = excluded.metodo_valor,
        costo_copia = case when p_keep_cost then public.ventas_listas_items_metodo.costo_copia else excluded.costo_copia end,
        actualizado_en = clock_timestamp();
  insert into public.ventas_listas_items_historial(empresa_id, lista_precio_id, item_id, precio_neto_anterior, precio_neto_nuevo,
    metodo, metodo_valor, costo_copia, origen, motivo, cambiado_por)
  values (p_company, p_list, p_item, v_old, p_new, p_method, p_value,
    case when p_keep_cost then v_old_cost else p_cost end, p_source, left(coalesce(p_reason, ''), 200), auth.uid());
end;
$function$;

CREATE OR REPLACE FUNCTION private.production_unit_cost(p_company uuid, p_item uuid, p_path uuid[] DEFAULT '{}'::uuid[])
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cost numeric;
  v_batch numeric;
  v_line record;
  v_total numeric := 0;
begin
  if p_item = any(p_path) or array_length(p_path,1) >= 15 then
    raise exception 'Se detectó un ciclo o demasiados niveles en la fórmula';
  end if;
  select f.cantidad_base * case when i.usa_rendimiento then i.factor_rendimiento else 1 end into v_batch
  from public.produccion_formulas f join public.stock_items i on i.empresa_id=f.empresa_id and i.id=f.producto_id
  where f.empresa_id=p_company and f.producto_id=p_item;
  if v_batch is null then
    select i.costo_unitario_referencia into v_cost from public.stock_items i
    where i.empresa_id=p_company and i.id=p_item;
    if v_cost is null then raise exception 'Falta el costo de referencia de un componente sin fórmula'; end if;
    return v_cost;
  end if;
  for v_line in select componente_id,cantidad from public.produccion_formulas_lineas
    where empresa_id=p_company and producto_id=p_item loop
    v_total := v_total + v_line.cantidad * private.production_unit_cost(
      p_company,v_line.componente_id,array_append(p_path,p_item));
  end loop;
  return round(v_total/v_batch,2);
end;
$function$;

CREATE OR REPLACE FUNCTION private.protect_archived_activity()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$ begin
  if new.archivado and new.activo then raise exception 'Recuperá el registro desde Archivados antes de activarlo'; end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION private.protect_preferred_material_cost()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if current_user='authenticated' and
    new.costo_unitario_referencia is distinct from old.costo_unitario_referencia and
    exists(select 1 from public.compras_proveedores_items si where si.empresa_id=old.empresa_id
      and si.item_id=old.id and si.preferido) then
    raise exception 'El costo se actualiza desde el proveedor principal. Modificá su cotización en Compras';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.purchase_request_lines_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  raise exception 'Las líneas de un pedido de compra no se modifican ni se borran';
end;
$function$;

CREATE OR REPLACE FUNCTION private.purchase_requests_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'Los pedidos de compra no se borran: se cancelan o se rechazan';
  end if;
  if old.estado <> 'pendiente' then
    raise exception 'El pedido ya fue resuelto y no admite cambios';
  end if;
  if new.empresa_id <> old.empresa_id or new.numero <> old.numero
     or new.solicitado_por <> old.solicitado_por or new.creado_en <> old.creado_en
     or new.solicitante_nombre <> old.solicitante_nombre or new.prioridad <> old.prioridad
     or new.fecha_necesaria is distinct from old.fecha_necesaria or new.nota <> old.nota then
    raise exception 'Solo se puede cambiar el estado de un pedido';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.quote_lines_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  raise exception 'Las líneas de un presupuesto no se modifican ni se borran';
end;
$function$;

CREATE OR REPLACE FUNCTION private.quotes_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'Un presupuesto no se borra: cancelalo';
  end if;
  if (to_jsonb(new) - 'estado' - 'estado_cambiado_en' - 'estado_cambiado_por')
     is distinct from (to_jsonb(old) - 'estado' - 'estado_cambiado_en' - 'estado_cambiado_por') then
    raise exception 'Un presupuesto no se edita: creá uno nuevo';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.rebalance_production_on_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.rebalance_production_reservations(new.empresa_id);
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.rebalance_production_reservations(p_company uuid)
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
  delete from public.produccion_reservas_ubicaciones where empresa_id=p_company;
  for v_row in
    select r.empresa_id,r.orden_id,r.componente_id,r.cantidad_requerida,j.estado
    from public.produccion_ordenes_reservas r
    join public.produccion_ordenes j on j.empresa_id=r.empresa_id and j.id=r.orden_id
    where r.empresa_id=p_company
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

CREATE OR REPLACE FUNCTION private.refresh_fx_costs()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_item record;
begin
  for v_item in select si.item_id from public.compras_proveedores_items si
    where si.empresa_id=new.empresa_id and si.tipo_cambio_id=new.tipo_cambio_id and si.preferido loop
    perform private.sync_preferred_material_cost(new.empresa_id,v_item.item_id);
  end loop;
  update public.stock_items i
    set costo_unitario_referencia=round(i.costo_referencia_usd*private.current_fx_rate(i.empresa_id,new.tipo_cambio_id),2)
    where i.empresa_id=new.empresa_id and i.tipo_cambio_referencia_id=new.tipo_cambio_id
      and i.costo_referencia_usd is not null and not exists(select 1 from public.compras_proveedores_items q
        where q.empresa_id=i.empresa_id and q.item_id=i.id and q.preferido);
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION private.refresh_quote_cost()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op='DELETE' then
    perform private.sync_preferred_material_cost(old.empresa_id,old.item_id);
    return old;
  end if;
  perform private.sync_preferred_material_cost(new.empresa_id,new.item_id);
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.reject_stock_history_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  raise exception 'El historial de stock es inmutable; registrá una operación compensatoria';
end;
$function$;

CREATE OR REPLACE FUNCTION private.reject_stock_operation_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'UPDATE'
     and old.lote_id is null and new.lote_id is not null
     and (to_jsonb(new) - 'lote_id') = (to_jsonb(old) - 'lote_id') then
    return new;
  end if;
  raise exception 'El historial de stock es inmutable; registrá una operación compensatoria';
end;
$function$;

CREATE OR REPLACE FUNCTION private.release_closed_production_job()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.estado in ('terminada','cancelada') and old.estado <> new.estado then
    perform private.rebalance_production_reservations(new.empresa_id);
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.reserve_new_production_job()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into public.produccion_ordenes_reservas
    (empresa_id,orden_id,componente_id,cantidad_requerida)
  select new.empresa_id,new.id,(x->>'component_id')::uuid,
    sum((x->>'quantity')::numeric)
  from jsonb_array_elements(new.formula_copia) x
  group by (x->>'component_id')::uuid;
  perform private.rebalance_production_reservations(new.empresa_id);
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.row_has_cost(p_row jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select exists(select 1 from (values ('costo_referencia_ars'),('costo_usd'),('tipo_dolar'),
      ('proveedor'),('supplier_id'),('exchange_type_id')) k(key)
    where nullif(btrim(coalesce(p_row->>k.key,'')),'') is not null);
$function$;

CREATE OR REPLACE FUNCTION private.sale_resolve_price(p_company uuid, p_customer uuid, p_item uuid)
 RETURNS TABLE(price numeric, list_id uuid, tax_percent numeric, source text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_tax numeric; v_price numeric; v_list public.ventas_listas_precios%rowtype; r record;
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  select coalesce(s.impuesto_porcentaje, (select ps.impuesto_porcentaje_predeterminado from public.ventas_precios_config ps
    where ps.empresa_id = p_company), 21)
    into v_tax from (select 1) x
    left join public.ventas_items_config s on s.empresa_id = p_company and s.item_id = p_item;
  for r in
    select l.lista_precio_id as id, 1 as ord from public.ventas_clientes l
      where l.empresa_id = p_company and l.id = p_customer and l.lista_precio_id is not null
    union all
    select d.id, 2 from public.ventas_listas_precios d where d.empresa_id = p_company and d.es_predeterminada
    order by 2
  loop
    select * into v_list from public.ventas_listas_precios pl
    where pl.empresa_id = p_company and pl.id = r.id and not pl.archivado and pl.moneda = 'ARS'
      and (pl.vigente_desde is null or pl.vigente_desde <= v_today) and (pl.vigente_hasta is null or pl.vigente_hasta >= v_today);
    if not found then continue; end if;
    select coalesce(own.precio_neto,
        private.price_round(b.precio_neto * (1 - v_list.descuento_base_porcentaje / 100), v_list.redondeo))
      into v_price
    from (select 1) x
    left join public.ventas_listas_items own
      on own.empresa_id = p_company and own.lista_precio_id = v_list.id and own.item_id = p_item
    left join public.ventas_listas_items b
      on b.empresa_id = p_company and b.lista_precio_id = v_list.lista_base_id and b.item_id = p_item;
    if v_price is not null then
      price := v_price; list_id := v_list.id; tax_percent := v_tax;
      source := case when r.ord = 1 then 'customer' else 'default' end;
      return next; return;
    end if;
  end loop;
  select i.precio_venta_unitario into v_price from public.stock_items i where i.empresa_id = p_company and i.id = p_item;
  price := v_price; list_id := null; tax_percent := v_tax; source := 'item';
  return next;
end;
$function$;

CREATE OR REPLACE FUNCTION private.save_item_with_cost(p_company uuid, p_item uuid, p_row jsonb, p_expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_preserve_cost boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old public.stock_items%rowtype; v_row jsonb; v_supplier uuid; v_fx uuid; v_usd numeric;
  v_primary boolean; v_id uuid; v_unit_code text; v_category_code text;
begin
  if auth.uid() is null or not private.has_permission(p_company,'items',
    case when p_item is null then 'crear' else 'editar' end) then
    raise exception 'Sin permiso para guardar el ítem' using errcode='42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('import-items:'||p_company::text,0));
  if p_item is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('preferred:'||p_company::text||':'||p_item::text,0));
    select * into v_old from public.stock_items where empresa_id=p_company and id=p_item for update;
    if not found then raise exception 'El ítem no existe en esta empresa'; end if;
    if p_expected_updated_at is null or v_old.actualizado_en<>p_expected_updated_at then
      raise exception 'La ficha cambió mientras la editabas. Recargá antes de guardar'; end if;
  end if;
  -- El formulario selecciona IDs; Excel usa códigos/nombres. Resolverlos siempre en la empresa.
  select u.codigo into v_unit_code from public.stock_unidades u
    where u.empresa_id=p_company and u.id=nullif(p_row->>'unit_id','')::uuid;
  select c.codigo into v_category_code from public.stock_categorias c
    where c.empresa_id=p_company and c.id=nullif(p_row->>'category_id','')::uuid;
  if nullif(p_row->>'category_id','') is not null and v_category_code is null then
    raise exception 'La categoría no pertenece a esta empresa'; end if;
  v_row:=p_row || jsonb_build_object('unidad_codigo',v_unit_code,'categoria_codigo',coalesce(v_category_code,''));
  if nullif(p_row->>'supplier_id','') is not null then
    select s.nombre into v_unit_code from public.compras_proveedores s where s.empresa_id=p_company
      and s.id=(p_row->>'supplier_id')::uuid and s.activo;
    if not found then raise exception 'Elegí un proveedor activo de esta empresa'; end if;
    v_row:=v_row || jsonb_build_object('proveedor',v_unit_code);
  end if;
  if nullif(p_row->>'exchange_type_id','') is not null then
    select t.nombre into v_unit_code from public.finanzas_tipos_cambio t where t.empresa_id=p_company
      and t.id=(p_row->>'exchange_type_id')::uuid and t.activo;
    if not found then raise exception 'Elegí un tipo de dólar activo de esta empresa'; end if;
    v_row:=v_row || jsonb_build_object('tipo_dolar',v_unit_code);
  end if;
  select exists(select 1 from public.compras_proveedores_items q where q.empresa_id=p_company
    and q.item_id=p_item and q.preferido) into v_primary;
  if p_item is not null and (p_preserve_cost or v_primary) and nullif(p_row->>'supplier_id','') is null then
    v_row:=v_row || jsonb_build_object('costo_referencia_ars',v_old.costo_unitario_referencia,
      'costo_usd','','tipo_dolar','');
  end if;
  v_row:=private.prepare_item_import(p_company,jsonb_build_array(v_row),p_item)->0;
  v_supplier:=nullif(v_row->>'supplier_id','')::uuid;
  v_fx:=nullif(v_row->>'exchange_type_id','')::uuid;
  v_usd:=nullif(v_row->>'cost_usd','')::numeric;
  if p_item is null then
    -- Importación de una fila reutiliza las mismas reglas y triggers.
    perform public.import_items(p_company,jsonb_build_array(v_row));
    select id into v_id from public.stock_items where empresa_id=p_company and codigo=btrim(v_row->>'codigo');
    return v_id;
  end if;
  update public.stock_items set codigo=btrim(v_row->>'codigo'),nombre=btrim(v_row->>'nombre'),
    tipo_item=v_row->>'tipo',categoria_id=nullif(v_row->>'category_id','')::uuid,
    unidad_id=(v_row->>'unit_id')::uuid,codigo_barras=nullif(btrim(v_row->>'codigo_barras'),''),
    descripcion=btrim(v_row->>'descripcion'),stock_minimo=(v_row->>'stock_minimo')::numeric,
    usa_lotes=(v_row->>'seguir_lotes')::boolean,stock_infinito=(v_row->>'stock_infinito')::boolean,
    costo_unitario_referencia=case when v_primary or p_preserve_cost then v_old.costo_unitario_referencia else nullif(v_row->>'cost_ars','')::numeric end,
    costo_referencia_usd=case when v_primary or p_preserve_cost then v_old.costo_referencia_usd
      when v_supplier is null then v_usd end,
    tipo_cambio_referencia_id=case when v_primary or p_preserve_cost then v_old.tipo_cambio_referencia_id
      when v_supplier is null then v_fx end
    where empresa_id=p_company and id=p_item;
  if v_supplier is not null then
    perform public.save_supplier_quote(p_company,v_supplier,p_item,
      coalesce(v_usd,(v_row->>'cost_ars')::numeric),'',
      case when v_usd is null then 'ARS' else 'USD' end,v_fx,0,null,true);
    if not v_primary then perform public.set_preferred_supplier(p_company,p_item,v_supplier); end if;
  end if;
  return p_item;
end; $function$;

CREATE OR REPLACE FUNCTION private.save_role_permissions(p_company uuid, p_role uuid, p_permissions jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_total integer;
  v_distinct integer;
  v_valid integer;
begin
  if not exists (select 1 from public.ajustes_roles where id = p_role and empresa_id = p_company) then
    raise exception 'Rol inexistente en esta empresa';
  end if;
  if jsonb_typeof(p_permissions) is distinct from 'array' then
    raise exception 'Lista de permisos inválida';
  end if;
  if jsonb_array_length(p_permissions) > 300 then
    raise exception 'Lista de permisos inválida';
  end if;
  if exists (select 1 from jsonb_array_elements(p_permissions) e
    where jsonb_typeof(e) <> 'object' or jsonb_typeof(e->'resource') is distinct from 'string'
      or jsonb_typeof(e->'action') is distinct from 'string') then
    raise exception 'Lista de permisos inválida';
  end if;
  select count(*), count(distinct (e->>'resource', e->>'action')) into v_total, v_distinct
    from jsonb_array_elements(p_permissions) e;
  if v_total <> v_distinct then raise exception 'Permisos repetidos'; end if;
  select count(*) into v_valid
    from (select distinct e->>'resource' as r, e->>'action' as a from jsonb_array_elements(p_permissions) e) x
    join public.ajustes_permisos_catalogo c on c.recurso = x.r and x.a = any (c.acciones) and not c.solo_admin;
  if v_valid <> v_distinct then
    raise exception 'Permisos desconocidos o reservados al administrador';
  end if;

  insert into public.ajustes_roles_permisos (empresa_id, rol_id, recurso, accion)
  select p_company, p_role, e->>'resource', e->>'action' from jsonb_array_elements(p_permissions) e
  on conflict do nothing;

  -- "Módulo completo" en el pedido = todas sus pantallas.
  insert into public.ajustes_roles_permisos (empresa_id, rol_id, recurso, accion)
  select p_company, p_role, c.recurso, rp.accion
  from public.ajustes_roles_permisos rp
  join public.ajustes_permisos_catalogo c on c.padre = rp.recurso
  where rp.rol_id = p_role and rp.accion = any (c.acciones)
  on conflict do nothing;

  -- El permiso del módulo existe solo si el rol tiene TODAS sus pantallas con esa acción.
  insert into public.ajustes_roles_permisos (empresa_id, rol_id, recurso, accion)
  select p_company, p_role, g.recurso, a.action
  from public.ajustes_permisos_catalogo g cross join lateral unnest(g.acciones) as a(action)
  where g.es_grupo
    and exists (select 1 from public.ajustes_permisos_catalogo ch where ch.padre = g.recurso)
    and not exists (
      select 1 from public.ajustes_permisos_catalogo ch
      where ch.padre = g.recurso and a.action = any (ch.acciones)
        and not exists (select 1 from public.ajustes_roles_permisos rp
          where rp.rol_id = p_role and rp.recurso = ch.recurso and rp.accion = a.action))
  on conflict do nothing;
end;
$function$;

CREATE OR REPLACE FUNCTION private.snapshot_purchase_item_name()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_name text;
begin
  select i.nombre into v_name from public.stock_items i
  where i.empresa_id = new.empresa_id and i.id = new.item_id;
  if v_name is null then raise exception 'Ítem inexistente'; end if;
  new.item_nombre := v_name;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.snapshot_work_options(p_company uuid, p_options jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    select t.*,u.simbolo into v_type from public.produccion_tipos_envase t
      join public.stock_unidades u on u.empresa_id=t.empresa_id and u.id=t.unidad_id
      where t.empresa_id=p_company and t.id=(v_pack->>'id')::uuid and t.activo;
    if not found then raise exception 'Elegí un envasado activo de esta empresa'; end if;
    if exists(select 1 from jsonb_array_elements(v_result) x where x->>'id'=v_type.id::text) then
      raise exception 'No repitas el tipo de envasado'; end if;
    v_result:=v_result||jsonb_build_array(jsonb_build_object('id',v_type.id,'name',v_type.nombre,
      'capacity',v_type.capacidad,'unit',v_type.simbolo,'count',v_count));
  end loop;
  v_obs:=coalesce(p_options->'observations','{}');
  select observaciones_etiquetas into v_labels from public.produccion_documentos_config where empresa_id=p_company;
  if exists(select 1 from jsonb_each(v_obs) e where jsonb_typeof(e.value)<>'string'
    or length(e.value#>>'{}')>500 or not (coalesce(v_labels,'[]') ? e.key)) then
    raise exception 'Las observaciones deben corresponder a los campos configurados'; end if;
  return jsonb_build_object('packaging',v_result,'observations',v_obs);
end; $function$;

CREATE OR REPLACE FUNCTION private.strip_snapshot_cost(p_snapshot jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_agg(x.value-'unit_cost' order by x.ord),'[]'::jsonb)
  from jsonb_array_elements(case when jsonb_typeof(p_snapshot)='array' then p_snapshot else '[]'::jsonb end)
    with ordinality as x(value,ord);
$function$;

CREATE OR REPLACE FUNCTION private.support_session_active(p_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from private.soporte_sesiones ss
    join private.soporte_operadores so on so.usuario_id=ss.usuario_id and so.activo
    join public.empresas c on c.id=ss.empresa_id and c.activo
    where ss.usuario_id=(select auth.uid()) and ss.empresa_id=p_company
      and ss.vence_en>now()
  );
$function$;

CREATE OR REPLACE FUNCTION private.sync_preferred_material_cost(p_company uuid, p_item uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_quote public.compras_proveedores_items%rowtype; v_rate numeric; v_cost numeric;
begin
  select * into v_quote from public.compras_proveedores_items
    where empresa_id=p_company and item_id=p_item and preferido;
  if not found then return; end if;
  if v_quote.moneda='USD' then
    v_rate:=private.current_fx_rate(p_company,v_quote.tipo_cambio_id);
    if v_rate is null then raise exception 'Cargá una cotización vigente para el tipo de dólar seleccionado'; end if;
  else v_rate:=1; end if;
  v_cost:=round(v_quote.precio_unitario*v_rate*(1+v_quote.ajuste_porcentaje/100),2);
  -- El proveedor principal pasa a ser la única fuente de costo.
  update public.stock_items set costo_unitario_referencia=v_cost,costo_referencia_usd=null,
    tipo_cambio_referencia_id=null
    where empresa_id=p_company and id=p_item and
      (costo_unitario_referencia is distinct from v_cost or costo_referencia_usd is not null);
end; $function$;

CREATE OR REPLACE FUNCTION private.touch_item_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.actualizado_en := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.access_audit_events_list(p_company uuid, p_page integer DEFAULT 0)
 RETURNS TABLE(created_at timestamp with time zone, action text, actor_email text, target_email text, target_role_name text, detail jsonb, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'administrador' then
    raise exception 'Solo el administrador puede ver el historial de accesos' using errcode = '42501';
  end if;
  if p_page is null or p_page < 0 or p_page > 100000 then
    raise exception 'Página inválida';
  end if;
  return query
    select e.creado_en, e.accion, a.email::text, t.email::text, r.nombre, e.detalle, count(*) over ()
    from public.ajustes_auditoria_accesos e
    left join auth.users a on a.id = e.autor_id
    left join auth.users t on t.id = e.usuario_destino_id
    left join public.ajustes_roles r on r.id = e.rol_destino_id and r.empresa_id = e.empresa_id
    where e.empresa_id = p_company
    order by e.creado_en desc, e.id desc
    limit 25 offset p_page * 25;
end;
$function$;

CREATE OR REPLACE FUNCTION public.activate_item_lots(p_company uuid, p_item uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_item public.stock_items%rowtype;
  v_balance record;
  v_lot_id uuid;
begin
  if v_actor is null
     or not private.has_permission(p_company, 'items', 'editar')
     or not private.has_permission(p_company, 'stock', 'crear') then
    raise exception 'Sin permiso para activar lotes' using errcode = '42501';
  end if;

  perform 1 from public.empresas c
  where c.id = p_company and c.activo for share;
  if not found then
    raise exception 'La empresa no está activa' using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_company::text || ':' || p_item::text, 0)
  );

  select * into v_item from public.stock_items i
  where i.empresa_id = p_company and i.id = p_item and i.activo for update;
  if not found then raise exception 'Ítem inexistente o inactivo'; end if;
  if v_item.usa_lotes then return; end if;

  if exists (
    select 1 from public.stock_lotes l
    where l.empresa_id = p_company and l.item_id = p_item
  ) then
    raise exception 'El ítem ya tiene lotes registrados';
  end if;

  for v_balance in
    select b.deposito_id, b.cantidad, w.codigo as warehouse_code
    from public.stock_saldos b
    join public.stock_depositos w
      on w.empresa_id = b.empresa_id and w.id = b.deposito_id
    where b.empresa_id = p_company and b.item_id = p_item
      and b.cantidad > 0
    order by b.deposito_id
  loop
    insert into public.stock_lotes(empresa_id, item_id, codigo)
    values (
      p_company, p_item,
      'Inicial ' || left(v_balance.warehouse_code, 24)
        || ' ' || v_balance.deposito_id::text
    ) returning id into v_lot_id;

    insert into public.stock_lotes_saldos(
      empresa_id, item_id, deposito_id, lote_id, cantidad
    ) values (p_company, p_item, v_balance.deposito_id, v_lot_id,
      v_balance.cantidad);

    insert into public.stock_lotes_aperturas(
      empresa_id, item_id, deposito_id, lote_id, cantidad, autor_id
    ) values (p_company, p_item, v_balance.deposito_id, v_lot_id,
      v_balance.cantidad, v_actor);
  end loop;

  update public.stock_items i set usa_lotes = true
  where i.empresa_id = p_company and i.id = p_item;
end;
$function$;

CREATE OR REPLACE FUNCTION public.add_exchange_rate(p_company uuid, p_type uuid, p_rate numeric, p_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid; v_latest public.finanzas_cotizaciones%rowtype;
begin
  if auth.uid() is null or not private.has_permission(p_company,'compras_proveedores','editar') then
    raise exception 'Sin permiso para actualizar el tipo de cambio' using errcode='42501';
  end if;
  if p_rate is null or p_rate<=0 or p_rate>=1000000000000
    or p_rate<>round(p_rate,6) or p_date is null
    or p_date>(now() at time zone 'America/Argentina/Buenos_Aires')::date then
    raise exception 'Indicá una cotización válida y una fecha no futura';
  end if;
  perform 1 from public.empresas c where c.id=p_company and c.activo for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('exchange-rate:'||p_company::text||':'||p_type::text,0));
  perform 1 from public.finanzas_tipos_cambio t where t.empresa_id=p_company
    and t.id=p_type and t.activo for share;
  if not found then raise exception 'Elegí un tipo de dólar activo'; end if;
  select * into v_latest from public.finanzas_cotizaciones r
    where r.empresa_id=p_company and r.tipo_cambio_id=p_type and r.vigente_desde=p_date
    order by r.creado_en desc,r.id desc limit 1;
  if found and v_latest.ars_por_usd=p_rate then return v_latest.id; end if;
  insert into public.finanzas_cotizaciones(empresa_id,tipo_cambio_id,ars_por_usd,vigente_desde,autor_id)
    values(p_company,p_type,p_rate,p_date,auth.uid()) returning id into v_id;
  return v_id;
end; $function$;

CREATE OR REPLACE FUNCTION public.add_exchange_rate_type(p_company uuid, p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'compras_proveedores','editar') then
    raise exception 'Sin permiso para configurar tipos de cambio' using errcode='42501';
  end if;
  if p_name is null or length(btrim(p_name)) not between 2 and 60 then
    raise exception 'Indicá un nombre de 2 a 60 caracteres'; end if;
  insert into public.finanzas_tipos_cambio(empresa_id,nombre) values(p_company,btrim(p_name))
  returning id into v_id;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.adjust_sale(p_company uuid, p_sale uuid, p_kind text, p_reason text, p_lines jsonb, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_existing public.ventas_ajustes%rowtype; v_sale public.ventas%rowtype;
  v_row public.ventas_lineas%rowtype; v_entry jsonb; v_adjustment uuid;
  v_quantity numeric; v_remaining numeric; v_credit numeric:=0;
  v_line_credit numeric; v_restock boolean; v_operation uuid; v_expiry date;
  v_expected integer; v_count integer:=0;
begin
  if auth.uid() is null or not private.has_permission(p_company,'ventas','editar')
    or not private.has_permission(p_company,'stock','crear') then
    raise exception 'Necesitás permisos para modificar ventas y registrar stock' using errcode='42501'; end if;
  if p_kind not in ('anulacion','devolucion') or p_kind is null or p_sale is null
    or p_request_id is null or length(btrim(coalesce(p_reason,''))) not between 5 and 300
    or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) not between 1 and 40 then
    raise exception 'Indicá el motivo y los productos a devolver'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('receivable:'||p_company::text||':'||p_sale::text,0));
  select * into v_existing from public.ventas_ajustes
    where empresa_id=p_company and solicitud_id=p_request_id;
  if found then
    if v_existing.autor_id<>auth.uid() or v_existing.venta_id<>p_sale
      or v_existing.tipo<>p_kind or v_existing.motivo<>btrim(p_reason)
      or (select jsonb_agg(jsonb_build_object('line_no',l.venta_linea,
        'quantity',l.cantidad,'restock',l.reingresado) order by l.venta_linea)
          from public.ventas_ajustes_lineas l
          where l.empresa_id=p_company and l.ajuste_id=v_existing.id)
        is distinct from (
          select jsonb_agg(jsonb_build_object('line_no',(x.value->>'line_no')::smallint,
            'quantity',(x.value->>'quantity')::numeric,
            'restock',(x.value->>'restock')::boolean) order by (x.value->>'line_no')::smallint)
          from jsonb_array_elements(p_lines) x(value)) then
      raise exception 'Esta solicitud ya se utilizó con otros datos'; end if;
    return v_existing.id;
  end if;
  select * into v_sale from public.ventas where empresa_id=p_company and id=p_sale;
  if not found then raise exception 'Venta inexistente'; end if;
  if exists(select 1 from public.ventas_ajustes
    where empresa_id=p_company and venta_id=p_sale and tipo='anulacion') then
    raise exception 'Esta venta ya está anulada'; end if;
  select count(*) into v_expected from public.ventas_lineas l
    where l.empresa_id=p_company and l.venta_id=p_sale
      and l.cantidad>coalesce((select sum(al.cantidad)
        from public.ventas_ajustes_lineas al
        where al.empresa_id=l.empresa_id and al.venta_id=l.venta_id
          and al.venta_linea=l.linea),0);
  if p_kind='anulacion' and jsonb_array_length(p_lines)<>v_expected then
    raise exception 'Para anular, devolvé todas las cantidades pendientes'; end if;
  insert into public.ventas_ajustes(empresa_id,venta_id,solicitud_id,tipo,motivo,
    credito_total,autor_id)
  values(p_company,p_sale,p_request_id,p_kind,btrim(p_reason),0,auth.uid())
  returning id into v_adjustment;
  for v_entry in select value from jsonb_array_elements(p_lines) x(value) loop
    if jsonb_typeof(v_entry)<>'object' or coalesce(v_entry->>'line_no','') !~ '^[0-9]{1,2}$'
      or coalesce(v_entry->>'quantity','') !~ '^[0-9]+(\.[0-9]{1,6})?$'
      or jsonb_typeof(v_entry->'restock')<>'boolean' then
      raise exception 'Revisá los productos y las cantidades devueltas'; end if;
    select * into v_row from public.ventas_lineas
      where empresa_id=p_company and venta_id=p_sale
        and linea=(v_entry->>'line_no')::smallint;
    if not found then raise exception 'Producto inexistente en la venta'; end if;
    v_quantity:=(v_entry->>'quantity')::numeric;
    v_restock:=(v_entry->>'restock')::boolean;
    select v_row.cantidad-coalesce(sum(al.cantidad),0) into v_remaining
      from public.ventas_ajustes_lineas al
      where al.empresa_id=p_company and al.venta_id=p_sale
        and al.venta_linea=v_row.linea;
    if v_quantity<=0 or v_quantity>v_remaining then
      raise exception 'La devolución supera la cantidad pendiente de %',v_row.item_nombre; end if;
    if p_kind='anulacion' and v_quantity<>v_remaining then
      raise exception 'La anulación debe incluir toda la cantidad pendiente'; end if;
    v_line_credit:=case when v_quantity=v_remaining then
      v_row.total_linea-coalesce((select sum(al.credito_importe)
        from public.ventas_ajustes_lineas al where al.empresa_id=p_company
          and al.venta_id=p_sale and al.venta_linea=v_row.linea),0)
      else round(v_quantity*v_row.precio_unitario,2) end;
    v_operation:=null;
    if v_restock then
      if v_row.lote_codigo is not null then
        select vencimiento into v_expiry from public.stock_lotes
        where empresa_id=p_company and item_id=v_row.item_id
          and lower(codigo)=lower(v_row.lote_codigo);
      else v_expiry:=null; end if;
      v_operation:=public.post_stock_operation(p_company,v_row.item_id,
        v_row.deposito_id,null,'ingreso',v_quantity,
        'Devolución venta '||v_sale.numero::text,gen_random_uuid(),v_row.lote_codigo,v_expiry);
    end if;
    insert into public.ventas_ajustes_lineas(empresa_id,ajuste_id,venta_id,
      venta_linea,cantidad,credito_importe,reingresado,operacion_stock_id)
    values(p_company,v_adjustment,p_sale,v_row.linea,v_quantity,v_line_credit,
      v_restock,v_operation);
    v_credit:=v_credit+v_line_credit;
    v_count:=v_count+1;
  end loop;
  if p_kind='anulacion' and v_count<>v_expected then
    raise exception 'Faltan productos por anular'; end if;
  update public.ventas_ajustes set credito_total=v_credit
    where empresa_id=p_company and id=v_adjustment;
  return v_adjustment;
end;
$function$;

CREATE OR REPLACE FUNCTION public.adjust_supplier_prices(p_company uuid, p_supplier uuid, p_item uuid, p_percent numeric, p_request_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_previous public.compras_proveedores_ajustes_precio%rowtype; v_count integer;
begin
  if auth.uid() is null or not private.has_permission(p_company,'compras_proveedores','editar') then
    raise exception 'Sin permiso para ajustar precios' using errcode='42501'; end if;
  if p_request_id is null or p_percent is null or p_percent not between -99.99 and 1000
    or p_percent<>round(p_percent,2) or p_percent=0 or (p_supplier is null and p_item is null) then
    raise exception 'Elegí proveedor o materia prima y un porcentaje distinto de cero'; end if;
  perform 1 from public.empresas c where c.id=p_company and c.activo for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('adjustment:'||p_company::text,0));
  select * into v_previous from public.compras_proveedores_ajustes_precio
    where empresa_id=p_company and solicitud_id=p_request_id;
  if found then
    if v_previous.autor_id<>auth.uid() or v_previous.proveedor_id is distinct from p_supplier
      or v_previous.item_id is distinct from p_item or v_previous.porcentaje<>p_percent then
      raise exception 'La solicitud ya se usó con otros datos'; end if;
    return v_previous.cantidad_cambiados;
  end if;
  update public.compras_proveedores_items si
    set precio_unitario=round(si.precio_unitario*(1+p_percent/100),2)
    where si.empresa_id=p_company
      and exists(select 1 from public.compras_proveedores s where s.empresa_id=si.empresa_id
        and s.id=si.proveedor_id and s.activo)
      and exists(select 1 from public.stock_items i where i.empresa_id=si.empresa_id
        and i.id=si.item_id and i.activo)
      and (p_supplier is null or si.proveedor_id=p_supplier)
      and (p_item is null or si.item_id=p_item);
  get diagnostics v_count = row_count;
  if v_count=0 then raise exception 'No hay cotizaciones para ese filtro'; end if;
  insert into public.compras_proveedores_ajustes_precio(empresa_id,solicitud_id,proveedor_id,
    item_id,porcentaje,cantidad_cambiados,autor_id)
  values(p_company,p_request_id,p_supplier,p_item,p_percent,v_count,auth.uid());
  return v_count;
end;
$function$;

create or replace function public.archived_records(p_company uuid, p_resource text, p_search text default ''::text, p_page integer default 0)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare v_target record; v_label text; v_date text; v_count bigint; v_rows jsonb; v_filter text;
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if auth.uid() is null or not private.has_permission(p_company,v_target.permission,'ver') then
    raise exception 'Sin acceso a este archivo' using errcode='42501'; end if;
  if p_page is null or p_page<0 or p_page>100000 or length(coalesce(p_search,''))>100 then raise exception 'Búsqueda o página inválida'; end if;
  v_label:=case p_resource
    when 'items' then 't.codigo||'' · ''||t.nombre'
    when 'tipos_cambio' then 't.nombre'
    when 'formulas' then '(select i.nombre from public.stock_items i where i.empresa_id=t.empresa_id and i.id=t.producto_id)'
    when 'ordenes' then '''OF ''||t.numero::text||'' · ''||(select i.nombre from public.stock_items i where i.empresa_id=t.empresa_id and i.id=t.producto_id)'
    when 'remitos' then '''Remito ''||t.numero::text||'' · ''||t.destinatario'
    else '(select i.nombre from public.stock_items i where i.empresa_id=t.empresa_id and i.id=t.producto_id)' end;
  v_date:=case when p_resource='formulas' then 't.actualizado_en'
    when p_resource='tipos_cambio' then '(select max(e.creado_en) from public.finanzas_cotizaciones e where e.empresa_id=t.empresa_id and e.tipo_cambio_id=t.id)'
    else 't.creado_en' end;
  v_filter:='t.empresa_id=$1 and t.archivado and ('||v_label||') ilike ''%''||$2||''%''';
  execute format('select count(*) from public.%I t where %s',v_target.table_name,v_filter) into v_count using p_company,coalesce(p_search,'');
  execute format('select coalesce(jsonb_agg(x),''[]''::jsonb) from (select t.%I id,%s label,%s created_at from public.%I t where %s order by %s desc,t.%I limit 25 offset $3) x',
    v_target.id_field,v_label,v_date,v_target.table_name,v_filter,v_date,v_target.id_field)
    into v_rows using p_company,coalesce(p_search,''),p_page*25;
  return jsonb_build_object('rows',v_rows,'count',v_count);
end
$function$;

CREATE OR REPLACE FUNCTION public.assign_customer_price_list(p_company uuid, p_customer uuid, p_list uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.price_require_admin(p_company);
  if not exists (select 1 from public.ventas_clientes where empresa_id = p_company and id = p_customer) then
    raise exception 'Cliente inexistente';
  end if;
  if p_list is null then
    update public.ventas_clientes set lista_precio_id = null where empresa_id = p_company and id = p_customer;
    return;
  end if;
  if not exists (select 1 from public.ventas_listas_precios where empresa_id = p_company and id = p_list and not archivado) then
    raise exception 'Lista inexistente o archivada';
  end if;
  update public.ventas_clientes set lista_precio_id = p_list where empresa_id = p_company and id = p_customer;
end;
$function$;

CREATE OR REPLACE FUNCTION public.assign_sale_payment_account(p_company uuid, p_payment uuid, p_account uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'finanzas','editar') then
    raise exception 'Sin permiso para asignar cobros' using errcode='42501'; end if;
  perform 1 from public.ventas_cobros where empresa_id=p_company and id=p_payment;
  if not found then raise exception 'Cobro inexistente'; end if;
  perform 1 from public.finanzas_cuentas where empresa_id=p_company and id=p_account and activo;
  if not found then raise exception 'Elegí una cuenta activa'; end if;
  insert into public.finanzas_cobros_cuentas(empresa_id,cobro_id,cuenta_id,autor_id)
  values(p_company,p_payment,p_account,auth.uid());
end;
$function$;

CREATE OR REPLACE FUNCTION public.begin_support_session(p_company uuid, p_reason text)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_expires timestamptz := now()+interval '30 minutes';
begin
  if auth.uid() is null or length(btrim(coalesce(p_reason,''))) not between 8 and 300
    or not exists (select 1 from private.soporte_operadores so
      where so.usuario_id=auth.uid() and so.activo)
    or not exists (select 1 from public.empresas c
      where c.id=p_company and c.activo) then
    raise exception 'Acceso de soporte no autorizado' using errcode='42501';
  end if;
  insert into private.soporte_sesiones(usuario_id,empresa_id,vence_en)
  values(auth.uid(),p_company,v_expires)
  on conflict(usuario_id) do update set empresa_id=excluded.empresa_id,
    vence_en=excluded.vence_en;
  insert into private.soporte_accesos(usuario_id,empresa_id,motivo,vence_en)
  values(auth.uid(),p_company,btrim(p_reason),v_expires);
  return v_expires;
end;
$function$;

CREATE OR REPLACE FUNCTION public.bulk_price_change(p_company uuid, p_list uuid, p_mode text, p_percent numeric, p_item_ids uuid[], p_apply boolean, p_reason text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_list public.ventas_listas_precios%rowtype; r record; v_new numeric;
  v_total int := 0; v_changed int := 0; v_skipped int := 0; v_sample jsonb := '[]'::jsonb;
  v_prev jsonb; v_result jsonb; v_method text; v_value numeric;
begin
  if p_mode not in ('porcentaje', 'recalculo') then raise exception 'Modo inválido'; end if;
  perform private.price_require_admin(p_company, p_mode = 'recalculo');
  if p_mode = 'porcentaje' and (p_percent is null or p_percent <= -100 or p_percent > 1000) then
    raise exception 'Indicá un porcentaje entre -99,99 y 1000';
  end if;
  if p_item_ids is not null and cardinality(p_item_ids) > 5000 then
    raise exception 'Seleccioná hasta 5000 productos por operación';
  end if;
  if p_apply then
    if p_request_id is null then raise exception 'Identificador de solicitud inválido'; end if;
    select * into v_list from public.ventas_listas_precios where empresa_id = p_company and id = p_list for update;
  else
    select * into v_list from public.ventas_listas_precios where empresa_id = p_company and id = p_list;
  end if;
  if not found or v_list.archivado then raise exception 'Lista inexistente o archivada'; end if;
  if p_apply then
    select resultado into v_prev from public.ventas_precios_antiduplicado
    where empresa_id = p_company and solicitud_id = p_request_id and lista_precio_id = p_list and tipo = p_mode;
    if v_prev is not null then return v_prev; end if;
    if exists (select 1 from public.ventas_precios_antiduplicado where empresa_id = p_company and solicitud_id = p_request_id) then
      raise exception 'Ese identificador ya se usó en otra operación';
    end if;
  end if;

  for r in
    with c as materialized (
      select cc.item_id, cc.cost from private.price_costs(p_company, (
        select array_agg(x.item_id) from public.ventas_listas_items x
        where x.empresa_id = p_company and x.lista_precio_id = p_list
          and (p_item_ids is null or x.item_id = any (p_item_ids)))) cc
      where p_mode = 'recalculo')
    select pi.item_id, pi.precio_neto, pp.metodo, pp.metodo_valor, i.codigo, i.nombre, c.cost
    from public.ventas_listas_items pi
    join public.stock_items i on i.empresa_id = pi.empresa_id and i.id = pi.item_id and i.activo
    left join public.ventas_listas_items_metodo pp
      on pp.empresa_id = pi.empresa_id and pp.lista_precio_id = pi.lista_precio_id and pp.item_id = pi.item_id
    left join c on c.item_id = pi.item_id
    where pi.empresa_id = p_company and pi.lista_precio_id = p_list
      and (p_item_ids is null or pi.item_id = any (p_item_ids))
    order by i.nombre, pi.item_id
    limit 5001
  loop
    v_total := v_total + 1;
    if v_total > 5000 then raise exception 'La lista supera 5000 filas: seleccioná un subconjunto'; end if;
    if p_mode = 'porcentaje' then
      v_new := private.price_round(r.precio_neto * (1 + p_percent / 100), v_list.redondeo);
      v_method := 'fijo'; v_value := v_new;
    else
      if coalesce(r.metodo, '') not in ('margen', 'recargo') or r.cost is null then v_skipped := v_skipped + 1; continue; end if;
      v_new := private.price_compute(r.metodo, r.metodo_valor, r.cost, v_list.redondeo);
      v_method := r.metodo; v_value := r.metodo_valor;
    end if;
    if v_new >= 10000000000000000 then raise exception 'El aumento deja un precio fuera de rango'; end if;
    if v_new = r.precio_neto then continue; end if;
    v_changed := v_changed + 1;
    if jsonb_array_length(v_sample) < 200 then
      v_sample := v_sample || jsonb_build_object('item_id', r.item_id, 'code', r.codigo, 'name', r.nombre,
        'old_price', r.precio_neto, 'new_price', v_new);
    end if;
    if p_apply then
      perform private.price_write(p_company, p_list, r.item_id, v_new, v_method, v_value, r.cost,
        p_mode = 'porcentaje', case p_mode when 'porcentaje' then 'masivo' else 'recalculo' end, p_reason);
    end if;
  end loop;

  v_result := jsonb_build_object('mode', p_mode, 'applied', p_apply, 'total', v_total,
    'changed', v_changed, 'skipped', v_skipped, 'sample', v_sample);
  if p_apply then
    insert into public.ventas_precios_antiduplicado(empresa_id, solicitud_id, lista_precio_id, tipo, resultado, creado_por)
    values (p_company, p_request_id, p_list, p_mode, v_result, auth.uid());
  end if;
  return v_result;
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
  if auth.uid() is null or not private.has_permission(p_company,'produccion_ordenes','editar') then
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

CREATE OR REPLACE FUNCTION public.cancel_production_plan(p_company uuid, p_plan uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_plan public.produccion_planes%rowtype;
begin
  if not private.has_permission(p_company,'produccion_planificacion','editar') then
    raise exception 'Sin permiso para cancelar planes' using errcode='42501'; end if;
  select * into v_plan from public.produccion_planes
    where empresa_id=p_company and id=p_plan for update;
  if not found then raise exception 'Plan inexistente'; end if;
  if exists(select 1 from public.produccion_ordenes j
    where j.empresa_id=p_company and j.plan_id=p_plan) then
    raise exception 'Este plan tiene una orden. Gestioná su estado desde Fabricación'; end if;
  if v_plan.estado='terminado' then
    raise exception 'Una fabricación registrada no se puede cancelar'; end if;
  if v_plan.estado='planificado' then
    update public.produccion_planes set estado='cancelado',cancelado_en=clock_timestamp()
      where empresa_id=p_company and id=p_plan;
  end if;
  return p_plan;
end;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_purchase_order(p_company uuid, p_order uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.has_permission(p_company,'compras_ordenes','editar') then
    raise exception 'Sin permiso para cancelar órdenes' using errcode = '42501';
  end if;
  perform 1 from public.empresas c
  where c.id = p_company and c.activo for share;
  if not found then raise exception 'Empresa inactiva'; end if;
  update public.compras_ordenes o
  set estado = 'cancelada', cancelado_en = clock_timestamp()
  where o.empresa_id = p_company and o.id = p_order
    and o.estado in ('abierta', 'parcial');
  if not found then raise exception 'Orden inexistente o cerrada'; end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_purchase_request(p_company uuid, p_request uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row public.compras_pedidos%rowtype;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'compras_pedidos', 'editar') then
    raise exception 'Sin permiso para cancelar pedidos' using errcode = '42501';
  end if;
  select * into v_row from public.compras_pedidos
  where id = p_request and empresa_id = p_company and solicitado_por = auth.uid() for update;
  if not found then raise exception 'Pedido inexistente o no es tuyo'; end if;
  if v_row.estado <> 'pendiente' then raise exception 'El pedido ya fue resuelto'; end if;
  update public.compras_pedidos
  set estado = 'cancelado', resuelto_por = auth.uid(), resuelto_en = clock_timestamp()
  where id = p_request;
end;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_supplier_payment_order(p_company uuid, p_payment uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'finanzas','editar') then
    raise exception 'Sin permiso para anular' using errcode='42501'; end if;
  perform 1 from public.empresas where id=p_company and activo for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  update public.compras_pagos set estado='cancelado'
    where empresa_id=p_company and id=p_payment and estado='borrador';
  if not found then raise exception 'Solo se pueden anular borradores sin pagos'; end if;
end; $function$;

create or replace function public.cleanup_preview(p_company uuid, p_resource text, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_target record; v_row jsonb; v_action text:='delete'; v_message text;
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if auth.uid() is null or not private.has_permission(p_company,v_target.permission,'eliminar') then
    raise exception 'Necesitás permiso de eliminar en este módulo' using errcode='42501'; end if;
  execute format('select to_jsonb(t) from public.%I t where empresa_id=$1 and %I=$2',v_target.table_name,v_target.id_field)
    into v_row using p_company,p_id;
  if v_row is null then raise exception 'El registro no existe en esta empresa'; end if;
  if (v_row->>'archivado')::boolean then raise exception 'El registro ya está archivado'; end if;
  if p_resource='items' then
    if exists(select 1 from public.stock_saldos where empresa_id=p_company and item_id=p_id and cantidad<>0) then
      v_action:='blocked'; v_message:='El ítem todavía tiene stock. Regularizá sus existencias antes de retirarlo.';
    elsif exists(select 1 from public.produccion_formulas_lineas l join public.produccion_formulas f
      on f.empresa_id=l.empresa_id and f.producto_id=l.producto_id where l.empresa_id=p_company
        and (l.componente_id=p_id or l.producto_id=p_id) and not f.archivado) then
      v_action:='blocked'; v_message:='El ítem forma parte de una fórmula activa. Modificá o archivá esa fórmula primero.';
    elsif exists(select 1 from public.produccion_ordenes j where j.empresa_id=p_company and j.estado in ('pendiente','en_proceso')
      and (j.producto_id=p_id or exists(select 1 from jsonb_array_elements(j.formula_copia) x where x->>'component_id'=p_id::text)))
      or exists(select 1 from public.produccion_planes p where p.empresa_id=p_company and p.estado='planificado'
        and (p.producto_id=p_id or exists(select 1 from jsonb_array_elements(p.componentes_copia) x where x->>'component_id'=p_id::text)))
      or exists(select 1 from public.compras_ordenes_lineas l join public.compras_ordenes o on o.empresa_id=l.empresa_id and o.id=l.orden_compra_id
        where l.empresa_id=p_company and l.item_id=p_id and o.estado in ('abierta','parcial') and l.cantidad_recibida<l.cantidad) then
      v_action:='blocked'; v_message:='El ítem tiene fabricación, planificación o compras pendientes. Resolvé esas operaciones primero.';
    end if;
  elsif p_resource='tipos_cambio' then
    if exists(select 1 from public.stock_items where empresa_id=p_company and activo and tipo_cambio_referencia_id=p_id)
      or exists(select 1 from public.compras_proveedores_items q join public.stock_items i on i.empresa_id=q.empresa_id and i.id=q.item_id
        join public.compras_proveedores s on s.empresa_id=q.empresa_id and s.id=q.proveedor_id
        where q.empresa_id=p_company and q.tipo_cambio_id=p_id and i.activo and s.activo) then
      v_action:='blocked'; v_message:='Este dólar se usa en costos actuales. Cambiá primero el tipo de dólar de esos ítems o proveedores.';
    end if;
  elsif p_resource='formulas' then
    if exists(select 1 from public.produccion_ordenes where empresa_id=p_company and producto_id=p_id and estado in ('pendiente','en_proceso'))
      or exists(select 1 from public.produccion_planes where empresa_id=p_company and producto_id=p_id and estado='planificado') then
      v_action:='blocked'; v_message:='Hay órdenes o planes pendientes de este producto. Terminá o cancelá el trabajo primero.';
    end if;
  elsif p_resource='ordenes' then
    if v_row->>'estado'='en_proceso' or (v_row->>'estado'='pendiente' and exists(
      select 1 from public.produccion_ordenes_eventos where empresa_id=p_company and orden_id=p_id)) then
      v_action:='blocked'; v_message:='La orden está en proceso o tiene entregas. Completala o devolvé los materiales y cancelala antes de retirarla.';
    end if;
  elsif p_resource='fabricaciones' then v_action:='archive';
  elsif p_resource='planes' and v_row->>'estado'='planificado' and exists(
    select 1 from public.produccion_ordenes where empresa_id=p_company and plan_id=p_id) then
    v_action:='blocked'; v_message:='El plan tiene una orden vinculada. Gestioná primero esa orden.';
  elsif p_resource='remitos' then v_action:='archive';
  end if;
  if v_action='delete' and private.cleanup_has_references(p_company,p_resource,p_id) then v_action:='archive'; end if;
  if v_action='delete' then v_message:='Se eliminará definitivamente este registro sin uso. La acción no se puede deshacer.'; end if;
  if v_action='archive' then v_message:=case when p_resource='remitos'
    then 'El remito saldrá del listado, conservando la entrega y su historial. Archivar NO devuelve mercadería al stock. Para devolverla usá Anular entrega.'
    else 'El registro tiene información relacionada. Saldrá del listado y conservará sus movimientos, costos y vínculos. Podés recuperarlo en Archivados.' end; end if;
  return jsonb_build_object('action',v_action,'message',v_message);
end
$function$;

create or replace function public.cleanup_record(p_company uuid, p_resource text, p_id uuid, p_action text)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare v_target record; v_preview jsonb; v_row jsonb; v_cost numeric;
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if auth.uid() is null or not private.has_permission(p_company,v_target.permission,'eliminar') then
    raise exception 'Sin permiso para retirar el registro' using errcode='42501'; end if;
  perform 1 from public.empresas where id=p_company and activo for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  execute format('select to_jsonb(t) from public.%I t where empresa_id=$1 and %I=$2 for update',v_target.table_name,v_target.id_field)
    into v_row using p_company,p_id;
  if v_row is null then raise exception 'El registro ya no existe'; end if;
  v_preview:=public.cleanup_preview(p_company,p_resource,p_id);
  if v_preview->>'action'='blocked' then raise exception '%',v_preview->>'message'; end if;
  if p_action is null or p_action<>v_preview->>'action' then raise exception 'Cambió el uso del registro. Reabrí la confirmación para revisar la acción'; end if;
  if p_action='archive' then
    if p_resource in ('items','tipos_cambio') then
      execute format('update public.%I set activo_antes_de_archivar=activo,activo=false,archivado=true where empresa_id=$1 and %I=$2',v_target.table_name,v_target.id_field)
        using p_company,p_id;
    else
      execute format('update public.%I set archivado=true where empresa_id=$1 and %I=$2',v_target.table_name,v_target.id_field) using p_company,p_id;
    end if;
    return 'archive';
  end if;
  if p_resource='items' then
    update public.compras_proveedores_items set preferido=false where empresa_id=p_company and item_id=p_id and preferido;
    delete from public.compras_proveedores_items where empresa_id=p_company and item_id=p_id;
  elsif p_resource='formulas' then
    v_cost:=private.production_unit_cost(p_company,p_id);
    update public.stock_items set costo_unitario_referencia=v_cost where empresa_id=p_company and id=p_id
      and costo_referencia_usd is null and not exists(select 1 from public.compras_proveedores_items where empresa_id=p_company and item_id=p_id and preferido);
    delete from public.produccion_formulas_lineas where empresa_id=p_company and producto_id=p_id;
  elsif p_resource='ordenes' then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('production-reservations:'||p_company::text,0));
    delete from public.produccion_reservas_ubicaciones where empresa_id=p_company and orden_id=p_id;
    delete from public.produccion_ordenes_reservas where empresa_id=p_company and orden_id=p_id;
  end if;
  if p_resource in ('ordenes','planes') then
    insert into private.produccion_solicitudes_eliminadas(empresa_id,recurso,solicitud_id,autor_id)
      values(p_company,p_resource,(v_row->>'solicitud_id')::uuid,auth.uid()) on conflict do nothing;
  end if;
  execute format('delete from public.%I where empresa_id=$1 and %I=$2',v_target.table_name,v_target.id_field) using p_company,p_id;
  if p_resource='ordenes' then perform private.rebalance_production_reservations(p_company); end if;
  return 'delete';
exception when foreign_key_violation then
  raise exception 'El registro tiene nuevos vínculos. Reabrí la confirmación para revisar la acción';
end
$function$;

CREATE OR REPLACE FUNCTION public.company_members(p_company uuid)
 RETURNS TABLE(user_id uuid, email text, display_name text, role_id uuid, role_name text, active boolean, joined_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company, 'usuarios', 'ver') then
    raise exception 'Sin permiso para consultar usuarios' using errcode = '42501';
  end if;

  return query
    select cu.usuario_id, u.email::text, nullif(p.nombre, u.id::text),
      cu.rol_id, r.nombre, cu.activo, cu.creado_en
    from public.empresas_usuarios cu
    join auth.users u on u.id = cu.usuario_id
    join public.ajustes_roles r on r.id = cu.rol_id and r.empresa_id = cu.empresa_id
    left join public.ajustes_perfiles p on p.id = cu.usuario_id
    where cu.empresa_id = p_company
    order by cu.creado_en desc
    limit 500;
end;
$function$;

CREATE OR REPLACE FUNCTION public.complete_production_now(p_company uuid, p_product uuid, p_planned_quantity numeric, p_actual_quantity numeric, p_warehouse uuid, p_output_lot text, p_expires_on date, p_note text, p_variance_note text, p_inputs jsonb, p_request_id uuid, p_finish_request_id uuid, p_plan uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_previous public.produccion_fabricaciones_antiduplicado%rowtype;
  v_payload jsonb; v_job uuid; v_run uuid; v_input jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_ordenes','crear')
    or not private.has_permission(p_company,'stock','crear') then
    raise exception 'Necesitás permisos de producción y stock' using errcode='42501'; end if;
  if p_request_id is null or p_finish_request_id is null
    or jsonb_typeof(p_inputs) is distinct from 'array'
    or jsonb_array_length(p_inputs) not between 1 and 500 then
    raise exception 'Revisá los insumos de la fabricación'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('job-create:'||p_company::text||':'||p_request_id::text,0));
  v_payload:=jsonb_build_object('product',p_product,'planned',p_planned_quantity,
    'actual',p_actual_quantity,'warehouse',p_warehouse,
    'lot',nullif(btrim(p_output_lot),''),'expires',p_expires_on,
    'note',btrim(p_note),'variance',nullif(btrim(p_variance_note),''),
    'inputs',p_inputs,'plan',p_plan,'finish',p_finish_request_id);
  select * into v_previous from public.produccion_fabricaciones_antiduplicado
    where empresa_id=p_company and solicitud_id=p_request_id;
  if found then
    if v_previous.autor_id<>auth.uid() or v_previous.solicitud_datos<>v_payload then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_previous.fabricacion_id;
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
  insert into public.produccion_fabricaciones_antiduplicado(empresa_id,solicitud_id,
    solicitud_datos,orden_id,fabricacion_id,autor_id)
  values(p_company,p_request_id,v_payload,v_job,v_run,auth.uid());
  return v_run;
end;
$function$;

CREATE OR REPLACE FUNCTION public.complete_production_plan(p_company uuid, p_plan uuid, p_request_id uuid, p_inputs jsonb, p_output_lot text, p_expires_on date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_plan public.produccion_planes%rowtype;
  v_run uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_planificacion','crear')
    or not private.has_permission(p_company,'stock','crear') then
    raise exception 'Necesitás permiso de producción y stock' using errcode='42501';
  end if;
  if p_request_id is null then raise exception 'Solicitud inválida'; end if;
  select * into v_plan from public.produccion_planes
  where empresa_id=p_company and id=p_plan for update;
  if not found then raise exception 'Plan inexistente'; end if;
  if v_plan.estado='terminado' then
    if v_plan.solicitud_cierre_id <> p_request_id then
      raise exception 'Esta planificación ya fue completada';
    end if;
    return v_plan.fabricacion_id;
  end if;
  if v_plan.estado<>'planificado' then raise exception 'Esta planificación fue cancelada'; end if;
  perform 1 from public.produccion_formulas f
    where f.empresa_id=p_company and f.producto_id=v_plan.producto_id
      and f.version=v_plan.formula_version for share;
  if not found then
    raise exception 'La fórmula cambió. Creá un plan nuevo para revisar los insumos';
  end if;
  v_run := public.post_production_run(p_company,v_plan.producto_id,p_request_id,
    v_plan.cantidad,v_plan.deposito_id,p_output_lot,p_expires_on,
    v_plan.nota,p_inputs);
  update public.produccion_planes set estado='terminado',fabricacion_id=v_run,
    solicitud_cierre_id=p_request_id,terminado_en=clock_timestamp()
  where empresa_id=p_company and id=p_plan;
  return v_run;
end;
$function$;

CREATE OR REPLACE FUNCTION public.confirm_supplier_payment_order(p_company uuid, p_payment uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_payment public.compras_pagos%rowtype; v_line record; v_entry uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'finanzas','crear')
    or not private.has_permission(p_company,'compras_cuentas','ver') then raise exception 'Sin permiso para pagar' using errcode='42501'; end if;
  perform 1 from public.empresas where id=p_company and activo for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('treasury:'||p_company::text,0));
  select * into v_payment from public.compras_pagos where empresa_id=p_company and id=p_payment for update;
  if not found then raise exception 'Orden de pago inexistente'; end if;
  if v_payment.estado='pagado' then return v_payment.id; end if;
  if v_payment.estado<>'borrador' then raise exception 'La orden está anulada'; end if;
  for v_line in select * from public.compras_pagos_lineas
    where empresa_id=p_company and pago_id=p_payment order by orden_compra_id loop
    v_entry:=public.post_treasury_entry(p_company,v_payment.cuenta_id,'pago_proveedor',
      v_line.importe,v_line.orden_compra_id,v_payment.nota,v_payment.fecha_pago,v_line.solicitud_finanzas_id,null);
    update public.compras_pagos_lineas set movimiento_finanzas_id=v_entry
      where empresa_id=p_company and pago_id=p_payment and orden_compra_id=v_line.orden_compra_id;
  end loop;
  update public.compras_pagos set estado='pagado',confirmado_en=clock_timestamp()
    where empresa_id=p_company and id=p_payment;
  return p_payment;
end; $function$;

CREATE OR REPLACE FUNCTION public.convert_purchase_request(p_company uuid, p_request uuid, p_supplier uuid, p_note text, p_lines jsonb, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row public.compras_pedidos%rowtype; v_order uuid;
begin
  if auth.uid() is null or not (private.has_permission(p_company,'compras_pedidos','gestionar') and private.has_permission(p_company,'compras_ordenes','crear')) then
    raise exception 'Sin permiso para convertir pedidos en órdenes' using errcode = '42501';
  end if;
  if p_request_id is null then raise exception 'Identificador de solicitud inválido'; end if;
  select * into v_row from public.compras_pedidos
  where id = p_request and empresa_id = p_company for update;
  if not found then raise exception 'Pedido inexistente'; end if;
  if v_row.estado = 'ordenado' then
    -- Reintento de la misma conversión: solo si esta solicitud ya creó esa orden.
    if v_row.orden_compra_id is not null and exists (
      select 1 from public.compras_ordenes_antiduplicado r
      where r.empresa_id = p_company and r.solicitud_id = p_request_id
        and r.orden_compra_id = v_row.orden_compra_id) then
      return v_row.orden_compra_id;
    end if;
    raise exception 'El pedido ya fue resuelto';
  end if;
  if v_row.estado <> 'pendiente' then raise exception 'El pedido ya fue resuelto'; end if;

  v_order := public.create_purchase_order_once(p_company, p_supplier, p_note, p_lines, p_request_id);
  update public.compras_pedidos
  set estado = 'ordenado', orden_compra_id = v_order,
      resuelto_por = auth.uid(), resuelto_en = clock_timestamp()
  where id = p_request;
  return v_order;
end;
$function$;

create or replace function public.create_company(p_name text)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_company uuid;
  v_role uuid;
  v_user uuid := auth.uid();
  v_name text := nullif(btrim(p_name), '');
begin
  if v_user is null then raise exception 'Iniciá sesión' using errcode = '42501'; end if;
  if v_name is null or length(v_name) not between 2 and 100 then
    raise exception 'El nombre debe tener entre 2 y 100 caracteres';
  end if;
  insert into public.empresas(nombre, identificador)
    values (v_name, 'empresa-' || replace(gen_random_uuid()::text, '-', ''))
    returning id into v_company;
  insert into public.ajustes_roles(empresa_id, codigo, nombre)
    values (v_company, 'administrador', 'Administrador') returning id into v_role;
  insert into public.empresas_usuarios(empresa_id, usuario_id, rol_id) values (v_company, v_user, v_role);
  insert into public.ajustes_roles_permisos(empresa_id, rol_id, recurso, accion)
  select v_company, v_role, c.recurso, a.accion
  from public.ajustes_permisos_catalogo c cross join lateral unnest(c.acciones) as a(accion);
  insert into public.ajustes_perfiles(id, nombre)
    values (v_user, coalesce(nullif(v_user::text, ''), 'Usuario'))
    on conflict (id) do nothing;
  return v_company;
end
$function$;

CREATE OR REPLACE FUNCTION public.create_company_role(p_company uuid, p_name text, p_code text, p_permissions jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role uuid;
  v_name text := btrim(p_name);
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'administrador' then
    raise exception 'Solo el administrador puede crear roles' using errcode = '42501';
  end if;
  if v_name is null or length(v_name) not between 2 and 60 or p_code is null or p_code !~ '^[a-z][a-z0-9_]{1,39}$' then
    raise exception 'Nombre o código inválido';
  end if;
  if p_code in ('administrador', 'soporte') then
    raise exception 'Ese código de rol está reservado';
  end if;
  insert into public.ajustes_roles(empresa_id, codigo, nombre) values (p_company, p_code, v_name) returning id into v_role;
  perform private.save_role_permissions(p_company, v_role, p_permissions);
  perform private.log_access_event(p_company, 'rol_creado', null, v_role, jsonb_build_object(
    'name', v_name, 'code', p_code,
    'permissions', coalesce((select jsonb_agg(rp.recurso || ':' || rp.accion order by rp.recurso, rp.accion)
      from public.ajustes_roles_permisos rp where rp.rol_id = v_role), '[]'::jsonb)));
  return v_role;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_production_job(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due_on date, p_note text, p_request_id uuid, p_plan uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_formula public.produccion_formulas%rowtype;
  v_plan public.produccion_planes%rowtype; v_previous public.produccion_ordenes%rowtype;
  v_payload jsonb; v_snapshot jsonb; v_job uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_ordenes','crear') then
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
  select * into v_previous from public.produccion_ordenes
    where empresa_id=p_company and solicitud_id=p_request_id;
  if found then
    if v_previous.autor_id<>auth.uid() or v_previous.solicitud_datos<>v_payload then
      raise exception 'La solicitud ya se usó con otros datos'; end if;
    return v_previous.id;
  end if;
  select * into v_formula from public.produccion_formulas
    where empresa_id=p_company and producto_id=p_product for share;
  if not found then raise exception 'El producto no tiene fórmula'; end if;
  perform 1 from public.stock_items i where i.empresa_id=p_company and i.id=p_product
    and i.activo and i.tipo_item in ('semielaborado','producto_terminado') for share;
  if not found then raise exception 'Producto inactivo o no fabricable'; end if;
  perform 1 from public.stock_depositos w where w.empresa_id=p_company
    and w.id=p_warehouse and w.activo for share;
  if not found then raise exception 'Depósito de destino inactivo'; end if;
  if p_plan is not null then
    select * into v_plan from public.produccion_planes
      where empresa_id=p_company and id=p_plan for update;
    if not found or v_plan.estado<>'planificado' or v_plan.producto_id<>p_product
      or v_plan.deposito_id<>p_warehouse or v_plan.cantidad<>p_quantity
      or v_plan.formula_version<>v_formula.version then
      raise exception 'La planificación cambió. Revisá su fórmula y cantidades'; end if;
    if exists(select 1 from public.produccion_ordenes
      where empresa_id=p_company and plan_id=p_plan) then
      raise exception 'La planificación ya tiene una orden de fabricación'; end if;
    v_snapshot:=v_plan.componentes_copia;
  else
    select jsonb_agg(jsonb_build_object('component_id',l.componente_id,
      'quantity',l.cantidad*p_quantity/v_formula.cantidad_base,
      'unit_cost',private.production_unit_cost(p_company,l.componente_id))
      order by l.componente_id) into v_snapshot
    from public.produccion_formulas_lineas l
    where l.empresa_id=p_company and l.producto_id=p_product;
  end if;
  if v_snapshot is null or jsonb_array_length(v_snapshot)=0
    or exists(select 1 from jsonb_array_elements(v_snapshot) entry
      where (entry->>'quantity')::numeric<=0
        or (entry->>'quantity')::numeric<>round((entry->>'quantity')::numeric,6)) then
    raise exception 'La fórmula necesita componentes con hasta seis decimales'; end if;
  insert into public.produccion_ordenes(empresa_id,solicitud_id,solicitud_datos,
    producto_id,plan_id,cantidad_planificada,deposito_id,fecha_limite,
    formula_version,formula_copia,nota,autor_id)
  values(p_company,p_request_id,v_payload,p_product,p_plan,p_quantity,p_warehouse,
    p_due_on,v_formula.version,v_snapshot,btrim(p_note),auth.uid())
  returning id into v_job;
  return v_job;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_production_plan(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due_on date, p_note text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_formula public.produccion_formulas%rowtype;
  v_previous public.produccion_planes%rowtype;
  v_snapshot jsonb;
  v_cost numeric;
  v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_planificacion','crear') then
    raise exception 'Sin permiso para planificar producción' using errcode='42501';
  end if;
  if p_request_id is null or p_product is null or p_warehouse is null
    or p_quantity is null or p_quantity <= 0 or p_quantity >= 1000000000000
    or p_quantity <> round(p_quantity,6)
    or p_note is null or length(btrim(p_note)) not between 3 and 400 then
    raise exception 'Revisá producto, cantidad, depósito y nota';
  end if;
  select * into v_previous from public.produccion_planes
    where empresa_id=p_company and solicitud_id=p_request_id;
  if found then
    if v_previous.autor_id <> auth.uid() or v_previous.producto_id <> p_product
      or v_previous.cantidad <> p_quantity or v_previous.deposito_id <> p_warehouse
      or v_previous.fecha_limite is distinct from p_due_on or v_previous.nota <> btrim(p_note) then
      raise exception 'Esta solicitud ya se utilizó con otros datos';
    end if;
    return v_previous.id;
  end if;
  select * into v_formula from public.produccion_formulas
    where empresa_id=p_company and producto_id=p_product for share;
  if not found then raise exception 'El producto no tiene fórmula'; end if;
  perform 1 from public.stock_items where empresa_id=p_company and id=p_product
    and activo and tipo_item in ('semielaborado','producto_terminado') for share;
  if not found then raise exception 'El producto está inactivo'; end if;
  perform 1 from public.stock_depositos where empresa_id=p_company
    and id=p_warehouse and activo for share;
  if not found then raise exception 'El depósito está inactivo'; end if;
  select jsonb_agg(jsonb_build_object('component_id',l.componente_id,
    'quantity',l.cantidad*p_quantity/v_formula.cantidad_base,
    'unit_cost',private.production_unit_cost(p_company,l.componente_id))
    order by l.componente_id)
  into v_snapshot from public.produccion_formulas_lineas l
  where l.empresa_id=p_company and l.producto_id=p_product;
  if v_snapshot is null then raise exception 'La fórmula no tiene componentes'; end if;
  if exists (select 1 from jsonb_array_elements(v_snapshot) component
    where (component->>'quantity')::numeric <= 0
      or (component->>'quantity')::numeric >= 1000000000000
      or (component->>'quantity')::numeric <> round((component->>'quantity')::numeric,6)) then
    raise exception 'Esta cantidad genera consumos con más de seis decimales';
  end if;
  v_cost := round(private.production_unit_cost(p_company,p_product)*p_quantity,2);
  insert into public.produccion_planes(empresa_id,solicitud_id,producto_id,deposito_id,
    cantidad,formula_version,costo_estimado,componentes_copia,fecha_limite,nota,autor_id)
  values(p_company,p_request_id,p_product,p_warehouse,p_quantity,
    v_formula.version,v_cost,v_snapshot,p_due_on,btrim(p_note),auth.uid())
  returning id into v_id;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_production_work_order(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due date, p_note text, p_request uuid, p_plan uuid, p_options jsonb, p_finish jsonb DEFAULT NULL::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old public.produccion_ordenes%rowtype; v_snapshot jsonb; v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'produccion_ordenes','crear') then
    raise exception 'Sin permiso para crear órdenes' using errcode='42501'; end if;
  perform 1 from public.empresas where id=p_company and activo for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('work-order:'||p_company::text||':'||p_request::text,0));
  select * into v_old from public.produccion_ordenes where empresa_id=p_company and solicitud_id=p_request;
  if found then
    if v_old.opciones_trabajo_solicitadas is distinct from p_options then raise exception 'Solicitud usada con otro envasado u observaciones'; end if;
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
    select id into v_id from public.produccion_ordenes where empresa_id=p_company and solicitud_id=p_request;
  end if;
  perform pg_catalog.set_config('dromux.work_options','',true);
  return v_id;
end; $function$;

CREATE OR REPLACE FUNCTION public.create_purchase_order(p_company uuid, p_supplier uuid, p_note text, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_number bigint;
  v_order uuid;
  v_line jsonb;
  v_item uuid;
  v_quantity numeric;
  v_price numeric;
  v_code text;
  v_unit text;
  v_supplier_name text;
  v_index smallint := 0;
begin
  if not private.has_permission(p_company,'compras_ordenes','crear') then
    raise exception 'Sin permiso para crear órdenes' using errcode = '42501';
  end if;
  if p_supplier is null or length(coalesce(p_note, '')) > 500
     or jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) not between 1 and 200 then
    raise exception 'Datos de orden inválidos';
  end if;

  perform 1 from public.empresas c
  where c.id = p_company and c.activo for share;
  if not found then raise exception 'Empresa inactiva'; end if;
  select s.nombre into v_supplier_name from public.compras_proveedores s
  where s.id = p_supplier and s.empresa_id = p_company and s.activo for share;
  if not found then raise exception 'Elegí un proveedor activo'; end if;

  insert into public.empresas_numeradores(empresa_id,documento) values (p_company,'orden_compra')
  on conflict (empresa_id,documento) do nothing;
  update public.empresas_numeradores c
  set proximo_numero = c.proximo_numero + 1
  where c.empresa_id = p_company and c.documento = 'orden_compra'
  returning c.proximo_numero - 1 into v_number;

  insert into public.compras_ordenes(
    empresa_id, numero, proveedor_id, proveedor_nombre, nota, autor_id
  ) values (
    p_company, v_number, p_supplier, v_supplier_name,
    btrim(coalesce(p_note, '')), auth.uid()
  )
  returning id into v_order;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(v_line) is distinct from 'object'
       or coalesce(v_line->>'item_id', '') !~
         '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
       or coalesce(v_line->>'quantity', '') !~ '^[0-9]+(\.[0-9]{1,6})?$'
       or coalesce(v_line->>'unit_price', '') !~ '^[0-9]+(\.[0-9]{1,2})?$' then
      raise exception 'Línea de compra inválida';
    end if;
    v_item := (v_line->>'item_id')::uuid;
    v_quantity := (v_line->>'quantity')::numeric;
    v_price := (v_line->>'unit_price')::numeric;
    if v_quantity <= 0 or v_quantity >= 1000000000000
       or v_price >= 10000000000000000 then
      raise exception 'Cantidad o precio fuera de rango';
    end if;

    select i.codigo, u.simbolo into v_code, v_unit
    from public.stock_items i
    join public.stock_unidades u on u.empresa_id = i.empresa_id and u.id = i.unidad_id
    where i.empresa_id = p_company and i.id = v_item and i.activo
    for share of i;
    if not found then raise exception 'La orden contiene un ítem inactivo'; end if;

    v_index := v_index + 1;
    insert into public.compras_ordenes_lineas(
      empresa_id, orden_compra_id, linea, item_id, item_codigo,
      unidad_simbolo, cantidad, precio_unitario
    ) values (p_company, v_order, v_index, v_item, v_code,
      v_unit, v_quantity, v_price);
  end loop;

  return v_order;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_purchase_order_once(p_company uuid, p_supplier uuid, p_note text, p_lines jsonb, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_existing public.compras_ordenes_antiduplicado%rowtype;
  v_payload jsonb; v_order uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'compras_ordenes','crear') then
    raise exception 'Sin permiso para crear órdenes' using errcode='42501'; end if;
  if p_request_id is null then raise exception 'Identificador de solicitud inválido'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('purchase-order:'||p_company::text||':'||p_request_id::text,0));
  v_payload:=jsonb_build_object('supplier',p_supplier,
    'note',btrim(coalesce(p_note,'')),'lines',p_lines);
  select * into v_existing from public.compras_ordenes_antiduplicado
    where empresa_id=p_company and solicitud_id=p_request_id;
  if found then
    if v_existing.autor_id<>auth.uid() or v_existing.solicitud_datos<>v_payload then
      raise exception 'Esta solicitud ya se usó con otra orden'; end if;
    return v_existing.orden_compra_id;
  end if;
  v_order:=public.create_purchase_order(p_company,p_supplier,p_note,p_lines);
  insert into public.compras_ordenes_antiduplicado(empresa_id,solicitud_id,orden_compra_id,
    solicitud_datos,autor_id)
  values(p_company,p_request_id,v_order,v_payload,auth.uid());
  return v_order;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_purchase_request(p_company uuid, p_note text, p_needed_by date, p_priority text, p_lines jsonb, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_existing public.compras_pedidos_antiduplicado%rowtype;
  v_payload jsonb;
  v_number bigint;
  v_request uuid;
  v_label text;
  v_line jsonb;
  v_item uuid;
  v_quantity numeric;
  v_code text;
  v_name text;
  v_unit text;
  v_note text;
  v_index smallint := 0;
  v_seen uuid[] := '{}';
begin
  if auth.uid() is null
     or not (private.has_permission(p_company, 'compras_pedidos', 'crear')
             or private.has_permission(p_company,'compras_pedidos','crear')) then
    raise exception 'Sin permiso para crear pedidos de compra' using errcode = '42501';
  end if;
  if p_request_id is null then raise exception 'Identificador de solicitud inválido'; end if;
  if p_priority is null or p_priority not in ('normal', 'urgente')
     or (p_needed_by is not null
         and (p_needed_by < current_date - 1 or p_needed_by > current_date + 730))
     or length(coalesce(p_note, '')) > 500
     or jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) not between 1 and 200 then
    raise exception 'Datos del pedido inválidos';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('purchase-request:' || p_company::text || ':' || p_request_id::text, 0));
  v_payload := jsonb_build_object('note', btrim(coalesce(p_note, '')),
    'needed_by', p_needed_by, 'priority', p_priority, 'lines', p_lines);
  select * into v_existing from public.compras_pedidos_antiduplicado
  where empresa_id = p_company and solicitud_id = p_request_id;
  if found then
    if v_existing.autor_id <> auth.uid() or v_existing.solicitud_datos <> v_payload then
      raise exception 'Esta solicitud ya se usó con otro pedido';
    end if;
    return v_existing.pedido_id;
  end if;

  perform 1 from public.empresas c where c.id = p_company and c.activo for share;
  if not found then raise exception 'Empresa inactiva'; end if;

  -- Nombre visible: el cargado en el perfil o, si falta, la parte local del correo (sin el dominio).
  select coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                  nullif(split_part(coalesce(u.email, ''), '@', 1), ''), 'Usuario')
  into v_label from auth.users u where u.id = auth.uid();

  insert into public.empresas_numeradores(empresa_id,documento) values (p_company,'pedido_interno')
  on conflict (empresa_id,documento) do nothing;
  update public.empresas_numeradores c
  set proximo_numero = c.proximo_numero + 1
  where c.empresa_id = p_company and c.documento = 'pedido_interno'
  returning c.proximo_numero - 1 into v_number;

  insert into public.compras_pedidos(
    empresa_id, numero, solicitado_por, solicitante_nombre, prioridad, fecha_necesaria, nota
  ) values (
    p_company, v_number, auth.uid(), left(coalesce(v_label, 'Usuario'), 200),
    p_priority, p_needed_by, btrim(coalesce(p_note, ''))
  ) returning id into v_request;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(v_line) is distinct from 'object'
       or coalesce(v_line ->> 'quantity', '') !~ '^[0-9]+(\.[0-9]{1,6})?$' then
      raise exception 'Línea de pedido inválida';
    end if;
    v_quantity := (v_line ->> 'quantity')::numeric;
    if v_quantity <= 0 or v_quantity >= 1000000000000 then
      raise exception 'Cantidad fuera de rango';
    end if;
    v_note := btrim(coalesce(v_line ->> 'note', ''));
    if length(v_note) > 200 then raise exception 'La nota de una línea es demasiado larga'; end if;

    v_index := v_index + 1;
    if coalesce(v_line ->> 'item_id', '') <> '' then
      if (v_line ->> 'item_id') !~
         '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
        raise exception 'Línea de pedido inválida';
      end if;
      v_item := (v_line ->> 'item_id')::uuid;
      if v_item = any (v_seen) then raise exception 'Un ítem no puede repetirse en el pedido'; end if;
      v_seen := v_seen || v_item;
      select i.codigo, i.nombre, u.simbolo into v_code, v_name, v_unit
      from public.stock_items i
      join public.stock_unidades u on u.empresa_id = i.empresa_id and u.id = i.unidad_id
      where i.empresa_id = p_company and i.id = v_item and i.activo and not i.archivado
      for share of i;
      if not found then raise exception 'El pedido contiene un ítem inexistente o inactivo'; end if;
      insert into public.compras_pedidos_lineas(
        empresa_id, pedido_id, linea, item_id, item_codigo, item_nombre, unidad_simbolo, cantidad, nota
      ) values (p_company, v_request, v_index, v_item, v_code, v_name, v_unit, v_quantity, v_note);
    else
      v_name := btrim(coalesce(v_line ->> 'free_text', ''));
      v_unit := btrim(coalesce(v_line ->> 'unit', ''));
      if length(v_name) not between 2 and 160 or length(v_unit) > 20 then
        raise exception 'Escribí qué necesitás (2 a 160 caracteres) y una unidad de hasta 20';
      end if;
      insert into public.compras_pedidos_lineas(
        empresa_id, pedido_id, linea, item_id, item_codigo, item_nombre, unidad_simbolo, cantidad, nota
      ) values (p_company, v_request, v_index, null, null, v_name, v_unit, v_quantity, v_note);
    end if;
  end loop;

  insert into public.compras_pedidos_antiduplicado(empresa_id, solicitud_id, pedido_id, solicitud_datos, autor_id)
  values (p_company, p_request_id, v_request, v_payload, auth.uid());
  return v_request;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_quote(p_company uuid, p_customer uuid, p_name text, p_tax_id text, p_email text, p_phone text, p_address text, p_valid_until date, p_note text, p_show_tax boolean, p_lines jsonb, p_request_id uuid, p_tax_included boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_payload jsonb; v_existing public.ventas_presupuestos%rowtype; v_customer public.ventas_clientes%rowtype;
  v_name text; v_tax_id text; v_email text; v_phone text; v_address text;
  v_line jsonb; v_item public.stock_items%rowtype; v_res record; v_unit_symbol text;
  v_qty numeric; v_disc numeric; v_reason text; v_cap numeric; v_unit numeric; v_total numeric;
  v_lines jsonb := '[]'::jsonb; v_seen uuid[] := '{}'; v_n smallint := 0;
  v_net numeric := 0; v_tax numeric := 0; v_breakdown jsonb; v_id uuid := gen_random_uuid(); v_number bigint;
  v_label text; v_item_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'ventas', 'crear')
     or not private.has_permission(p_company, 'ventas', 'ver') then
    raise exception 'Necesitás permiso para crear presupuestos' using errcode = '42501';
  end if;
  if p_request_id is null or p_lines is null or jsonb_typeof(p_lines) <> 'array'
     or jsonb_array_length(p_lines) not between 1 and 200 then
    raise exception 'Revisá los productos del presupuesto (entre 1 y 200)';
  end if;
  if coalesce(p_show_tax, true) and coalesce(p_tax_included, false) then
    raise exception 'Elegí mostrar el IVA discriminado o sumarlo sin discriminar, no las dos cosas';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('quote:' || p_company::text || ':' || p_request_id::text, 0));
  v_payload := jsonb_build_object('customer', p_customer, 'name', btrim(coalesce(p_name, '')),
    'tax_id', btrim(coalesce(p_tax_id, '')), 'email', btrim(coalesce(p_email, '')),
    'phone', btrim(coalesce(p_phone, '')), 'address', btrim(coalesce(p_address, '')),
    'valid_until', p_valid_until, 'note', btrim(coalesce(p_note, '')),
    'show_tax', coalesce(p_show_tax, true), 'lines', p_lines)
    || case when coalesce(p_tax_included, false) then jsonb_build_object('tax_included', true) else '{}'::jsonb end;
  select * into v_existing from public.ventas_presupuestos where empresa_id = p_company and solicitud_id = p_request_id;
  if found then
    if v_existing.creado_por <> auth.uid() or v_existing.solicitud_datos <> v_payload then
      raise exception 'Esta solicitud ya se utilizó con otros datos';
    end if;
    return v_existing.id;
  end if;
  -- Estas validaciones van DESPUÉS de la idempotencia: un reintento tardío devuelve el presupuesto ya creado.
  if p_valid_until is null or p_valid_until < v_today or p_valid_until > v_today + 365 then
    raise exception 'La vigencia debe estar entre hoy y un año';
  end if;
  if length(coalesce(p_note, '')) > 1000 then raise exception 'Las condiciones son demasiado largas'; end if;
  perform 1 from public.empresas where id = p_company and activo for share;
  if not found then raise exception 'La empresa no está activa'; end if;

  if p_customer is not null then
    select * into v_customer from public.ventas_clientes
    where empresa_id = p_company and id = p_customer and activo for share;
    if not found then raise exception 'Elegí un cliente activo'; end if;
    v_name := v_customer.nombre; v_tax_id := v_customer.identificacion_fiscal; v_email := v_customer.email;
    v_phone := v_customer.telefono; v_address := v_customer.direccion;
  else
    v_name := btrim(coalesce(p_name, '')); v_tax_id := btrim(coalesce(p_tax_id, ''));
    v_email := btrim(coalesce(p_email, '')); v_phone := btrim(coalesce(p_phone, ''));
    v_address := btrim(coalesce(p_address, ''));
    if length(v_name) not between 2 and 160 or length(v_tax_id) > 30 or length(v_email) > 160
       or length(v_phone) > 40 or length(v_address) > 240 then
      raise exception 'Indicá el nombre del interesado (hasta 160 caracteres) y revisá sus datos';
    end if;
  end if;

  select coalesce(s.descuento_maximo_porcentaje, 0) into v_cap from (select 1) x
  left join public.ventas_precios_config s on s.empresa_id = p_company;

  -- Se conserva el orden en que se cargaron las líneas (es el orden que ve el cliente en el PDF).
  for v_line in select t.value from jsonb_array_elements(p_lines) with ordinality as t(value, ord) order by t.ord loop
    v_n := v_n + 1;
    begin
      v_qty := (v_line ->> 'quantity')::numeric;
    exception when others then v_qty := null;
    end;
    if v_qty is null or v_qty <= 0 or v_qty >= 1000000000000 or v_qty <> round(v_qty, 6) then
      raise exception 'La cantidad de la línea % es inválida', v_n;
    end if;
    begin
      v_item_id := (v_line ->> 'item_id')::uuid;
    exception when others then v_item_id := null;
    end;
    select * into v_item from public.stock_items
    where empresa_id = p_company and id = v_item_id and activo and tipo_item = 'producto_terminado';
    if v_item_id is null or not found then raise exception 'La línea % tiene un producto inactivo o que no es terminado', v_n; end if;
    if v_item.id = any (v_seen) then raise exception 'Cada producto puede figurar una sola vez'; end if;
    v_seen := v_seen || v_item.id;
    select * into v_res from private.sale_resolve_price(p_company, p_customer, v_item.id);
    if v_res.price is null or v_res.price <= 0 then raise exception 'Definí el precio de venta de %', v_item.nombre; end if;

    begin
      v_disc := coalesce(nullif(btrim(v_line ->> 'discount_percent'), '')::numeric, 0);
    exception when others then v_disc := -1;
    end;
    v_reason := nullif(btrim(v_line ->> 'discount_reason'), '');
    if v_disc = 0 then v_reason := null; end if;
    if v_disc < 0 or v_disc >= 100 or v_disc <> round(v_disc, 2) then
      raise exception 'El descuento de % es inválido', v_item.nombre;
    end if;
    if length(coalesce(v_reason, '')) > 200 then raise exception 'El motivo del descuento es demasiado largo'; end if;
    if v_disc > v_cap then
      if private.get_user_role(p_company) is distinct from 'administrador' then
        raise exception 'El descuento de % supera el máximo permitido (% %%)', v_item.nombre, v_cap;
      end if;
      if length(regexp_replace(coalesce(v_reason, ''), '[^[:alnum:]]', '', 'g')) < 3 then
        raise exception 'Indicá el motivo del descuento de %', v_item.nombre;
      end if;
    end if;
    v_unit := round(v_res.price * (1 - v_disc / 100), 2);
    if v_disc > 0 and v_unit <= 0 then raise exception 'El descuento de % deja el precio en cero', v_item.nombre; end if;
    v_total := round(v_qty * v_unit, 2);
    v_net := v_net + v_total;
    if v_net >= 10000000000000000 then raise exception 'El total supera el máximo permitido'; end if;
    select simbolo into v_unit_symbol from public.stock_unidades where empresa_id = p_company and id = v_item.unidad_id;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'item_id', v_item.id, 'item_code', v_item.codigo, 'item_name', v_item.nombre, 'unit_symbol', v_unit_symbol,
      'quantity', v_qty, 'price_list_id', v_res.list_id, 'list_unit_price', v_res.price,
      'discount_percent', v_disc, 'discount_reason', v_reason, 'unit_price', v_unit,
      'line_total', v_total, 'tax_percent', v_res.tax_percent));
  end loop;

  -- IVA por alícuota. Discriminado: sobre la base de cada alícuota. Sumado sin discriminar (consumidor final):
  -- línea por línea, para que los precios con IVA que ve el cliente sumen exactamente el total.
  select coalesce(jsonb_agg(jsonb_build_object('rate', g.rate, 'base', g.base, 'tax', g.tax) order by g.rate), '[]'::jsonb)
  into v_breakdown
  from (select (e ->> 'tax_percent')::numeric as rate, sum((e ->> 'line_total')::numeric) as base,
          case when coalesce(p_tax_included, false)
            then sum(round((e ->> 'line_total')::numeric * (e ->> 'tax_percent')::numeric / 100, 2))
            else round(sum((e ->> 'line_total')::numeric) * (e ->> 'tax_percent')::numeric / 100, 2) end as tax
        from jsonb_array_elements(v_lines) e group by 1) g;
  select coalesce(sum((b ->> 'tax')::numeric), 0) into v_tax from jsonb_array_elements(v_breakdown) b;
  if v_net + v_tax >= 10000000000000000 then raise exception 'El total supera el máximo permitido'; end if;

  insert into public.empresas_numeradores(empresa_id,documento) values (p_company,'presupuesto') on conflict do nothing;
  update public.empresas_numeradores set proximo_numero = proximo_numero + 1
  where empresa_id = p_company and documento = 'presupuesto' returning proximo_numero - 1 into v_number;
  -- Si el perfil guarda un identificador en vez de un nombre, se muestra "Usuario".
  select coalesce(nullif(btrim(case when p.nombre ~* '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    then null else p.nombre end), ''), 'Usuario') into v_label
  from (select 1) x left join public.ajustes_perfiles p on p.id = auth.uid();

  insert into public.ventas_presupuestos(id, empresa_id, numero, solicitud_id, solicitud_datos, cliente_id, cliente_nombre,
    cliente_identificacion_fiscal, cliente_email, cliente_telefono, cliente_direccion, vigente_hasta, nota, mostrar_impuesto,
    impuesto_incluido, total_neto, total_impuesto, total_bruto, impuestos_detalle, creado_por, creado_por_nombre)
  values (v_id, p_company, v_number, p_request_id, v_payload, p_customer, v_name, v_tax_id, v_email, v_phone,
    v_address, p_valid_until, btrim(coalesce(p_note, '')), coalesce(p_show_tax, true),
    coalesce(p_tax_included, false), v_net, v_tax,
    v_net + v_tax, v_breakdown, auth.uid(), coalesce(v_label, 'Usuario'));

  v_n := 0;
  for v_line in select value from jsonb_array_elements(v_lines) loop
    v_n := v_n + 1;
    insert into public.ventas_presupuestos_lineas(empresa_id, presupuesto_id, linea, item_id, item_codigo, item_nombre, unidad_simbolo,
      cantidad, lista_precio_id, precio_unitario_lista, descuento_porcentaje, descuento_motivo, precio_unitario, total_linea,
      impuesto_porcentaje)
    values (p_company, v_id, v_n, (v_line ->> 'item_id')::uuid, v_line ->> 'item_code', v_line ->> 'item_name',
      v_line ->> 'unit_symbol', (v_line ->> 'quantity')::numeric, (v_line ->> 'price_list_id')::uuid,
      (v_line ->> 'list_unit_price')::numeric, (v_line ->> 'discount_percent')::numeric,
      v_line ->> 'discount_reason', (v_line ->> 'unit_price')::numeric, (v_line ->> 'line_total')::numeric,
      (v_line ->> 'tax_percent')::numeric);
  end loop;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_supplier_payment_order(p_company uuid, p_supplier uuid, p_account uuid, p_on date, p_note text, p_reference text, p_lines jsonb, p_request uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid; v_row jsonb; v_amount numeric; v_total numeric:=0; v_old public.compras_pagos%rowtype;
  v_payload jsonb; v_order uuid; v_remaining numeric; v_number bigint;
begin
  if auth.uid() is null or not private.has_permission(p_company,'finanzas','crear')
    or not private.has_permission(p_company,'compras_cuentas','ver') then
    raise exception 'Necesitás crear Finanzas y leer Compras' using errcode='42501'; end if;
  perform 1 from public.empresas where id=p_company and activo for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  if p_request is null or p_on is null or p_on>(now() at time zone 'America/Argentina/Buenos_Aires')::date
    or length(btrim(coalesce(p_note,''))) not between 3 and 240
    or length(coalesce(p_reference,''))>120 or p_lines is null or jsonb_typeof(p_lines)<>'array'
    or jsonb_array_length(p_lines) not between 1 and 40 then raise exception 'Revisá fecha, detalle y órdenes a pagar'; end if;
  v_payload:=jsonb_build_object('supplier',p_supplier,'account',p_account,'on',p_on,
    'note',btrim(p_note),'reference',coalesce(p_reference,''),'lines',p_lines);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('treasury:'||p_company::text,0));
  select * into v_old from public.compras_pagos where empresa_id=p_company and solicitud_id=p_request;
  if found then
    if v_old.solicitud_datos<>v_payload or v_old.autor_id<>auth.uid() then raise exception 'Solicitud usada con otros datos'; end if;
    return v_old.id;
  end if;
  perform 1 from public.compras_proveedores where empresa_id=p_company and id=p_supplier and activo;
  if not found then raise exception 'Elegí un proveedor activo'; end if;
  perform 1 from public.finanzas_cuentas where empresa_id=p_company and id=p_account and activo;
  if not found then raise exception 'Elegí una cuenta activa'; end if;
  for v_row in select value from jsonb_array_elements(p_lines) loop
    v_order:=(v_row->>'order_id')::uuid; v_amount:=(v_row->>'amount')::numeric;
    if v_amount is null or v_amount<=0 or v_amount>=1000000000000 or v_amount<>round(v_amount,2) then
      raise exception 'Importe inválido, hasta dos decimales'; end if;
    perform 1 from public.compras_ordenes where empresa_id=p_company and id=v_order
      and proveedor_id=p_supplier and estado in ('abierta','parcial','recibida');
    if not found then raise exception 'Todas las órdenes deben ser del proveedor y estar vigentes'; end if;
    select round(sum(l.cantidad*l.precio_unitario),2)-coalesce((select sum(t.importe)
      from public.finanzas_movimientos t where t.empresa_id=p_company and t.orden_compra_id=v_order),0)
      into v_remaining from public.compras_ordenes_lineas l where l.empresa_id=p_company and l.orden_compra_id=v_order;
    if v_amount>v_remaining then raise exception 'El importe supera el saldo pendiente de la orden'; end if;
    v_total:=v_total+v_amount;
  end loop;
  insert into public.empresas_numeradores(empresa_id,documento,proximo_numero) values(p_company,'pago_proveedor',2)
    on conflict(empresa_id,documento) do update set proximo_numero=public.empresas_numeradores.proximo_numero+1
    returning proximo_numero-1 into v_number;
  insert into public.compras_pagos(empresa_id,numero,proveedor_id,cuenta_id,solicitud_id,solicitud_datos,
    importe,fecha_pago,nota,referencia,autor_id)
  values(p_company,v_number,p_supplier,p_account,p_request,v_payload,v_total,p_on,btrim(p_note),coalesce(p_reference,''),auth.uid()) returning id into v_id;
  insert into public.compras_pagos_lineas(empresa_id,pago_id,orden_compra_id,importe)
    select p_company,v_id,(x->>'order_id')::uuid,(x->>'amount')::numeric from jsonb_array_elements(p_lines) x;
  return v_id;
end; $function$;

CREATE OR REPLACE FUNCTION public.create_treasury_account(p_company uuid, p_name text, p_kind text, p_opening numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'finanzas','crear') then
    raise exception 'Sin permiso para crear cuentas' using errcode='42501'; end if;
  if p_name is null or length(btrim(p_name)) not between 2 and 100
    or p_kind not in ('caja','banco','otra') or p_opening is null
    or p_opening<>round(p_opening,2) then raise exception 'Revisá los datos de la cuenta'; end if;
  insert into public.finanzas_cuentas(empresa_id,nombre,tipo,saldo_inicial)
  values(p_company,btrim(p_name),p_kind,p_opening) returning id into v_id;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_admin_price_list_rows(p_company uuid, p_list uuid, p_search text DEFAULT ''::text, p_filter text DEFAULT 'all'::text, p_page integer DEFAULT 0, p_page_size integer DEFAULT 50)
 RETURNS TABLE(item_id uuid, code text, name text, unit_symbol text, net_price numeric, source text, method text, method_value numeric, cost numeric, margin_percent numeric, markup_percent numeric, profit numeric, profit_after_costs numeric, low_margin boolean, cost_changed boolean, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare v_size integer; v_term text; v_min numeric; v_over numeric; v_ids uuid[]; v_total bigint;
  v_page integer; v_by_cost boolean;
begin
  perform private.price_require_cost_view(p_company);
  if p_filter is null or p_filter not in ('all', 'missing', 'low_margin', 'cost_changed') then
    raise exception 'Filtro inválido';
  end if;
  if not exists (select 1 from public.ventas_listas_precios where empresa_id = p_company and id = p_list) then
    raise exception 'Lista inexistente';
  end if;
  select coalesce(s.margen_minimo_porcentaje, 0), coalesce(s.comision_porcentaje, 0) + coalesce(s.estructura_porcentaje, 0)
    into v_min, v_over
  from (select 1) x left join public.ventas_precios_config s on s.empresa_id = p_company;
  v_size := least(greatest(coalesce(p_page_size, 50), 1), 200);
  v_page := greatest(coalesce(p_page, 0), 0);
  v_term := lower(btrim(coalesce(p_search, '')));
  v_by_cost := p_filter in ('low_margin', 'cost_changed');

  if v_by_cost then
    select coalesce(array_agg(t.item_id), '{}') into v_ids from (
      select e.item_id from private.price_effective(p_company, p_list, v_term) e
      where e.net_price is not null limit 1001) t;
    if cardinality(v_ids) > 1000 then
      raise exception 'Hay más de 1000 productos con precio: buscá por nombre para acotar este filtro';
    end if;
  else
    select count(*) into v_total from private.price_effective(p_company, p_list, v_term) e
    where p_filter = 'all' or e.net_price is null;
    select coalesce(array_agg(t.item_id), '{}') into v_ids from (
      select e.item_id from private.price_effective(p_company, p_list, v_term) e
      where p_filter = 'all' or e.net_price is null
      order by (e.net_price is null) desc, e.name, e.item_id
      limit v_size offset v_page * v_size) t;
  end if;

  return query
  with c as materialized (select cc.item_id, cc.cost from private.price_costs(p_company, v_ids) cc),
  calc as (
    select e.*, c.cost,
      case when e.net_price > 0 and c.cost is not null then round((e.net_price - c.cost) / e.net_price * 100, 2) end as margin_percent,
      case when c.cost > 0 and e.net_price is not null then round((e.net_price - c.cost) / c.cost * 100, 2) end as markup_percent,
      case when e.net_price is not null and c.cost is not null then round(e.net_price - c.cost, 2) end as profit,
      case when e.net_price is not null and c.cost is not null
        then round(e.net_price - c.cost - e.net_price * v_over / 100, 2) end as profit_after_costs
    from private.price_effective(p_company, p_list, v_term) e
    left join c on c.item_id = e.item_id
    where e.item_id = any (v_ids)
  ),
  flagged as (
    select k.*, (k.margin_percent is not null and k.margin_percent < v_min) as low_margin,
      (k.cost_snapshot is not null and k.cost is not null and k.cost_snapshot <> k.cost) as cost_changed
    from calc k
  )
  select f.item_id, f.code, f.name, f.unit_symbol, f.net_price, f.source, f.method, f.method_value, f.cost,
    f.margin_percent, f.markup_percent, f.profit, f.profit_after_costs, f.low_margin, f.cost_changed,
    case when v_by_cost then count(*) over () else v_total end
  from flagged f
  where case p_filter when 'low_margin' then f.low_margin when 'cost_changed' then f.cost_changed else true end
  order by (f.net_price is null) desc, f.name, f.item_id
  limit v_size offset case when v_by_cost then v_page * v_size else 0 end;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_admin_product_costs(p_company uuid, p_search text DEFAULT ''::text)
 RETURNS TABLE(item_id uuid, code text, name text, item_type text, unit_symbol text, cost numeric, price numeric, margin numeric, margin_percent numeric, status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or private.get_user_role(p_company)<>'administrador'
    or not private.has_permission(p_company,'finanzas','ver')
    or not private.has_permission(p_company,'items','ver') then
    raise exception 'Solo un administrador puede consultar costos y márgenes'
      using errcode='42501'; end if;
  return query select * from public.erp_product_costs(p_company,p_search);
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_admin_sales_profit_detail(p_company uuid, p_from date, p_to date, p_search text DEFAULT ''::text, p_page integer DEFAULT 0)
 RETURNS TABLE(sale_id uuid, sale_number bigint, customer_name text, sold_at timestamp with time zone, product_summary text, net_revenue numeric, known_cost numeric, gross_profit numeric, missing_lines bigint, cancelled boolean, total_rows bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or private.get_user_role(p_company) <> 'administrador'
    or not private.has_permission(p_company, 'finanzas', 'ver')
    or not private.has_permission(p_company, 'ventas', 'ver') then
    raise exception 'Solo el administrador puede consultar la rentabilidad por venta'
      using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_to < p_from
    or p_to - p_from > 366 or p_page is null or p_page < 0 or p_page > 10000
    or length(coalesce(p_search, '')) > 100 then
    raise exception 'Revisá el período y la búsqueda';
  end if;

  return query
  with selected_sales as (
    select s.id, s.numero, s.cliente_nombre, s.creado_en
    from public.ventas s
    where s.empresa_id = p_company
      and s.creado_en >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
      and s.creado_en < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
      and (btrim(coalesce(p_search, '')) = ''
        or s.cliente_nombre ilike '%' || btrim(p_search) || '%'
        or s.numero::text ilike '%' || btrim(p_search) || '%'
        or exists (
          select 1 from public.ventas_lineas sl
          where sl.empresa_id = p_company and sl.venta_id = s.id
            and (sl.item_nombre ilike '%' || btrim(p_search) || '%'
              or sl.item_codigo ilike '%' || btrim(p_search) || '%')
        ))
  ), line_values as (
    select sl.venta_id, sl.item_nombre, sl.linea,
      sl.total_linea - coalesce(adj.credit_amount, 0) as revenue,
      sl.cantidad - coalesce(adj.restocked_quantity, 0) as retained_quantity,
      sl.costo_unitario_estimado
    from public.ventas_lineas sl
    join selected_sales ss on ss.id = sl.venta_id
    left join lateral (
      select sum(al.credito_importe) as credit_amount,
        sum(al.cantidad) filter (where al.reingresado) as restocked_quantity
      from public.ventas_ajustes_lineas al
      where al.empresa_id = sl.empresa_id
        and al.venta_id = sl.venta_id and al.venta_linea = sl.linea
    ) adj on true
    where sl.empresa_id = p_company
  ), amounts as (
    select lv.venta_id,
      string_agg(lv.item_nombre, ', ' order by lv.linea) as products,
      sum(lv.revenue) as revenue,
      sum(lv.retained_quantity * lv.costo_unitario_estimado)
        filter (where lv.costo_unitario_estimado is not null) as cost,
      count(*) filter (where lv.costo_unitario_estimado is null
        and lv.retained_quantity > 0) as missing
    from line_values lv group by lv.venta_id
  ), details as (
    select ss.id, ss.numero, ss.cliente_nombre, ss.creado_en,
      a.products, a.revenue, a.cost, a.missing,
      exists (select 1 from public.ventas_ajustes sa
        where sa.empresa_id = p_company and sa.venta_id = ss.id
          and sa.tipo = 'anulacion') as is_cancelled
    from selected_sales ss join amounts a on a.venta_id = ss.id
  )
  select d.id, d.numero, d.cliente_nombre, d.creado_en, d.products,
    d.revenue, d.cost,
    case when d.missing = 0 then d.revenue - coalesce(d.cost, 0)
      else null end,
    d.missing, d.is_cancelled, count(*) over()
  from details d
  order by d.creado_en desc, d.id desc
  limit 25 offset p_page * 25;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_admin_sales_profit_summary(p_company uuid)
 RETURNS TABLE(sales_total numeric, covered_revenue numeric, covered_cost numeric, estimated_profit numeric, missing_lines bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or private.get_user_role(p_company) <> 'administrador'
    or not private.has_permission(p_company, 'finanzas', 'ver')
    or not private.has_permission(p_company, 'ventas', 'ver') then
    raise exception 'Solo el administrador puede consultar ganancias'
      using errcode = '42501';
  end if;
  return query
  with line_values as (
    select l.venta_id,
      l.total_linea - coalesce(a.credit_amount, 0) as revenue,
      l.cantidad - coalesce(a.restocked_quantity, 0) as retained_quantity,
      l.costo_unitario_estimado
    from public.ventas_lineas l
    left join lateral (
      select sum(al.credito_importe) credit_amount,
        sum(al.cantidad) filter (where al.reingresado) restocked_quantity
      from public.ventas_ajustes_lineas al
      where al.empresa_id = l.empresa_id and al.venta_id = l.venta_id
        and al.venta_linea = l.linea
    ) a on true
    where l.empresa_id = p_company
  ), sale_totals as (
    select lv.venta_id, sum(lv.revenue) revenue,
      sum(lv.retained_quantity * lv.costo_unitario_estimado)
        filter (where lv.costo_unitario_estimado is not null) cost,
      count(*) filter (where lv.costo_unitario_estimado is null
        and lv.retained_quantity > 0) missing
    from line_values lv group by lv.venta_id
  )
  select coalesce(sum(st.revenue), 0),
    coalesce(sum(st.revenue) filter (where st.missing = 0), 0),
    coalesce(sum(st.cost) filter (where st.missing = 0), 0),
    coalesce(sum(st.revenue - coalesce(st.cost, 0)) filter (where st.missing = 0), 0),
    coalesce(sum(st.missing), 0)::bigint
  from sale_totals st;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_can_manufacture(p_company uuid, p_product uuid, p_quantity numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_formula public.produccion_formulas%rowtype; v_lines jsonb;
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null
    or not private.has_permission(p_company,'produccion_disponibilidad','ver')
    or not private.has_permission(p_company,'stock_saldos','ver') then
    raise exception 'Necesitás acceso a producción y stock' using errcode='42501';
  end if;
  if p_product is null or p_quantity is null or p_quantity<=0
    or p_quantity>=1000000000000 or p_quantity<>round(p_quantity,6) then
    raise exception 'Indicá una cantidad válida con hasta seis decimales';
  end if;
  select * into v_formula from public.produccion_formulas
    where empresa_id=p_company and producto_id=p_product;
  if not found then raise exception 'El producto no tiene fórmula'; end if;
  select jsonb_agg(jsonb_build_object(
    'item_id',n.item_id,'item_code',n.item_code,'item_name',n.item_name,
    'item_type',n.tipo_item,'unit_symbol',n.unit_symbol,
    'required',n.required,'infinite_stock',n.stock_infinito,'physical',coalesce(b.physical,0),
    'usable',coalesce(sl.usable,0),'reserved',coalesce(r.reserved,0),
    'free',case when n.stock_infinito then n.required else greatest(0,coalesce(sl.usable,0)-coalesce(r.reserved,0)) end,
    'locations',coalesce(sl.locations,'[]'::jsonb)) order by n.item_name)
    into v_lines
  from (
    select i.empresa_id,i.id item_id,i.codigo item_code,i.nombre item_name,
      i.tipo_item,i.usa_lotes,i.stock_infinito,u.simbolo unit_symbol,
      round(sum(l.cantidad)*p_quantity/v_formula.cantidad_base,6) required
    from public.produccion_formulas_lineas l
    join public.stock_items i on i.empresa_id=l.empresa_id and i.id=l.componente_id
    join public.stock_unidades u on u.empresa_id=i.empresa_id and u.id=i.unidad_id
    where l.empresa_id=p_company and l.producto_id=p_product
    group by i.empresa_id,i.id,u.simbolo
  ) n
  left join lateral (
    select sum(b.cantidad) physical from public.stock_saldos b
    where b.empresa_id=p_company and b.item_id=n.item_id
  ) b on true
  left join lateral (
    select sum(a.cantidad) reserved from public.produccion_reservas_ubicaciones a
    join public.produccion_ordenes j on j.empresa_id=a.empresa_id and j.id=a.orden_id
    where a.empresa_id=p_company and a.componente_id=n.item_id
      and j.estado in ('pendiente','en_proceso')
  ) r on true
  left join lateral (
    select sum(s.cantidad) usable,
      jsonb_agg(jsonb_build_object(
        'warehouse_id',s.deposito_id,'warehouse_name',s.warehouse_name,
        'lot_code',s.lote_codigo,'expires_on',s.vencimiento,
        'physical',s.cantidad,'reserved',coalesce(ar.reserved,0),
        'free',greatest(0,s.cantidad-coalesce(ar.reserved,0)))
        order by s.vencimiento asc nulls last,s.warehouse_name,s.lote_codigo) locations
    from (
      select sb.deposito_id,w.nombre warehouse_name,
        null::uuid lote_id,null::text lote_codigo,null::date vencimiento,sb.cantidad
      from public.stock_saldos sb
      join public.stock_depositos w on w.empresa_id=sb.empresa_id
        and w.id=sb.deposito_id and w.activo
      where sb.empresa_id=p_company and sb.item_id=n.item_id
        and not n.usa_lotes and sb.cantidad>0
      union all
      select lb.deposito_id,w.nombre,lb.lote_id,l.codigo,l.vencimiento,lb.cantidad
      from public.stock_lotes_saldos lb
      join public.stock_lotes l on l.empresa_id=lb.empresa_id
        and l.item_id=lb.item_id and l.id=lb.lote_id
      join public.stock_depositos w on w.empresa_id=lb.empresa_id
        and w.id=lb.deposito_id and w.activo
      where lb.empresa_id=p_company and lb.item_id=n.item_id
        and n.usa_lotes and lb.cantidad>0
        and (l.vencimiento is null or l.vencimiento>=v_today)
    ) s
    left join lateral (
      select sum(a.cantidad) reserved from public.produccion_reservas_ubicaciones a
      join public.produccion_ordenes j on j.empresa_id=a.empresa_id and j.id=a.orden_id
      where a.empresa_id=p_company and a.componente_id=n.item_id
        and a.deposito_id=s.deposito_id
        and a.lote_id is not distinct from s.lote_id
        and j.estado in ('pendiente','en_proceso')
    ) ar on true
  ) sl on true;
  return jsonb_build_object('product_id',p_product,'quantity',p_quantity,
    'formula_version',v_formula.version,'lines',coalesce(v_lines,'[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_company_profile(p_company uuid)
 RETURNS TABLE(legal_name text, tax_id text, tax_condition text, address text, phone text, email text, website text, logo_data text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
  if auth.uid() is null or not (private.has_permission(p_company, 'ventas', 'ver')
     or private.has_permission(p_company,'produccion_ordenes','ver')) then
    raise exception 'Sin acceso a los datos de la empresa' using errcode = '42501';
  end if;
  return query
  select coalesce(nullif(p.razon_social, ''), c.nombre), coalesce(p.identificacion_fiscal, ''), coalesce(p.condicion_fiscal, ''),
    coalesce(p.direccion, ''), coalesce(p.telefono, ''), coalesce(p.email, ''), coalesce(p.sitio_web, ''),
    coalesce(p.logo, '')
  from public.empresas c left join public.empresas_perfil p on p.empresa_id = c.id
  where c.id = p_company;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_dashboard(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_result jsonb:='{}'::jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'inicio','ver') then
    raise exception 'Sin acceso al inicio' using errcode='42501'; end if;
  if private.has_permission(p_company,'items','ver') then
    v_result:=v_result||jsonb_build_object('items',
      (select count(*) from public.stock_items where empresa_id=p_company and activo));
  end if;
  if private.has_permission(p_company,'compras_resumen','ver') then
    v_result:=v_result||jsonb_build_object('purchases',
      (select count(*) from public.compras_ordenes where empresa_id=p_company and estado='abierta'));
  end if;
  if private.has_permission(p_company,'produccion_resumen','ver') then
    v_result:=v_result||jsonb_build_object('formulas',
      (select count(*) from public.produccion_formulas where empresa_id=p_company));
  end if;
  if private.has_permission(p_company,'ventas','ver') then
    v_result:=v_result||jsonb_build_object('sales',
      (select count(*) from public.ventas where empresa_id=p_company));
  end if;
  if private.has_permission(p_company,'finanzas','ver') and
    private.has_permission(p_company,'ventas','ver') then
    v_result:=v_result||jsonb_build_object('receivables',
      (select coalesce(sum(s.total-coalesce(p.paid,0)),0)
        from public.ventas s left join lateral (
          select sum(sp.importe) paid from public.ventas_cobros sp
          where sp.empresa_id=s.empresa_id and sp.venta_id=s.id and not exists(
            select 1 from public.ventas_cobros_reversiones r
            where r.empresa_id=sp.empresa_id and r.cobro_id=sp.id)
        ) p on true where s.empresa_id=p_company));
  end if;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_operational_dashboard(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_result jsonb:='{}'::jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'inicio','ver') then
    raise exception 'Sin acceso al inicio' using errcode='42501'; end if;
  if private.has_permission(p_company,'ventas','ver') then
    v_result:=v_result||jsonb_build_object(
      'sales_30d',(select count(*) from public.ventas s
        where s.empresa_id=p_company and s.creado_en>=now()-interval '30 days'
          and s.total>coalesce((select sum(a.credito_total) from public.ventas_ajustes a
            where a.empresa_id=s.empresa_id and a.venta_id=s.id),0)),
      'revenue_30d',(select coalesce(sum(s.total-coalesce(a.credit,0)),0)
        from public.ventas s left join lateral (
          select sum(sa.credito_total) credit from public.ventas_ajustes sa
          where sa.empresa_id=s.empresa_id and sa.venta_id=s.id
        ) a on true
        where s.empresa_id=p_company and s.creado_en>=now()-interval '30 days')
    );
  end if;
  if private.has_permission(p_company,'finanzas','ver')
    and private.has_permission(p_company,'ventas','ver') then
    v_result:=v_result||jsonb_build_object(
      'receivables',(select coalesce(sum(greatest(0,s.total-coalesce(a.credit,0)
        -coalesce(p.paid,0))),0)
        from public.ventas s
        left join lateral (select sum(sa.credito_total) credit
          from public.ventas_ajustes sa
          where sa.empresa_id=s.empresa_id and sa.venta_id=s.id) a on true
        left join lateral (select sum(sp.importe) paid from public.ventas_cobros sp
          where sp.empresa_id=s.empresa_id and sp.venta_id=s.id
          and not exists(select 1 from public.ventas_cobros_reversiones r
            where r.empresa_id=sp.empresa_id and r.cobro_id=sp.id)) p on true
        where s.empresa_id=p_company)
    );
    if private.get_user_role(p_company)='administrador' then
      v_result:=v_result||jsonb_build_object(
        'profit_30d',(select coalesce(sum(
          (l.total_linea-coalesce(a.credit,0))
          -(l.cantidad-coalesce(a.quantity,0))*l.costo_unitario_estimado),0)
          from public.ventas_lineas l
          join public.ventas s on s.empresa_id=l.empresa_id and s.id=l.venta_id
          left join lateral (select sum(al.credito_importe) credit,
            sum(al.cantidad) filter(where al.reingresado) quantity
            from public.ventas_ajustes_lineas al where al.empresa_id=l.empresa_id
              and al.venta_id=l.venta_id and al.venta_linea=l.linea) a on true
          where s.empresa_id=p_company and s.creado_en>=now()-interval '30 days'
            and l.costo_unitario_estimado is not null)
      );
    end if;
  end if;
  if private.has_permission(p_company,'compras_resumen','ver') then
    v_result:=v_result||jsonb_build_object(
      'open_orders',(select count(*) from public.compras_ordenes o
        where o.empresa_id=p_company and o.estado in ('abierta','parcial')));
  end if;
  if private.has_permission(p_company,'produccion_resumen','ver') then
    v_result:=v_result||jsonb_build_object(
      'planned_runs',(select count(*) from public.produccion_planes p
        where p.empresa_id=p_company and p.estado='planificado'));
  end if;
  if private.has_permission(p_company,'items','ver')
    and private.has_permission(p_company,'stock_saldos','ver') then
    v_result:=v_result||jsonb_build_object(
      'low_stock',(select count(*) from public.stock_items i
        where i.empresa_id=p_company and i.activo and i.stock_minimo>0
          and i.stock_minimo>(select coalesce(sum(b.cantidad),0)
            from public.stock_saldos b where b.empresa_id=i.empresa_id
              and b.item_id=i.id)));
  end if;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_operational_report(p_company uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_result jsonb := '{}'::jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'reportes', 'ver') then
    raise exception 'Sin acceso a informes' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then
    raise exception 'Elegí un período de hasta un año';
  end if;
  if private.has_permission(p_company, 'ventas', 'ver') then
    v_result := v_result || jsonb_build_object(
      'sales', (select count(*) from public.ventas s
        where s.empresa_id = p_company
          and s.creado_en >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
          and s.creado_en < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')),
      'revenue', (select coalesce(sum(s.total - coalesce(a.credits, 0)), 0)
        from public.ventas s
        left join lateral (select sum(sa.credito_total) as credits
          from public.ventas_ajustes sa
          where sa.empresa_id = s.empresa_id and sa.venta_id = s.id) a on true
        where s.empresa_id = p_company
          and s.creado_en >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
          and s.creado_en < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')),
      'top_products', (select coalesce(jsonb_agg(t.entry order by t.qty desc), '[]'::jsonb)
        from (select jsonb_build_object('name', l.item_nombre,
            'quantity', sum(l.cantidad - coalesce(a.returned, 0))) as entry,
            sum(l.cantidad - coalesce(a.returned, 0)) as qty
          from public.ventas_lineas l
          join public.ventas s on s.empresa_id = l.empresa_id and s.id = l.venta_id
          left join lateral (select sum(al.cantidad) as returned
            from public.ventas_ajustes_lineas al
            where al.empresa_id = l.empresa_id and al.venta_id = l.venta_id
              and al.venta_linea = l.linea) a on true
          where s.empresa_id = p_company
            and s.creado_en >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
            and s.creado_en < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
          group by l.item_id, l.item_nombre
          order by qty desc limit 5) t)
    );
  end if;
  if private.has_permission(p_company,'produccion_resumen','ver') then
    v_result := v_result || jsonb_build_object(
      'finished_jobs', (select count(*) from public.produccion_fabricaciones r
        where r.empresa_id = p_company
          and r.creado_en >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
          and r.creado_en < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')),
      'jobs_in_progress', (select count(*) from public.produccion_ordenes j
        where j.empresa_id = p_company
          and j.estado in ('pendiente', 'en_proceso'))
    );
  end if;
  if private.has_permission(p_company,'compras_resumen','ver') then
    v_result := v_result || jsonb_build_object(
      'purchase_orders', (select count(*) from public.compras_ordenes o
        where o.empresa_id = p_company
          and o.creado_en >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
          and o.creado_en < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires'))
    );
  end if;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_price_list_history(p_company uuid, p_list uuid, p_item uuid, p_page integer DEFAULT 0)
 RETURNS TABLE(changed_at timestamp with time zone, item_id uuid, item_code text, item_name text, old_net_price numeric, new_net_price numeric, method text, method_value numeric, cost_snapshot numeric, source text, reason text, changed_by_label text, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
  perform private.price_require_cost_view(p_company);
  return query
  select h.cambiado_en, h.item_id, i.codigo, i.nombre, h.precio_neto_anterior, h.precio_neto_nuevo, h.metodo, h.metodo_valor,
    h.costo_copia, h.origen, h.motivo,
    coalesce(nullif(btrim((select p.nombre from public.ajustes_perfiles p where p.id = h.cambiado_por)), ''), 'Usuario'),
    count(*) over ()
  from public.ventas_listas_items_historial h
  join public.stock_items i on i.empresa_id = h.empresa_id and i.id = h.item_id
  where h.empresa_id = p_company and h.lista_precio_id = p_list and (p_item is null or h.item_id = p_item)
  order by h.cambiado_en desc, h.id
  limit 50 offset greatest(coalesce(p_page, 0), 0) * 50;
end;
$function$;

CREATE OR REPLACE FUNCTION public.erp_price_list_rows(p_company uuid, p_list uuid, p_search text DEFAULT ''::text, p_only_missing boolean DEFAULT false, p_page integer DEFAULT 0, p_page_size integer DEFAULT 50)
 RETURNS TABLE(item_id uuid, code text, name text, unit_symbol text, net_price numeric, source text, tax_percent numeric, gross_price numeric, content_quantity numeric, content_unit_symbol text, price_per_content numeric, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare v_tax numeric; v_size integer; v_term text;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'ventas', 'ver') then
    raise exception 'Sin acceso a ventas' using errcode = '42501';
  end if;
  if not exists (select 1 from public.ventas_listas_precios where empresa_id = p_company and id = p_list) then
    raise exception 'Lista inexistente';
  end if;
  select coalesce((select s.impuesto_porcentaje_predeterminado from public.ventas_precios_config s where s.empresa_id = p_company), 21)
    into v_tax;
  v_size := least(greatest(coalesce(p_page_size, 50), 1), 200);
  v_term := lower(btrim(coalesce(p_search, '')));
  return query
  select e.item_id, e.code, e.name, e.unit_symbol, e.net_price, e.source, coalesce(s.impuesto_porcentaje, v_tax),
    round(e.net_price * (1 + coalesce(s.impuesto_porcentaje, v_tax) / 100), 2), s.contenido_cantidad, cu.simbolo,
    case when s.contenido_cantidad is not null and e.net_price is not null
      then round(e.net_price / s.contenido_cantidad, 4) end,
    count(*) over ()
  from private.price_effective(p_company, p_list, v_term) e
  left join public.ventas_items_config s on s.empresa_id = p_company and s.item_id = e.item_id
  left join public.stock_unidades cu on cu.empresa_id = s.empresa_id and cu.id = s.contenido_unidad_id
  where (not coalesce(p_only_missing, false) or e.net_price is null)
  order by (e.net_price is null) desc, e.name, e.item_id
  limit v_size offset greatest(coalesce(p_page, 0), 0) * v_size;
end;
$function$;

commit;

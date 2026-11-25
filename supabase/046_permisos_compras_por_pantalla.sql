-- Dromux ERP · 046 · Compras por pantalla: funciones y políticas exigen el permiso de CADA pantalla y los costos de
-- materiales exigen costs_materials (cierra H-011).
-- ESTADO: PREPARADA, NO APLICADA. Aplicar solo con autorización del propietario, con respaldo y en este orden:
-- respaldo -> esta migración -> supabase/verificaciones/046_comprobaciones.sql -> pruebas_roles_empresas.sql (grupo 11)
-- -> publicar el frontend (el frontend nuevo exige las pantallas por separado; publicarlo antes de aplicar es seguro:
-- con la 045 los roles actuales ya tienen todas las pantallas).
-- Deshacer: supabase/reparacion/0_deshacer_046.sql (usa las copias private.*_pre046; no usar si 047 o posterior ya está aplicada).
-- Diseño: docs/ai/DISENO_045_PERMISOS_FINOS.md §5. Decisiones del propietario (24/11/2026) en docs/ai/AVANCE_FASES.md.
--
-- Método (igual que 037): lee la definición VIGENTE de cada función con pg_get_functiondef, reemplaza SOLO la llamada
-- private.has_permission(p_company,'purchases',<acción>) según un mapa explícito función -> permiso, y ABORTA sin cambiar
-- nada si una función no tiene exactamente una aparición de esa llamada. No reescribe cuerpos desde archivos locales.
-- Las políticas (17) se re-apuntan con ALTER POLICY, también con mapa explícito y conteo de apariciones.
--
-- Mapa (función -> pantalla):
--   Resumen de compras (purchases_overview): tableros (sección de compras) y reporte operativo.
--   Pedidos internos (purchase_requests): pedir/ver opciones; rechazar = 'manage' + 'update'; convertir en orden = 'manage' +
--     purchases_orders:insert. 'manage' = "Gestionar" (decidir sobre pedidos ajenos); la política de lectura muestra TODOS los
--     pedidos a quien tiene 'manage' y solo los propios a quien solo puede pedir. 'manage' no lo usaba nada más.
--   Órdenes de compra (purchases_orders): crear, cancelar, recibir, líneas por recibir, proveedores y cotizaciones por ítem.
--   Proveedores (purchases_suppliers): directorio, catálogo de cotizaciones, ajuste de precios, tipos de cambio, proveedor
--     preferido, importación de ítems que asocia proveedor.
--   Compras y cuentas (purchases_accounts): deuda, órdenes de pago (además de finance, como hasta hoy) y estadística.
--   Costos de materiales (costs_materials): can_see_reference_cost (H-011) y item_cost_context (costo del proveedor preferido
--     en la ficha del ítem). exchange_rate_overview y las políticas de tipos de cambio también las lee quien tiene costs_materials
--     (la ficha del ítem muestra el tipo de cambio).
--   NO se tocan (decidido): erp_replenishment_forecast (pertenece a Producción, 047), has_permission, create_company,
--     private.cleanup_target, cancel_purchase_request (ya exige purchase_requests:update y es solo para los pedidos propios).
-- Cambios de acceso respecto de hoy con los roles existentes: NINGUNO salvo (a) el Vendedor deja de ver costos de materiales
--   (H-011, intención de la migración) y (b) quien tenga purchases:read pero no purchase_requests:manage ve solo sus pedidos
--   (hoy no existe tal rol). El Vendedor conserva convertir (tiene 'manage' por reparto de 045) y NO puede rechazar
--   (no tiene 'update'), igual que hoy.

begin;

-- ---------------------------------------------------------------------------------------------
-- 0) Copias de seguridad para deshacer (sin acceso para la API)
-- ---------------------------------------------------------------------------------------------
create table private.function_defs_pre046 (signature text primary key, definition text not null);
create table private.policy_defs_pre046 (
  tbl text not null, policy text not null, cmd text not null, qual text, with_check text, primary key (tbl, policy)
);
create table private.permission_catalog_pre046 as select * from public.permission_catalog;
alter table private.function_defs_pre046 enable row level security;
alter table private.policy_defs_pre046 enable row level security;
alter table private.permission_catalog_pre046 enable row level security;
revoke all on private.function_defs_pre046, private.policy_defs_pre046, private.permission_catalog_pre046
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 1) Funciones: mapa explícito (kind: one = un permiso; or = cualquiera de dos; and = los dos)
-- ---------------------------------------------------------------------------------------------
create temporary table _map_046 (
  signature text primary key, old_action text not null, kind text not null check (kind in ('one', 'or', 'and')),
  res_a text not null, act_a text not null, res_b text, act_b text
) on commit drop;

insert into _map_046 (signature, old_action, kind, res_a, act_a, res_b, act_b) values
  -- Proveedores
  ('public.add_exchange_rate_type(uuid,text)', 'update', 'one', 'purchases_suppliers', 'update', null, null),
  ('public.add_exchange_rate(uuid,uuid,numeric,date)', 'update', 'one', 'purchases_suppliers', 'update', null, null),
  ('public.adjust_supplier_prices(uuid,uuid,uuid,numeric,uuid)', 'update', 'one', 'purchases_suppliers', 'update', null, null),
  ('public.set_preferred_supplier(uuid,uuid,uuid)', 'update', 'one', 'purchases_suppliers', 'update', null, null),
  ('public.save_supplier_quote(uuid,uuid,uuid,numeric,text,text,uuid,numeric,timestamp with time zone,boolean)', 'update', 'one', 'purchases_suppliers', 'update', null, null),
  ('public.supplier_adjustment_preview(uuid,uuid,uuid,numeric)', 'update', 'one', 'purchases_suppliers', 'update', null, null),
  ('public.supplier_directory(uuid,text,integer)', 'read', 'one', 'purchases_suppliers', 'read', null, null),
  ('public.supplier_quote_catalog(uuid,uuid,uuid,text,integer)', 'read', 'one', 'purchases_suppliers', 'read', null, null),
  ('private.prepare_item_import(uuid,jsonb,uuid)', 'update', 'one', 'purchases_suppliers', 'update', null, null),
  ('public.exchange_rate_overview(uuid)', 'read', 'or', 'purchases_suppliers', 'read', 'costs_materials', 'read'),
  -- Órdenes de compra
  ('public.cancel_purchase_order(uuid,uuid)', 'update', 'one', 'purchases_orders', 'update', null, null),
  ('public.create_purchase_order_once(uuid,uuid,text,jsonb,uuid)', 'insert', 'one', 'purchases_orders', 'insert', null, null),
  ('public.create_purchase_order(uuid,uuid,text,jsonb)', 'insert', 'one', 'purchases_orders', 'insert', null, null),
  ('public.receive_purchase_order(uuid,uuid,uuid,text,jsonb)', 'insert', 'one', 'purchases_orders', 'insert', null, null),
  ('public.purchase_receivable_lines(uuid,uuid)', 'read', 'one', 'purchases_orders', 'read', null, null),
  ('public.purchase_suppliers_for_items(uuid,uuid[])', 'read', 'one', 'purchases_orders', 'read', null, null),
  ('public.purchase_item_options(uuid,text)', 'read', 'or', 'purchases_orders', 'read', 'purchases_suppliers', 'read'),
  ('public.purchase_material_options(uuid,text,uuid)', 'read', 'or', 'purchases_orders', 'read', 'purchases_suppliers', 'read'),
  ('public.purchase_supplier_quotes(uuid,uuid,uuid)', 'read', 'or', 'purchases_orders', 'read', 'purchases_suppliers', 'read'),
  ('public.supplier_cost_comparison(uuid,uuid,uuid)', 'read', 'or', 'purchases_orders', 'read', 'purchases_suppliers', 'read'),
  -- Pedidos internos
  ('public.create_purchase_request(uuid,text,date,text,jsonb,uuid)', 'insert', 'one', 'purchase_requests', 'insert', null, null),
  ('public.purchase_request_item_options(uuid,text)', 'insert', 'one', 'purchase_requests', 'insert', null, null),
  ('public.reject_purchase_request(uuid,uuid,text)', 'update', 'and', 'purchase_requests', 'manage', 'purchase_requests', 'update'),
  ('public.convert_purchase_request(uuid,uuid,uuid,text,jsonb,uuid)', 'insert', 'and', 'purchase_requests', 'manage', 'purchases_orders', 'insert'),
  -- Compras y cuentas (finance se mantiene en las funciones que ya lo exigían)
  ('public.confirm_supplier_payment_order(uuid,uuid)', 'read', 'one', 'purchases_accounts', 'read', null, null),
  ('public.create_supplier_payment_order(uuid,uuid,uuid,date,text,text,jsonb,uuid)', 'read', 'one', 'purchases_accounts', 'read', null, null),
  ('public.supplier_account(uuid,uuid,date,date,integer)', 'read', 'one', 'purchases_accounts', 'read', null, null),
  ('public.supplier_payable_orders(uuid,uuid,integer)', 'read', 'one', 'purchases_accounts', 'read', null, null),
  ('public.supplier_purchase_statistics(uuid,date,date)', 'read', 'one', 'purchases_accounts', 'read', null, null),
  -- Resumen de compras (secciones de compras de funciones compartidas; si falta, la sección sale vacía)
  ('public.erp_dashboard(uuid)', 'read', 'one', 'purchases_overview', 'read', null, null),
  ('public.erp_operational_dashboard(uuid)', 'read', 'one', 'purchases_overview', 'read', null, null),
  ('public.erp_operational_report(uuid,date,date)', 'read', 'one', 'purchases_overview', 'read', null, null),
  -- Costos de materiales (H-011)
  ('private.can_see_reference_cost(uuid)', 'read', 'one', 'costs_materials', 'read', null, null),
  ('public.item_cost_context(uuid,uuid)', 'read', 'one', 'costs_materials', 'read', null, null);

do $$
declare
  r record;
  v_def text;
  v_new text;
  v_pat text;
  v_repl text;
  v_count integer;
  v_before text;
  v_after text;
begin
  if (select count(*) from _map_046) <> 34 then
    raise exception 'El mapa de la 046 debe tener 34 funciones (tiene %).', (select count(*) from _map_046);
  end if;
  for r in select * from _map_046 order by signature loop
    v_def := pg_get_functiondef(r.signature::regprocedure);
    insert into private.function_defs_pre046 (signature, definition) values (r.signature, v_def);
    -- Llamada a reemplazar: private.has_permission(p_company,'purchases','<acción>') con espacios opcionales.
    v_pat := 'private\.has_permission\(\s*p_company\s*,\s*''purchases''\s*,\s*''' || r.old_action || '''\s*\)';
    select count(*) into v_count from regexp_matches(v_def, v_pat, 'g');
    if v_count <> 1 then
      raise exception 'La función % tiene % apariciones de la llamada a reemplazar (se esperaba 1). No se cambió nada.',
        r.signature, v_count;
    end if;
    v_repl := case r.kind
      when 'one' then format('private.has_permission(p_company,%L,%L)', r.res_a, r.act_a)
      when 'or' then format('(private.has_permission(p_company,%L,%L) or private.has_permission(p_company,%L,%L))',
        r.res_a, r.act_a, r.res_b, r.act_b)
      else format('(private.has_permission(p_company,%L,%L) and private.has_permission(p_company,%L,%L))',
        r.res_a, r.act_a, r.res_b, r.act_b)
    end;
    v_new := regexp_replace(v_def, v_pat, v_repl);
    -- Atributos de seguridad antes y después: deben quedar idénticos (SECURITY DEFINER, search_path, EXECUTE de anon y authenticated).
    select prosecdef::text || coalesce(proconfig::text, '') || has_function_privilege('anon', oid, 'execute')::text
      || has_function_privilege('authenticated', oid, 'execute')::text into v_before
      from pg_proc where oid = r.signature::regprocedure;
    execute v_new;
    select prosecdef::text || coalesce(proconfig::text, '') || has_function_privilege('anon', oid, 'execute')::text
      || has_function_privilege('authenticated', oid, 'execute')::text into v_after
      from pg_proc where oid = r.signature::regprocedure;
    if v_before is distinct from v_after then
      raise exception 'Cambió la seguridad de % (antes %, después %). No se aplicó nada.', r.signature, v_before, v_after;
    end if;
    if position(r.res_a in pg_get_functiondef(r.signature::regprocedure)) = 0
      or pg_get_functiondef(r.signature::regprocedure) ~ v_pat then
      raise exception 'No se pudo comprobar el nuevo permiso en %', r.signature;
    end if;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------------------------
-- 2) Políticas: mapa explícito (se comprueba que cada una tenga las apariciones esperadas del permiso viejo)
-- ---------------------------------------------------------------------------------------------
create temporary table _pol_046 (
  tbl text not null, policy text not null, new_using text, new_check text, esperado integer not null, primary key (tbl, policy)
) on commit drop;

insert into _pol_046 (tbl, policy, new_using, new_check, esperado) values
  -- Tipos de cambio: Proveedores o quien ve costos de materiales (la ficha del ítem los muestra)
  ('exchange_rate_types', 'exchange_rate_types_read',
    '(select private.has_permission(company_id,''purchases_suppliers'',''read'')) or (select private.has_permission(company_id,''costs_materials'',''read''))', null, 1),
  ('exchange_rates', 'exchange_rates_read',
    '(select private.has_permission(company_id,''purchases_suppliers'',''read'')) or (select private.has_permission(company_id,''costs_materials'',''read''))', null, 1),
  -- Órdenes y recepciones: Órdenes de compra o Resumen de compras (el resumen lista órdenes)
  ('purchase_orders', 'purchase_orders_read',
    '(select private.has_permission(company_id,''purchases_orders'',''read'')) or (select private.has_permission(company_id,''purchases_overview'',''read''))', null, 1),
  ('purchase_order_lines', 'purchase_lines_read',
    '(select private.has_permission(company_id,''purchases_orders'',''read'')) or (select private.has_permission(company_id,''purchases_overview'',''read''))', null, 1),
  ('purchase_receipts', 'purchase_receipts_read',
    '(select private.has_permission(company_id,''purchases_orders'',''read'')) or (select private.has_permission(company_id,''purchases_overview'',''read''))', null, 1),
  ('purchase_receipt_lines', 'purchase_receipt_lines_read',
    '(select private.has_permission(company_id,''purchases_orders'',''read'')) or (select private.has_permission(company_id,''purchases_overview'',''read''))', null, 1),
  -- Pedidos: todos los ven quienes gestionan; el resto solo los propios (soporte: private.support_session_active no es ejecutable por authenticated, no se usa)
  ('purchase_requests', 'purchase_requests_read',
    '(select private.has_permission(company_id,''purchase_requests'',''manage'')) or (requested_by = (select auth.uid()) and (select private.has_permission(company_id,''purchase_requests'',''read'')))', null, 1),
  -- Catálogo de cotizaciones y ajustes: Proveedores
  ('supplier_items', 'supplier_items_read',
    '(select private.has_permission(company_id,''purchases_suppliers'',''read''))', null, 1),
  ('supplier_items', 'supplier_items_insert', null,
    '(select private.has_permission(company_id,''purchases_suppliers'',''update''))', 1),
  ('supplier_items', 'supplier_items_update',
    '(select private.has_permission(company_id,''purchases_suppliers'',''update''))',
    '(select private.has_permission(company_id,''purchases_suppliers'',''update''))', 2),
  ('supplier_items', 'supplier_items_delete',
    '(select private.has_permission(company_id,''purchases_suppliers'',''update''))', null, 1),
  ('supplier_price_adjustments', 'supplier_price_adjustments_read',
    '(select private.has_permission(company_id,''purchases_suppliers'',''read''))', null, 1),
  -- Proveedores: lo ven las pantallas que los nombran (Proveedores, Órdenes, Cuentas, Resumen); escribe solo Proveedores
  ('suppliers', 'suppliers_read',
    '(select private.has_permission(company_id,''purchases_suppliers'',''read'')) or (select private.has_permission(company_id,''purchases_orders'',''read'')) or (select private.has_permission(company_id,''purchases_accounts'',''read'')) or (select private.has_permission(company_id,''purchases_overview'',''read''))', null, 1),
  ('suppliers', 'suppliers_insert', null,
    '(select private.has_permission(company_id,''purchases_suppliers'',''insert''))', 1),
  ('suppliers', 'suppliers_update',
    '(select private.has_permission(company_id,''purchases_suppliers'',''update''))',
    '(select private.has_permission(company_id,''purchases_suppliers'',''update''))', 2),
  -- Órdenes de pago: finanzas + Compras y cuentas (como hasta hoy finance + purchases)
  ('supplier_payment_orders', 'payment_orders_read',
    'private.has_permission(company_id,''finance'',''read'') and private.has_permission(company_id,''purchases_accounts'',''read'')', null, 1),
  ('supplier_payment_order_lines', 'payment_order_lines_read',
    'private.has_permission(company_id,''finance'',''read'') and private.has_permission(company_id,''purchases_accounts'',''read'')', null, 1);

do $$
declare
  r record;
  v_pol record;
  v_count integer;
  v_sql text;
begin
  for r in select * from _pol_046 order by tbl, policy loop
    select * into v_pol from pg_policies where schemaname = 'public' and tablename = r.tbl and policyname = r.policy;
    if not found then
      raise exception 'No existe la política % de %. No se cambió nada.', r.policy, r.tbl;
    end if;
    v_count := (select count(*) from regexp_matches(coalesce(v_pol.qual, '') || ' ' || coalesce(v_pol.with_check, ''),
      '''purchases''::text', 'g'));
    if v_count <> r.esperado then
      raise exception 'La política % de % tiene % apariciones de ''purchases'' (se esperaban %). No se cambió nada.',
        r.policy, r.tbl, v_count, r.esperado;
    end if;
    insert into private.policy_defs_pre046 (tbl, policy, cmd, qual, with_check)
      values (r.tbl, r.policy, v_pol.cmd, v_pol.qual, v_pol.with_check);
    v_sql := format('alter policy %I on public.%I', r.policy, r.tbl)
      || case when r.new_using is not null then ' using (' || r.new_using || ')' else '' end
      || case when r.new_check is not null then ' with check (' || r.new_check || ')' else '' end;
    execute v_sql;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------------------------
-- 3) Catálogo: "manage" solo existe donde se usa (Pedidos internos: Gestionar); pantallas exigidas por el servidor
-- ---------------------------------------------------------------------------------------------
update public.permission_catalog set actions = array_remove(actions, 'manage')
where resource <> 'purchase_requests' and 'manage' = any (actions);

update public.permission_catalog set enforced = true
where resource in ('purchases', 'purchases_overview', 'purchase_requests', 'purchases_orders', 'purchases_suppliers',
  'purchases_accounts', 'costs_materials');

-- ---------------------------------------------------------------------------------------------
-- 4) Comprobaciones finales (abortan toda la migración si algo quedó mal)
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_left text;
begin
  -- Ninguna política conserva el permiso de módulo de Compras.
  select string_agg(tablename || '.' || policyname, ', ') into v_left from pg_policies
  where schemaname = 'public' and coalesce(qual, '') || coalesce(with_check, '') like '%''purchases''::text%';
  if v_left is not null then raise exception 'Quedaron políticas con el permiso purchases: %', v_left; end if;

  -- Ninguna función (salvo la reposición, que pasa a 047) exige ya el módulo completo de Compras.
  select string_agg(p.oid::regprocedure::text, ', ') into v_left
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.prokind = 'f'
    and p.proname not in ('erp_replenishment_forecast', 'has_permission')
    and pg_get_functiondef(p.oid) ~ 'has_permission\(\s*[a-z_]+\s*,\s*''purchases''\s*,';
  if v_left is not null then raise exception 'Quedaron funciones con el permiso purchases: %', v_left; end if;

  -- Respaldo completo: 34 funciones y 17 políticas.
  if (select count(*) from private.function_defs_pre046) <> 34 or (select count(*) from private.policy_defs_pre046) <> 17 then
    raise exception 'El respaldo para deshacer está incompleto.';
  end if;
end
$$;

commit;

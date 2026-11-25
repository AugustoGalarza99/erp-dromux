-- Dromux ERP · 048 · Stock (lecturas) y Archivados por pantalla.
-- ESTADO: PREPARADA, NO APLICADA. Requiere 045, 046, 046b, 046c, 047 y 047b aplicadas. Aplicar con respaldo en este orden:
-- respaldo -> esta migración -> verificaciones/048_comprobaciones.sql -> pruebas_roles_empresas.sql (grupo 13) -> publicar frontend.
-- Deshacer: reparacion/0_deshacer_048.sql (no usar si una migración posterior ya está aplicada).
--
-- PROBLEMA QUE RESUELVE (hallazgo H-O1, 25/11): con un rol de Stock PARCIAL (p. ej. solo "Stock por depósito") el servidor seguía pidiendo el
-- módulo 'stock' completo, que la 045 solo deriva cuando el rol tiene TODAS las pantallas. Resultado visto con un operario real: existencias
-- en blanco y "Asignado 0" / "Falta" falsos en las órdenes de fabricación.
--
-- ALCANCE (decisión de diseño; ver DISENO_048_STOCK_POR_PANTALLA.md):
--   LECTURAS por pantalla:
--     Stock por depósito (stock_levels) / Resumen de stock (inventory) / Remitos (stock_delivery_notes): saldos y lotes
--       (stock_balances, stock_lots, stock_lot_balances, stock_lot_openings) y stock_summary.
--     Movimientos (stock_movements): stock_movements y stock_operations.
--     Remitos (stock_delivery_notes): delivery_notes, delivery_note_lines, delivery_note_reversals (más los remitos de fabricación
--       para quien ve Órdenes, como ya hacía la 047).
--     Opciones de ítems, depósitos y lotes (stock_*_options, stock_lot_breakdown): cualquiera de las 4 pantallas de Stock.
--     Reservas de fabricación: producción (Órdenes o Alcanza) Y Stock por depósito (misma decisión que Reposición en la 047).
--     erp_can_manufacture, erp_replenishment_forecast, recalculate_production_reservations, alertas de producción y tablero
--       operativo: Stock por depósito en lugar del módulo 'stock'.
--   ARCHIVADOS (private.cleanup_target): cada recurso pide el permiso de eliminar de SU pantalla (hoy: módulo completo).
--   CATÁLOGO: ítems, unidades, categorías, depósitos (ya eran por recurso en las políticas) y las pantallas de Stock pasan a 'exigido'.
--   NO SE TOCA: issue_sale_delivery_note (remito de venta: lote de Ventas).
--   NO SE TOCA (queda para una migración posterior, 048b): las ESCRITURAS que mueven stock (post_stock_operation y todo el que la llama:
--     remitos, producción, compras, ventas). Siguen pidiendo stock:insert/delete a nivel módulo, así que un rol parcial de Stock puede
--     VER pero no registrar movimientos. Razón: todas las funciones de flujo llaman a post_stock_operation, cuyo control interno no distingue
--     quién la invoca; cambiarlo sin una marca de "flujo interno" abriría el ingreso manual a roles de solo remitos.
-- Cambios de acceso reales (para la revisión): (a) un rol con solo Stock por depósito (ver) ahora VE saldos, lotes y reservas; (b) un rol con
--   solo Movimientos no ve saldos ni lotes por tabla ni por stock_summary / opciones de lotes, PERO el propio historial de movimientos trae
--   balance_after y el lote: quien ve Movimientos puede reconstruir el saldo (aceptado; revisión crítica P1-1); (b2) los roles que ya tenían
--   inventory:read (Resumen de stock, permiso de módulo antes de la 045) y NO tenían stock:read pasan a ver saldos y lotes: la comprobación 7
--   los lista para revisarlos ANTES de aplicar; (c) un rol con permiso de eliminar en una sola
--   pantalla de Producción/Remitos/Proveedores puede archivar SUS registros; (d) un rol con solo "Resumen de producción" no cambia.
begin;

-- Bloqueos en orden fijo (evita el "deadlock detected" visto al aplicarla con la app abierta): se toman TODOS al principio, en el mismo orden,
-- y si no se consiguen en 20 s la migración se cancela entera (sin cambios) en vez de quedarse trabada. Aplicar con la app cerrada.
set local lock_timeout = '20s';
lock table public.delivery_notes, public.delivery_note_lines, public.delivery_note_reversals,
  public.stock_balances, public.stock_lot_balances, public.stock_lot_openings, public.stock_lots,
  public.stock_movements, public.stock_operations,
  public.production_job_reservations, public.production_reservation_locations
  in access exclusive mode;

create table private.function_defs_pre048 (signature text primary key, definition text not null);
create table private.policy_defs_pre048 (tbl text not null, policy text not null, qual text, with_check text, primary key (tbl, policy));
create table private.permission_catalog_pre048 as select * from public.permission_catalog;
alter table private.function_defs_pre048 enable row level security;
alter table private.policy_defs_pre048 enable row level security;
alter table private.permission_catalog_pre048 enable row level security;
revoke all on private.function_defs_pre048, private.policy_defs_pre048, private.permission_catalog_pre048 from public, anon, authenticated;

-- 1) Funciones: se reemplaza UNA aparición de has_permission(p_company,'stock','read') por la expresión de la columna `repl`.
create temporary table _m (signature text primary key, repl text not null) on commit drop;
insert into _m values
  ('public.stock_summary(uuid,integer,text)',
   '(private.has_permission(p_company,''stock_levels'',''read'') or private.has_permission(p_company,''inventory'',''read''))'),
  ('public.stock_item_options(uuid,text)',
   '(private.has_permission(p_company,''stock_levels'',''read'') or private.has_permission(p_company,''stock_delivery_notes'',''read'') or private.has_permission(p_company,''stock_movements'',''read'') or private.has_permission(p_company,''inventory'',''read''))'),
  ('public.stock_warehouse_options(uuid,text)',
   '(private.has_permission(p_company,''stock_levels'',''read'') or private.has_permission(p_company,''stock_delivery_notes'',''read'') or private.has_permission(p_company,''stock_movements'',''read'') or private.has_permission(p_company,''inventory'',''read''))'),
  -- Lotes con cantidades: SIN Movimientos (devuelven saldo por lote; revisión crítica P1-1).
  ('public.stock_lot_options(uuid,uuid,uuid)',
   '(private.has_permission(p_company,''stock_levels'',''read'') or private.has_permission(p_company,''stock_delivery_notes'',''read'') or private.has_permission(p_company,''inventory'',''read''))'),
  ('public.stock_lot_breakdown(uuid,uuid)',
   '(private.has_permission(p_company,''stock_levels'',''read'') or private.has_permission(p_company,''stock_delivery_notes'',''read'') or private.has_permission(p_company,''inventory'',''read''))'),
  ('public.erp_can_manufacture(uuid,uuid,numeric)', 'private.has_permission(p_company,''stock_levels'',''read'')'),
  ('public.erp_replenishment_forecast(uuid)', 'private.has_permission(p_company,''stock_levels'',''read'')'),
  ('public.recalculate_production_reservations(uuid)', 'private.has_permission(p_company,''stock_levels'',''read'')'),
  ('public.erp_production_alerts(uuid)', 'private.has_permission(p_company,''stock_levels'',''read'')'),
  ('private.erp_production_alerts(uuid)', 'private.has_permission(p_company,''stock_levels'',''read'')'),
  ('public.erp_operational_dashboard(uuid)', 'private.has_permission(p_company,''stock_levels'',''read'')');

do $$
declare
  r record; d text; n int; v_before text; v_after text;
  v_pat constant text := 'private\.has_permission\(\s*p_company\s*,\s*''stock''\s*,\s*''read''\s*\)';
begin
  if (select count(*) from _m) <> 11 then raise exception 'El mapa de la 048 debe tener 11 filas (tiene %).', (select count(*) from _m); end if;
  for r in select * from _m order by signature loop
    d := pg_get_functiondef(r.signature::regprocedure);
    insert into private.function_defs_pre048 values (r.signature, d);
    select count(*) into n from regexp_matches(d, v_pat, 'g');
    if n <> 1 then raise exception '% tiene % apariciones de stock/read (se esperaba 1). No se cambió nada.', r.signature, n; end if;
    select prosecdef::text || coalesce(proconfig::text,'') || has_function_privilege('anon', oid, 'execute')::text
      || has_function_privilege('authenticated', oid, 'execute')::text into v_before from pg_proc where oid = r.signature::regprocedure;
    -- regexp_replace interpreta "\" y "&" del reemplazo: la expresión no los contiene (se comprueba).
    if r.repl ~ '[\\&]' then raise exception 'Reemplazo inválido para %', r.signature; end if;
    execute regexp_replace(d, v_pat, r.repl);
    select prosecdef::text || coalesce(proconfig::text,'') || has_function_privilege('anon', oid, 'execute')::text
      || has_function_privilege('authenticated', oid, 'execute')::text into v_after from pg_proc where oid = r.signature::regprocedure;
    if v_before is distinct from v_after then raise exception 'Cambió la seguridad de %', r.signature; end if;
    if pg_get_functiondef(r.signature::regprocedure) ~ v_pat then raise exception 'No se aplicó el cambio en %', r.signature; end if;
  end loop;
end $$;

-- 2) Políticas de lectura: expresión nueva explícita; se comprueba que la vigente tenga exactamente 1 aparición de 'stock'::text.
create temporary table _pol (tbl text, policy text, new_using text not null, primary key (tbl, policy)) on commit drop;
insert into _pol values
  ('stock_balances','stock_balances_read',
   '(select private.has_permission(company_id,''stock_levels'',''read'')) or (select private.has_permission(company_id,''inventory'',''read'')) or (select private.has_permission(company_id,''stock_delivery_notes'',''read''))'),
  ('stock_lot_balances','stock_lot_balances_read',
   '(select private.has_permission(company_id,''stock_levels'',''read'')) or (select private.has_permission(company_id,''inventory'',''read'')) or (select private.has_permission(company_id,''stock_delivery_notes'',''read''))'),
  ('stock_lot_openings','stock_lot_openings_read',
   '(select private.has_permission(company_id,''stock_levels'',''read'')) or (select private.has_permission(company_id,''inventory'',''read'')) or (select private.has_permission(company_id,''stock_delivery_notes'',''read''))'),
  ('stock_lots','stock_lots_read',
   '(select private.has_permission(company_id,''stock_levels'',''read'')) or (select private.has_permission(company_id,''inventory'',''read'')) or (select private.has_permission(company_id,''stock_delivery_notes'',''read''))'),
  ('stock_movements','stock_movements_read',
   '(select private.has_permission(company_id,''stock_movements'',''read''))'),
  ('stock_operations','stock_operations_read',
   '(select private.has_permission(company_id,''stock_movements'',''read''))'),
  ('delivery_notes','delivery_notes_read',
   '(select private.has_permission(company_id,''stock_delivery_notes'',''read'')) or (kind = ''production'' and (select private.has_permission(company_id,''production_orders'',''read'')))'),
  ('delivery_note_lines','delivery_lines_read',
   'exists (select 1 from public.delivery_notes d where d.company_id = delivery_note_lines.company_id and d.id = delivery_note_lines.note_id and (private.has_permission(d.company_id,''stock_delivery_notes'',''read'') or (d.kind = ''production'' and private.has_permission(d.company_id,''production_orders'',''read''))))'),
  ('delivery_note_reversals','delivery_reversals_read',
   'exists (select 1 from public.delivery_notes d where d.company_id = delivery_note_reversals.company_id and d.id = delivery_note_reversals.note_id and (private.has_permission(d.company_id,''stock_delivery_notes'',''read'') or (d.kind = ''production'' and private.has_permission(d.company_id,''production_orders'',''read''))))'),
  ('production_job_reservations','production_reservations_read',
   '((select private.has_permission(company_id,''production_availability'',''read'')) or (select private.has_permission(company_id,''production_orders'',''read''))) and (select private.has_permission(company_id,''stock_levels'',''read''))'),
  ('production_reservation_locations','reservation_locations_read',
   '((select private.has_permission(company_id,''production_availability'',''read'')) or (select private.has_permission(company_id,''production_orders'',''read''))) and (select private.has_permission(company_id,''stock_levels'',''read''))');

do $$
declare r record; v record; n int;
begin
  if (select count(*) from _pol) <> 11 then raise exception 'El mapa de políticas debe tener 11 filas.'; end if;
  for r in select * from _pol order by tbl, policy loop
    select * into v from pg_policies where schemaname='public' and tablename=r.tbl and policyname=r.policy and cmd='SELECT';
    if not found then raise exception 'No existe la política de lectura % de %.', r.policy, r.tbl; end if;
    select count(*) into n from regexp_matches(coalesce(v.qual,'') || ' ' || coalesce(v.with_check,''), 'has_permission\([^,]+,\s*''stock''::text', 'g');
    if n <> 1 then raise exception 'La política % de % tiene % apariciones de ''stock'' (se esperaba 1).', r.policy, r.tbl, n; end if;
    insert into private.policy_defs_pre048 values (r.tbl, r.policy, v.qual, v.with_check);
    execute format('alter policy %I on public.%I using (%s)', r.policy, r.tbl, r.new_using);
  end loop;
end $$;

-- 3) Archivados: cada recurso pide el permiso de eliminar de su pantalla (la definición vigente se guarda para deshacer).
do $$
declare d text;
begin
  d := pg_get_functiondef('private.cleanup_target(text)'::regprocedure);
  if d !~ '\(''items'',''items'',''id'',''items''\)' or d !~ '\(''delivery_notes'',''delivery_notes'',''id'',''stock''\)'
     or d !~ '\(''jobs'',''production_jobs'',''id'',''production''\)'
     or (select count(*) from regexp_matches(d, '\(''[a-z_]+'',''[a-z_]+'',''[a-z_]+'',''[a-z_]+''\)', 'g')) <> 7 then
    raise exception 'private.cleanup_target no tiene la forma esperada. No se cambió nada.';
  end if;
  insert into private.function_defs_pre048 values ('private.cleanup_target(text)', d);
end $$;

create or replace function private.cleanup_target(p_resource text)
returns table(table_name text, id_field text, permission text)
language sql immutable set search_path = '' as $$
  select t.table_name, t.id_field, t.permission from (values
    ('items', 'items', 'id', 'items'),
    ('exchange_types', 'exchange_rate_types', 'id', 'purchases_suppliers'),
    ('formulas', 'production_formulas', 'product_id', 'production_formulas'),
    ('jobs', 'production_jobs', 'id', 'production_orders'),
    ('runs', 'production_runs', 'id', 'production_orders'),
    ('plans', 'production_plans', 'id', 'production_planning'),
    ('delivery_notes', 'delivery_notes', 'id', 'stock_delivery_notes')
  ) t(resource, table_name, id_field, permission) where resource = p_resource
$$;
-- CREATE OR REPLACE conserva los permisos, pero se deja explícito que nadie más la ejecuta.
revoke all on function private.cleanup_target(text) from public, anon, authenticated;

-- 4) Catálogo: pantallas cuyas LECTURAS exige el servidor. (Las escrituras de Stock siguen a nivel módulo: ver cabecera.)
update public.permission_catalog set enforced = true
where resource in ('inventory','items','stock','stock_levels','stock_movements','stock_delivery_notes','units','categories','warehouses');

-- 5) Comprobaciones finales
do $$
declare v_left text;
begin
  select string_agg(tablename || '.' || policyname, ', ') into v_left from pg_policies
  where schemaname='public' and cmd='SELECT' and coalesce(qual,'') || coalesce(with_check,'') ~ 'has_permission\([^,]+,\s*''stock''::text';
  if v_left is not null then raise exception 'Quedaron políticas de lectura con el permiso stock: %', v_left; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v_left
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public','private') and p.prokind='f' and p.proname <> 'has_permission'
    and p.proname <> 'issue_sale_delivery_note'   -- remito de venta: pertenece al lote de Ventas (pide ventas + stock a nivel módulo)
    and pg_get_functiondef(p.oid) ~ 'has_permission\(\s*[a-z_]+\s*,\s*''stock''\s*,\s*''read''';
  if v_left is not null then raise exception 'Quedaron funciones con stock/read: %', v_left; end if;
  if (select count(*) from private.function_defs_pre048) <> 12 or (select count(*) from private.policy_defs_pre048) <> 11 then
    raise exception 'El respaldo para deshacer está incompleto.';
  end if;
end $$;

commit;

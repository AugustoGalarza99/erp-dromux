-- Dromux ERP · 047 · Producción por pantalla + costs_production (costos de producción solo para quien el administrador autorice).
-- ESTADO: PREPARADA, NO APLICADA. Requiere 045, 046, 046b y 046c aplicadas. Aplicar con respaldo en este orden:
-- respaldo -> esta migración -> verificaciones/047_comprobaciones.sql -> pruebas_roles_empresas.sql (grupo 12) -> publicar frontend.
-- Deshacer: reparacion/0_deshacer_047.sql (no usar si 048 o posterior ya está aplicada).
-- Método de 037/046: definición vigente (pg_get_functiondef) + mapa explícito función->pantalla + conteo exacto (aborta si no coincide)
-- + atributos de seguridad idénticos antes y después. Las políticas se re-apuntan con ALTER POLICY y conteo de apariciones.
-- Mapa (decisiones del propietario 24/11: reposición = Reposición + Stock, sin exigir Compras; precios y márgenes de Ventas NO se tocan):
--   Órdenes de fabricación (production_orders): crear/iniciar/cancelar/terminar, entregas (remito para fabricación), devoluciones,
--     envasado y controles, fabricación inmediata, listas de órdenes y corridas, remitos anulados, perfil de empresa para el PDF.
--   Planificación (production_planning): crear/cancelar/completar planes y su lista.
--   Alcanza el stock (production_availability): erp_can_manufacture; recalcular reservas también para Órdenes.
--   Fórmulas (production_formulas): guardar fórmulas. Envases (production_packaging): guardar presentaciones.
--   Resumen (production_overview): tablero de producción, avisos y la sección de producción de Inicio/tablero/reporte.
--   Estadística (production_stats). Reposición (production_replenishment): erp_replenishment_forecast (ya no exige Compras).
--   Costos (costs_production): private.can_see_production_costs = administrador O costs_production:read (antes: administrador + finanzas).
-- El stock sigue exigiendo stock:insert/read en cada función que ya lo pedía (no se toca).
-- Lecturas por tabla: cada tabla la leen las pantallas que la necesitan (p. ej. fórmulas: Fórmulas, Órdenes, Planificación y Alcanza).
-- Cambios de acceso (revisión crítica): (a) un administrador SIN finance:read ahora ve costos de producción; (b) un rol no administrador con
--   costs_production (hoy solo los administradores lo tienen, por la 045) los ve; (c) Reposición deja de exigir Compras; (d) un rol solo de
--   Planificación no puede completar planes (complete_production_plan llama a post_production_run, que exige Órdenes:crear). Ver comprobación 8.
--   Nota: production_formula_cost solo exige can_see_production_costs: un rol con costs_production y sin pantallas de Producción puede pedirlo.
begin;

create table private.function_defs_pre047 (signature text primary key, definition text not null);
create table private.policy_defs_pre047 (tbl text not null, policy text not null, qual text, with_check text, primary key (tbl, policy));
create table private.permission_catalog_pre047 as select * from public.permission_catalog;
alter table private.function_defs_pre047 enable row level security;
alter table private.policy_defs_pre047 enable row level security;
alter table private.permission_catalog_pre047 enable row level security;
revoke all on private.function_defs_pre047, private.policy_defs_pre047, private.permission_catalog_pre047 from public, anon, authenticated;

create temporary table _m (
  signature text not null, old_res text not null, old_action text not null, kind text not null check (kind in ('one','or','true')),
  res_a text, act_a text, res_b text, act_b text, primary key (signature, old_res, old_action)
) on commit drop;

insert into _m values
  -- Órdenes de fabricación
  ('public.cancel_production_job(uuid,uuid,text)','production','update','one','production_orders','update',null,null),
  ('public.complete_production_now(uuid,uuid,numeric,numeric,uuid,text,date,text,text,jsonb,uuid,uuid,uuid)','production','insert','one','production_orders','insert',null,null),
  ('public.create_production_job(uuid,uuid,numeric,uuid,date,text,uuid,uuid)','production','insert','one','production_orders','insert',null,null),
  ('public.create_production_work_order(uuid,uuid,numeric,uuid,date,text,uuid,uuid,jsonb,jsonb)','production','insert','one','production_orders','insert',null,null),
  ('public.finish_production_job_adjusted(uuid,uuid,numeric,text,date,text,uuid,jsonb,jsonb)','production','insert','one','production_orders','insert',null,null),
  ('public.finish_production_job_adjusted(uuid,uuid,numeric,text,date,text,uuid,jsonb,jsonb)','production','update','one','production_orders','update',null,null),
  ('public.finish_production_job(uuid,uuid,numeric,text,date,text,uuid)','production','insert','one','production_orders','insert',null,null),
  ('public.issue_delivery_note(uuid,text,uuid,text,text,jsonb,uuid)','production','insert','one','production_orders','insert',null,null),
  ('public.issue_production_material(uuid,uuid,uuid,uuid,text,numeric,text,uuid)','production','insert','one','production_orders','insert',null,null),
  ('private.issue_production_material(uuid,uuid,uuid,uuid,text,numeric,text,uuid)','production','insert','one','production_orders','insert',null,null),
  ('public.post_production_run(uuid,uuid,uuid,numeric,uuid,text,date,text,jsonb)','production','insert','one','production_orders','insert',null,null),
  ('public.return_production_material(uuid,uuid,uuid,numeric,text,uuid)','production','update','one','production_orders','update',null,null),
  ('public.start_production_job(uuid,uuid)','production','update','one','production_orders','update',null,null),
  ('public.save_production_work_details(uuid,uuid,jsonb,jsonb,timestamp with time zone)','production','update','one','production_orders','update',null,null),
  ('public.void_delivery_note(uuid,uuid,text)','production','update','one','production_orders','update',null,null),
  ('public.list_production_jobs(uuid)','production','read','or','production_orders','read','production_overview','read'),
  ('public.list_production_runs(uuid)','production','read','or','production_orders','read','production_overview','read'),
  ('public.erp_company_profile(uuid)','production','read','one','production_orders','read',null,null),
  -- Planificación
  ('public.create_production_plan(uuid,uuid,numeric,uuid,date,text,uuid)','production','insert','one','production_planning','insert',null,null),
  ('public.cancel_production_plan(uuid,uuid)','production','update','one','production_planning','update',null,null),
  ('public.complete_production_plan(uuid,uuid,uuid,jsonb,text,date)','production','insert','one','production_planning','insert',null,null),
  ('public.list_production_plans(uuid)','production','read','one','production_planning','read',null,null),
  -- Alcanza el stock
  ('public.erp_can_manufacture(uuid,uuid,numeric)','production','read','one','production_availability','read',null,null),
  ('public.recalculate_production_reservations(uuid)','production','read','or','production_availability','read','production_orders','read'),
  -- Fórmulas y envases
  ('public.save_production_formula(uuid,uuid,numeric,jsonb)','production','update','one','production_formulas','update',null,null),
  ('public.save_production_formula_v2(uuid,uuid,numeric,jsonb,boolean,numeric)','production','update','one','production_formulas','update',null,null),
  ('public.save_production_packaging_type(uuid,uuid,text,numeric,uuid,boolean)','production','update','one','production_packaging','update',null,null),
  -- Resumen
  ('public.erp_production_dashboard(uuid)','production','read','one','production_overview','read',null,null),
  ('public.erp_production_alerts(uuid)','production','read','one','production_overview','read',null,null),
  ('private.erp_production_alerts(uuid)','production','read','one','production_overview','read',null,null),
  ('public.erp_dashboard(uuid)','production','read','one','production_overview','read',null,null),
  ('public.erp_operational_dashboard(uuid)','production','read','one','production_overview','read',null,null),
  ('public.erp_operational_report(uuid,date,date)','production','read','one','production_overview','read',null,null),
  -- Estadística
  ('public.production_output_by_product(uuid,date,date,text,integer,integer,text)','production','read','one','production_stats','read',null,null),
  ('public.production_output_summary(uuid,date,date,text,uuid,text)','production','read','one','production_stats','read',null,null),
  -- Reposición (ya no exige Compras: decisión del propietario)
  ('public.erp_replenishment_forecast(uuid)','production','read','one','production_replenishment','read',null,null),
  ('public.erp_replenishment_forecast(uuid)','purchases','read','true',null,null,null,null);

do $$
declare
  r record; d text; n int; v_before text; v_after text; v_pat text; v_repl text; v_sig text;
begin
  if (select count(*) from _m) <> 37 then raise exception 'El mapa de la 047 debe tener 37 filas (tiene %).', (select count(*) from _m); end if;
  -- Una función con 2 filas se reescribe una vez por fila sobre la definición vigente en ese momento.
  for r in select * from _m order by signature, old_res, old_action loop
    d := pg_get_functiondef(r.signature::regprocedure);
    if not exists (select 1 from private.function_defs_pre047 where signature = r.signature) then
      insert into private.function_defs_pre047 values (r.signature, d);
    end if;
    v_pat := 'private\.has_permission\(\s*p_company\s*,\s*''' || r.old_res || '''\s*,\s*''' || r.old_action || '''\s*\)';
    select count(*) into n from regexp_matches(d, v_pat, 'g');
    if n <> 1 then raise exception '% tiene % apariciones de %/% (se esperaba 1). No se cambió nada.', r.signature, n, r.old_res, r.old_action; end if;
    v_repl := case r.kind
      when 'one' then format('private.has_permission(p_company,%L,%L)', r.res_a, r.act_a)
      when 'or' then format('(private.has_permission(p_company,%L,%L) or private.has_permission(p_company,%L,%L))', r.res_a, r.act_a, r.res_b, r.act_b)
      else 'true' end;
    select prosecdef::text || coalesce(proconfig::text,'') || has_function_privilege('anon', oid, 'execute')::text
      || has_function_privilege('authenticated', oid, 'execute')::text into v_before from pg_proc where oid = r.signature::regprocedure;
    execute regexp_replace(d, v_pat, v_repl);
    select prosecdef::text || coalesce(proconfig::text,'') || has_function_privilege('anon', oid, 'execute')::text
      || has_function_privilege('authenticated', oid, 'execute')::text into v_after from pg_proc where oid = r.signature::regprocedure;
    if v_before is distinct from v_after then raise exception 'Cambió la seguridad de %', r.signature; end if;
    if pg_get_functiondef(r.signature::regprocedure) ~ v_pat then raise exception 'No se aplicó el cambio en % (%/%)', r.signature, r.old_res, r.old_action; end if;
  end loop;

  -- Costos de producción: administrador O costs_production:read (antes administrador + finanzas).
  v_sig := 'private.can_see_production_costs(uuid)';
  d := pg_get_functiondef(v_sig::regprocedure);
  v_pat := 'private\.get_user_role\(p_company\)\s*=\s*''admin''\s+and\s+private\.has_permission\(p_company,\s*''finance'',\s*''read''\)';
  select count(*) into n from regexp_matches(d, v_pat, 'g');
  if n <> 1 then raise exception '% no tiene la forma esperada (% apariciones).', v_sig, n; end if;
  insert into private.function_defs_pre047 values (v_sig, d);
  select prosecdef::text || coalesce(proconfig::text,'') || has_function_privilege('anon', oid, 'execute')::text
    || has_function_privilege('authenticated', oid, 'execute')::text into v_before from pg_proc where oid = v_sig::regprocedure;
  execute regexp_replace(d, v_pat, '(private.get_user_role(p_company)=''admin'' or private.has_permission(p_company,''costs_production'',''read''))');
  select prosecdef::text || coalesce(proconfig::text,'') || has_function_privilege('anon', oid, 'execute')::text
    || has_function_privilege('authenticated', oid, 'execute')::text into v_after from pg_proc where oid = v_sig::regprocedure;
  if v_before is distinct from v_after then raise exception 'Cambió la seguridad de %', v_sig; end if;
end $$;

-- Políticas: expresiones nuevas explícitas (se comprueba que la vigente tenga 1 aparición de 'production'::text)
create temporary table _pol (tbl text, policy text, new_using text not null, primary key (tbl, policy)) on commit drop;
insert into _pol values
  ('delivery_note_lines','delivery_lines_read',
   'exists (select 1 from public.delivery_notes d where d.company_id = delivery_note_lines.company_id and d.id = delivery_note_lines.note_id and (private.has_permission(d.company_id,''stock'',''read'') or (d.kind = ''production'' and private.has_permission(d.company_id,''production_orders'',''read''))))'),
  ('delivery_note_reversals','delivery_reversals_read',
   'exists (select 1 from public.delivery_notes d where d.company_id = delivery_note_reversals.company_id and d.id = delivery_note_reversals.note_id and (private.has_permission(d.company_id,''stock'',''read'') or (d.kind = ''production'' and private.has_permission(d.company_id,''production_orders'',''read''))))'),
  ('delivery_notes','delivery_notes_read',
   '(select private.has_permission(company_id,''stock'',''read'')) or (kind = ''production'' and (select private.has_permission(company_id,''production_orders'',''read'')))'),
  ('production_document_settings','document_settings_read',
   'private.has_permission(company_id,''production_documents'',''read'') or private.has_permission(company_id,''production_orders'',''read'') or (private.get_user_role(company_id) = ''admin'' and private.has_permission(company_id,''dashboard'',''read''))'),
  ('production_formula_lines','production_formula_lines_read',
   '(select private.has_permission(company_id,''production_formulas'',''read'')) or (select private.has_permission(company_id,''production_orders'',''read'')) or (select private.has_permission(company_id,''production_planning'',''read'')) or (select private.has_permission(company_id,''production_availability'',''read''))'),
  ('production_formulas','production_formulas_read',
   '(select private.has_permission(company_id,''production_formulas'',''read'')) or (select private.has_permission(company_id,''production_orders'',''read'')) or (select private.has_permission(company_id,''production_planning'',''read'')) or (select private.has_permission(company_id,''production_availability'',''read''))'),
  ('production_job_events','production_job_events_read',
   '(select private.has_permission(company_id,''production_orders'',''read''))'),
  ('production_job_reservations','production_reservations_read',
   '((select private.has_permission(company_id,''production_availability'',''read'')) or (select private.has_permission(company_id,''production_orders'',''read''))) and (select private.has_permission(company_id,''stock'',''read''))'),
  ('production_jobs','production_jobs_read',
   '(select private.has_permission(company_id,''production_orders'',''read'')) or (select private.has_permission(company_id,''production_overview'',''read''))'),
  ('production_packaging_types','packaging_types_read',
   'private.has_permission(company_id,''production_packaging'',''read'') or private.has_permission(company_id,''production_orders'',''read'')'),
  ('production_plans','production_plans_read',
   '(select private.has_permission(company_id,''production_planning'',''read''))'),
  ('production_reservation_locations','reservation_locations_read',
   '((select private.has_permission(company_id,''production_availability'',''read'')) or (select private.has_permission(company_id,''production_orders'',''read''))) and (select private.has_permission(company_id,''stock'',''read''))'),
  ('production_run_lines','production_run_lines_read',
   '(select private.has_permission(company_id,''production_orders'',''read'')) or (select private.has_permission(company_id,''production_overview'',''read''))'),
  ('production_runs','production_runs_read',
   '(select private.has_permission(company_id,''production_orders'',''read'')) or (select private.has_permission(company_id,''production_overview'',''read''))');

do $$
declare r record; v record; n int;
begin
  if (select count(*) from _pol) <> 14 then raise exception 'El mapa de políticas debe tener 14 filas.'; end if;
  for r in select * from _pol order by tbl, policy loop
    select * into v from pg_policies where schemaname='public' and tablename=r.tbl and policyname=r.policy;
    if not found then raise exception 'No existe la política % de %.', r.policy, r.tbl; end if;
    select count(*) into n from regexp_matches(coalesce(v.qual,'') || ' ' || coalesce(v.with_check,''), 'has_permission\([^,]+,\s*''production''::text', 'g');
    if n <> 1 then raise exception 'La política % de % tiene % apariciones de ''production'' (se esperaba 1).', r.policy, r.tbl, n; end if;
    insert into private.policy_defs_pre047 values (r.tbl, r.policy, v.qual, v.with_check);
    execute format('alter policy %I on public.%I using (%s)', r.policy, r.tbl, r.new_using);
  end loop;
end $$;

-- Catálogo: pantallas de Producción y costos exigidos por el servidor
update public.permission_catalog set enforced = true
where resource in ('production','production_overview','production_orders','production_formulas','production_planning',
  'production_availability','production_replenishment','production_packaging','production_stats','production_documents','costs_production');

-- Comprobaciones finales
do $$
declare v_left text;
begin
  select string_agg(tablename || '.' || policyname, ', ') into v_left from pg_policies
  where schemaname='public' and coalesce(qual,'') || coalesce(with_check,'') ~ 'has_permission\([^,]+,\s*''production''::text';
  if v_left is not null then raise exception 'Quedaron políticas con el permiso production: %', v_left; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v_left
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public','private') and p.prokind='f' and p.proname <> 'has_permission'
    and pg_get_functiondef(p.oid) ~ 'has_permission\(\s*[a-z_]+\s*,\s*''production''\s*,';
  if v_left is not null then raise exception 'Quedaron funciones con el permiso production: %', v_left; end if;
  if (select count(*) from private.function_defs_pre047) <> 36 or (select count(*) from private.policy_defs_pre047) <> 14 then
    raise exception 'El respaldo para deshacer está incompleto.';
  end if;
end $$;

commit;

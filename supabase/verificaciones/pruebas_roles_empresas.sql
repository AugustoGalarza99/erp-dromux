-- Dromux ERP · Pruebas de aislamiento entre empresas y de roles (Fase 2c/3).
-- SOLO PARA EL EDITOR SQL de Supabase (rol postgres). Pegar TODO el archivo y ejecutar una sola vez.
--
-- Qué hace: suplanta a cada usuario (rol `authenticated` + su id) y ejecuta cada caso en un punto de guardado que
-- SIEMPRE se revierte: NO deja datos, ni permisos, ni cambios. Los únicos objetos que crea son temporales de la
-- sesión (tabla _res y función pg_temp.t) y desaparecen al cerrar la conexión. No usa contraseñas.
-- Resultado: una tabla con una fila por caso. Pegarla completa en el chat.
--   PASA   = el sistema se comportó como se espera (lo prohibido falló o devolvió 0 filas; lo permitido funcionó).
--   FALLA  = comportamiento inesperado: es un hallazgo.
--   INFO   = no hay veredicto automático; leer "obtenido" (ver notas al pie del archivo).
-- Si el editor muestra "relation _res does not exist", ejecutar el archivo entero otra vez en una sola pestaña.

create temp table _res(
  n serial primary key, grupo text, caso text, esperado text, obtenido text, resultado text
);

create or replace function pg_temp.t(
  p_group text, p_case text, p_uid uuid, p_role text, p_pre text, p_sql text, p_mode text, p_expect text
) returns void language plpgsql as $f$
declare
  v_msg text;
  n bigint;
  v_ok boolean;
begin
  begin
    if p_pre is not null then execute p_pre; end if;                      -- preparación como postgres (se revierte)
    execute format('set local role %I', p_role);
    perform set_config('request.jwt.claims',
      case when p_uid is null then '{"role":"anon"}'
           else json_build_object('sub', p_uid, 'role', p_role)::text end, true);
    perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
    if p_mode = 'q' then
      execute format('select count(*) from (%s) q', p_sql) into n;
      v_msg := 'filas=' || n;
    elsif p_mode = 'w' then
      execute p_sql;
      get diagnostics n = row_count;
      v_msg := 'filas=' || n;
    else
      execute p_sql;
      v_msg := 'sin error';
    end if;
    raise exception '__rollback__';
  exception when others then
    if sqlerrm <> '__rollback__' then
      v_msg := 'ERROR ' || sqlstate || ': ' || left(sqlerrm, 150);
    end if;
  end;
  v_ok := case p_expect
    when 'negado'    then v_msg like 'ERROR%' or v_msg = 'filas=0'
    when 'error'     then v_msg like 'ERROR%'
    when 'sin_error' then v_msg not like 'ERROR%'
    when 'datos'     then v_msg like 'filas=%' and v_msg <> 'filas=0'
    else null end;
  insert into _res(grupo, caso, esperado, obtenido, resultado)
  values (p_group, p_case, p_expect, v_msg,
          case when v_ok is null then 'INFO' when v_ok then 'PASA' else 'FALLA' end);
end
$f$;

-- Ayudantes del grupo 11 (permisos de Compras por pantalla).
-- Prepara (como postgres, dentro del punto de guardado que se revierte) los permisos de Compras del rol: lista "recurso:acción,...".
create or replace function pg_temp.setrole(p_company uuid, p_role uuid, p_list text) returns text language sql as $f$
  select format($q$delete from public.role_permissions where role_id=%L and (resource like 'purchase%%' or resource like 'costs\_%%');
    insert into public.role_permissions(company_id,role_id,resource,action)
    select %L,%L,split_part(x,':',1),split_part(x,':',2) from unnest(string_to_array(%L,',')) x on conflict do nothing$q$,
    p_role, p_company, p_role, p_list)
$f$;
-- Bloque que PASA si la llamada se rechaza con 42501 (permiso); cualquier otro resultado (incluso un error de validación) FALLA.
create or replace function pg_temp.denegado(p_call text) returns text language sql as $f$
  select 'do $b$ begin begin perform (select count(*) from ' || p_call
    || '); exception when insufficient_privilege then return; end; raise exception ''NO fue denegado''; end $b$'
$f$;
-- Bloque que PASA si la llamada NO se rechaza por permiso (un error de validación posterior es aceptable: el permiso se evalúa primero).
create or replace function pg_temp.permitido(p_call text) returns text language sql as $f$
  select 'do $b$ begin begin perform (select count(*) from ' || p_call
    || '); exception when insufficient_privilege then raise exception ''DENEGADO 42501: %'', sqlerrm; when others then null; end; end $b$'
$f$;

-- Ayudante del grupo 12: permisos de Producción y costos del rol (lista "recurso:acción,...").
create or replace function pg_temp.setrole_prod(p_company uuid, p_role uuid, p_list text) returns text language sql as $f$
  select format($q$delete from public.role_permissions where role_id=%L and (resource like 'production%%' or resource = 'costs_production');
    insert into public.role_permissions(company_id,role_id,resource,action)
    select %L,%L,split_part(x,':',1),split_part(x,':',2) from unnest(string_to_array(%L,',')) x on conflict do nothing$q$,
    p_role, p_company, p_role, p_list)
$f$;

-- Ayudante del grupo 13: REEMPLAZA todos los permisos del rol por la lista "recurso:acción,..." (se revierte dentro del caso).
create or replace function pg_temp.setrole_all(p_company uuid, p_role uuid, p_list text) returns text language sql as $f$
  select format($q$delete from public.role_permissions where role_id=%L;
    insert into public.role_permissions(company_id,role_id,resource,action)
    select %L,%L,split_part(x,':',1),split_part(x,':',2) from unnest(string_to_array(%L,',')) x on conflict do nothing$q$,
    p_role, p_company, p_role, p_list)
$f$;

do $do$
declare
  -- Usuarios de prueba
  adm uuid := '3c69e2c8-3792-46c8-b35b-7ba3c1ad77c3';   -- Augusto Galarza: admin de Dromux ERP (A) y de Metalurgica Cerquatti (C)
  ven uuid := 'f086a333-cf12-4327-bc31-f9c61282db13';   -- Vendedor Dromux: solo empresa A
  dem uuid := '23f10efa-f2b4-4269-880e-258acb8a99e0';   -- Demo Dromux: admin solo de Espacio Demo (B)
  -- Empresas
  ca uuid := '2f4264a3-96fc-4663-a965-480bae4f0a52';    -- A Dromux ERP
  cb uuid := '539c24c9-955e-4e86-ab1e-5b40672dc7d0';    -- B Espacio Demo
  cc uuid := 'f5d93ed5-6c1a-4895-b41a-021ad8e912ce';    -- C Metalurgica Cerquatti
  -- Roles de A
  rol_adm_a uuid := '4ccfaa37-49b0-4b63-a895-b969a040a7a0';
  rol_ven_a uuid := 'a2b930d0-7df7-489f-855a-856da660258b';
  t text;
  tablas text[] := array['items','warehouses','production_jobs','production_job_events','production_runs',
    'production_formulas','production_plans','stock_balances','stock_movements','stock_operations','purchase_orders',
    'suppliers','purchase_requests','price_lists','price_list_items','quotes','customers','sales','treasury_entries',
    'delivery_notes','roles','role_permissions','company_users','company_profile'];
  todos text := '[{"resource":"finance","action":"read"},{"resource":"users","action":"update"},{"resource":"roles","action":"update"},{"resource":"purchases","action":"manage"}]';
  pre_delegado text;
  -- Grupo 11: roles de Compras de prueba (se aplican al rol del Vendedor DENTRO del punto de guardado, se revierten)
  pre_pedidos text; pre_resumen text; pre_ordenes text; pre_ordenes_nc text; pre_ordenes_w text; pre_prov text; pre_sin_manage text; pre_encargado text;
  c_mat text; c_dir text; c_cat text; c_rate text; c_acc text; c_stat text; c_pay text; c_cpay text; c_corder text; c_rec text;
  c_cancel text; c_rej text; c_conv text; c_ropt text; c_itemcost text; c_save text; c_adj text; c_pref text; c_addrate text;
  tp text;
  p_ov text; p_ord text; p_ordr text; p_stats text; p_plan text; p_form text; p_pack text; p_avail text; p_costs text;
  q_dash text; q_jobs text; q_runs text; q_plans text; q_can text; q_stats text; q_prod text; q_cjob text; q_start text; q_cxl text; q_ret text;
  q_cplan text; q_form text; q_pkg text; q_fcost text; q_repl text;
  tablas_compras text[] := array['purchase_orders','purchase_order_lines','purchase_receipts','purchase_receipt_lines','suppliers',
    'supplier_items','exchange_rates','exchange_rate_types','supplier_payment_orders','supplier_price_adjustments'];
begin
  ----------------------------------------------------------------------------------------------------
  -- 1) Controles positivos: lo permitido funciona (si esto falla, el resto no es confiable).
  ----------------------------------------------------------------------------------------------------
  perform pg_temp.t('1 Control','Admin A lee items de A',adm,'authenticated',null,format('select 1 from public.items where company_id=%L',ca),'q','datos');
  perform pg_temp.t('1 Control','Admin A lee órdenes de A',adm,'authenticated',null,format('select 1 from public.production_jobs where company_id=%L',ca),'q','datos');
  perform pg_temp.t('1 Control','Admin A lee depósitos de C (también es admin de C)',adm,'authenticated',null,format('select 1 from public.warehouses where company_id=%L',cc),'q','datos');
  perform pg_temp.t('1 Control','Vendedor lee items de A',ven,'authenticated',null,format('select 1 from public.items where company_id=%L',ca),'q','datos');
  perform pg_temp.t('1 Control','Vendedor lee órdenes de A (production:read)',ven,'authenticated',null,format('select 1 from public.production_jobs where company_id=%L',ca),'q','datos');
  perform pg_temp.t('1 Control','Admin B lee su empresa (companies)',dem,'authenticated',null,format('select 1 from public.companies where id=%L',cb),'q','datos');

  ----------------------------------------------------------------------------------------------------
  -- 2) Aislamiento de lectura entre empresas (tablas).
  ----------------------------------------------------------------------------------------------------
  foreach t in array tablas loop
    perform pg_temp.t('2 Lectura cruzada','Admin B lee '||t||' de A',dem,'authenticated',null,format('select 1 from public.%I where company_id=%L',t,ca),'q','negado');
    perform pg_temp.t('2 Lectura cruzada','Admin B lee '||t||' de C',dem,'authenticated',null,format('select 1 from public.%I where company_id=%L',t,cc),'q','negado');
    perform pg_temp.t('2 Lectura cruzada','Vendedor (solo A) lee '||t||' de B',ven,'authenticated',null,format('select 1 from public.%I where company_id=%L',t,cb),'q','negado');
    perform pg_temp.t('2 Lectura cruzada','Vendedor (solo A) lee '||t||' de C',ven,'authenticated',null,format('select 1 from public.%I where company_id=%L',t,cc),'q','negado');
  end loop;
  perform pg_temp.t('2 Lectura cruzada','Admin B lee companies de A',dem,'authenticated',null,format('select 1 from public.companies where id=%L',ca),'q','negado');
  perform pg_temp.t('2 Lectura cruzada','Vendedor lee companies de B',ven,'authenticated',null,format('select 1 from public.companies where id=%L',cb),'q','negado');

  ----------------------------------------------------------------------------------------------------
  -- 3) Escritura cruzada y escrituras no permitidas (filas afectadas = 0 o error).
  ----------------------------------------------------------------------------------------------------
  perform pg_temp.t('3 Escritura','Admin B modifica items de A',dem,'authenticated',null,format('update public.items set name=name where company_id=%L',ca),'w','negado');
  perform pg_temp.t('3 Escritura','Admin B borra depósitos de A',dem,'authenticated',null,format('delete from public.warehouses where company_id=%L',ca),'w','negado');
  perform pg_temp.t('3 Escritura','Admin B inserta depósito en A',dem,'authenticated',null,format($q$insert into public.warehouses(company_id,code,name) values (%L,'ZZTEST','Prueba')$q$,ca),'w','error');
  perform pg_temp.t('3 Escritura','Admin B renombra la empresa A',dem,'authenticated',null,format($q$update public.companies set name='x' where id=%L$q$,ca),'w','negado');
  perform pg_temp.t('3 Escritura','Admin B escribe permisos de roles de A (sin grant)',dem,'authenticated',null,format($q$insert into public.role_permissions(company_id,role_id,resource,action) values (%L,%L,'finance','read')$q$,ca,rol_ven_a),'w','error');
  perform pg_temp.t('3 Escritura','Vendedor modifica items de B',ven,'authenticated',null,format('update public.items set name=name where company_id=%L',cb),'w','negado');
  perform pg_temp.t('3 Escritura','Vendedor se pone el rol admin directo (company_users)',ven,'authenticated',null,format($q$update public.company_users set role_id=%L where user_id=%L$q$,rol_adm_a,ven),'w','error');
  perform pg_temp.t('3 Escritura','Vendedor se da permisos directo (role_permissions)',ven,'authenticated',null,format($q$insert into public.role_permissions(company_id,role_id,resource,action) values (%L,%L,'finance','read')$q$,ca,rol_ven_a),'w','error');
  perform pg_temp.t('3 Escritura','Vendedor borra un ítem (sin permiso delete)',ven,'authenticated',null,format('delete from public.items where company_id=%L',ca),'w','negado');
  perform pg_temp.t('3 Escritura','Vendedor modifica una orden de producción directo',ven,'authenticated',null,format($q$update public.production_jobs set status='cancelled' where company_id=%L$q$,ca),'w','error');
  perform pg_temp.t('3 Escritura','Vendedor modifica stock directo',ven,'authenticated',null,format('update public.stock_balances set quantity=quantity+1 where company_id=%L',ca),'w','error');

  ----------------------------------------------------------------------------------------------------
  -- 4) Funciones (RPC) entre empresas: un usuario de otra empresa no debe obtener ni hacer nada.
  ----------------------------------------------------------------------------------------------------
  perform pg_temp.t('4 RPC cruzada','Admin B: listar órdenes de A',dem,'authenticated',null,format($q$select 1 where coalesce(public.list_production_jobs(%L)::text,'[]') not in ('null','[]','{}')$q$,ca),'q','negado');
  perform pg_temp.t('4 RPC cruzada','Admin B: listar corridas de A',dem,'authenticated',null,format($q$select 1 where coalesce(public.list_production_runs(%L)::text,'[]') not in ('null','[]','{}')$q$,ca),'q','negado');
  perform pg_temp.t('4 RPC cruzada','Admin B: ítems de producción de A',dem,'authenticated',null,format($q$select 1 where coalesce(public.list_production_items(%L,true)::text,'[]') not in ('null','[]','{}')$q$,ca),'q','negado');
  perform pg_temp.t('4 RPC cruzada','Admin B: tablero de producción de A',dem,'authenticated',null,format($q$select 1 where coalesce(public.erp_production_dashboard(%L)::text,'{}') not in ('null','[]','{}')$q$,ca),'q','negado');
  perform pg_temp.t('4 RPC cruzada','Admin B: tablero operativo de A',dem,'authenticated',null,format($q$select 1 where coalesce(public.erp_operational_dashboard(%L)::text,'{}') not in ('null','[]','{}')$q$,ca),'q','negado');
  perform pg_temp.t('4 RPC cruzada','Admin B: resumen de stock de A',dem,'authenticated',null,format($q$select * from public.stock_summary(%L,0,'')$q$,ca),'q','negado');
  perform pg_temp.t('4 RPC cruzada','Admin B: miembros de A',dem,'authenticated',null,format($q$select * from public.company_members(%L)$q$,ca),'q','negado');
  perform pg_temp.t('4 RPC cruzada','Admin B: estadística de producción de A',dem,'authenticated',null,format($q$select * from public.production_output_summary(%L,'2026-01-01','2026-12-31','month')$q$,ca),'q','negado');
  perform pg_temp.t('4 RPC cruzada','Admin B: producción por producto de A',dem,'authenticated',null,format($q$select * from public.production_output_by_product(%L,'2026-01-01','2026-12-31')$q$,ca),'q','negado');
  perform pg_temp.t('4 RPC cruzada','Admin B: costos de lista de A',dem,'authenticated',null,format($q$select * from public.erp_price_settings(%L)$q$,ca),'q','negado');
  perform pg_temp.t('4 RPC cruzada','Admin B: cambia el rol de un usuario de A',dem,'authenticated',null,format('select public.set_company_member(%L,%L,%L,true)',ca,ven,rol_adm_a),'x','error');
  perform pg_temp.t('4 RPC cruzada','Admin B: crea un rol en A',dem,'authenticated',null,format($q$select public.create_company_role(%L,'Rol B','rol_b','[]'::jsonb)$q$,ca),'x','error');
  perform pg_temp.t('4 RPC cruzada','Admin B: termina una orden de A',dem,'authenticated',null,format($q$select public.finish_production_job_adjusted(%L,(select id from public.production_jobs where company_id=%L limit 1),1,null,null,null,gen_random_uuid(),'[]'::jsonb,'{}'::jsonb)$q$,ca,ca),'x','error');
  perform pg_temp.t('4 RPC cruzada','Vendedor (solo A): estadística de producción de B',ven,'authenticated',null,format($q$select * from public.production_output_summary(%L,'2026-01-01','2026-12-31','month')$q$,cb),'q','negado');
  perform pg_temp.t('4 RPC cruzada','Vendedor (solo A): listar órdenes de B',ven,'authenticated',null,format($q$select 1 where coalesce(public.list_production_jobs(%L)::text,'[]') not in ('null','[]','{}')$q$,cb),'q','negado');

  ----------------------------------------------------------------------------------------------------
  -- 5) Costos y márgenes: un rol no administrador no debe recibirlos (columnas, RPC y JSON).
  ----------------------------------------------------------------------------------------------------
  perform pg_temp.t('5 Costos','Vendedor lee items.reference_unit_cost',ven,'authenticated',null,'select reference_unit_cost from public.items limit 1','q','error');
  perform pg_temp.t('5 Costos','Vendedor lee items.reference_cost_usd',ven,'authenticated',null,'select reference_cost_usd from public.items limit 1','q','error');
  perform pg_temp.t('5 Costos','Vendedor lee production_runs.estimated_cost',ven,'authenticated',null,'select estimated_cost from public.production_runs limit 1','q','error');
  perform pg_temp.t('5 Costos','Vendedor lee production_run_lines.unit_cost',ven,'authenticated',null,'select unit_cost from public.production_run_lines limit 1','q','error');
  perform pg_temp.t('5 Costos','Vendedor lee production_job_events.unit_cost',ven,'authenticated',null,'select unit_cost from public.production_job_events limit 1','q','error');
  perform pg_temp.t('5 Costos','Vendedor lee production_jobs.formula_snapshot',ven,'authenticated',null,'select formula_snapshot from public.production_jobs limit 1','q','error');
  perform pg_temp.t('5 Costos','Vendedor lee production_plans.component_snapshot',ven,'authenticated',null,'select component_snapshot from public.production_plans limit 1','q','error');
  perform pg_temp.t('5 Costos','Vendedor lee production_plans.estimated_cost',ven,'authenticated',null,'select estimated_cost from public.production_plans limit 1','q','error');
  perform pg_temp.t('5 Costos','Vendedor lee sale_lines.estimated_unit_cost',ven,'authenticated',null,'select estimated_unit_cost from public.sale_lines limit 1','q','error');
  perform pg_temp.t('5 Costos','Admin A lee items.reference_unit_cost directo (también revocado: el admin usa RPC)',adm,'authenticated',null,'select reference_unit_cost from public.items limit 1','q','error');
  perform pg_temp.t('5 Costos','Vendedor: costo de la fórmula',ven,'authenticated',null,format('select public.production_formula_cost(%L,(select id from public.items where company_id=%L limit 1))',ca,ca),'x','error');
  perform pg_temp.t('5 Costos','Vendedor: parámetros de márgenes y comisión',ven,'authenticated',null,format('select * from public.erp_price_settings(%L)',ca),'q','error');
  perform pg_temp.t('5 Costos','Vendedor: filas de lista de precios con costos',ven,'authenticated',null,format($q$select * from public.erp_admin_price_list_rows(%L,gen_random_uuid(),'','all',0,25)$q$,ca),'q','error');
  perform pg_temp.t('5 Costos','Vendedor: guardar parámetros de precios',ven,'authenticated',null,format('select public.save_price_settings(%L,21,10,0,0,10)',ca),'x','error');
  perform pg_temp.t('5 Costos','Vendedor: JSON de corridas sin valores de costo (las claves vienen en null)',ven,'authenticated',null,format($q$select 1 where public.list_production_runs(%L)::text ~ '"(unit_cost|estimated_cost)": [^n]'$q$,ca),'q','negado');
  perform pg_temp.t('5 Costos','Vendedor: JSON de órdenes sin valores de costo',ven,'authenticated',null,format($q$select 1 where public.list_production_jobs(%L)::text ~ '"unit_cost": [^n]'$q$,ca),'q','negado');
  perform pg_temp.t('5 Costos','Vendedor: JSON de planes sin valores de costo',ven,'authenticated',null,format($q$select 1 where public.list_production_plans(%L)::text ~ '"(unit_cost|estimated_cost)": [^n]'$q$,ca),'q','negado');
  perform pg_temp.t('5 Costos','Vendedor: tablero operativo sin ganancia',ven,'authenticated',null,format($q$select 1 where public.erp_operational_dashboard(%L)::text ~* '(profit|ganancia|margin|margen|cost)'$q$,ca),'q','negado');
  perform pg_temp.t('5 Costos','Vendedor: JSON de ítems con costo de referencia (INFO: compras:read lo habilita por diseño)',ven,'authenticated',null,format($q$select 1 where public.list_production_items(%L,true)::text ~ '"reference_unit_cost"'$q$,ca),'q','info');
  perform pg_temp.t('5 Costos','Admin A: JSON de corridas (INFO: el admin sí puede ver costos)',adm,'authenticated',null,format($q$select 1 where public.list_production_runs(%L)::text ~ '"(unit_cost|estimated_cost)"'$q$,ca),'q','info');

  ----------------------------------------------------------------------------------------------------
  -- 6) Usuarios, roles y permisos (Ajustes). Casos H-007: se preparan permisos delegados como postgres
  --    (dentro del punto de guardado, se revierten) y se comprueba si el sistema permite la escalada.
  ----------------------------------------------------------------------------------------------------
  pre_delegado := format($p$insert into public.role_permissions(company_id,role_id,resource,action) values
    (%L,%L,'users','read'),(%L,%L,'users','update'),(%L,%L,'roles','read'),(%L,%L,'roles','insert'),(%L,%L,'roles','update')
    on conflict do nothing$p$, ca,rol_ven_a, ca,rol_ven_a, ca,rol_ven_a, ca,rol_ven_a, ca,rol_ven_a);

  perform pg_temp.t('6 Roles','Vendedor: ver miembros (sin users:read)',ven,'authenticated',null,format('select * from public.company_members(%L)',ca),'q','error');
  perform pg_temp.t('6 Roles','Vendedor: asignarse el rol admin',ven,'authenticated',null,format('select public.set_company_member(%L,%L,%L,true)',ca,ven,rol_adm_a),'x','error');
  perform pg_temp.t('6 Roles','Vendedor: crear un rol (sin roles:insert)',ven,'authenticated',null,format($q$select public.create_company_role(%L,'Escala','escala_a','[]'::jsonb)$q$,ca),'x','error');
  perform pg_temp.t('6 Roles','Vendedor: editar su propio rol (sin roles:update)',ven,'authenticated',null,format($q$select public.update_company_role(%L,%L,'Vendedor',%L::jsonb)$q$,ca,rol_ven_a,todos),'x','error');
  perform pg_temp.t('6 Roles','Admin A: crear un rol (se revierte)',adm,'authenticated',null,format($q$select public.create_company_role(%L,'Rol prueba','rol_prueba_t','[{"resource":"stock","action":"read"}]'::jsonb)$q$,ca),'x','sin_error');
  perform pg_temp.t('6 Roles','Admin A: editar el rol admin (debe estar protegido)',adm,'authenticated',null,format($q$select public.update_company_role(%L,%L,'Administrador','[]'::jsonb)$q$,ca,rol_adm_a),'x','error');
  perform pg_temp.t('6 Roles','Admin B: quitarse a sí mismo el rol admin siendo el único admin',dem,'authenticated',null,format($q$select public.set_company_member(%L,%L,(select id from public.roles where company_id=%L and code<>'admin' limit 1),true)$q$,cb,dem,cb),'x','error');
  perform pg_temp.t('6 Roles','Admin B: suspender su propia cuenta',dem,'authenticated',null,format($q$select public.set_company_member(%L,%L,(select id from public.roles where company_id=%L and code='admin'),false)$q$,cb,dem,cb),'x','error');
  perform pg_temp.t('6 Roles','H-007 INFO: con users:update+roles:insert, crear un rol con permisos y asignárselo a sí mismo',ven,'authenticated',pre_delegado,
    format($q$do $b$ declare r uuid; begin r:=public.create_company_role(%L,'Escala','escala_h7','[{"resource":"finance","action":"read"},{"resource":"purchases","action":"manage"},{"resource":"stock","action":"delete"}]'::jsonb); perform public.set_company_member(%L,%L,r,true); end $b$$q$,ca,ca,ven),'x','info');
  perform pg_temp.t('6 Roles','H-007 INFO: con roles:update, ampliar los permisos de su PROPIO rol',ven,'authenticated',pre_delegado,
    format($q$select public.update_company_role(%L,%L,'Vendedor',%L::jsonb)$q$,ca,rol_ven_a,todos),'x','info');

  ----------------------------------------------------------------------------------------------------
  -- 7) Producción (043): permisos y validaciones de las funciones nuevas.
  ----------------------------------------------------------------------------------------------------
  perform pg_temp.t('7 Producción','Admin A: estadística mensual de A',adm,'authenticated',null,format($q$select * from public.production_output_summary(%L,'2026-01-01','2026-12-31','month')$q$,ca),'q','sin_error');
  perform pg_temp.t('7 Producción','Admin A: estadística de C (también admin)',adm,'authenticated',null,format($q$select * from public.production_output_summary(%L,'2026-01-01','2026-12-31','week')$q$,cc),'q','sin_error');
  perform pg_temp.t('7 Producción','Vendedor: estadística de A (production:read)',ven,'authenticated',null,format($q$select * from public.production_output_summary(%L,'2026-01-01','2026-12-31','month')$q$,ca),'q','sin_error');
  perform pg_temp.t('7 Producción','Admin A: producción por producto de A',adm,'authenticated',null,format($q$select * from public.production_output_by_product(%L,'2026-01-01','2026-12-31','',25,0)$q$,ca),'q','sin_error');
  perform pg_temp.t('7 Producción','Rango invertido',adm,'authenticated',null,format($q$select * from public.production_output_summary(%L,'2026-12-31','2026-01-01','month')$q$,ca),'q','error');
  perform pg_temp.t('7 Producción','Rango mayor a 10 años',adm,'authenticated',null,format($q$select * from public.production_output_summary(%L,'2000-01-01','2026-12-31','month')$q$,ca),'q','error');
  perform pg_temp.t('7 Producción','Agrupar por año (no permitido)',adm,'authenticated',null,format($q$select * from public.production_output_summary(%L,'2026-01-01','2026-12-31','year')$q$,ca),'q','error');
  perform pg_temp.t('7 Producción','Día sobre más de un año',adm,'authenticated',null,format($q$select * from public.production_output_summary(%L,'2025-01-01','2026-12-31','day')$q$,ca),'q','error');
  perform pg_temp.t('7 Producción','Zona horaria inválida',adm,'authenticated',null,format($q$select * from public.production_output_summary(%L,'2026-01-01','2026-12-31','month',null,'Marte/Olimpo')$q$,ca),'q','error');
  perform pg_temp.t('7 Producción','Paginación inválida (límite 0)',adm,'authenticated',null,format($q$select * from public.production_output_by_product(%L,'2026-01-01','2026-12-31','',0,0)$q$,ca),'q','error');
  perform pg_temp.t('7 Producción','Vendedor: devolver insumo (exige production:update, no lo tiene)',ven,'authenticated',null,format($q$select public.return_production_material(%L,gen_random_uuid(),gen_random_uuid(),1,'prueba',gen_random_uuid())$q$,ca),'x','error');
  perform pg_temp.t('7 Producción','Cierre con ajuste sin tipo (solo comprueba que falla; la prueba de fondo exige una orden en proceso)',adm,'authenticated',null,format($q$select public.finish_production_job_adjusted(%L,gen_random_uuid(),1,null,null,null,gen_random_uuid(),'[{"component_id":"00000000-0000-4000-8000-000000000001","quantity":"1"}]'::jsonb,'{}'::jsonb)$q$,ca),'x','error');
  perform pg_temp.t('7 Producción','Cierre de una orden inexistente',adm,'authenticated',null,format($q$select public.finish_production_job_adjusted(%L,gen_random_uuid(),1,null,null,null,gen_random_uuid(),'[]'::jsonb,'{}'::jsonb)$q$,ca),'x','error');

  ----------------------------------------------------------------------------------------------------
  -- 8) Sin sesión (anon): nada.
  ----------------------------------------------------------------------------------------------------
  perform pg_temp.t('8 Anónimo','anon lee items',null,'anon',null,'select 1 from public.items limit 1','q','error');
  perform pg_temp.t('8 Anónimo','anon lee companies',null,'anon',null,'select 1 from public.companies limit 1','q','error');
  perform pg_temp.t('8 Anónimo','anon pide sus empresas',null,'anon',null,'select * from public.my_company_access()','q','error');
  perform pg_temp.t('8 Anónimo','anon pide estadística',null,'anon',null,format($q$select * from public.production_output_summary(%L,'2026-01-01','2026-12-31','month')$q$,ca),'q','error');
  perform pg_temp.t('8 Anónimo','anon crea una empresa',null,'anon',null,$q$select public.create_company('Empresa anon')$q$,'x','error');

  ----------------------------------------------------------------------------------------------------
  -- 9) TRAS LA MIGRACIÓN 044 (antes de aplicarla, los casos 9.x que esperan error darán FALLA: es lo esperado).
  ----------------------------------------------------------------------------------------------------
  perform pg_temp.t('9 Tras 044','H-007: con users:update+roles:insert, crearse un rol y asignárselo (debe fallar)',ven,'authenticated',pre_delegado,
    format($q$do $b$ declare r uuid; begin r:=public.create_company_role(%L,'Escala','escala_h7','[{"resource":"finance","action":"read"}]'::jsonb); perform public.set_company_member(%L,%L,r,true); end $b$$q$,ca,ca,ven),'x','error');
  perform pg_temp.t('9 Tras 044','H-007: con roles:update, ampliar su PROPIO rol (debe fallar)',ven,'authenticated',pre_delegado,
    format($q$select public.update_company_role(%L,%L,'Vendedor',%L::jsonb)$q$,ca,rol_ven_a,todos),'x','error');
  perform pg_temp.t('9 Tras 044','Con users:update, asignarse otro rol (debe fallar)',ven,'authenticated',pre_delegado,
    format($q$select public.set_company_member(%L,%L,%L,true)$q$,ca,ven,rol_ven_a),'x','error');
  perform pg_temp.t('9 Tras 044','Admin A: crear rol con código reservado support (debe fallar)',adm,'authenticated',null,format($q$select public.create_company_role(%L,'Soporte','support','[]'::jsonb)$q$,ca),'x','error');
  perform pg_temp.t('9 Tras 044','Admin A: crear rol con código admin (debe fallar)',adm,'authenticated',null,format($q$select public.create_company_role(%L,'Otro admin','admin','[]'::jsonb)$q$,ca),'x','error');
  perform pg_temp.t('9 Tras 044','Admin A: crear un rol sigue funcionando',adm,'authenticated',null,format($q$select public.create_company_role(%L,'Rol prueba','rol_prueba_t2','[{"resource":"stock","action":"read"}]'::jsonb)$q$,ca),'x','sin_error');
  perform pg_temp.t('9 Tras 044','Admin A: crear un rol deja un evento en el historial',adm,'authenticated',null,
    format($q$do $b$ declare r uuid; n int; begin r:=public.create_company_role(%L,'Rol hist','rol_hist_t','[]'::jsonb); select count(*) into n from public.access_audit_events_list(%L,0) where action='role_created'; if n=0 then raise exception 'sin evento'; end if; end $b$$q$,ca,ca),'x','sin_error');
  perform pg_temp.t('9 Tras 044','Admin A ve el historial',adm,'authenticated',null,format($q$select * from public.access_audit_events_list(%L,0)$q$,ca),'q','sin_error');
  perform pg_temp.t('9 Tras 044','Vendedor no ve el historial',ven,'authenticated',null,format($q$select * from public.access_audit_events_list(%L,0)$q$,ca),'q','error');
  perform pg_temp.t('9 Tras 044','Admin B no ve el historial de A',dem,'authenticated',null,format($q$select * from public.access_audit_events_list(%L,0)$q$,ca),'q','error');
  perform pg_temp.t('9 Tras 044','Nadie lee la tabla de historial directo (admin)',adm,'authenticated',null,'select 1 from public.access_audit_events','q','error');

  ----------------------------------------------------------------------------------------------------
  -- 10) TRAS LA MIGRACIÓN 045 (antes de aplicarla, estos casos dan FALLA: es lo esperado).
  ----------------------------------------------------------------------------------------------------
  perform pg_temp.t('10 Tras 045','El catálogo se lee con sesión (authenticated)',ven,'authenticated',null,'select 1 from public.permission_catalog','q','datos');
  perform pg_temp.t('10 Tras 045','El catálogo no se lee sin sesión (anon)',null,'anon',null,'select 1 from public.permission_catalog','q','error');
  perform pg_temp.t('10 Tras 045','Nadie escribe el catálogo (admin)',adm,'authenticated',null,$q$update public.permission_catalog set label='x'$q$,'w','error');
  perform pg_temp.t('10 Tras 045','Vendedor (permisos de compras) recibió las 5 pantallas de compras',ven,'authenticated',null,
    format($q$select 1 where (select count(*) from public.role_permissions where role_id=%L and resource in ('purchases_overview','purchase_requests','purchases_orders','purchases_suppliers','purchases_accounts') and action='read')=5$q$,rol_ven_a),'q','datos');
  perform pg_temp.t('10 Tras 045','El vendedor NO recibió costos',ven,'authenticated',null,
    format($q$select 1 from public.role_permissions where role_id=%L and resource like 'costs\_%%'$q$,rol_ven_a),'q','negado');
  perform pg_temp.t('10 Tras 045','El admin tiene costos y todas las pantallas',adm,'authenticated',null,
    format($q$select 1 where (select count(*) from public.role_permissions where role_id=%L and resource in ('costs_materials','costs_production','production_orders','stock_levels','purchases_orders'))>=5$q$,rol_adm_a),'q','datos');
  perform pg_temp.t('10 Tras 045','Rol con SOLO Pedidos internos: se guarda sin abrir el resto de Compras',adm,'authenticated',null,
    format($q$do $b$ declare r uuid; begin r:=public.create_company_role(%L,'Solo pedidos','solo_pedidos_t','[{"resource":"purchase_requests","action":"read"},{"resource":"purchase_requests","action":"insert"}]'::jsonb); if exists(select 1 from public.role_permissions where role_id=r and resource in ('purchases','purchases_orders','purchases_overview','purchases_suppliers','purchases_accounts')) then raise exception 'abrió otras pantallas'; end if; if (select count(*) from public.role_permissions where role_id=r and resource='purchase_requests')<>2 then raise exception 'faltan permisos'; end if; end $b$$q$,ca),'x','sin_error');
  perform pg_temp.t('10 Tras 045','Rol con las 5 pantallas de Compras (ver): se deriva el permiso del módulo',adm,'authenticated',null,
    format($q$do $b$ declare r uuid; begin r:=public.create_company_role(%L,'Todo compras','todo_compras_t','[{"resource":"purchases_overview","action":"read"},{"resource":"purchase_requests","action":"read"},{"resource":"purchases_orders","action":"read"},{"resource":"purchases_suppliers","action":"read"},{"resource":"purchases_accounts","action":"read"}]'::jsonb); if not exists(select 1 from public.role_permissions where role_id=r and resource='purchases' and action='read') then raise exception 'no derivó el módulo'; end if; end $b$$q$,ca),'x','sin_error');
  perform pg_temp.t('10 Tras 045','Pedir el módulo completo de Producción expande a sus 9 pantallas',adm,'authenticated',null,
    format($q$do $b$ declare r uuid; begin r:=public.create_company_role(%L,'Prod total','prod_total_t','[{"resource":"production","action":"read"}]'::jsonb); if (select count(*) from public.role_permissions where role_id=r and resource like 'production\_%%' and action='read')<>9 then raise exception 'no expandió'; end if; end $b$$q$,ca),'x','sin_error');
  perform pg_temp.t('10 Tras 045','Permiso desconocido se rechaza',adm,'authenticated',null,format($q$select public.create_company_role(%L,'Raro','raro_t','[{"resource":"inventado","action":"read"}]'::jsonb)$q$,ca),'x','error');
  perform pg_temp.t('10 Tras 045','Usuarios y roles no se delegan',adm,'authenticated',null,format($q$select public.create_company_role(%L,'Delegado','delegado_t','[{"resource":"users","action":"update"}]'::jsonb)$q$,ca),'x','error');
  perform pg_temp.t('10 Tras 045','Los costos solo admiten ver (no crear)',adm,'authenticated',null,format($q$select public.create_company_role(%L,'Costos','costos_t','[{"resource":"costs_materials","action":"insert"}]'::jsonb)$q$,ca),'x','error');
  perform pg_temp.t('10 Tras 045','Permisos repetidos se rechazan',adm,'authenticated',null,format($q$select public.create_company_role(%L,'Doble','doble_t','[{"resource":"dashboard","action":"read"},{"resource":"dashboard","action":"read"}]'::jsonb)$q$,ca),'x','error');
  perform pg_temp.t('10 Tras 045','Admin A edita un rol: quita pantallas y el módulo deja de estar completo',adm,'authenticated',null,
    format($q$do $b$ declare r uuid; begin r:=public.create_company_role(%L,'Edit','edit_t','[{"resource":"purchases","action":"read"}]'::jsonb); perform public.update_company_role(%L,r,'Edit','[{"resource":"purchases_overview","action":"read"}]'::jsonb); if exists(select 1 from public.role_permissions where role_id=r and resource in ('purchases','purchases_orders')) then raise exception 'quedó abierto'; end if; end $b$$q$,ca,ca),'x','sin_error');
  perform pg_temp.t('10 Tras 045','Vendedor no puede crear roles (sigue siendo solo admin)',ven,'authenticated',null,format($q$select public.create_company_role(%L,'X','x_t','[]'::jsonb)$q$,ca),'x','error');

  ----------------------------------------------------------------------------------------------------
  -- 11) TRAS LA MIGRACIÓN 046 (antes de aplicarla, estos casos dan FALLA: es lo esperado).
  --     Compras por pantalla. Se reemplazan los permisos de Compras del rol del Vendedor DENTRO del punto de guardado
  --     (se revierte) y se comprueba, con el servidor, qué pantallas responden y cuáles dan 42501.
  --     "Denegado" = el servidor responde 42501 (permiso). "Permitido" = no hay 42501 (un error de validación posterior vale).
  ----------------------------------------------------------------------------------------------------
  pre_pedidos     := pg_temp.setrole(ca, rol_ven_a, 'purchase_requests:read,purchase_requests:insert');
  pre_resumen     := pg_temp.setrole(ca, rol_ven_a, 'purchases_overview:read');
  pre_ordenes     := pg_temp.setrole(ca, rol_ven_a, 'purchases_orders:read,costs_materials:read');
  pre_ordenes_nc  := pg_temp.setrole(ca, rol_ven_a, 'purchases_orders:read');
  pre_ordenes_w   := pg_temp.setrole(ca, rol_ven_a, 'purchases_orders:read,purchases_orders:insert,purchases_orders:update');
  pre_prov        := pg_temp.setrole(ca, rol_ven_a, 'purchases_suppliers:read');
  pre_sin_manage  := pg_temp.setrole(ca, rol_ven_a, 'purchase_requests:read,purchase_requests:insert,purchase_requests:update,purchases_orders:read,purchases_orders:insert');
  pre_encargado   := pg_temp.setrole(ca, rol_ven_a,
    'purchases_overview:read,purchase_requests:read,purchase_requests:insert,purchase_requests:update,purchase_requests:manage,'
    || 'purchases_orders:read,purchases_orders:insert,purchases_orders:update,purchases_suppliers:read,purchases_suppliers:insert,'
    || 'purchases_suppliers:update,purchases_accounts:read,purchases_accounts:insert,costs_materials:read,finance:read,finance:insert');

  c_mat      := format('public.purchase_material_options(%L,%L,null)', ca, '');
  c_dir      := format('public.supplier_directory(%L,%L,0)', ca, '');
  c_cat      := format('public.supplier_quote_catalog(%L,gen_random_uuid(),null,%L,0)', ca, '');
  c_rate     := format('public.exchange_rate_overview(%L)', ca);
  c_acc      := format('public.supplier_account(%L,gen_random_uuid(),%L::date,%L::date,0)', ca, '2026-01-01', '2026-12-31');
  c_stat     := format('public.supplier_purchase_statistics(%L,%L::date,%L::date)', ca, '2026-01-01', '2026-12-31');
  c_pay      := format('public.supplier_payable_orders(%L,gen_random_uuid(),0)', ca);
  c_cpay     := format('public.create_supplier_payment_order(%L,gen_random_uuid(),null,current_date,%L,%L,%L::jsonb,gen_random_uuid())', ca, 'x', 'x', '[]');
  -- create_purchase_order (sin _once) no tiene EXECUTE para la API (correcto): se prueba la que usa la app.
  c_corder   := format('public.create_purchase_order_once(%L,gen_random_uuid(),%L,%L::jsonb,gen_random_uuid())', ca, 'x', '[]');
  c_rec      := format('public.receive_purchase_order(%L,gen_random_uuid(),gen_random_uuid(),%L,%L::jsonb)', ca, 'x', '[]');
  c_cancel   := format('public.cancel_purchase_order(%L,gen_random_uuid())', ca);
  c_rej      := format('public.reject_purchase_request(%L,gen_random_uuid(),%L)', ca, 'x');
  c_conv     := format('public.convert_purchase_request(%L,gen_random_uuid(),gen_random_uuid(),%L,%L::jsonb,gen_random_uuid())', ca, 'x', '[]');
  c_ropt     := format('public.purchase_request_item_options(%L,%L)', ca, '');
  c_itemcost := format('public.item_cost_context(%L,gen_random_uuid())', ca);
  c_save     := format('public.save_supplier_quote(%L,gen_random_uuid(),gen_random_uuid(),1,%L,%L,null,null,null,false)', ca, '', 'ARS');
  c_adj      := format('public.supplier_adjustment_preview(%L,gen_random_uuid(),null,5)', ca);
  c_pref     := format('public.set_preferred_supplier(%L,gen_random_uuid(),gen_random_uuid())', ca);
  c_addrate  := format('public.add_exchange_rate(%L,gen_random_uuid(),1,current_date)', ca);

  -- 11a) Rol con SOLO Pedidos internos: entra a esa pantalla y todo lo demás da 42501 / 0 filas.
  perform pg_temp.t('11 Tras 046','Solo pedidos: opciones de ítems para pedir',ven,'authenticated',pre_pedidos,pg_temp.permitido(c_ropt),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo pedidos: lista sus pedidos',ven,'authenticated',pre_pedidos,format('select 1 from public.purchase_requests where company_id=%L',ca),'q','sin_error');
  perform pg_temp.t('11 Tras 046','Solo pedidos: materiales para órdenes de compra (denegado)',ven,'authenticated',pre_pedidos,pg_temp.denegado(c_mat),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo pedidos: directorio de proveedores (denegado)',ven,'authenticated',pre_pedidos,pg_temp.denegado(c_dir),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo pedidos: catálogo de cotizaciones (denegado)',ven,'authenticated',pre_pedidos,pg_temp.denegado(c_cat),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo pedidos: tipos de cambio (denegado)',ven,'authenticated',pre_pedidos,pg_temp.denegado(c_rate),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo pedidos: cuenta con proveedor (denegado)',ven,'authenticated',pre_pedidos,pg_temp.denegado(c_acc),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo pedidos: estadística de compras (denegado)',ven,'authenticated',pre_pedidos,pg_temp.denegado(c_stat),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo pedidos: órdenes por pagar (denegado)',ven,'authenticated',pre_pedidos,pg_temp.denegado(c_pay),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo pedidos: crear orden de pago (denegado)',ven,'authenticated',pre_pedidos,pg_temp.denegado(c_cpay),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo pedidos: crear orden de compra (denegado)',ven,'authenticated',pre_pedidos,pg_temp.denegado(c_corder),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo pedidos: recibir mercadería (denegado)',ven,'authenticated',pre_pedidos,pg_temp.denegado(c_rec),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo pedidos: cancelar orden de compra (denegado)',ven,'authenticated',pre_pedidos,pg_temp.denegado(c_cancel),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo pedidos: rechazar pedido ajeno (denegado)',ven,'authenticated',pre_pedidos,pg_temp.denegado(c_rej),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo pedidos: convertir pedido en orden (denegado)',ven,'authenticated',pre_pedidos,pg_temp.denegado(c_conv),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo pedidos: guardar cotización de proveedor (denegado)',ven,'authenticated',pre_pedidos,pg_temp.denegado(c_save),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo pedidos: costo de proveedor en la ficha del ítem (denegado)',ven,'authenticated',pre_pedidos,pg_temp.denegado(c_itemcost),'x','sin_error');
  foreach tp in array tablas_compras loop
    perform pg_temp.t('11 Tras 046','Solo pedidos: lee '||tp||' (sin filas o error)',ven,'authenticated',pre_pedidos,format('select 1 from public.%I where company_id=%L',tp,ca),'q','negado');
  end loop;

  -- 11b) Una sola pantalla a la vez: cada una abre lo suyo y nada más.
  perform pg_temp.t('11 Tras 046','Solo resumen: lee órdenes (el resumen las lista)',ven,'authenticated',pre_resumen,format('select 1 from public.purchase_orders where company_id=%L',ca),'q','sin_error');
  perform pg_temp.t('11 Tras 046','Solo resumen: materiales para órdenes (denegado)',ven,'authenticated',pre_resumen,pg_temp.denegado(c_mat),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo resumen: directorio de proveedores (denegado)',ven,'authenticated',pre_resumen,pg_temp.denegado(c_dir),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo resumen: cuenta con proveedor (denegado)',ven,'authenticated',pre_resumen,pg_temp.denegado(c_acc),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo resumen: lee cotizaciones de proveedores (sin filas o error)',ven,'authenticated',pre_resumen,format('select 1 from public.supplier_items where company_id=%L',ca),'q','negado');
  perform pg_temp.t('11 Tras 046','Solo órdenes (ver) CON costs_materials: materiales para órdenes (permitido)',ven,'authenticated',pre_ordenes,pg_temp.permitido(c_mat),'x','sin_error');
  perform pg_temp.t('11 Tras 046','046b: Solo órdenes (ver) SIN costs_materials: materiales con precios (denegado)',ven,'authenticated',pre_ordenes_nc,pg_temp.denegado(c_mat),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo órdenes (ver): directorio de proveedores (denegado)',ven,'authenticated',pre_ordenes,pg_temp.denegado(c_dir),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo órdenes (ver): crear orden (denegado: falta crear)',ven,'authenticated',pre_ordenes,pg_temp.denegado(c_corder),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo órdenes (ver): recibir (denegado: falta crear)',ven,'authenticated',pre_ordenes,pg_temp.denegado(c_rec),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo órdenes (ver): cancelar (denegado: falta editar)',ven,'authenticated',pre_ordenes,pg_temp.denegado(c_cancel),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo órdenes (ver): cuenta con proveedor (denegado)',ven,'authenticated',pre_ordenes,pg_temp.denegado(c_acc),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Órdenes con crear/editar: crear orden (permitido)',ven,'authenticated',pre_ordenes_w,pg_temp.permitido(c_corder),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Órdenes con crear/editar: cancelar (permitido)',ven,'authenticated',pre_ordenes_w,pg_temp.permitido(c_cancel),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Órdenes con crear/editar: rechazar pedido (denegado)',ven,'authenticated',pre_ordenes_w,pg_temp.denegado(c_rej),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Órdenes con crear/editar: convertir pedido (denegado: falta Gestionar)',ven,'authenticated',pre_ordenes_w,pg_temp.denegado(c_conv),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo proveedores (ver): directorio y catálogo (permitido)',ven,'authenticated',pre_prov,pg_temp.permitido(c_dir),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo proveedores (ver): tipos de cambio (permitido)',ven,'authenticated',pre_prov,pg_temp.permitido(c_rate),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo proveedores (ver): guardar cotización (denegado: falta editar)',ven,'authenticated',pre_prov,pg_temp.denegado(c_save),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo proveedores (ver): ajustar precios (denegado)',ven,'authenticated',pre_prov,pg_temp.denegado(c_adj),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo proveedores (ver): proveedor preferido (denegado)',ven,'authenticated',pre_prov,pg_temp.denegado(c_pref),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo proveedores (ver): cargar tipo de cambio (denegado)',ven,'authenticated',pre_prov,pg_temp.denegado(c_addrate),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Solo proveedores (ver): lee órdenes (sin filas o error)',ven,'authenticated',pre_prov,format('select 1 from public.purchase_orders where company_id=%L',ca),'q','negado');
  perform pg_temp.t('11 Tras 046','Solo proveedores (ver): crear orden (denegado)',ven,'authenticated',pre_prov,pg_temp.denegado(c_corder),'x','sin_error');

  -- 11c) Gestionar pedidos ('manage'): sin Gestionar no se rechaza ni se convierte, aunque pueda editar.
  perform pg_temp.t('11 Tras 046','Editar pedidos sin Gestionar: rechazar (denegado)',ven,'authenticated',pre_sin_manage,pg_temp.denegado(c_rej),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Editar pedidos sin Gestionar: convertir (denegado)',ven,'authenticated',pre_sin_manage,pg_temp.denegado(c_conv),'x','sin_error');

  -- 11d) Costos de materiales (H-011): solo con costs_materials.
  perform pg_temp.t('11 Tras 046','Vendedor (compras completo, sin costs_materials): costo del proveedor en la ficha (denegado)',ven,'authenticated',null,pg_temp.denegado(c_itemcost),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Vendedor sin costs_materials: JSON de ítems sin valores de costo de referencia (H-011)',ven,'authenticated',null,format($q$select 1 where public.list_production_items(%L,true)::text ~ '"reference_unit_cost": [^n]'$q$,ca),'q','negado');
  perform pg_temp.t('11 Tras 046','Vendedor conserva convertir pedidos (tiene Gestionar y crear órdenes)',ven,'authenticated',null,pg_temp.permitido(c_conv),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Vendedor sigue sin poder rechazar (no tiene editar en pedidos)',ven,'authenticated',null,pg_temp.denegado(c_rej),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Vendedor conserva tipos de cambio (Proveedores)',ven,'authenticated',null,pg_temp.permitido(c_rate),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Encargado de compras con costs_materials: costo del proveedor en la ficha (permitido)',ven,'authenticated',pre_encargado,pg_temp.permitido(c_itemcost),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Encargado de compras: JSON de ítems (INFO: puede traer costos de referencia)',ven,'authenticated',pre_encargado,format($q$select 1 where public.list_production_items(%L,true)::text ~ '"reference_unit_cost": [^n]'$q$,ca),'q','info');
  perform pg_temp.t('11 Tras 046','Encargado: materiales para órdenes',ven,'authenticated',pre_encargado,pg_temp.permitido(c_mat),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Encargado: directorio de proveedores',ven,'authenticated',pre_encargado,pg_temp.permitido(c_dir),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Encargado: cuenta con proveedor (compras + finanzas)',ven,'authenticated',pre_encargado,pg_temp.permitido(c_acc),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Encargado: rechazar pedido (Gestionar + editar)',ven,'authenticated',pre_encargado,pg_temp.permitido(c_rej),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Encargado: convertir pedido en orden',ven,'authenticated',pre_encargado,pg_temp.permitido(c_conv),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Encargado: guardar cotización',ven,'authenticated',pre_encargado,pg_temp.permitido(c_save),'x','sin_error');

  -- 11d2) H-011 (ABIERTO, decide el propietario): precios de proveedor por tabla, aunque falte costs_materials.
  perform pg_temp.t('11 Tras 046','H-011 INFO: Vendedor sin costs_materials lee precios en supplier_items (si da filas, el precio de proveedor sigue visible)',ven,'authenticated',null,format('select unit_price from public.supplier_items where company_id=%L',ca),'q','info');
  perform pg_temp.t('11 Tras 046','Pedidos: la lectura de purchase_requests no falla para quien solo pide (control del P0 de la revisión)',ven,'authenticated',pre_pedidos,format('select 1 from public.purchase_requests where company_id=%L',ca),'q','sin_error');

  -- 11e) Administrador, otras empresas y anónimo.
  perform pg_temp.t('11 Tras 046','Admin A: materiales, costo en la ficha y cuenta con proveedor (permitidos)',adm,'authenticated',null,pg_temp.permitido(c_mat),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Admin A: costo del proveedor en la ficha',adm,'authenticated',null,pg_temp.permitido(c_itemcost),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Admin A: cuenta con proveedor',adm,'authenticated',null,pg_temp.permitido(c_acc),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Admin B (otra empresa): materiales de A (denegado)',dem,'authenticated',null,pg_temp.denegado(c_mat),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Admin B: costo en la ficha de A (denegado)',dem,'authenticated',null,pg_temp.denegado(c_itemcost),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Vendedor (solo A): materiales de B (denegado)',ven,'authenticated',null,pg_temp.denegado(format('public.purchase_material_options(%L,%L,null)',cb,'')),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Anónimo: materiales de A',null,'anon',null,'select * from '||c_mat,'q','error');
  perform pg_temp.t('11 Tras 046','Anónimo: costo en la ficha de A',null,'anon',null,'select * from '||c_itemcost,'q','error');

  -- 11f) Catálogo: "Gestionar" solo en Pedidos internos; los costos solo admiten ver.
  perform pg_temp.t('11 Tras 046','Catálogo: solo purchase_requests admite manage',ven,'authenticated',null,
    $q$select 1 where (select array_agg(resource) from public.permission_catalog where 'manage' = any (actions)) = array['purchase_requests']$q$,'q','datos');
  perform pg_temp.t('11 Tras 046','Catálogo: las 5 pantallas de Compras y costs_materials figuran como exigidas',ven,'authenticated',null,
    $q$select 1 where (select count(*) from public.permission_catalog where enforced and resource in ('purchases','purchases_overview','purchase_requests','purchases_orders','purchases_suppliers','purchases_accounts','costs_materials'))=7$q$,'q','datos');
  perform pg_temp.t('11 Tras 046','Admin A: rol con Gestionar en Pedidos internos se guarda',adm,'authenticated',null,
    format($q$select public.create_company_role(%L,'Encargado t','encargado_t','[{"resource":"purchase_requests","action":"read"},{"resource":"purchase_requests","action":"manage"}]'::jsonb)$q$,ca),'x','sin_error');
  perform pg_temp.t('11 Tras 046','Admin A: Gestionar en Órdenes de compra se rechaza (no existe)',adm,'authenticated',null,
    format($q$select public.create_company_role(%L,'Raro t','raro2_t','[{"resource":"purchases_orders","action":"manage"}]'::jsonb)$q$,ca),'x','error');

  ----------------------------------------------------------------------------------------------------
  -- 12) TRAS LA MIGRACIÓN 047 (antes de aplicarla, estos casos dan FALLA: es lo esperado).
  --     Producción por pantalla + costs_production. Se reemplazan los permisos de Producción del rol del Vendedor DENTRO del punto de
  --     guardado (se revierte). "Denegado" = 42501; "Permitido" = no hay 42501 (un error de validación posterior vale).
  ----------------------------------------------------------------------------------------------------
  p_ov    := pg_temp.setrole_prod(ca, rol_ven_a, 'production_overview:read');
  p_ord   := pg_temp.setrole_prod(ca, rol_ven_a, 'production_orders:read,production_orders:insert,production_orders:update');
  p_ordr  := pg_temp.setrole_prod(ca, rol_ven_a, 'production_orders:read');
  p_stats := pg_temp.setrole_prod(ca, rol_ven_a, 'production_stats:read');
  p_plan  := pg_temp.setrole_prod(ca, rol_ven_a, 'production_planning:read,production_planning:insert,production_planning:update');
  p_form  := pg_temp.setrole_prod(ca, rol_ven_a, 'production_formulas:read,production_formulas:update');
  p_pack  := pg_temp.setrole_prod(ca, rol_ven_a, 'production_packaging:read,production_packaging:update');
  p_avail := pg_temp.setrole_prod(ca, rol_ven_a, 'production_availability:read');
  p_costs := pg_temp.setrole_prod(ca, rol_ven_a, 'production_orders:read,costs_production:read');

  q_dash  := format('public.erp_production_dashboard(%L)', ca);
  q_jobs  := format('public.list_production_jobs(%L)', ca);
  q_runs  := format('public.list_production_runs(%L)', ca);
  q_plans := format('public.list_production_plans(%L)', ca);
  q_can   := format('public.erp_can_manufacture(%L,gen_random_uuid(),1)', ca);
  q_stats := format('public.production_output_summary(%L,%L::date,%L::date,%L,null,%L)', ca, '2026-01-01', '2026-12-31', 'month', 'America/Argentina/Buenos_Aires');
  q_prod  := format('public.production_output_by_product(%L,%L::date,%L::date,%L,25,0,%L)', ca, '2026-01-01', '2026-12-31', '', 'America/Argentina/Buenos_Aires');
  q_cjob  := format('public.create_production_job(%L,gen_random_uuid(),1,gen_random_uuid(),null,%L,gen_random_uuid(),null)', ca, 'x');
  q_start := format('public.start_production_job(%L,gen_random_uuid())', ca);
  q_cxl   := format('public.cancel_production_job(%L,gen_random_uuid(),%L)', ca, 'prueba');
  q_ret   := format('public.return_production_material(%L,gen_random_uuid(),gen_random_uuid(),1,%L,gen_random_uuid())', ca, 'prueba');
  q_cplan := format('public.create_production_plan(%L,gen_random_uuid(),1,gen_random_uuid(),null,%L,gen_random_uuid())', ca, 'x');
  q_form  := format('public.save_production_formula(%L,gen_random_uuid(),1,%L::jsonb)', ca, '[]');
  q_pkg   := format('public.save_production_packaging_type(%L,null,%L,1,gen_random_uuid(),true)', ca, 'Prueba');
  q_fcost := format('public.production_formula_cost(%L,gen_random_uuid())', ca);
  q_repl  := format('public.erp_replenishment_forecast(%L)', ca);

  -- 12a) Solo Resumen: ve el tablero y las listas de órdenes, nada más.
  perform pg_temp.t('12 Tras 047','Solo resumen: tablero de producción (permitido)',ven,'authenticated',p_ov,pg_temp.permitido(q_dash),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo resumen: lista de órdenes (permitido)',ven,'authenticated',p_ov,format($q$select 1 where jsonb_array_length(%s)>0$q$,q_jobs),'q','datos');
  perform pg_temp.t('12 Tras 047','Solo resumen: crear orden (denegado)',ven,'authenticated',p_ov,pg_temp.denegado(q_cjob),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo resumen: planes (denegado)',ven,'authenticated',p_ov,format($q$select 1 where jsonb_array_length(%s)>0$q$,q_plans),'q','negado');
  perform pg_temp.t('12 Tras 047','Solo resumen: estadística (denegado)',ven,'authenticated',p_ov,pg_temp.denegado(q_stats),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo resumen: ¿alcanza el stock? (denegado)',ven,'authenticated',p_ov,pg_temp.denegado(q_can),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo resumen: guardar fórmula (denegado)',ven,'authenticated',p_ov,pg_temp.denegado(q_form),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo resumen: lee fórmulas (sin filas o error)',ven,'authenticated',p_ov,format('select 1 from public.production_formulas where company_id=%L',ca),'q','negado');
  perform pg_temp.t('12 Tras 047','Solo resumen: lee planes (sin filas o error)',ven,'authenticated',p_ov,format('select 1 from public.production_plans where company_id=%L',ca),'q','negado');
  perform pg_temp.t('12 Tras 047','Solo resumen: lee eventos de órdenes (sin filas o error)',ven,'authenticated',p_ov,format('select 1 from public.production_job_events where company_id=%L',ca),'q','negado');

  -- 12b) Solo Órdenes: opera órdenes; no ve planes, estadística, tablero ni reposición.
  perform pg_temp.t('12 Tras 047','Solo órdenes (ver): lista de órdenes y corridas (permitido)',ven,'authenticated',p_ordr,format($q$select 1 where jsonb_array_length(%s)>0$q$,q_jobs),'q','datos');
  perform pg_temp.t('12 Tras 047','Solo órdenes (ver): crear orden (denegado: falta crear)',ven,'authenticated',p_ordr,pg_temp.denegado(q_cjob),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo órdenes (ver): iniciar (denegado: falta editar)',ven,'authenticated',p_ordr,pg_temp.denegado(q_start),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Órdenes con crear/editar: crear, iniciar, cancelar y devolver (permitidos)',ven,'authenticated',p_ord,pg_temp.permitido(q_cjob),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Órdenes con crear/editar: iniciar',ven,'authenticated',p_ord,pg_temp.permitido(q_start),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Órdenes con crear/editar: cancelar',ven,'authenticated',p_ord,pg_temp.permitido(q_cxl),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Órdenes con crear/editar: devolver insumo (exige stock:insert, el vendedor lo tiene)',ven,'authenticated',p_ord,pg_temp.permitido(q_ret),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Órdenes con crear/editar: tablero de producción (denegado)',ven,'authenticated',p_ord,pg_temp.denegado(q_dash),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Órdenes con crear/editar: crear plan (denegado)',ven,'authenticated',p_ord,pg_temp.denegado(q_cplan),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Órdenes con crear/editar: guardar fórmula (denegado)',ven,'authenticated',p_ord,pg_temp.denegado(q_form),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Órdenes con crear/editar: guardar presentación (denegado)',ven,'authenticated',p_ord,pg_temp.denegado(q_pkg),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Órdenes con crear/editar: estadística (denegado)',ven,'authenticated',p_ord,pg_temp.denegado(q_stats),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Órdenes: lee fórmulas y presentaciones (necesarias para crear la orden)',ven,'authenticated',p_ord,format('select 1 from public.production_formulas where company_id=%L',ca),'q','datos');
  perform pg_temp.t('12 Tras 047','Órdenes: lee presentaciones',ven,'authenticated',p_ord,format('select 1 from public.production_packaging_types where company_id=%L',ca),'q','info');
  perform pg_temp.t('12 Tras 047','Órdenes: NO lee planes (sin filas o error)',ven,'authenticated',p_ord,format('select 1 from public.production_plans where company_id=%L',ca),'q','negado');

  -- 12c) Una pantalla por rol: estadística, planificación, fórmulas, envases, alcanza.
  perform pg_temp.t('12 Tras 047','Solo estadística: resumen y por producto (permitido)',ven,'authenticated',p_stats,pg_temp.permitido(q_stats),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo estadística: por producto',ven,'authenticated',p_stats,pg_temp.permitido(q_prod),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo estadística: lista de órdenes (denegado)',ven,'authenticated',p_stats,format($q$select 1 where jsonb_array_length(%s)>0$q$,q_jobs),'q','negado');
  perform pg_temp.t('12 Tras 047','Solo estadística: tablero (denegado)',ven,'authenticated',p_stats,pg_temp.denegado(q_dash),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo planificación: lista y crear plan (permitido)',ven,'authenticated',p_plan,format($q$select 1 where jsonb_array_length(%s)>0$q$,q_plans),'q','info');
  perform pg_temp.t('12 Tras 047','Solo planificación: completar un plan exige Órdenes (denegado)',ven,'authenticated',p_plan,pg_temp.denegado(format('public.complete_production_plan(%L,gen_random_uuid(),gen_random_uuid(),%L::jsonb,%L,null)',ca,'[]','x')),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo planificación: crear plan',ven,'authenticated',p_plan,pg_temp.permitido(q_cplan),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo planificación: crear orden (denegado)',ven,'authenticated',p_plan,pg_temp.denegado(q_cjob),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo fórmulas: guardar fórmula (permitido)',ven,'authenticated',p_form,pg_temp.permitido(q_form),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo fórmulas: crear orden (denegado)',ven,'authenticated',p_form,pg_temp.denegado(q_cjob),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo fórmulas: lee fórmulas',ven,'authenticated',p_form,format('select 1 from public.production_formulas where company_id=%L',ca),'q','datos');
  perform pg_temp.t('12 Tras 047','Solo envases: guardar presentación (permitido)',ven,'authenticated',p_pack,pg_temp.permitido(q_pkg),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo envases: guardar fórmula (denegado)',ven,'authenticated',p_pack,pg_temp.denegado(q_form),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo "¿alcanza?": simulador (permitido)',ven,'authenticated',p_avail,pg_temp.permitido(q_can),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Solo "¿alcanza?": lista de planes (denegado)',ven,'authenticated',p_avail,format($q$select 1 where jsonb_array_length(%s)>0$q$,q_plans),'q','negado');

  -- 12d) Costos de producción: solo administrador o costs_production.
  perform pg_temp.t('12 Tras 047','Sin costs_production: costo de la fórmula (denegado)',ven,'authenticated',p_ord,pg_temp.denegado(q_fcost),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Con costs_production (no admin): costo de la fórmula (permitido)',ven,'authenticated',p_costs,pg_temp.permitido(q_fcost),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Con costs_production: sus órdenes traen costos (INFO)',ven,'authenticated',p_costs,format($q$select 1 where public.list_production_jobs(%L)::text ~ '"unit_cost": [^n]'$q$,ca),'q','info');
  perform pg_temp.t('12 Tras 047','Control: con el rol de prueba la lista de órdenes NO está vacía (si no, los casos de costos no prueban nada)',ven,'authenticated',p_costs,format($q$select 1 where jsonb_array_length(%s)>0$q$,q_jobs),'q','datos');
  perform pg_temp.t('12 Tras 047','Sin costs_production: JSON de órdenes sin valores de costo',ven,'authenticated',p_ord,format($q$select 1 where public.list_production_jobs(%L)::text ~ '"unit_cost": [^n]'$q$,ca),'q','negado');
  perform pg_temp.t('12 Tras 047','Sin costs_production: JSON de corridas sin valores de costo',ven,'authenticated',p_ord,format($q$select 1 where public.list_production_runs(%L)::text ~ '"(unit_cost|estimated_cost)": [^n]'$q$,ca),'q','negado');
  perform pg_temp.t('12 Tras 047','Vendedor actual (sin costs_production): costo de la fórmula (denegado)',ven,'authenticated',null,pg_temp.denegado(q_fcost),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Admin A: costo de la fórmula (permitido)',adm,'authenticated',null,pg_temp.permitido(q_fcost),'x','sin_error');

  -- 12e) Reposición, otras empresas y anónimo.
  perform pg_temp.t('12 Tras 047','Reposición solo con producción:reposición + stock (INFO: filas que devuelve)',ven,'authenticated',pg_temp.setrole_prod(ca, rol_ven_a, 'production_replenishment:read,stock_levels:read'),'select * from '||q_repl,'q','info');
  perform pg_temp.t('12 Tras 047','Sin la pantalla de reposición: pronóstico vacío (negado)',ven,'authenticated',p_ord,'select * from '||q_repl,'q','negado');
  perform pg_temp.t('12 Tras 047','Admin B (otra empresa): crear orden en A (denegado)',dem,'authenticated',null,pg_temp.denegado(q_cjob),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Admin B: costo de fórmula de A (denegado)',dem,'authenticated',null,pg_temp.denegado(q_fcost),'x','sin_error');
  perform pg_temp.t('12 Tras 047','Anónimo: estadística de A',null,'anon',null,'select * from '||q_stats,'q','error');
  perform pg_temp.t('12 Tras 047','Catálogo: pantallas de Producción y costs_production exigidas (11)',ven,'authenticated',null,
    $q$select 1 where (select count(*) from public.permission_catalog where enforced and (module='production' or resource='costs_production'))=11$q$,'q','datos');

  ----------------------------------------------------------------------------------------------------
  -- 13) TRAS LA MIGRACIÓN 048 (antes de aplicarla, estos casos dan FALLA: es lo esperado).
  --     Stock por pantalla (LECTURAS) y Archivados por pantalla. El rol del Vendedor se reemplaza ENTERO dentro del punto de guardado
  --     (se revierte). Las ESCRITURAS de Stock siguen a nivel módulo (ver cabecera de la 048).
  --     Nota: un "negado" con 0 filas es débil si la tabla está vacía en esa empresa; los casos "datos" prueban que hay filas.
  ----------------------------------------------------------------------------------------------------
  -- 13a) Solo "Stock por depósito" (ver).
  perform pg_temp.t('13 Tras 048','Solo stock por depósito: stock_summary (permitido)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_levels:read'),pg_temp.permitido(format('public.stock_summary(%L,1,%L)',ca,'')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Solo stock por depósito: lee saldos (control: hay filas)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_levels:read'),format('select 1 from public.stock_balances where company_id=%L',ca),'q','datos');
  perform pg_temp.t('13 Tras 048','Solo stock por depósito: opciones de ítems (permitido)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_levels:read'),pg_temp.permitido(format('public.stock_item_options(%L,%L)',ca,'')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Solo stock por depósito: lee movimientos (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_levels:read'),format('select 1 from public.stock_movements where company_id=%L',ca),'q','negado');
  perform pg_temp.t('13 Tras 048','Solo stock por depósito: lee operaciones de stock (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_levels:read'),format('select 1 from public.stock_operations where company_id=%L',ca),'q','negado');
  perform pg_temp.t('13 Tras 048','Solo stock por depósito: lee remitos (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_levels:read'),format('select 1 from public.delivery_notes where company_id=%L',ca),'q','negado');
  perform pg_temp.t('13 Tras 048','Con stock_levels:insert pero sin el módulo: ingreso manual (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_levels:read,stock_levels:insert'),
    pg_temp.denegado(format('public.post_stock_operation(%L,gen_random_uuid(),gen_random_uuid(),null,%L,1,%L,gen_random_uuid(),null,null)',ca,'in','prueba')),'x','sin_error');
  -- 13b) Solo "Movimientos".
  perform pg_temp.t('13 Tras 048','Solo movimientos: lee movimientos (control: hay filas)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_movements:read'),format('select 1 from public.stock_movements where company_id=%L',ca),'q','datos');
  perform pg_temp.t('13 Tras 048','Solo movimientos: lee saldos (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_movements:read'),format('select 1 from public.stock_balances where company_id=%L',ca),'q','negado');
  perform pg_temp.t('13 Tras 048','Solo movimientos: lee lotes (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_movements:read'),format('select 1 from public.stock_lots where company_id=%L',ca),'q','negado');
  perform pg_temp.t('13 Tras 048','Solo movimientos: stock_summary (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_movements:read'),pg_temp.denegado(format('public.stock_summary(%L,1,%L)',ca,'')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Solo movimientos: desglose de lotes de un ítem (denegado: devuelve saldo por lote)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_movements:read'),pg_temp.denegado(format('public.stock_lot_breakdown(%L,gen_random_uuid())',ca)),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Solo movimientos: opciones de lotes (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_movements:read'),pg_temp.denegado(format('public.stock_lot_options(%L,gen_random_uuid(),gen_random_uuid())',ca)),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Solo resumen de stock (inventory): lee lotes (INFO: filas si A tiene lotes)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,inventory:read'),format('select 1 from public.stock_lots where company_id=%L',ca),'q','info');
  perform pg_temp.t('13 Tras 048','Solo movimientos: opciones de depósitos (permitido)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_movements:read'),pg_temp.permitido(format('public.stock_warehouse_options(%L,%L)',ca,'')),'x','sin_error');
  -- 13c) Solo "Remitos de entrega" y solo "Resumen de stock".
  perform pg_temp.t('13 Tras 048','Solo remitos: lee remitos (INFO: filas si A tiene remitos)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_delivery_notes:read'),format('select 1 from public.delivery_notes where company_id=%L',ca),'q','info');
  perform pg_temp.t('13 Tras 048','Solo remitos: lee movimientos (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_delivery_notes:read'),format('select 1 from public.stock_movements where company_id=%L',ca),'q','negado');
  perform pg_temp.t('13 Tras 048','Solo remitos: opciones de lotes (permitido)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_delivery_notes:read'),pg_temp.permitido(format('public.stock_lot_options(%L,gen_random_uuid(),gen_random_uuid())',ca)),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Solo resumen de stock: stock_summary (permitido)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,inventory:read'),pg_temp.permitido(format('public.stock_summary(%L,1,%L)',ca,'')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Solo resumen de stock: lee movimientos (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,inventory:read'),format('select 1 from public.stock_movements where company_id=%L',ca),'q','negado');
  perform pg_temp.t('13 Tras 048','Sin ninguna pantalla de Stock: stock_summary (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,items:read'),pg_temp.denegado(format('public.stock_summary(%L,1,%L)',ca,'')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Sin ninguna pantalla de Stock: lee saldos (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,items:read'),format('select 1 from public.stock_balances where company_id=%L',ca),'q','negado');
  -- 13d) Producción + Stock por depósito (caso del operario, H-O1).
  perform pg_temp.t('13 Tras 048','Operario (órdenes + stock por depósito): lee reservas (INFO)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,production_orders:read,stock_levels:read'),format('select 1 from public.production_job_reservations where company_id=%L',ca),'q','info');
  perform pg_temp.t('13 Tras 048','Órdenes SIN stock por depósito: lee reservas (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,production_orders:read'),format('select 1 from public.production_job_reservations where company_id=%L',ca),'q','negado');
  perform pg_temp.t('13 Tras 048','Órdenes SIN stock por depósito: ubicaciones de reserva (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,production_orders:read'),format('select 1 from public.production_reservation_locations where company_id=%L',ca),'q','negado');
  perform pg_temp.t('13 Tras 048','Órdenes + stock por depósito: recalcular reservas (permitido)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,production_orders:read,stock_levels:read'),pg_temp.permitido(format('public.recalculate_production_reservations(%L)',ca)),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Órdenes SIN stock por depósito: recalcular reservas (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,production_orders:read'),pg_temp.denegado(format('public.recalculate_production_reservations(%L)',ca)),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Alcanza + stock por depósito: ¿alcanza? (permitido)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,production_availability:read,stock_levels:read'),pg_temp.permitido(q_can),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Alcanza SIN stock por depósito: ¿alcanza? (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,production_availability:read'),pg_temp.denegado(q_can),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Reposición SIN stock por depósito: pronóstico vacío (negado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,production_replenishment:read'),'select * from '||q_repl,'q','negado');
  perform pg_temp.t('13 Tras 048','Reposición + stock por depósito: pronóstico (INFO: filas)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,production_replenishment:read,stock_levels:read'),'select * from '||q_repl,'q','info');
  -- 13e) Archivados por pantalla (cleanup_preview exige eliminar en la pantalla del recurso; un error de validación posterior vale como permitido).
  perform pg_temp.t('13 Tras 048','Archivar fórmula con production_formulas:delete (permitido)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,production_formulas:delete'),pg_temp.permitido(format('public.cleanup_preview(%L,%L,gen_random_uuid())',ca,'formulas')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Archivar fórmula con solo production_orders:delete (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,production_orders:delete'),pg_temp.denegado(format('public.cleanup_preview(%L,%L,gen_random_uuid())',ca,'formulas')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Archivar orden con production_orders:delete (permitido)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,production_orders:delete'),pg_temp.permitido(format('public.cleanup_preview(%L,%L,gen_random_uuid())',ca,'jobs')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Archivar orden con solo production_planning:delete (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,production_planning:delete'),pg_temp.denegado(format('public.cleanup_preview(%L,%L,gen_random_uuid())',ca,'jobs')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Archivar plan con production_planning:delete (permitido)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,production_planning:delete'),pg_temp.permitido(format('public.cleanup_preview(%L,%L,gen_random_uuid())',ca,'plans')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Archivar remito con stock_delivery_notes:delete (permitido)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_delivery_notes:delete'),pg_temp.permitido(format('public.cleanup_preview(%L,%L,gen_random_uuid())',ca,'delivery_notes')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Archivar remito con solo stock_movements:delete (denegado)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,stock_movements:delete'),pg_temp.denegado(format('public.cleanup_preview(%L,%L,gen_random_uuid())',ca,'delivery_notes')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Archivar tipo de cambio con purchases_suppliers:delete (permitido)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,purchases_suppliers:delete'),pg_temp.permitido(format('public.cleanup_preview(%L,%L,gen_random_uuid())',ca,'exchange_types')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Archivar ítem con items:delete (permitido)',ven,'authenticated',pg_temp.setrole_all(ca,rol_ven_a,'dashboard:read,items:delete'),pg_temp.permitido(format('public.cleanup_preview(%L,%L,gen_random_uuid())',ca,'items')),'x','sin_error');
  -- 13f) Administradores, otra empresa y anónimo.
  perform pg_temp.t('13 Tras 048','Admin A: stock_summary (permitido)',adm,'authenticated',null,pg_temp.permitido(format('public.stock_summary(%L,1,%L)',ca,'')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Admin A: lee saldos (control: hay filas)',adm,'authenticated',null,format('select 1 from public.stock_balances where company_id=%L',ca),'q','datos');
  perform pg_temp.t('13 Tras 048','Admin B (otra empresa): stock_summary de A (denegado)',dem,'authenticated',null,pg_temp.denegado(format('public.stock_summary(%L,1,%L)',ca,'')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Admin B: opciones de ítems de A (denegado)',dem,'authenticated',null,pg_temp.denegado(format('public.stock_item_options(%L,%L)',ca,'')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Admin B: archivar una fórmula de A (denegado)',dem,'authenticated',null,pg_temp.denegado(format('public.cleanup_preview(%L,%L,gen_random_uuid())',ca,'formulas')),'x','sin_error');
  perform pg_temp.t('13 Tras 048','Anónimo: stock_summary de A',null,'anon',null,format('select * from public.stock_summary(%L,1,%L)',ca,''),'q','error');
  perform pg_temp.t('13 Tras 048','Catálogo: pantallas de Stock y Ajustes exigidas (9)',ven,'authenticated',null,
    $q$select 1 where (select count(*) from public.permission_catalog where enforced and resource in ('inventory','items','stock','stock_levels','stock_movements','stock_delivery_notes','units','categories','warehouses'))=9$q$,'q','datos');

end
$do$;

-- Resultado: primero los FALLA, luego INFO, luego PASA.
select n, grupo, caso, esperado, obtenido, resultado
from _res
order by case resultado when 'FALLA' then 0 when 'INFO' then 1 else 2 end, n;

-- NOTAS PARA INTERPRETAR
-- * "negado" pasa con error o con 0 filas. Un 0 puede ser trivial si la tabla está vacía en esa empresa: los controles del
--   grupo 1 muestran que A tiene datos en items, producción y depósitos; el resto se confirma en el recorrido de la app.
-- * Grupo 5 (HISTÓRICO, antes de 046): el vendedor tenía purchases:read y por eso veía el costo de referencia (D-004: admin o
--   compras). Si el vendedor NO debe ver costos de materiales, hay que quitarle purchases del rol (o separar permisos: Fase 4).
-- * H-007 (grupo 6, INFO): si "sin error", la escalada está confirmada con pruebas; tras la migración 044 debe dar ERROR.

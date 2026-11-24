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
end
$do$;

-- Resultado: primero los FALLA, luego INFO, luego PASA.
select n, grupo, caso, esperado, obtenido, resultado
from _res
order by case resultado when 'FALLA' then 0 when 'INFO' then 1 else 2 end, n;

-- NOTAS PARA INTERPRETAR
-- * "negado" pasa con error o con 0 filas. Un 0 puede ser trivial si la tabla está vacía en esa empresa: los controles del
--   grupo 1 muestran que A tiene datos en items, producción y depósitos; el resto se confirma en el recorrido de la app.
-- * Grupo 5: el vendedor tiene purchases:read, por eso la referencia de costo de ítems es visible (diseño D-004: admin o
--   compras). Si el vendedor NO debe ver costos de materiales, hay que quitarle purchases del rol (o separar permisos: Fase 4).
-- * H-007 (grupo 6, INFO): si "sin error", la escalada está confirmada con pruebas; tras la migración 044 debe dar ERROR.

-- Solo lectura. Esperado: catalogo = true, admins_sin_gestionar = 0, cancelar_exige_gestionar = true,
-- stock_con_ayudante = 2, marcan_la_orden = 3, ejecuta_stock = false, ejecuta_operar = false.
-- roles_con_gestionar y no_pueden_cancelar son informativos.
select
  (select acciones = array['ver','crear','editar','eliminar','gestionar']::text[]
     from public.ajustes_permisos_catalogo where recurso = 'produccion_ordenes') as catalogo,
  (select count(*) from public.ajustes_roles r where r.codigo = 'administrador' and not exists (
     select 1 from public.ajustes_roles_permisos p where p.rol_id = r.id
       and p.recurso = 'produccion_ordenes' and p.accion = 'gestionar')) as admins_sin_gestionar,
  (select position('''produccion_ordenes'',''gestionar''' in prosrc) > 0 from pg_proc
     where oid = 'public.cancel_production_job(uuid,uuid,text)'::regprocedure) as cancelar_exige_gestionar,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'private') and p.proname = 'post_stock_operation'
       and position('private.can_post_stock(p_company)' in p.prosrc) > 0) as stock_con_ayudante,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('issue_production_material', 'return_production_material', 'finish_production_job')
       and position('dromux.production_job' in p.prosrc) > 0) as marcan_la_orden,
  has_function_privilege('authenticated', 'private.can_post_stock(uuid)', 'execute') as ejecuta_stock,
  has_function_privilege('authenticated', 'private.can_operate_production(uuid)', 'execute') as ejecuta_operar,
  (select count(*) from public.ajustes_roles_permisos
     where recurso = 'produccion_ordenes' and accion = 'gestionar') as roles_con_gestionar,
  (select count(*) from public.ajustes_roles_permisos e join public.ajustes_roles r on r.id = e.rol_id
     where e.recurso = 'produccion_ordenes' and e.accion = 'editar' and r.codigo <> 'administrador'
       and not exists (select 1 from public.ajustes_roles_permisos g where g.rol_id = e.rol_id
         and g.recurso = 'produccion_ordenes' and g.accion = 'gestionar')) as no_pueden_cancelar;

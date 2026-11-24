-- Comprobaciones de solo lectura para 044. No leen datos de clientes.

-- 0) ANTES de aplicar: roles que no son admin pero gestionan roles/usuarios, y roles con código support.
-- Esos permisos quedan inertes para las 3 funciones; revisar si hay que quitarlos desde Roles y permisos.
select r.company_id, r.code, count(*) filter (where rp.resource in ('roles','users')) as permisos_gestion
from public.roles r left join public.role_permissions rp on rp.role_id = r.id
where r.code = 'support' or (r.code <> 'admin' and exists (select 1 from public.role_permissions x where x.role_id = r.id and x.resource in ('roles','users')))
group by 1, 2;
-- Esperado el 24/11: 0 filas.

-- DESPUÉS de aplicar:

-- 1) Funciones: misma firma, SECURITY DEFINER, search_path vacío, anon sin acceso.
select p.oid::regprocedure as firma, p.prosecdef as security_definer,
  coalesce(array_to_string(p.proconfig, ','), '') as config,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where (n.nspname = 'public' and p.proname in ('create_company_role', 'update_company_role', 'set_company_member', 'access_audit_events_list'))
   or (n.nspname = 'private' and p.proname in ('log_access_event', 'access_audit_immutable'))
order by 1;
-- Esperado: 6 filas. secdef = true en las públicas y en log_access_event; search_path="" en todas; anon = false.
-- authenticated = true en las 3 funciones de ajustes (mismos permisos que antes) y en access_audit_events_list; false en las privadas.

-- 2) Las 3 funciones exigen administrador (texto del cuerpo).
select p.proname, position('get_user_role(p_company) is distinct from ''admin''' in p.prosrc) > 0 as exige_admin,
  position('log_access_event' in p.prosrc) > 0 as audita
from pg_proc p where p.pronamespace = 'public'::regnamespace
  and p.proname in ('create_company_role', 'update_company_role', 'set_company_member');
-- Esperado: 3 filas con exige_admin = true y audita = true.

-- 3) Tabla de historial: RLS activa, sin privilegios para anon/authenticated, 2 disparadores de inmutabilidad.
select c.relrowsecurity as rls,
  has_table_privilege('authenticated', c.oid, 'SELECT,INSERT,UPDATE,DELETE') as auth_any,
  has_table_privilege('anon', c.oid, 'SELECT,INSERT,UPDATE,DELETE') as anon_any,
  (select count(*) from pg_trigger t where t.tgrelid = c.oid and not t.tgisinternal) as disparadores
from pg_class c where c.oid = 'public.access_audit_events'::regclass;
-- Esperado: rls = true, auth_any = false, anon_any = false, disparadores = 2.

-- PRUEBAS DE COMPORTAMIENTO: supabase/verificaciones/pruebas_roles_empresas.sql, grupo "9 Tras 044" (todo debe PASAR).

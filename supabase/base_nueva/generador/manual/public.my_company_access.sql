create or replace function public.my_company_access()
returns table(company_id uuid, company_name text, company_slug text, company_active boolean, role_id uuid, role_name text, role_code text, company_modules jsonb)
language sql
stable
security definer
set search_path to ''
as $function$
  select cu.empresa_id, c.nombre, c.identificador, c.activo, cu.rol_id, r.nombre, r.codigo, c.modulos
  from public.empresas_usuarios cu
  join public.empresas c on c.id = cu.empresa_id
  join public.ajustes_roles r on r.id = cu.rol_id and r.empresa_id = cu.empresa_id
  where cu.usuario_id = (select auth.uid()) and cu.activo
  union all
  select c.id, c.nombre, c.identificador, c.activo, null::uuid, 'Soporte Dromux', 'soporte', c.modulos
  from public.empresas c
  where c.activo and exists (
    select 1 from private.soporte_operadores so
    where so.usuario_id = (select auth.uid()) and so.activo
  ) and not exists (
    select 1 from public.empresas_usuarios cu
    where cu.empresa_id = c.id and cu.usuario_id = (select auth.uid()) and cu.activo
  )
$function$

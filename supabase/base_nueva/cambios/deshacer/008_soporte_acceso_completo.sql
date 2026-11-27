-- Deshace el cambio 008: soporte vuelve a solo lectura, sin costos, durante 30 minutos.
begin;

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

drop function if exists public.end_support_session();
-- Las sesiones abiertas no deben superar la duración anterior.
update private.soporte_sesiones set vence_en = least(vence_en, now() + interval '30 minutes');

commit;

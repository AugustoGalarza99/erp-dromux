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
$function$

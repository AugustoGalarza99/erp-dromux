-- Un módulo apagado en empresas.modulos bloquea sus permisos.
-- Inicio, Ajustes, permisos de costos y los datos base (ítems, unidades,
-- categorías y depósitos) no dependen de ningún módulo.
create or replace function private.module_enabled(p_company uuid, p_resource text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  with pedido as (
    select case
      when p_resource in ('items', 'unidades', 'categorias', 'depositos') then null
      else coalesce(
        (select c.modulo from public.ajustes_permisos_catalogo c where c.recurso = p_resource),
        case p_resource
          when 'inventario' then 'stock'
          else p_resource
        end
      )
    end as modulo
  )
  select case
    when p.modulo is null or p.modulo not in ('stock', 'produccion', 'compras', 'ventas', 'finanzas', 'reportes') then true
    else coalesce((select (e.modulos ->> p.modulo)::boolean from public.empresas e where e.id = p_company), false)
  end
  from pedido p
$function$

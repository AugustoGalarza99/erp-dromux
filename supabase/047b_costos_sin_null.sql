-- 047b: corrige una falla de la 047 (y de la 046b) detectada por el caso 336 del script de pruebas.
-- Problema: para quien NO es miembro de la empresa, private.get_user_role() devuelve NULL; "NULL = 'admin' OR false" da NULL (no false),
-- y "if not NULL" no entra al rechazo. Resultado: un usuario de otra empresa pasaba la puerta de production_formula_cost (y de toda
-- función que haga "if not private.can_see_*"). Antes de la 047 era "admin AND finanzas" (NULL AND false = false), por eso no pasaba.
-- Solución: las dos funciones siempre devuelven true/false (coalesce). Misma firma, atributos y permisos.
-- Solo reemplaza dos definiciones; no toca datos ni roles.
begin;

create or replace function private.can_see_production_costs(p_company uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.get_user_role(p_company) = 'admin', false)
      or private.has_permission(p_company, 'costs_production', 'read');
$$;

create or replace function private.can_see_reference_cost(p_company uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.get_user_role(p_company) = 'admin', false)
      or private.has_permission(p_company, 'costs_materials', 'read');
$$;

-- Los permisos no cambian con CREATE OR REPLACE; se verifica que siguen cerrados.
do $$
begin
  if has_function_privilege('anon', 'private.can_see_production_costs(uuid)', 'execute')
     or has_function_privilege('anon', 'private.can_see_reference_cost(uuid)', 'execute') then
    raise exception 'anon no debe ejecutar estas funciones';
  end if;
end $$;

commit;

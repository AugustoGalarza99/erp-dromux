-- Deshacer 047b: vuelve a la versión con NULL (insegura). Solo para diagnóstico; no dejar así en un entorno con más de una empresa.
begin;
create or replace function private.can_see_production_costs(p_company uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select (private.get_user_role(p_company)='admin' or private.has_permission(p_company,'costs_production','read'));
$$;
create or replace function private.can_see_reference_cost(p_company uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.get_user_role(p_company)='admin' or private.has_permission(p_company,'costs_materials','read');
$$;
commit;

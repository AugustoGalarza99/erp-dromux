-- Deshace el PASO 1 (035_costos_funciones.sql) si algo sale mal después de aplicarlo.
-- Vuelve save_item_with_cost, import_items y production_formula_cost a su comportamiento original
-- y borra las funciones nuevas. Es seguro ejecutarlo aunque el paso 2 (036) no se haya aplicado.
-- NO usar si ya aplicaste el paso 2: en ese caso primero revertí el paso 2 (bloque final de 036).
begin;

drop function if exists public.save_item_with_cost(uuid,uuid,jsonb,timestamp with time zone,boolean);
drop function if exists public.import_items(uuid,jsonb);
alter function private.save_item_with_cost(uuid,uuid,jsonb,timestamp with time zone,boolean) set schema public;
alter function private.import_items(uuid,jsonb) set schema public;
revoke all on function public.save_item_with_cost(uuid,uuid,jsonb,timestamp with time zone,boolean),
  public.import_items(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.save_item_with_cost(uuid,uuid,jsonb,timestamp with time zone,boolean),
  public.import_items(uuid,jsonb) to authenticated;

create or replace function public.production_formula_cost(p_company uuid,p_product uuid)
returns numeric
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','read') then
    raise exception 'Sin permiso para consultar costos' using errcode='42501'; end if;
  return private.production_unit_cost(p_company,p_product);
end;
$$;

drop function if exists public.list_production_jobs(uuid);
drop function if exists public.list_production_plans(uuid);
drop function if exists public.list_production_runs(uuid);
drop function if exists public.list_production_items(uuid,boolean);
drop function if exists public.get_item_detail(uuid,uuid);
drop function if exists private.row_has_cost(jsonb);
drop function if exists private.strip_snapshot_cost(jsonb);
drop function if exists private.can_see_reference_cost(uuid);
drop function if exists private.can_see_production_costs(uuid);

commit;

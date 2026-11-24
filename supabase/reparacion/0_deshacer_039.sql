-- Deshace 039 (listas de precios). ATENCIÓN: borra listas, precios, historial y asignaciones a clientes.
-- Aborta mientras existan listas, precios o historial cargados: exportalos antes (o cambiá la guarda
-- solo si decidís descartarlos). No toca items.sale_unit_price ni ventas.
begin;

do $$
begin
  if exists (select 1 from public.price_lists)
     or exists (select 1 from public.price_list_items)
     or exists (select 1 from public.price_list_item_history)
     or exists (select 1 from public.item_sale_settings)
     or exists (select 1 from public.price_settings)
     or exists (select 1 from public.customer_price_lists) then
    raise exception 'Hay listas o precios cargados. Exportalos antes de deshacer la migración 039.';
  end if;
end
$$;

drop function if exists public.erp_resolve_sale_price(uuid, uuid, uuid);
drop function if exists public.erp_price_list_history(uuid, uuid, uuid, integer);
drop function if exists public.erp_admin_price_list_rows(uuid, uuid, text, text, integer, integer);
drop function if exists public.erp_price_list_rows(uuid, uuid, text, boolean, integer, integer);
drop function if exists public.assign_customer_price_list(uuid, uuid, uuid);
drop function if exists public.save_item_sale_settings(uuid, uuid, numeric, numeric, uuid);
drop function if exists public.import_price_list_items(uuid, uuid, jsonb, boolean, text, uuid);
drop function if exists public.bulk_price_change(uuid, uuid, text, numeric, uuid[], boolean, text, uuid);
drop function if exists public.remove_price_list_item(uuid, uuid, uuid, text);
drop function if exists public.set_price_list_item(uuid, uuid, uuid, text, numeric, text);
drop function if exists public.save_price_list(uuid, uuid, text, text, date, date, boolean, uuid, numeric, numeric, text, boolean);
drop function if exists public.erp_price_settings(uuid);
drop function if exists public.save_price_settings(uuid, numeric, numeric, numeric, numeric);

drop table if exists public.customer_price_lists;
drop table if exists public.item_sale_settings;
drop table if exists public.price_change_requests;
drop table if exists public.price_list_item_history;
drop table if exists public.price_list_item_pricing;
drop table if exists public.price_list_items;
drop table if exists public.price_lists;
drop table if exists public.price_settings;

drop function if exists private.price_write(uuid, uuid, uuid, numeric, text, numeric, numeric, boolean, text, text);
drop function if exists private.price_effective(uuid, uuid, text);
drop function if exists private.price_item_cost(uuid, uuid);
drop function if exists private.price_costs(uuid, uuid[]);
drop function if exists private.price_compute(text, numeric, numeric, numeric);
drop function if exists private.price_round(numeric, numeric);
drop function if exists private.price_require_cost_view(uuid);
drop function if exists private.price_require_admin(uuid, boolean);
drop function if exists private.price_history_immutable();
drop function if exists private.price_lists_guard();

commit;

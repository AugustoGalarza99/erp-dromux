-- Solo lectura: comprobar instalación de la versión 031.
select column_name,data_type from information_schema.columns
where table_schema='public' and table_name='items'
  and column_name in ('reference_cost_usd','reference_exchange_rate_type_id')
order by column_name;

select p.oid::regprocedure as function_signature,p.prosecdef as security_definer
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in
  ('preview_item_import','import_items','save_item_with_cost','item_cost_context')
order by p.proname;

select tgname, pg_get_triggerdef(oid) as definition
from pg_catalog.pg_trigger where tgrelid='public.items'::regclass
  and tgname='items_reference_fx_cost';

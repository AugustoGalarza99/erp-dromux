-- Consultas de lectura para comprobar la instalación.
select table_name from information_schema.tables
where table_schema='public' and table_name in
  ('supplier_payment_orders','supplier_payment_order_lines','production_document_settings','production_packaging_types');

select table_name,column_name from information_schema.columns
where table_schema='public' and (
  (table_name='items' and column_name in ('yield_enabled','yield_factor')) or
  (table_name='production_jobs' and column_name in ('number','expected_output','yield_factor','document_snapshot','work_options','details_updated_at')))
order by table_name,column_name;

select n.nspname,p.proname,p.prosecdef from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in
  ('supplier_purchase_statistics','supplier_account','supplier_payable_orders','create_supplier_payment_order',
   'confirm_supplier_payment_order','cancel_supplier_payment_order','save_production_document_settings',
   'save_production_packaging_type','save_production_formula_v2','create_production_work_order','save_production_work_details')
order by p.proname;

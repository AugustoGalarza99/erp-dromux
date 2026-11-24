-- Comprobaciones de solo lectura para 037. No leen datos de clientes.

-- 1) Tope vigente de cada función (esperado tras 037: 500, 500, 500, 200, 200, 200; antes: 40).
select p.proname,
  (regexp_match(p.prosrc, 'between 1 and (\d+)'))[1]::int as tope,
  p.prosecdef as security_definer,
  coalesce(array_to_string(p.proconfig, ','), '') as config,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in (
  'save_production_formula', 'complete_production_now', 'issue_delivery_note',
  'issue_sale_delivery_note', 'create_purchase_order', 'receive_purchase_order')
order by 1;

-- 2) Las funciones de dinero deben seguir en 40 (no se tocan en 037).
select p.proname, (regexp_match(p.prosrc, 'between 1 and (\d+)'))[1]::int as tope
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('post_sale', 'adjust_sale', 'create_supplier_payment_order')
order by 1;

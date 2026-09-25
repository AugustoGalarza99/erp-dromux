-- Consultas de solo lectura para ejecutar tras completar una planificación.
-- Todas deben devolver cero filas.

-- Una planificación completada debe vincular exactamente el producto,
-- la cantidad y el depósito registrados en su fabricación.
select p.company_id, p.id as plan_id, p.run_id
from public.production_plans p
left join public.production_runs r
  on r.company_id=p.company_id and r.id=p.run_id
where p.status='completed' and (
  r.id is null or r.product_id<>p.product_id
  or r.quantity<>p.quantity or r.warehouse_id<>p.warehouse_id
  or r.formula_version<>p.formula_version
);

-- El historial de insumos debe coincidir con los egresos reales de stock.
select l.company_id, l.run_id, l.component_id, l.stock_operation_id
from public.production_run_lines l
left join public.stock_operations o
  on o.company_id=l.company_id and o.id=l.stock_operation_id
where o.id is null or o.kind<>'issue' or o.item_id<>l.component_id
  or o.warehouse_id<>l.warehouse_id or o.quantity<>l.quantity
  or o.lot_code is distinct from l.lot_code;

-- Cada fabricación genera una entrada del producto final.
select r.company_id, r.id, r.output_operation_id
from public.production_runs r
left join public.stock_operations o
  on o.company_id=r.company_id and o.id=r.output_operation_id
where o.id is null or o.kind<>'receipt' or o.item_id<>r.product_id
  or o.warehouse_id<>r.warehouse_id or o.quantity<>r.quantity;

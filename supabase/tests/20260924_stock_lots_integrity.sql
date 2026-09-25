-- Consultas de solo lectura: cada una debe devolver cero filas.
-- Ejecutar después de probar ingresos, salidas y transferencias con lotes.

-- Saldo total del depósito = suma de sus lotes para ítems trazados.
select b.company_id, b.item_id, b.warehouse_id,
       b.quantity as balance_quantity,
       coalesce(sum(lb.quantity), 0) as lot_quantity
from public.stock_balances b
join public.items i on i.company_id = b.company_id and i.id = b.item_id
left join public.stock_lot_balances lb
  on lb.company_id = b.company_id and lb.item_id = b.item_id
  and lb.warehouse_id = b.warehouse_id
where i.track_lots
group by b.company_id, b.item_id, b.warehouse_id, b.quantity
having b.quantity <> coalesce(sum(lb.quantity), 0);

-- Saldo de cada lote = apertura auditada + movimientos posteriores.
select b.company_id, b.item_id, b.warehouse_id, b.lot_id,
       b.quantity as balance_quantity,
       coalesce(o.quantity, 0) + coalesce(sum(m.delta), 0) as history_quantity
from public.stock_lot_balances b
left join public.stock_lot_openings o
  on o.company_id = b.company_id and o.item_id = b.item_id
  and o.warehouse_id = b.warehouse_id and o.lot_id = b.lot_id
left join public.stock_movements m
  on m.company_id = b.company_id and m.item_id = b.item_id
  and m.warehouse_id = b.warehouse_id and m.lot_id = b.lot_id
group by b.company_id, b.item_id, b.warehouse_id, b.lot_id, b.quantity, o.quantity
having b.quantity <> coalesce(o.quantity, 0) + coalesce(sum(m.delta), 0);

-- Una operación de transferencia trazada mueve el mismo lote en ambas líneas.
select o.company_id, o.id, o.lot_id,
       count(m.id) as movement_count,
       coalesce(sum(m.delta), 0) as net_quantity
from public.stock_operations o
left join public.stock_movements m
  on m.company_id = o.company_id and m.operation_id = o.id
where o.kind = 'transfer' and o.lot_id is not null
group by o.company_id, o.id, o.lot_id
having count(m.id) <> 2 or coalesce(sum(m.delta), 0) <> 0
    or bool_or(m.lot_id is distinct from o.lot_id);

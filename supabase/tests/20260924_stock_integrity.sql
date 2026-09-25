-- Comprobaciones de lectura. Ejecutar desde SQL Editor después de las pruebas.
-- Cada consulta debe devolver CERO FILAS si el historial es coherente.

-- 1. Saldo guardado vs. último movimiento de ese ítem en ese depósito.
select b.company_id, b.item_id, b.warehouse_id,
       b.quantity as saldo_guardado, b.version as version_guardada,
       m.balance_after as ultimo_saldo_historial,
       m.balance_version as ultima_version_historial
from public.stock_balances b
left join lateral (
  select sm.balance_after, sm.balance_version
  from public.stock_movements sm
  where sm.company_id = b.company_id
    and sm.item_id = b.item_id
    and sm.warehouse_id = b.warehouse_id
  order by sm.balance_version desc
  limit 1
) m on true
where b.quantity is distinct from coalesce(m.balance_after, 0)
   or b.version is distinct from coalesce(m.balance_version, 0);

-- 2. Cada transferencia debe tener dos líneas con efecto neto cero.
select op.company_id, op.id as operacion, op.quantity,
       count(m.id) as cantidad_lineas,
       sum(m.delta) as efecto_neto
from public.stock_operations op
left join public.stock_movements m
  on m.company_id = op.company_id and m.operation_id = op.id
where op.kind = 'transfer'
group by op.company_id, op.id, op.quantity
having count(m.id) <> 2
    or coalesce(sum(m.delta), 0) <> 0
    or count(*) filter (
      where m.kind = 'transfer_out'
        and m.warehouse_id = op.warehouse_id
        and m.delta = -op.quantity
    ) <> 1
    or count(*) filter (
      where m.kind = 'transfer_in'
        and m.warehouse_id = op.to_warehouse_id
        and m.delta = op.quantity
    ) <> 1;

-- 3. La suma de todas las variaciones históricas coincide con cada saldo.
select b.company_id, b.item_id, b.warehouse_id,
       b.quantity as saldo_guardado,
       coalesce(sum(m.delta), 0) as suma_movimientos
from public.stock_balances b
left join public.stock_movements m
  on m.company_id = b.company_id
  and m.item_id = b.item_id
  and m.warehouse_id = b.warehouse_id
group by b.company_id, b.item_id, b.warehouse_id, b.quantity
having b.quantity <> coalesce(sum(m.delta), 0);

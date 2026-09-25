-- Consultas de solo lectura: cada una debe devolver cero filas.
-- Ejecutar después de ensayar recepciones parciales y completas.

-- Lo recibido por línea debe coincidir con el historial de recepciones.
select l.company_id, l.order_id, l.line_no,
       l.received_quantity as recorded,
       coalesce(sum(rl.quantity), 0) as from_receipts
from public.purchase_order_lines l
left join public.purchase_receipt_lines rl
  on rl.company_id = l.company_id and rl.order_id = l.order_id
  and rl.line_no = l.line_no
group by l.company_id, l.order_id, l.line_no, l.received_quantity
having l.received_quantity <> coalesce(sum(rl.quantity), 0);

-- Cada línea recibida genera exactamente una operación de entrada correcta.
select rl.company_id, rl.receipt_id, rl.line_no, rl.stock_operation_id
from public.purchase_receipt_lines rl
left join public.stock_operations op
  on op.company_id = rl.company_id and op.id = rl.stock_operation_id
where op.id is null or op.kind <> 'receipt'
   or op.item_id <> rl.item_id
   or op.warehouse_id <> rl.warehouse_id
   or op.quantity <> rl.quantity
   or op.lot_code is distinct from rl.lot_code;

-- Las órdenes no canceladas muestran su estado según sus cantidades.
select o.company_id, o.id, o.status
from public.purchase_orders o
where o.status <> 'cancelled'
  and o.status <> (
    case
      when not exists (
        select 1 from public.purchase_order_lines l
        where l.company_id = o.company_id and l.order_id = o.id
          and l.received_quantity < l.quantity
      ) then 'received'
      when exists (
        select 1 from public.purchase_order_lines l
        where l.company_id = o.company_id and l.order_id = o.id
          and l.received_quantity > 0
      ) then 'partial'
      else 'open'
    end
  );

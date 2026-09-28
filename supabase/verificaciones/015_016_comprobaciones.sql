-- Consultas de solo lectura para el editor SQL del proyecto.
-- Reemplazá el UUID siguiente por el id de la empresa; no modifica datos.
-- La primera consulta muestra los ids disponibles.
select id, name, active from public.companies order by name;

-- Reemplazar 'EMPRESA_UUID' en las consultas siguientes antes de ejecutarlas.
-- Si no hay proveedor principal, el costo de referencia puede ser manual.
select i.code, i.name, s.name as proveedor_principal,
  si.currency_code as moneda, si.unit_price as precio_moneda,
  si.adjustment_percent as ajuste_porcentaje,
  fx.name as tipo_dolar,
  private.current_fx_rate(i.company_id, si.exchange_rate_type_id) as pesos_por_dolar,
  i.reference_unit_cost as costo_en_pesos
from public.items i
left join public.supplier_items si on si.company_id=i.company_id
  and si.item_id=i.id and si.preferred
left join public.suppliers s on s.company_id=si.company_id and s.id=si.supplier_id
left join public.exchange_rate_types fx on fx.company_id=si.company_id
  and fx.id=si.exchange_rate_type_id
where i.company_id='EMPRESA_UUID'::uuid and i.item_type='raw_material'
order by i.name;

-- Ningún cobro se contabiliza dos veces: exactamente una cuenta por pago.
select p.id, p.amount, p.paid_on,
  count(a.account_id) as cuentas_asignadas,
  bool_or(r.payment_id is not null) as anulado
from public.sale_payments p
left join public.treasury_sale_accounts a on a.company_id=p.company_id
  and a.payment_id=p.id
left join public.sale_payment_reversals r on r.company_id=p.company_id
  and r.payment_id=p.id
where p.company_id='EMPRESA_UUID'::uuid
group by p.id,p.amount,p.paid_on
order by p.paid_on desc;

-- Duplicados: estas consultas deberían devolver cero filas.
select company_id,item_id,count(*) from public.supplier_items
where preferred and company_id='EMPRESA_UUID'::uuid
group by company_id,item_id having count(*)>1;
select company_id,request_id,count(*) from public.supplier_price_adjustments
where company_id='EMPRESA_UUID'::uuid
group by company_id,request_id having count(*)>1;

import { supabase } from '../../../compartido/utilidades/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function getTreasuryBalances(companyId) {
  return unwrap(await supabase.rpc('treasury_balances', { p_company: companyId }));
}

export async function listTreasuryEntries(companyId) {
  return unwrap(await supabase.rpc('treasury_activity', { p_company: companyId }));
}

export async function listUnassignedPayments(companyId) {
  const rows = unwrap(await supabase.from('ventas_cobros')
    .select('id, amount:importe, paid_on:fecha_pago, sale_id:venta_id, sale:ventas(number:numero, customer_name:cliente_nombre), allocation:finanzas_cobros_cuentas(account_id:cuenta_id), reversal:ventas_cobros_reversiones(id)')
    .eq('empresa_id', companyId).order('creado_en', { ascending: false }).limit(100));
  // Son relaciones de uno a uno: la base devuelve un objeto (o null), no una lista.
  const existe = (relacion) => (Array.isArray(relacion) ? relacion.length > 0 : Boolean(relacion));
  return rows.filter((row) => !existe(row.allocation) && !existe(row.reversal));
}

export async function createTreasuryAccount(companyId, values) {
  return unwrap(await supabase.rpc('create_treasury_account', {
    p_company: companyId, p_name: values.name, p_kind: values.kind,
    p_opening: values.opening,
  }));
}

export async function postTreasuryEntry(companyId, values, requestId) {
  return unwrap(await supabase.rpc('post_treasury_entry', {
    p_company: companyId, p_account: values.accountId, p_kind: values.kind,
    p_amount: values.amount, p_order: values.orderId || null, p_note: values.note,
    p_on: values.date, p_request: requestId, p_target: values.targetId || null,
  }));
}

export async function assignSalePayment(companyId, paymentId, accountId) {
  return unwrap(await supabase.rpc('assign_sale_payment_account', {
    p_company: companyId, p_payment: paymentId, p_account: accountId,
  }));
}

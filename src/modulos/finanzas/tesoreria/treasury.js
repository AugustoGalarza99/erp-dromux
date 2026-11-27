import { supabase } from '../lib/supabase';

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
  const rows = unwrap(await supabase.from('sale_payments')
    .select('id, amount, paid_on, sale_id, sale: sales(number, customer_name), allocation:treasury_sale_accounts(account_id), reversal:sale_payment_reversals(id)')
    .eq('company_id', companyId).order('created_at', { ascending: false }).limit(100));
  return rows.filter((row) => !row.allocation?.length && !row.reversal?.length);
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

import { supabase } from '../lib/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listReceivables(companyId, page, search) {
  const rows = unwrap(await supabase.rpc('sale_receivables', {
    p_company: companyId,
    p_page: page,
    p_search: search.trim(),
  }));
  return {
    rows: rows ?? [],
    count: Number(rows?.[0]?.total_count ?? 0),
  };
}

export async function listSalePayments(companyId, saleId) {
  const [payments, reversals] = await Promise.all([
    supabase.from('sale_payments')
      .select('id, sale_id, amount, method, paid_on, reference, note, created_at')
      .eq('company_id', companyId).eq('sale_id', saleId)
      .order('created_at', { ascending: false }),
    supabase.from('sale_payment_reversals')
      .select('payment_id, reason, created_at')
      .eq('company_id', companyId).eq('sale_id', saleId),
  ]);
  const rows = unwrap(payments);
  const canceled = unwrap(reversals);
  const byPayment = new Map((canceled ?? []).map((row) => [row.payment_id, row]));
  return rows.map((row) => ({ ...row, reversal: byPayment.get(row.id) ?? null }));
}

export async function postSalePayment(companyId, values, requestId) {
  return unwrap(await supabase.rpc('post_sale_payment_to_account', {
    p_company: companyId,
    p_sale: values.saleId,
    p_amount: values.amount,
    p_method: values.method,
    p_paid_on: values.paidOn,
    p_reference: values.reference.trim(),
    p_note: values.note.trim(),
    p_request_id: requestId,
    p_account: values.accountId,
  }));
}

export async function reverseSalePayment(companyId, paymentId, reason) {
  return unwrap(await supabase.rpc('reverse_sale_payment', {
    p_company: companyId,
    p_payment: paymentId,
    p_reason: reason.trim(),
  }));
}

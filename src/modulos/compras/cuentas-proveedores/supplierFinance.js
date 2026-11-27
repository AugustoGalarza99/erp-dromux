import { supabase } from '../lib/supabase';

async function rpc(name, values) {
  const { data, error } = await supabase.rpc(name, values);
  if (error) throw error;
  return data;
}

export const purchaseStatistics = (company, from, to) =>
  rpc('supplier_purchase_statistics', {
    p_company: company,
    p_from: from,
    p_to: to,
  });

export const supplierAccount = (company, supplier, from, to, page) =>
  rpc('supplier_account', {
    p_company: company,
    p_supplier: supplier,
    p_from: from,
    p_to: to,
    p_page: page,
  });

export const payableOrders = (company, supplier, page) =>
  rpc('supplier_payable_orders', {
    p_company: company,
    p_supplier: supplier,
    p_page: page,
  });

export async function paymentOrders(company, page) {
  const { data, count, error } = await supabase
    .from('supplier_payment_orders')
    .select(
      '*, supplier:suppliers(name), account:treasury_accounts(name), lines:supplier_payment_order_lines(amount, order:purchase_orders(number))',
      { count: 'exact' },
    )
    .eq('company_id', company)
    .order('created_at', { ascending: false })
    .order('id')
    .range(page * 25, page * 25 + 24);
  if (error) throw error;
  return { rows: data ?? [], count: count ?? 0 };
}

export const createPaymentOrder = (company, values, request) =>
  rpc('create_supplier_payment_order', {
    p_company: company,
    p_supplier: values.supplier,
    p_account: values.account,
    p_on: values.date,
    p_note: values.note,
    p_reference: values.reference,
    p_lines: values.lines,
    p_request: request,
  });

export const confirmPaymentOrder = (company, id) =>
  rpc('confirm_supplier_payment_order', {
    p_company: company,
    p_payment: id,
  });

export const cancelPaymentOrder = (company, id) =>
  rpc('cancel_supplier_payment_order', {
    p_company: company,
    p_payment: id,
  });

export async function findFinanceSuppliers(company, term) {
  let query = supabase
    .from('suppliers')
    .select('id,name,active')
    .eq('company_id', company)
    .order('name')
    .order('id')
    .limit(30);
  if (term.trim()) query = query.ilike('name', `%${term.trim()}%`);
  const { data, error } = await query;
  if (error) throw error;
  return data ?? [];
}

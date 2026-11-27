import { supabase } from '../../../compartido/utilidades/supabase';

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
    .from('compras_pagos')
    .select(
      'id, number:numero, supplier_id:proveedor_id, account_id:cuenta_id, amount:importe, paid_on:fecha_pago, note:nota, reference:referencia, status:estado, created_at:creado_en, confirmed_at:confirmado_en, supplier:compras_proveedores(name:nombre), account:finanzas_cuentas(name:nombre), lines:compras_pagos_lineas(amount:importe, order:compras_ordenes(number:numero))',
      { count: 'exact' },
    )
    .eq('empresa_id', company)
    .order('creado_en', { ascending: false })
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
    .from('compras_proveedores')
    .select('id,name:nombre,active:activo')
    .eq('empresa_id', company)
    .order('nombre')
    .order('id')
    .limit(30);
  if (term.trim()) query = query.ilike('nombre', `%${term.trim()}%`);
  const { data, error } = await query;
  if (error) throw error;
  return data ?? [];
}

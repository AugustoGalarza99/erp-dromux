import { supabase } from '../lib/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listCustomers(companyId) {
  return unwrap(await supabase.from('customers')
    .select('id, name, tax_id, email, phone, address, notes, active, created_at')
    .eq('company_id', companyId)
    .order('name')
    .limit(500));
}

export async function saveCustomer(companyId, customerId, form) {
  const values = {
    name: form.name.trim(),
    tax_id: form.tax_id.trim(),
    email: form.email.trim(),
    phone: form.phone.trim(),
    address: form.address.trim(),
    notes: form.notes.trim(),
  };
  if (customerId) {
    return unwrap(await supabase.from('customers').update(values)
      .eq('company_id', companyId).eq('id', customerId)
      .select('id').single());
  }
  return unwrap(await supabase.from('customers')
    .insert({ ...values, company_id: companyId }).select('id').single());
}

export async function setCustomerActive(companyId, customerId, active) {
  return unwrap(await supabase.from('customers').update({ active })
    .eq('company_id', companyId).eq('id', customerId)
    .select('id').single());
}

export async function listSaleProducts(companyId) {
  return unwrap(await supabase.from('items')
    .select('id, code, name, active, track_lots, sale_unit_price, units!items_unit_company_fk(symbol)')
    .eq('company_id', companyId).eq('item_type', 'finished_product')
    .order('name').limit(500));
}

export async function listPublicPrices(companyId, search = '') {
  return unwrap(await supabase.rpc('erp_public_price_list', {
    p_company: companyId, p_search: search.trim(),
  }));
}

export async function saveSalePrice(companyId, itemId, price) {
  return unwrap(await supabase.rpc('erp_set_finished_product_price', {
    p_company: companyId, p_item: itemId, p_price: price,
  }));
}

export async function listSales(companyId) {
  return unwrap(await supabase.from('sales')
    .select('id, number, customer_name, customer_tax_id, note, total, created_at, sale_adjustments(id, kind, credit_total, reason, created_at, sale_adjustment_lines(sale_line_no, quantity, restocked)), sale_lines(line_no, item_id, warehouse_id, item_name, item_code, unit_symbol, warehouse_code, lot_code, quantity, unit_price, line_total)')
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })
    .limit(60));
}

export async function postSale(companyId, payload, requestId) {
  return unwrap(await supabase.rpc('post_sale_with_payment', {
    p_company: companyId,
    p_customer: payload.customerId,
    p_note: payload.note.trim(),
    p_request_id: requestId,
    p_payment_request_id: payload.paymentMode === 'pending' ? null : payload.paymentRequestId,
    p_payment_mode: payload.paymentMode,
    p_amount: payload.paymentMode === 'pending' ? null : payload.paymentAmount,
    p_method: payload.paymentMode === 'pending' ? null : payload.paymentMethod,
    p_account: payload.paymentMode === 'pending' ? null : payload.accountId,
    p_lines: payload.lines.map((line) => ({
      item_id: line.itemId,
      warehouse_id: line.warehouseId,
      quantity: line.quantity,
      lot_code: line.lotCode || null,
      expected_unit_price: line.price,
    })),
  }));
}

export async function adjustSale(companyId, saleId, kind, reason, lines, requestId) {
  return unwrap(await supabase.rpc('adjust_sale', {
    p_company: companyId,
    p_sale: saleId,
    p_kind: kind,
    p_reason: reason.trim(),
    p_lines: lines.map((line) => ({
      line_no: line.line_no,
      quantity: line.quantity,
      restock: line.restock,
    })),
    p_request_id: requestId,
  }));
}

export async function getSaleCredit(companyId, saleId) {
  const rows = unwrap(await supabase.rpc('sale_credit_balance', {
    p_company: companyId,
    p_sale: saleId,
  }));
  return rows?.[0] ?? null;
}

export async function refundSaleCredit(companyId, saleId, accountId, amount, reason, requestId) {
  return unwrap(await supabase.rpc('refund_sale_credit', {
    p_company: companyId,
    p_sale: saleId,
    p_account: accountId,
    p_amount: amount,
    p_reason: reason.trim(),
    p_request_id: requestId,
  }));
}

export async function findSalesByIds(companyId, ids) {
  if (!ids.length) return [];
  return unwrap(await supabase.from('sales')
    .select('id, number, customer_name')
    .eq('company_id', companyId).in('id', ids.slice(0, 50)));
}

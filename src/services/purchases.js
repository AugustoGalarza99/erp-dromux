import { supabase } from '../lib/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listSuppliers(companyId, search = '') {
  let query = supabase
    .from('suppliers')
    .select('id, name, tax_id, email, phone, notes, active, lead_time_days')
    .eq('company_id', companyId)
    .order('name')
    .limit(100);

  if (search.trim()) query = query.ilike('name', `%${search.trim()}%`);
  return unwrap(await query);
}

export async function getPurchaseSuggestion(companyId, itemId, supplierId) {
  const item = unwrap(await supabase.from('items')
    .select('id, code')
    .eq('company_id', companyId).eq('id', itemId).single());
  const options = await findPurchaseItems(companyId, item.code, supplierId || null);
  const choice = options.find((entry) => entry.id === itemId);
  if (!choice) throw new Error('El material ya no está disponible para ese proveedor.');

  let supplier = null;
  let price = choice.reference_unit_cost ?? null;
  if (supplierId) {
    supplier = unwrap(await supabase.from('suppliers')
      .select('id, name, active')
      .eq('company_id', companyId).eq('id', supplierId).single());
    const quote = (await listSupplierQuotes(companyId, supplierId, itemId))
      .find((entry) => entry.supplier_active && entry.unit_cost_ars != null);
    price = quote?.unit_cost_ars ?? null;
  }
  return { item: choice, supplier, price };
}

export async function saveSupplier(companyId, id, values) {
  const payload = {
    name: values.name.trim(),
    tax_id: values.tax_id.trim(),
    email: values.email.trim(),
    phone: values.phone.trim(),
    notes: values.notes.trim(),
    lead_time_days: Number(values.lead_time_days),
  };

  if (id) {
    return unwrap(await supabase
      .from('suppliers')
      .update(payload)
      .eq('company_id', companyId)
      .eq('id', id)
      .select('id')
      .single());
  }

  return unwrap(await supabase
    .from('suppliers')
    .insert({ ...payload, company_id: companyId })
    .select('id')
    .single());
}

export async function setSupplierActive(companyId, id, active) {
  return unwrap(await supabase
    .from('suppliers')
    .update({ active })
    .eq('company_id', companyId)
    .eq('id', id)
    .select('id')
    .single());
}

export async function listPurchaseOrders(companyId) {
  return unwrap(await supabase
    .from('purchase_orders')
    .select(`
      id, number, status, note, created_at, supplier_name,
      lines:purchase_order_lines(
        line_no, item_code, item_name, unit_symbol, quantity,
        received_quantity, unit_price
      )
    `)
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })
    .limit(50));
}

export async function findPurchaseItems(companyId, search, supplierId = null) {
  return unwrap(await supabase.rpc('purchase_material_options', {
    p_company: companyId,
    p_search: search.trim(),
    p_supplier: supplierId,
  }));
}

export async function listPurchaseSuppliersForItems(companyId, itemIds) {
  return unwrap(await supabase.rpc('purchase_suppliers_for_items', {
    p_company: companyId,
    p_items: itemIds,
  }));
}

export async function listSupplierQuotes(companyId, supplierId = null, itemId = null) {
  return unwrap(await supabase.rpc('supplier_cost_comparison', {
    p_company: companyId,
    p_supplier: supplierId,
    p_item: itemId,
  }));
}

export async function saveSupplierQuote(companyId, supplierId, itemId, price, sku = '', currency = 'ARS', exchangeTypeId = null, adjustment = 0) {
  const existing = unwrap(await supabase
    .from('supplier_items')
    .select('item_id')
    .eq('company_id', companyId)
    .eq('supplier_id', supplierId)
    .eq('item_id', itemId)
    .maybeSingle());

  const payload = { unit_price: price, supplier_sku: sku.trim(), currency_code: currency,
    exchange_rate_type_id: currency === 'USD' ? exchangeTypeId : null, adjustment_percent: adjustment };
  if (existing) {
    const { error } = await supabase
      .from('supplier_items')
      .update(payload)
      .eq('company_id', companyId)
      .eq('supplier_id', supplierId)
      .eq('item_id', itemId);
    if (error) throw error;
  } else {
    const { error } = await supabase
      .from('supplier_items')
      .insert({ company_id: companyId, supplier_id: supplierId,
        item_id: itemId, ...payload });
    if (error) throw error;
  }
}

export async function removeSupplierQuote(companyId, supplierId, itemId) {
  const { error, count } = await supabase
    .from('supplier_items')
    .delete({ count: 'exact' })
    .eq('company_id', companyId)
    .eq('supplier_id', supplierId)
    .eq('item_id', itemId);
  if (error) throw error;
  if (count !== 1) throw new Error('La cotización ya no existe o no tenés permiso.');
}

export async function createPurchaseOrder(companyId, supplierId, note, lines, requestId) {
  return unwrap(await supabase.rpc('create_purchase_order_once', {
    p_company: companyId,
    p_supplier: supplierId,
    p_note: note.trim(),
    p_request_id: requestId,
    p_lines: lines.map((line) => ({
      item_id: line.item_id,
      quantity: line.quantity,
      unit_price: line.unit_price,
    })),
  }));
}

export async function cancelPurchaseOrder(companyId, orderId) {
  return unwrap(await supabase.rpc('cancel_purchase_order', {
    p_company: companyId,
    p_order: orderId,
  }));
}

export async function getReceivableLines(companyId, orderId) {
  return unwrap(await supabase.rpc('purchase_receivable_lines', {
    p_company: companyId,
    p_order: orderId,
  }));
}

export async function listPurchaseReceipts(companyId, orderId) {
  return unwrap(await supabase
    .from('purchase_receipts')
    .select(`
      id, note, actor_id, created_at,
      lines:purchase_receipt_lines(
        line_no, quantity, warehouse_code, lot_code, expires_on,
        stock_operation_id
      )
    `)
    .eq('company_id', companyId)
    .eq('order_id', orderId)
    .order('created_at', { ascending: false })
    .limit(50));
}

export async function receivePurchaseOrder(companyId, orderId, requestId, note, lines) {
  return unwrap(await supabase.rpc('receive_purchase_order', {
    p_company: companyId,
    p_order: orderId,
    p_request_id: requestId,
    p_note: note.trim(),
    p_request_id: requestId,
    p_lines: lines.map((line) => ({
      line_no: line.line_no,
      quantity: line.quantity,
      warehouse_id: line.warehouse_id,
      lot_code: line.lot_code || null,
      expires_on: line.expires_on || null,
    })),
  }));
}

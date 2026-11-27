import { supabase } from '../../../compartido/utilidades/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listCustomers(companyId) {
  return unwrap(await supabase.from('ventas_clientes')
    .select('id, name:nombre, tax_id:identificacion_fiscal, email, phone:telefono, address:direccion, notes:nota, active:activo, created_at:creado_en')
    .eq('empresa_id', companyId)
    .order('nombre')
    .limit(500));
}

export async function saveCustomer(companyId, customerId, form) {
  const values = {
    nombre: form.name.trim(),
    identificacion_fiscal: form.tax_id.trim(),
    email: form.email.trim(),
    telefono: form.phone.trim(),
    direccion: form.address.trim(),
    nota: form.notes.trim(),
  };
  if (customerId) {
    return unwrap(await supabase.from('ventas_clientes').update(values)
      .eq('empresa_id', companyId).eq('id', customerId)
      .select('id').single());
  }
  return unwrap(await supabase.from('ventas_clientes')
    .insert({ ...values, empresa_id: companyId }).select('id').single());
}

export async function setCustomerActive(companyId, customerId, active) {
  return unwrap(await supabase.from('ventas_clientes').update({ activo: active })
    .eq('empresa_id', companyId).eq('id', customerId)
    .select('id').single());
}

export async function listSaleProducts(companyId) {
  return unwrap(await supabase.from('stock_items')
    .select('id, code:codigo, name:nombre, active:activo, track_lots:usa_lotes, infinite_stock:stock_infinito, sale_unit_price:precio_venta_unitario, units:stock_unidades!stock_items_unit_company_fk(symbol:simbolo)')
    .eq('empresa_id', companyId).eq('tipo_item', 'producto_terminado')
    .order('nombre').limit(500));
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
  return unwrap(await supabase.from('ventas')
    .select('id, number:numero, customer_name:cliente_nombre, customer_tax_id:cliente_identificacion_fiscal, note:nota, total, created_at:creado_en, sale_adjustments:ventas_ajustes(id, kind:tipo, credit_total:credito_total, reason:motivo, created_at:creado_en, sale_adjustment_lines:ventas_ajustes_lineas(sale_line_no:venta_linea, quantity:cantidad, restocked:reingresado)), sale_lines:ventas_lineas(line_no:linea, item_id, warehouse_id:deposito_id, item_name:item_nombre, item_code:item_codigo, unit_symbol:unidad_simbolo, warehouse_code:deposito_codigo, lot_code:lote_codigo, quantity:cantidad, unit_price:precio_unitario, line_total:total_linea)')
    .eq('empresa_id', companyId)
    .order('creado_en', { ascending: false })
    .limit(60));
}

export async function postSale(companyId, payload, requestId) {
  return unwrap(await supabase.rpc('post_sale_with_payment', {
    p_company: companyId,
    p_customer: payload.customerId,
    p_note: payload.note.trim(),
    p_request_id: requestId,
    p_payment_request_id: payload.paymentMode === 'pendiente' ? null : payload.paymentRequestId,
    p_payment_mode: payload.paymentMode,
    p_amount: payload.paymentMode === 'pendiente' ? null : payload.paymentAmount,
    p_method: payload.paymentMode === 'pendiente' ? null : payload.paymentMethod,
    p_account: payload.paymentMode === 'pendiente' ? null : payload.accountId,
    p_lines: payload.lines.map((line) => ({
      item_id: line.itemId,
      warehouse_id: line.warehouseId,
      quantity: line.quantity,
      lot_code: line.lotCode || null,
      expected_unit_price: line.price,
      ...(Number(line.discount) > 0 ? { discount_percent: Number(line.discount), discount_reason: (line.discountReason || '').trim() || null } : {}),
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
  return unwrap(await supabase.from('ventas')
    .select('id, number:numero, customer_name:cliente_nombre')
    .eq('empresa_id', companyId).in('id', ids.slice(0, 50)));
}

/* Indicadores del Resumen de ventas: el servidor omite lo que el rol no puede ver. */
export async function getSalesSummary(companyId) {
  return unwrap(await supabase.rpc('erp_operational_dashboard', { p_company: companyId }));
}

/* Precio neto que corresponde a cada producto para este cliente (lista del cliente → predeterminada → precio del producto). */
export async function getSalePrices(companyId, customerId, itemIds) {
  return unwrap(await supabase.rpc('erp_sale_prices', {
    p_company: companyId, p_customer: customerId, p_items: itemIds,
  }));
}

/* Tope de descuento de la empresa y si quien consulta puede superarlo. */
export async function getDiscountPolicy(companyId) {
  const rows = unwrap(await supabase.rpc('erp_sale_discount_policy', { p_company: companyId }));
  return rows?.[0] ?? { max_discount_percent: 0, can_exceed: false };
}

import { supabase } from '../../../compartido/utilidades/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listSuppliers(companyId, search = '') {
  let query = supabase
    .from('compras_proveedores')
    .select('id, name:nombre, tax_id:identificacion_fiscal, email, phone:telefono, notes:nota, active:activo, lead_time_days:demora_dias')
    .eq('empresa_id', companyId)
    .order('nombre')
    .limit(100);

  if (search.trim()) query = query.ilike('nombre', `%${search.trim()}%`);
  return unwrap(await query);
}

export async function getSupplier(companyId, supplierId) {
  return unwrap(await supabase.from('compras_proveedores')
    .select('id, name:nombre, active:activo')
    .eq('empresa_id', companyId).eq('id', supplierId).single());
}

export async function getPurchaseSuggestion(companyId, itemId, supplierId) {
  const item = unwrap(await supabase.from('stock_items')
    .select('id, code:codigo')
    .eq('empresa_id', companyId).eq('id', itemId).single());
  const options = await findPurchaseItems(companyId, item.code, supplierId || null);
  const choice = options.find((entry) => entry.id === itemId);
  if (!choice) throw new Error('El material ya no está disponible para ese proveedor.');

  let supplier = null;
  let price = choice.reference_unit_cost ?? null;
  if (supplierId) {
    supplier = unwrap(await supabase.from('compras_proveedores')
      .select('id, name:nombre, active:activo')
      .eq('empresa_id', companyId).eq('id', supplierId).single());
    const quote = (await listSupplierQuotes(companyId, supplierId, itemId))
      .find((entry) => entry.supplier_active && entry.unit_cost_ars != null);
    price = quote?.unit_cost_ars ?? null;
  }
  return { item: choice, supplier, price };
}

export async function saveSupplier(companyId, id, values) {
  const payload = {
    nombre: values.name.trim(),
    identificacion_fiscal: values.tax_id.trim(),
    email: values.email.trim(),
    telefono: values.phone.trim(),
    nota: values.notes.trim(),
    provee_descripcion: values.supplies_description?.trim() ?? '',
    demora_dias: Number(values.lead_time_days),
  };

  if (id) {
    return unwrap(await supabase
      .from('compras_proveedores')
      .update(payload)
      .eq('empresa_id', companyId)
      .eq('id', id)
      .select('id')
      .single());
  }

  return unwrap(await supabase
    .from('compras_proveedores')
    .insert({ ...payload, empresa_id: companyId })
    .select('id')
    .single());
}

export async function setSupplierActive(companyId, id, active) {
  return unwrap(await supabase
    .from('compras_proveedores')
    .update({ activo: active })
    .eq('empresa_id', companyId)
    .eq('id', id)
    .select('id')
    .single());
}

export async function listPurchaseOrders(companyId) {
  return unwrap(await supabase
    .from('compras_ordenes')
    .select(`
      id, number:numero, status:estado, note:nota, created_at:creado_en, supplier_name:proveedor_nombre,
      lines:compras_ordenes_lineas(
        line_no:linea, item_code:item_codigo, item_name:item_nombre, unit_symbol:unidad_simbolo,
        quantity:cantidad, received_quantity:cantidad_recibida, unit_price:precio_unitario
      )
    `)
    .eq('empresa_id', companyId)
    .order('creado_en', { ascending: false })
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
    .from('compras_proveedores_items')
    .select('item_id')
    .eq('empresa_id', companyId)
    .eq('proveedor_id', supplierId)
    .eq('item_id', itemId)
    .maybeSingle());

  const payload = { precio_unitario: price, proveedor_codigo: sku.trim(), moneda: currency,
    tipo_cambio_id: currency === 'USD' ? exchangeTypeId : null, ajuste_porcentaje: adjustment };
  if (existing) {
    const { error } = await supabase
      .from('compras_proveedores_items')
      .update(payload)
      .eq('empresa_id', companyId)
      .eq('proveedor_id', supplierId)
      .eq('item_id', itemId);
    if (error) throw error;
  } else {
    const { error } = await supabase
      .from('compras_proveedores_items')
      .insert({ empresa_id: companyId, proveedor_id: supplierId,
        item_id: itemId, ...payload });
    if (error) throw error;
  }
}

export async function removeSupplierQuote(companyId, supplierId, itemId) {
  const { error, count } = await supabase
    .from('compras_proveedores_items')
    .delete({ count: 'exact' })
    .eq('empresa_id', companyId)
    .eq('proveedor_id', supplierId)
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
    .from('compras_recepciones')
    .select(`
      id, note:nota, actor_id:autor_id, created_at:creado_en,
      lines:compras_recepciones_lineas(
        line_no:linea, quantity:cantidad, warehouse_code:deposito_codigo, lot_code:lote_codigo,
        expires_on:vencimiento, stock_operation_id:operacion_stock_id
      )
    `)
    .eq('empresa_id', companyId)
    .eq('orden_compra_id', orderId)
    .order('creado_en', { ascending: false })
    .limit(50));
}

export async function receivePurchaseOrder(companyId, orderId, requestId, note, lines) {
  return unwrap(await supabase.rpc('receive_purchase_order', {
    p_company: companyId,
    p_order: orderId,
    p_request_id: requestId,
    p_note: note.trim(),
    p_lines: lines.map((line) => ({
      line_no: line.line_no,
      quantity: line.quantity,
      warehouse_id: line.warehouse_id,
      lot_code: line.lot_code || null,
      expires_on: line.expires_on || null,
    })),
  }));
}

export async function listSupplierDirectory(companyId, search = '', page = 0) {
  return unwrap(await supabase.rpc('supplier_directory', {
    p_company: companyId, p_search: search.trim(), p_page: page,
  }));
}

export async function listSupplierCatalog(companyId, supplierId, itemId = null, search = '', page = 0) {
  return unwrap(await supabase.rpc('supplier_quote_catalog', {
    p_company: companyId, p_supplier: supplierId || null,
    p_item: itemId || null, p_search: search.trim(), p_page: page,
  }));
}

export async function saveSupplierCatalogQuote(companyId, supplierId, itemId, values, previous) {
  return unwrap(await supabase.rpc('save_supplier_quote', {
    p_company: companyId, p_supplier: supplierId, p_item: itemId,
    p_price: values.price, p_sku: values.sku.trim(), p_currency: values.currency,
    p_exchange_type: values.currency === 'USD' ? values.exchangeType : null,
    p_adjustment: values.adjustment,
    p_expected_updated_at: previous?.updated_at ?? null,
    p_create_only: !previous,
  }));
}

export async function previewSupplierAdjustment(companyId, supplierId, itemId, percent) {
  return unwrap(await supabase.rpc('supplier_adjustment_preview', {
    p_company: companyId, p_supplier: supplierId, p_item: itemId || null, p_percent: percent,
  }));
}

export async function listPurchaseOrdersPage(companyId, page = 0, search = '', status = '') {
  let query = supabase.from('compras_ordenes')
    .select(`id, number:numero, status:estado, note:nota, created_at:creado_en, supplier_name:proveedor_nombre,
      lines:compras_ordenes_lineas(line_no:linea, item_code:item_codigo, item_name:item_nombre,
        unit_symbol:unidad_simbolo, quantity:cantidad, received_quantity:cantidad_recibida,
        unit_price:precio_unitario)`, { count: 'exact' })
    .eq('empresa_id', companyId)
    .order('creado_en', { ascending: false }).order('id', { ascending: false })
    .range(page * 25, page * 25 + 24);
  const value = search.trim().replace(/^#/, '');
  if (value) query = /^\d+$/.test(value)
    ? query.eq('numero', value) : query.ilike('proveedor_nombre', `%${value}%`);
  if (status) query = query.eq('estado', status);
  const { data, count, error } = await query;
  if (error) throw error;
  return { rows: data ?? [], count: count ?? 0 };
}

import { supabase } from '../lib/supabase';

/*
 * Pedidos de compra internos: un operario pide materiales y Compras los convierte en orden.
 * Requiere la migración 038 (tablas y funciones `*_purchase_request*`). Los permisos reales los
 * valida la base: acá solo se arman las consultas.
 */
function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

const columns = `id, number, status, priority, needed_by, note, resolution_note, requester_label,
  requested_by, purchase_order_id, created_at, resolved_at,
  order:purchase_orders(number),
  lines:purchase_request_lines(line_no, item_id, item_code, item_name, unit_symbol, quantity, note)`;

export async function listPurchaseRequests(companyId, { page = 0, status = '', search = '', userId = '', mine = false } = {}) {
  let query = supabase
    .from('purchase_requests')
    .select(columns, { count: 'exact' })
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .range(page * 25, page * 25 + 24);
  if (status) query = query.eq('status', status);
  if (mine && userId) query = query.eq('requested_by', userId);
  const value = search.trim().replace(/^#/, '');
  if (value) {
    query = /^\d+$/.test(value)
      ? query.eq('number', value)
      : query.ilike('requester_label', `%${value}%`);
  }
  const { data, count, error } = await query;
  if (error) throw error;
  return { rows: data ?? [], count: count ?? 0 };
}

export async function getPurchaseRequest(companyId, requestId) {
  return unwrap(await supabase
    .from('purchase_requests')
    .select(columns)
    .eq('company_id', companyId)
    .eq('id', requestId)
    .single());
}

export async function findRequestItems(companyId, search) {
  return unwrap(await supabase.rpc('purchase_request_item_options', {
    p_company: companyId,
    p_search: search.trim(),
  }));
}

export async function createPurchaseRequest(companyId, values, requestId) {
  return unwrap(await supabase.rpc('create_purchase_request', {
    p_company: companyId,
    p_note: values.note.trim(),
    p_needed_by: values.neededBy || null,
    p_priority: values.priority,
    p_request_id: requestId,
    p_lines: values.lines.map((line) => (line.item_id
      ? { item_id: line.item_id, quantity: line.quantity, note: line.note.trim() }
      : { free_text: line.name.trim(), unit: line.unit.trim(), quantity: line.quantity, note: line.note.trim() })),
  }));
}

export async function cancelPurchaseRequest(companyId, requestId) {
  return unwrap(await supabase.rpc('cancel_purchase_request', {
    p_company: companyId,
    p_request: requestId,
  }));
}

export async function rejectPurchaseRequest(companyId, requestId, reason) {
  return unwrap(await supabase.rpc('reject_purchase_request', {
    p_company: companyId,
    p_request: requestId,
    p_reason: reason.trim(),
  }));
}

/* Crea la orden de compra desde el pedido y lo marca como ordenado, todo en una sola operación. */
export async function convertPurchaseRequest(companyId, requestId, supplierId, note, lines, submissionId) {
  return unwrap(await supabase.rpc('convert_purchase_request', {
    p_company: companyId,
    p_request: requestId,
    p_supplier: supplierId,
    p_note: note.trim(),
    p_request_id: submissionId,
    p_lines: lines.map((line) => ({
      item_id: line.item_id,
      quantity: line.quantity,
      unit_price: line.unit_price,
    })),
  }));
}

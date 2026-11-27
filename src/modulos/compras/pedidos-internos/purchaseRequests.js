import { supabase } from '../../../compartido/utilidades/supabase';

/*
 * Pedidos de compra internos: un operario pide materiales y Compras los convierte en orden.
 * Los permisos reales los valida la base: acá solo se arman las consultas.
 */
function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

const columns = `id, number:numero, status:estado, priority:prioridad, needed_by:fecha_necesaria, note:nota,
  resolution_note:nota_resolucion, requester_label:solicitante_nombre, requested_by:solicitado_por,
  purchase_order_id:orden_compra_id, created_at:creado_en, resolved_at:resuelto_en,
  order:compras_ordenes(number:numero),
  lines:compras_pedidos_lineas(line_no:linea, item_id, item_code:item_codigo, item_name:item_nombre,
    unit_symbol:unidad_simbolo, quantity:cantidad, note:nota)`;

export async function listPurchaseRequests(companyId, { page = 0, status = '', search = '', userId = '', mine = false } = {}) {
  let query = supabase
    .from('compras_pedidos')
    .select(columns, { count: 'exact' })
    .eq('empresa_id', companyId)
    .order('creado_en', { ascending: false })
    .order('id', { ascending: false })
    .range(page * 25, page * 25 + 24);
  if (status) query = query.eq('estado', status);
  if (mine && userId) query = query.eq('solicitado_por', userId);
  const value = search.trim().replace(/^#/, '');
  if (value) {
    query = /^\d+$/.test(value)
      ? query.eq('numero', value)
      : query.ilike('solicitante_nombre', `%${value}%`);
  }
  const { data, count, error } = await query;
  if (error) throw error;
  return { rows: data ?? [], count: count ?? 0 };
}

export async function getPurchaseRequest(companyId, requestId) {
  return unwrap(await supabase
    .from('compras_pedidos')
    .select(columns)
    .eq('empresa_id', companyId)
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

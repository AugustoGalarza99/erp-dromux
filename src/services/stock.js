import { supabase } from '../lib/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listStock(companyId, page, search) {
  const rows = unwrap(await supabase.rpc('stock_summary', {
    p_company: companyId,
    p_page: page,
    p_search: search.trim(),
  }));

  return {
    rows,
    count: rows[0]?.total_count ? Number(rows[0].total_count) : 0,
  };
}

export async function listStockBalances(companyId, itemId) {
  return unwrap(await supabase
    .from('stock_balances')
    .select(`
      warehouse_id, quantity,
      warehouse:warehouses!stock_balances_warehouse_company_fk(id, code, name)
    `)
    .eq('company_id', companyId)
    .eq('item_id', itemId)
    .gt('quantity', 0)
    .order('quantity', { ascending: false })
    .limit(100));
}

export async function findStockItems(companyId, search) {
  return unwrap(await supabase.rpc('stock_item_options', {
    p_company: companyId,
    p_search: search.trim(),
  }));
}

export async function findStockWarehouses(companyId, search) {
  return unwrap(await supabase.rpc('stock_warehouse_options', {
    p_company: companyId,
    p_search: search.trim(),
  }));
}

export async function listStockLots(companyId, itemId, warehouseId = null) {
  return unwrap(await supabase.rpc('stock_lot_options', {
    p_company: companyId,
    p_item: itemId,
    p_warehouse: warehouseId,
  }));
}

export async function listStockLotBreakdown(companyId, itemId) {
  return unwrap(await supabase.rpc('stock_lot_breakdown', {
    p_company: companyId,
    p_item: itemId,
  }));
}

export async function postStockOperation(companyId, payload, requestId) {
  return unwrap(await supabase.rpc('post_stock_operation', {
    p_company: companyId,
    p_item: payload.itemId,
    p_warehouse: payload.warehouseId,
    p_to_warehouse: payload.kind === 'transfer' ? payload.targetId : null,
    p_kind: payload.kind,
    p_quantity: payload.quantity,
    p_note: payload.note.trim(),
    p_request_id: requestId,
    p_lot_code: payload.lotCode || null,
    p_expires_on: payload.kind === 'receipt' && payload.expiresOn
      ? payload.expiresOn : null,
  }));
}

export async function listStockMovements(companyId, {
  page, itemId, warehouseId, kind, from, to,
}) {
  let query = supabase
    .from('stock_movements')
    .select(`
      id, operation_id, line_no, item_id, warehouse_id, kind,
      delta, balance_after, balance_version, item_code, warehouse_code,
      unit_symbol, note, actor_id, created_at, lot_code, lot_expires_on
    `, { count: 'exact' })
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .range(page * 25, page * 25 + 24);

  if (itemId) query = query.eq('item_id', itemId);
  if (warehouseId) query = query.eq('warehouse_id', warehouseId);
  if (kind) query = query.eq('kind', kind);
  if (from) query = query.gte('created_at', new Date(`${from}T00:00:00`).toISOString());
  if (to) {
    const end = new Date(`${to}T00:00:00`);
    end.setDate(end.getDate() + 1);
    query = query.lt('created_at', end.toISOString());
  }

  const { data, count, error } = await query;
  if (error) throw error;
  return { rows: data ?? [], count: count ?? 0 };
}

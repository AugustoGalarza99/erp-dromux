import { supabase } from '../../../compartido/utilidades/supabase';

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

  const { data: flags, error: flagsError } = rows.length
    ? await supabase.from('stock_items').select('id, infinite_stock:stock_infinito')
      .eq('empresa_id', companyId).in('id', rows.map((row) => row.item_id))
    : { data: [], error: null };
  if (flagsError) throw flagsError;
  const infinite = new Set((flags ?? []).filter((item) => item.infinite_stock).map((item) => item.id));
  return {
    rows: rows.map((row) => ({ ...row, infinite_stock: infinite.has(row.item_id) })),
    count: rows[0]?.total_count ? Number(rows[0].total_count) : 0,
  };
}

export async function listStockBalances(companyId, itemId) {
  return unwrap(await supabase
    .from('stock_saldos')
    .select(`
      warehouse_id:deposito_id, quantity:cantidad,
      warehouse:stock_depositos!stock_saldos_warehouse_company_fk(id, code:codigo, name:nombre)
    `)
    .eq('empresa_id', companyId)
    .eq('item_id', itemId)
    .gt('cantidad', 0)
    .order('cantidad', { ascending: false })
    .limit(100));
}

export async function findStockItems(companyId, search) {
  const options = unwrap(await supabase.rpc('stock_item_options', {
    p_company: companyId,
    p_search: search.trim(),
  }));
  if (!options.length) return options;
  const { data, error } = await supabase.from('stock_items').select('id, infinite_stock:stock_infinito')
    .eq('empresa_id', companyId).in('id', options.map((item) => item.id));
  if (error) throw error;
  const infinite = new Set((data ?? []).filter((item) => item.infinite_stock).map((item) => item.id));
  return options.map((item) => ({ ...item, infinite_stock: infinite.has(item.id) }));
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
    p_to_warehouse: payload.kind === 'transferencia' ? payload.targetId : null,
    p_kind: payload.kind,
    p_quantity: payload.quantity,
    p_note: payload.note.trim(),
    p_request_id: requestId,
    p_lot_code: payload.lotCode || null,
    p_expires_on: payload.kind === 'ingreso' && payload.expiresOn
      ? payload.expiresOn : null,
  }));
}

export async function listStockMovements(companyId, {
  page, itemId, warehouseId, kind, from, to,
}) {
  let query = supabase
    .from('stock_movimientos')
    .select(`
      id, operation_id:operacion_id, line_no:linea, item_id, warehouse_id:deposito_id, kind:tipo,
      delta:variacion, balance_after:saldo_posterior, balance_version:saldo_version,
      item_code:item_codigo, warehouse_code:deposito_codigo, unit_symbol:unidad_simbolo,
      note:nota, actor_id:autor_id, created_at:creado_en, lot_code:lote_codigo,
      lot_expires_on:lote_vencimiento
    `, { count: 'exact' })
    .eq('empresa_id', companyId)
    .order('creado_en', { ascending: false })
    .order('id', { ascending: false })
    .range(page * 25, page * 25 + 24);

  if (itemId) query = query.eq('item_id', itemId);
  if (warehouseId) query = query.eq('deposito_id', warehouseId);
  if (kind) query = query.eq('tipo', kind);
  if (from) query = query.gte('creado_en', new Date(`${from}T00:00:00`).toISOString());
  if (to) {
    const end = new Date(`${to}T00:00:00`);
    end.setDate(end.getDate() + 1);
    query = query.lt('creado_en', end.toISOString());
  }

  const { data, count, error } = await query;
  if (error) throw error;
  return { rows: data ?? [], count: count ?? 0 };
}

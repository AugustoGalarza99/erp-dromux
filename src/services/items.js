import { supabase } from '../lib/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

const detailColumns = `
  id, company_id, code, name, item_type, category_id, unit_id,
  barcode, description, minimum_stock, track_lots, active, reference_unit_cost,
  created_at, updated_at,
  category:item_categories!items_category_company_fk(id, name, active),
  unit:units!items_unit_company_fk(id, name, symbol, active)
`;

export async function listItems(companyId, { page, search, type, status }) {
  let query = supabase
    .from('items')
    .select('id, code, name, item_type, category_id, unit_id, minimum_stock, active', {
      count: 'exact',
    })
    .eq('company_id', companyId)
    .order('name', { ascending: true })
    .order('id', { ascending: true })
    .range(page * 25, page * 25 + 24);

  if (search.trim()) query = query.ilike('name', `%${search.trim()}%`);
  if (type) query = query.eq('item_type', type);
  if (status !== 'all') query = query.eq('active', status === 'active');

  const { data, count, error } = await query;
  if (error) throw error;
  return { rows: data ?? [], count: count ?? 0 };
}

export async function getItem(companyId, itemId) {
  return unwrap(await supabase
    .from('items')
    .select(detailColumns)
    .eq('company_id', companyId)
    .eq('id', itemId)
    .single());
}

export async function getUntrackedStock(companyId, itemId) {
  return unwrap(await supabase
    .from('stock_balances')
    .select(`
      quantity,
      warehouse:warehouses!stock_balances_warehouse_company_fk(name)
    `)
    .eq('company_id', companyId)
    .eq('item_id', itemId)
    .gt('quantity', 0)
    .limit(10));
}

export async function activateItemLots(companyId, itemId) {
  return unwrap(await supabase.rpc('activate_item_lots', {
    p_company: companyId,
    p_item: itemId,
  }));
}

export async function searchItemOptions(companyId, resource, term) {
  const table = resource === 'category' ? 'item_categories'
    : resource === 'unit' ? 'units' : null;
  if (!table) throw new Error('Catálogo desconocido');

  let query = supabase
    .from(table)
    .select(resource === 'unit' ? 'id, name, symbol' : 'id, name')
    .eq('company_id', companyId)
    .eq('active', true)
    .order('name', { ascending: true })
    .limit(30);

  if (term.trim()) query = query.ilike('name', `%${term.trim()}%`);
  return unwrap(await query);
}

export async function saveItem(companyId, itemId, values) {
  const payload = {
    code: values.code.trim(),
    name: values.name.trim(),
    item_type: values.item_type,
    category_id: values.category_id || null,
    unit_id: values.unit_id,
    barcode: values.barcode.trim() || null,
    description: values.description.trim(),
    minimum_stock: values.minimum_stock === '' ? '0' : values.minimum_stock,
    track_lots: values.track_lots,
    reference_unit_cost: values.reference_unit_cost === ''
      ? null : values.reference_unit_cost,
  };

  if (itemId) {
    return unwrap(await supabase
      .from('items')
      .update(payload)
      .eq('company_id', companyId)
      .eq('id', itemId)
      .select('id')
      .single());
  }

  return unwrap(await supabase
    .from('items')
    .insert({ ...payload, company_id: companyId })
    .select('id')
    .single());
}

export async function setItemActive(companyId, itemId, active) {
  return unwrap(await supabase
    .from('items')
    .update({ active })
    .eq('company_id', companyId)
    .eq('id', itemId)
    .select('id')
    .single());
}

import { supabase } from '../lib/supabase';

export const catalogs = {
  units: {
    table: 'units',
    columns: 'id, company_id, code, name, symbol, dimension, active, created_at',
    fields: ['code', 'name', 'symbol', 'dimension'],
  },
  categories: {
    table: 'item_categories',
    columns: 'id, company_id, code, name, description, active, created_at',
    fields: ['code', 'name', 'description'],
  },
  warehouses: {
    table: 'warehouses',
    columns: 'id, company_id, code, name, location, active, created_at',
    fields: ['code', 'name', 'location'],
  },
};

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listCatalog(resource, companyId, page, search) {
  const config = catalogs[resource];
  if (!config) throw new Error('Catálogo desconocido');

  let query = supabase
    .from(config.table)
    .select(config.columns, { count: 'exact' })
    .eq('company_id', companyId)
    .order('name', { ascending: true })
    .range(page * 25, page * 25 + 24);

  if (search.trim()) query = query.ilike('name', `%${search.trim()}%`);

  const { data, count, error } = await query;
  if (error) throw error;
  return { rows: data ?? [], count: count ?? 0 };
}

export async function saveCatalog(resource, companyId, id, values) {
  const config = catalogs[resource];
  if (!config) throw new Error('Catálogo desconocido');

  const payload = Object.fromEntries(
    config.fields.map((field) => [field, values[field]?.trim() ?? '']),
  );

  if (id) {
    return unwrap(await supabase
      .from(config.table)
      .update(payload)
      .eq('company_id', companyId)
      .eq('id', id)
      .select('id')
      .single());
  }

  return unwrap(await supabase
    .from(config.table)
    .insert({ ...payload, company_id: companyId })
    .select('id')
    .single());
}

export async function setCatalogActive(resource, companyId, id, active) {
  const config = catalogs[resource];
  if (!config) throw new Error('Catálogo desconocido');

  return unwrap(await supabase
    .from(config.table)
    .update({ active })
    .eq('company_id', companyId)
    .eq('id', id)
    .select('id')
    .single());
}

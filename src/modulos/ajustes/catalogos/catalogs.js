import { supabase } from '../../../compartido/utilidades/supabase';

const comunes = 'id, company_id:empresa_id, code:codigo, name:nombre, active:activo, created_at:creado_en';

// fields: [clave del formulario, columna de la base]
export const catalogs = {
  unidades: {
    table: 'stock_unidades',
    columns: `${comunes}, symbol:simbolo, dimension:magnitud`,
    fields: [['code', 'codigo'], ['name', 'nombre'], ['symbol', 'simbolo'], ['dimension', 'magnitud']],
  },
  categorias: {
    table: 'stock_categorias',
    columns: `${comunes}, description:descripcion`,
    fields: [['code', 'codigo'], ['name', 'nombre'], ['description', 'descripcion']],
  },
  depositos: {
    table: 'stock_depositos',
    columns: `${comunes}, location:ubicacion`,
    fields: [['code', 'codigo'], ['name', 'nombre'], ['location', 'ubicacion']],
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
    .eq('empresa_id', companyId)
    .order('nombre', { ascending: true })
    .range(page * 25, page * 25 + 24);

  if (search.trim()) query = query.ilike('nombre', `%${search.trim()}%`);

  const { data, count, error } = await query;
  if (error) throw error;
  return { rows: data ?? [], count: count ?? 0 };
}

export async function saveCatalog(resource, companyId, id, values) {
  const config = catalogs[resource];
  if (!config) throw new Error('Catálogo desconocido');

  const payload = Object.fromEntries(
    config.fields.map(([field, column]) => [column, values[field]?.trim() ?? '']),
  );

  if (id) {
    return unwrap(await supabase
      .from(config.table)
      .update(payload)
      .eq('empresa_id', companyId)
      .eq('id', id)
      .select('id')
      .single());
  }

  return unwrap(await supabase
    .from(config.table)
    .insert({ ...payload, empresa_id: companyId })
    .select('id')
    .single());
}

export async function setCatalogActive(resource, companyId, id, active) {
  const config = catalogs[resource];
  if (!config) throw new Error('Catálogo desconocido');

  return unwrap(await supabase
    .from(config.table)
    .update({ activo: active })
    .eq('empresa_id', companyId)
    .eq('id', id)
    .select('id')
    .single());
}

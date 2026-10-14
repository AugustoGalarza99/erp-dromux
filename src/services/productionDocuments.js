import { supabase } from '../lib/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function documentSettings(company) {
  return unwrap(
    await supabase
      .from('production_document_settings')
      .select('*')
      .eq('company_id', company)
      .maybeSingle(),
  );
}

export async function saveDocumentSettings(company, form) {
  return unwrap(
    await supabase.rpc('save_production_document_settings', {
      p_company: company,
      p_logo: form.logo_data,
      p_code: form.document_code,
      p_revision: form.revision,
      p_labels: form.labels
        .split('\n')
        .map((label) => label.trim())
        .filter(Boolean),
    }),
  );
}

export async function packagingTypes(company, page = 0, search = '') {
  let query = supabase
    .from('production_packaging_types')
    .select('*, unit:units!production_packaging_types_company_id_unit_id_fkey(id,name,symbol)', {
      count: 'exact',
    })
    .eq('company_id', company)
    .order('name')
    .order('id')
    .range(page * 25, page * 25 + 24);
  if (search.trim()) query = query.ilike('name', `%${search.trim()}%`);
  const { data, count, error } = await query;
  if (error) throw error;
  return { rows: data ?? [], count: count ?? 0 };
}

export async function savePackaging(company, form) {
  return unwrap(
    await supabase.rpc('save_production_packaging_type', {
      p_company: company,
      p_id: form.id || null,
      p_name: form.name,
      p_capacity: form.capacity,
      p_unit: form.unit_id,
      p_active: form.active,
    }),
  );
}

export async function createWorkOrder(company, values, request, finish = null) {
  return unwrap(
    await supabase.rpc('create_production_work_order', {
      p_company: company,
      p_product: values.productId,
      p_quantity: values.quantity,
      p_warehouse: values.warehouseId,
      p_due: values.dueOn || null,
      p_note: values.note.trim(),
      p_request: request,
      p_plan: values.planId || null,
      p_options: values.workOptions ?? { packaging: [], observations: {} },
      p_finish: finish,
    }),
  );
}

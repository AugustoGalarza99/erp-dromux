import { supabase } from '../../../compartido/utilidades/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function documentSettings(company) {
  return unwrap(
    await supabase
      .from('produccion_documentos_config')
      .select('logo_data:logo, document_code:documento_codigo, revision, observation_labels:observaciones_etiquetas, updated_at:actualizado_en')
      .eq('empresa_id', company)
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
    .from('produccion_tipos_envase')
    .select('id, name:nombre, capacity:capacidad, unit_id:unidad_id, active:activo, unit:stock_unidades!produccion_tipos_envase_empresa_id_unidad_id_fkey(id,name:nombre,symbol:simbolo)', {
      count: 'exact',
    })
    .eq('empresa_id', company)
    .order('nombre')
    .order('id')
    .range(page * 25, page * 25 + 24);
  if (search.trim()) query = query.ilike('nombre', `%${search.trim()}%`);
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

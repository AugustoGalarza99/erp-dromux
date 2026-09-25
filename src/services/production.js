import { supabase } from '../lib/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listProductionItems(companyId) {
  return unwrap(await supabase.from('items')
    .select('id, code, name, item_type, track_lots, reference_unit_cost, units!items_unit_company_fk(symbol)')
    .eq('company_id', companyId).eq('active', true)
    .in('item_type', ['raw_material', 'semi_finished', 'finished_product'])
    .order('name').limit(500));
}

export async function listFormulas(companyId) {
  return unwrap(await supabase.from('production_formulas')
    .select('product_id, batch_quantity, version, updated_at, production_formula_lines(component_id, quantity)')
    .eq('company_id', companyId).order('updated_at', { ascending: false }));
}

export async function saveFormula(companyId, productId, batchQuantity, lines) {
  return unwrap(await supabase.rpc('save_production_formula', {
    p_company: companyId,
    p_product: productId,
    p_batch_quantity: batchQuantity,
    p_lines: lines.map(({ componentId, quantity }) => ({
      component_id: componentId,
      quantity,
    })),
  }));
}

export async function getFormulaCost(companyId, productId) {
  return unwrap(await supabase.rpc('production_formula_cost', {
    p_company: companyId,
    p_product: productId,
  }));
}

export async function listProductionWarehouses(companyId) {
  return unwrap(await supabase.from('warehouses')
    .select('id, code, name').eq('company_id', companyId)
    .eq('active', true).order('name').limit(100));
}

export async function listProductionBalances(companyId, componentIds) {
  if (!componentIds.length) return [];
  return unwrap(await supabase.from('stock_balances')
    .select('item_id, warehouse_id, quantity')
    .eq('company_id', companyId).in('item_id', componentIds).limit(1000));
}

export async function listProductionRuns(companyId) {
  return unwrap(await supabase.from('production_runs')
    .select('id, product_id, quantity, formula_version, estimated_cost, created_at, warehouse_id, production_run_lines(component_id, quantity, lot_code, warehouse_id, unit_cost)')
    .eq('company_id', companyId).order('created_at', { ascending: false }).limit(30));
}

export async function postProductionRun(companyId, payload, requestId) {
  return unwrap(await supabase.rpc('post_production_run', {
    p_company: companyId,
    p_product: payload.productId,
    p_request_id: requestId,
    p_quantity: payload.quantity,
    p_warehouse: payload.warehouseId,
    p_output_lot: payload.outputLot || null,
    p_expires_on: payload.expiresOn || null,
    p_note: payload.note.trim(),
    p_inputs: payload.inputs.map((input) => ({
      component_id: input.componentId,
      warehouse_id: input.warehouseId,
      lot_code: input.lotCode || null,
    })),
  }));
}

export async function listProductionPlans(companyId) {
  return unwrap(await supabase.from('production_plans')
    .select('id, product_id, warehouse_id, quantity, formula_version, estimated_cost, component_snapshot, due_on, note, status, run_id, created_at')
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })
    .limit(100));
}

export async function createProductionPlan(companyId, values, requestId) {
  return unwrap(await supabase.rpc('create_production_plan', {
    p_company: companyId,
    p_product: values.productId,
    p_quantity: values.quantity,
    p_warehouse: values.warehouseId,
    p_due_on: values.dueOn || null,
    p_note: values.note.trim(),
    p_request_id: requestId,
  }));
}

export async function cancelProductionPlan(companyId, planId) {
  return unwrap(await supabase.rpc('cancel_production_plan', {
    p_company: companyId,
    p_plan: planId,
  }));
}

export async function completeProductionPlan(companyId, planId, inputs, outputLot, expiresOn, requestId) {
  return unwrap(await supabase.rpc('complete_production_plan', {
    p_company: companyId,
    p_plan: planId,
    p_request_id: requestId,
    p_inputs: inputs.map((input) => ({
      component_id: input.componentId,
      warehouse_id: input.warehouseId,
      lot_code: input.lotCode || null,
    })),
    p_output_lot: outputLot || null,
    p_expires_on: expiresOn || null,
  }));
}

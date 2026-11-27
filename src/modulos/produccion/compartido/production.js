import { supabase } from "../../../compartido/utilidades/supabase";
import { LINE_LIMITS } from "../../../compartido/utilidades/limits";

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listProductionItems(companyId, includeInactive = false) {
  return unwrap(
    await supabase.rpc("list_production_items", {
      p_company: companyId,
      p_include_inactive: includeInactive,
    }),
  );
}

export async function listFormulas(companyId) {
  return unwrap(
    await supabase
      .from("produccion_formulas")
      .select(
        "product_id:producto_id, batch_quantity:cantidad_base, version, updated_at:actualizado_en, production_formula_lines:produccion_formulas_lineas(component_id:componente_id, quantity:cantidad)",
      )
      .eq("empresa_id", companyId)
      .eq("archivado", false)
      .order("actualizado_en", { ascending: false }),
  );
}

/* Tope de componentes por fórmula: debe coincidir con la base. Ver `lib/limits.js` y H-006. */
export const FORMULA_LINE_LIMIT = LINE_LIMITS.formula;

export async function saveFormula(
  companyId,
  productId,
  batchQuantity,
  lines,
  yieldEnabled = false,
  yieldFactor = 1,
) {
  return unwrap(
    await supabase.rpc("save_production_formula_v2", {
      p_company: companyId,
      p_product: productId,
      p_batch_quantity: batchQuantity,
      p_yield_enabled: yieldEnabled,
      p_yield_factor: yieldFactor,
      p_lines: lines.map(({ componentId, quantity }) => ({
        component_id: componentId,
        quantity,
      })),
    }),
  );
}

export async function getFormulaCost(companyId, productId) {
  return unwrap(
    await supabase.rpc("production_formula_cost", {
      p_company: companyId,
      p_product: productId,
    }),
  );
}

export async function listProductionWarehouses(companyId) {
  return unwrap(
    await supabase
      .from("stock_depositos")
      .select("id, code:codigo, name:nombre")
      .eq("empresa_id", companyId)
      .eq("activo", true)
      .order("nombre")
      .limit(100),
  );
}

export async function listProductionBalances(companyId, componentIds) {
  if (!componentIds.length) return [];
  return unwrap(
    await supabase
      .from("stock_saldos")
      .select("item_id, warehouse_id:deposito_id, quantity:cantidad")
      .eq("empresa_id", companyId)
      .in("item_id", componentIds)
      .limit(1000),
  );
}

export async function listProductionRuns(companyId) {
  return unwrap(
    await supabase.rpc("list_production_runs", { p_company: companyId }),
  );
}

export async function postProductionRun(companyId, payload, requestId) {
  return unwrap(
    await supabase.rpc("post_production_run", {
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
    }),
  );
}

export async function listProductionPlans(companyId) {
  return unwrap(
    await supabase.rpc("list_production_plans", { p_company: companyId }),
  );
}

export async function createProductionPlan(companyId, values, requestId) {
  return unwrap(
    await supabase.rpc("create_production_plan", {
      p_company: companyId,
      p_product: values.productId,
      p_quantity: values.quantity,
      p_warehouse: values.warehouseId,
      p_due_on: values.dueOn || null,
      p_note: values.note.trim(),
      p_request_id: requestId,
    }),
  );
}

export async function cancelProductionPlan(companyId, planId) {
  return unwrap(
    await supabase.rpc("cancel_production_plan", {
      p_company: companyId,
      p_plan: planId,
    }),
  );
}

export async function listProductionJobs(companyId) {
  return unwrap(
    await supabase.rpc("list_production_jobs", { p_company: companyId }),
  );
}

export async function createProductionJob(companyId, values, requestId) {
  return unwrap(
    await supabase.rpc("create_production_job", {
      p_company: companyId,
      p_product: values.productId,
      p_quantity: values.quantity,
      p_warehouse: values.warehouseId,
      p_due_on: values.dueOn || null,
      p_note: values.note.trim(),
      p_request_id: requestId,
      p_plan: values.planId || null,
    }),
  );
}

export async function startProductionJob(companyId, jobId) {
  return unwrap(
    await supabase.rpc("start_production_job", {
      p_company: companyId,
      p_job: jobId,
    }),
  );
}

export async function issueProductionMaterial(
  companyId,
  jobId,
  entry,
  requestId,
) {
  return unwrap(
    await supabase.rpc("issue_production_material", {
      p_company: companyId,
      p_job: jobId,
      p_component: entry.componentId,
      p_warehouse: entry.warehouseId,
      p_lot: entry.lotCode || null,
      p_quantity: entry.quantity,
      p_note: entry.note.trim(),
      p_request_id: requestId,
    }),
  );
}

export async function returnProductionMaterial(
  companyId,
  jobId,
  issueId,
  quantity,
  note,
  requestId,
) {
  return unwrap(
    await supabase.rpc("return_production_material", {
      p_company: companyId,
      p_job: jobId,
      p_issue: issueId,
      p_quantity: quantity,
      p_note: note.trim(),
      p_request_id: requestId,
    }),
  );
}

export async function finishProductionJob(companyId, jobId, values, requestId) {
  return unwrap(
    await supabase.rpc("finish_production_job", {
      p_company: companyId,
      p_job: jobId,
      p_actual_quantity: values.actualQuantity,
      p_output_lot: values.outputLot.trim() || null,
      p_expires_on: values.expiresOn || null,
      p_variance_note: values.varianceNote.trim() || null,
      p_request_id: requestId,
    }),
  );
}

export async function cancelProductionJob(companyId, jobId, reason) {
  return unwrap(
    await supabase.rpc("cancel_production_job", {
      p_company: companyId,
      p_job: jobId,
      p_reason: reason.trim(),
    }),
  );
}

export async function completeProductionNow(
  companyId,
  values,
  requestId,
  finishRequestId,
) {
  return unwrap(
    await supabase.rpc("complete_production_now", {
      p_company: companyId,
      p_product: values.productId,
      p_planned_quantity: values.plannedQuantity,
      p_actual_quantity: values.actualQuantity,
      p_warehouse: values.warehouseId,
      p_output_lot: values.outputLot.trim() || null,
      p_expires_on: values.expiresOn || null,
      p_note: values.note.trim(),
      p_variance_note: values.varianceNote.trim() || null,
      p_inputs: values.inputs.map((input) => ({
        component_id: input.componentId,
        warehouse_id: input.warehouseId,
        lot_code: input.lotCode || null,
        quantity: input.quantity,
      })),
      p_request_id: requestId,
      p_finish_request_id: finishRequestId,
      p_plan: values.planId || null,
    }),
  );
}

export async function checkManufacturingAvailability(
  companyId,
  productId,
  quantity,
) {
  return unwrap(
    await supabase.rpc("erp_can_manufacture", {
      p_company: companyId,
      p_product: productId,
      p_quantity: quantity,
    }),
  );
}

export async function listProductionReservations(companyId) {
  return unwrap(
    await supabase
      .from("produccion_ordenes_reservas")
      .select("job_id:orden_id, component_id:componente_id, required_quantity:cantidad_requerida, reserved_quantity:cantidad_reservada")
      .eq("empresa_id", companyId)
      .limit(2000),
  );
}

export async function listProductionReservationLocations(companyId) {
  return unwrap(
    await supabase
      .from("produccion_reservas_ubicaciones")
      .select("job_id:orden_id, component_id:componente_id, warehouse_id:deposito_id, lot_code:lote_codigo, quantity:cantidad")
      .eq("empresa_id", companyId)
      .limit(3000),
  );
}

export async function recalculateProductionReservations(companyId) {
  return unwrap(
    await supabase.rpc("recalculate_production_reservations", {
      p_company: companyId,
    }),
  );
}

/*
 * Terminar la orden con ajustes de insumos y recuento de envases en una sola operación (migración 043).
 * adjustments: [{ kind: 'entrega' | 'devolucion', componentId, warehouseId?, lotCode?, quantity, note }]
 * packaging: { [id de envasado de la orden]: cantidad real de envases }
 */
export async function finishProductionJobAdjusted(
  companyId,
  jobId,
  values,
  adjustments,
  packaging,
  requestId,
) {
  return unwrap(
    await supabase.rpc("finish_production_job_adjusted", {
      p_company: companyId,
      p_job: jobId,
      p_actual_quantity: values.actualQuantity,
      p_output_lot: values.outputLot.trim() || null,
      p_expires_on: values.expiresOn || null,
      p_variance_note: values.varianceNote.trim() || null,
      p_request_id: requestId,
      p_adjustments: adjustments.map((entry) => ({
        kind: entry.kind,
        component_id: entry.componentId,
        warehouse_id: entry.warehouseId || null,
        lot_code: entry.lotCode || null,
        quantity: entry.quantity,
        note: entry.note,
      })),
      p_packaging: packaging,
    }),
  );
}

const BUENOS_AIRES = "America/Argentina/Buenos_Aires";

/* Producción terminada agrupada por día, semana o mes (sin costos). */
export async function getProductionOutputSummary(
  companyId,
  { from, to, bucket, productId = null },
) {
  return unwrap(
    await supabase.rpc("production_output_summary", {
      p_company: companyId,
      p_from: from,
      p_to: to,
      p_bucket: bucket,
      p_product: productId,
      p_tz: BUENOS_AIRES,
    }),
  );
}

/* Producción terminada por producto, paginada en el servidor (devuelve total_count en cada fila). */
export async function listProductionOutputByProduct(
  companyId,
  { from, to, search = "", page = 0, pageSize = 25 },
) {
  const rows = unwrap(
    await supabase.rpc("production_output_by_product", {
      p_company: companyId,
      p_from: from,
      p_to: to,
      p_search: search.trim() || null,
      p_limit: pageSize,
      p_offset: page * pageSize,
      p_tz: BUENOS_AIRES,
    }),
  );
  return { rows, count: rows[0]?.total_count ? Number(rows[0].total_count) : 0 };
}

import { supabase } from "../../../compartido/utilidades/supabase";
import { TIPOS_ITEM } from "../../../compartido/valores";

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listDeliveryNotes(companyId) {
  return unwrap(
    await supabase
      .from("stock_remitos")
      .select(
        `id, number:numero, kind:tipo, job_id:orden_id, sale_id:venta_id,
      sale:ventas(number:numero, customer_name:cliente_nombre), recipient:destinatario,
      note:nota, status:estado, void_reason:motivo_anulacion, created_at:creado_en,
      delivery_note_lines:stock_remitos_lineas(line_no:linea, item_id, sale_line_no:venta_linea,
        item_code:item_codigo, item_name:item_nombre, unit_symbol:unidad_simbolo,
        warehouse_id:deposito_id, warehouse_name:deposito_nombre, lot_code:lote_codigo,
        quantity:cantidad)`,
      )
      .eq("empresa_id", companyId)
      .eq("archivado", false)
      .order("creado_en", { ascending: false })
      .limit(100),
  );
}

export async function issueDeliveryNote(companyId, values, requestId) {
  return unwrap(
    await supabase.rpc("issue_delivery_note", {
      p_company: companyId,
      p_kind: values.kind,
      p_job: values.jobId || null,
      p_recipient: values.recipient.trim(),
      p_note: values.note.trim(),
      p_lines: values.lines.map((line) => ({
        item_id: line.itemId,
        warehouse_id: line.warehouseId,
        lot_code: line.lotCode || null,
        quantity: line.quantity,
      })),
      p_request: requestId,
    }),
  );
}

export async function voidDeliveryNote(companyId, noteId, reason) {
  return unwrap(
    await supabase.rpc("void_delivery_note", {
      p_company: companyId,
      p_note: noteId,
      p_reason: reason.trim(),
    }),
  );
}

export async function listDeliveryItems(companyId) {
  return unwrap(
    await supabase
      .from("stock_items")
      .select(
        "id, code:codigo, name:nombre, item_type:tipo_item, track_lots:usa_lotes, infinite_stock:stock_infinito, units:stock_unidades!stock_items_unit_company_fk(symbol:simbolo)",
      )
      .eq("empresa_id", companyId)
      .eq("activo", true)
      .in("tipo_item", TIPOS_ITEM)
      .order("nombre")
      .limit(600),
  );
}

export async function issueSaleDeliveryNote(companyId, values, requestId) {
  return unwrap(
    await supabase.rpc("issue_sale_delivery_note", {
      p_company: companyId,
      p_sale: values.saleId,
      p_recipient: values.recipient.trim(),
      p_note: values.note.trim(),
      p_lines: values.lines.map((line) => ({
        line_no: line.line_no,
        quantity: line.quantity,
      })),
      p_request: requestId,
    }),
  );
}

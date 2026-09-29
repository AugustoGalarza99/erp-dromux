import { supabase } from '../lib/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listDeliveryNotes(companyId) {
  return unwrap(await supabase.from('delivery_notes')
    .select(`id, number, kind, job_id, sale_id, sale:sales(number, customer_name), recipient, note, status,
      void_reason, created_at, delivery_note_lines(line_no, item_id, sale_line_no,
        item_code, item_name, unit_symbol, warehouse_id, warehouse_name,
        lot_code, quantity)`)
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })
    .limit(100));
}

export async function issueDeliveryNote(companyId, values, requestId) {
  return unwrap(await supabase.rpc('issue_delivery_note', {
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
  }));
}

export async function voidDeliveryNote(companyId, noteId, reason) {
  return unwrap(await supabase.rpc('void_delivery_note', {
    p_company: companyId,
    p_note: noteId,
    p_reason: reason.trim(),
  }));
}

export async function listDeliveryItems(companyId) {
  return unwrap(await supabase.from('items')
    .select('id, code, name, item_type, track_lots, infinite_stock, units!items_unit_company_fk(symbol)')
    .eq('company_id', companyId).eq('active', true)
    .in('item_type', ['raw_material', 'semi_finished', 'finished_product', 'consumable'])
    .order('name').limit(600));
}

export async function issueSaleDeliveryNote(companyId, values, requestId) {
  return unwrap(await supabase.rpc('issue_sale_delivery_note', {
    p_company: companyId,
    p_sale: values.saleId,
    p_recipient: values.recipient.trim(),
    p_note: values.note.trim(),
    p_lines: values.lines.map((line) => ({
      line_no: line.line_no,
      quantity: line.quantity,
    })),
    p_request: requestId,
  }));
}

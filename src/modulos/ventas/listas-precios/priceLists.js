import { supabase } from "../../../compartido/utilidades/supabase";

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listPriceLists(companyId) {
  return unwrap(
    await supabase
      .from("ventas_listas_precios")
      .select("id, name:nombre, currency:moneda, base_list_id:lista_base_id, base_discount_percent:descuento_base_porcentaje, rounding_step:redondeo, valid_from:vigente_desde, valid_to:vigente_hasta, is_default:es_predeterminada, archived:archivado, note:nota")
      .eq("empresa_id", companyId)
      .order("archivado")
      .order("nombre")
      .limit(200),
  );
}

export async function listCompanyUnits(companyId) {
  return unwrap(
    await supabase.from("stock_unidades").select("id, symbol:simbolo, name:nombre").eq("empresa_id", companyId).order("simbolo").limit(200),
  );
}

export async function getItemSaleSettings(companyId, itemId) {
  const rows = unwrap(
    await supabase
      .from("ventas_items_config")
      .select("tax_percent:impuesto_porcentaje, content_quantity:contenido_cantidad, content_unit_id:contenido_unidad_id")
      .eq("empresa_id", companyId)
      .eq("item_id", itemId)
      .limit(1),
  );
  return rows?.[0] ?? null;
}

export async function listPriceRows(companyId, listId, { search = "", missingOnly = false, page = 0, pageSize = 50 }) {
  return unwrap(
    await supabase.rpc("erp_price_list_rows", {
      p_company: companyId, p_list: listId, p_search: search.trim(),
      p_only_missing: missingOnly, p_page: page, p_page_size: pageSize,
    }),
  );
}

export async function listAdminPriceRows(companyId, listId, { search = "", filter = "all", page = 0, pageSize = 50 }) {
  return unwrap(
    await supabase.rpc("erp_admin_price_list_rows", {
      p_company: companyId, p_list: listId, p_search: search.trim(),
      p_filter: filter, p_page: page, p_page_size: pageSize,
    }),
  );
}

export async function getPriceSettings(companyId) {
  const rows = unwrap(await supabase.rpc("erp_price_settings", { p_company: companyId }));
  return rows?.[0] ?? null;
}

export async function savePriceSettings(companyId, s) {
  return unwrap(
    await supabase.rpc("save_price_settings", {
      p_company: companyId, p_default_tax: s.tax, p_min_margin: s.minMargin,
      p_commission: s.commission, p_structure: s.structure,
      // Solo existe desde la migración 040: sin ella no se envía para no romper la llamada.
      ...(s.maxDiscount === undefined ? {} : { p_max_discount: s.maxDiscount }),
    }),
  );
}

export async function savePriceList(companyId, id, f) {
  return unwrap(
    await supabase.rpc("save_price_list", {
      p_company: companyId, p_id: id || null, p_name: f.name, p_currency: f.currency,
      p_valid_from: f.valid_from || null, p_valid_to: f.valid_to || null, p_is_default: f.is_default,
      p_base_list: f.base_list_id || null, p_base_discount: f.base_list_id ? Number(f.base_discount) || 0 : 0,
      p_rounding_step: Number(f.rounding_step) || 0, p_note: f.note ?? "", p_archived: f.archived,
    }),
  );
}

export async function setPriceListItem(companyId, listId, itemId, method, value, reason) {
  return unwrap(
    await supabase.rpc("set_price_list_item", {
      p_company: companyId, p_list: listId, p_item: itemId, p_method: method, p_value: value, p_reason: reason ?? "",
    }),
  );
}

export async function removePriceListItem(companyId, listId, itemId, reason) {
  return unwrap(
    await supabase.rpc("remove_price_list_item", {
      p_company: companyId, p_list: listId, p_item: itemId, p_reason: reason ?? "",
    }),
  );
}

export async function bulkPriceChange(companyId, listId, { mode, percent, apply, reason, requestId }) {
  return unwrap(
    await supabase.rpc("bulk_price_change", {
      p_company: companyId, p_list: listId, p_mode: mode, p_percent: mode === "porcentaje" ? percent : null,
      p_item_ids: null, p_apply: apply, p_reason: reason ?? "", p_request_id: apply ? requestId : null,
    }),
  );
}

export async function importPriceRows(companyId, listId, rows, { apply, reason, requestId }) {
  return unwrap(
    await supabase.rpc("import_price_list_items", {
      p_company: companyId, p_list: listId, p_rows: rows, p_apply: apply,
      p_reason: reason ?? "", p_request_id: apply ? requestId : null,
    }),
  );
}

export async function saveItemSaleSettings(companyId, itemId, { tax, content, unitId }) {
  return unwrap(
    await supabase.rpc("save_item_sale_settings", {
      p_company: companyId, p_item: itemId, p_tax: tax, p_content: content, p_content_unit: unitId,
    }),
  );
}

export async function listPriceHistory(companyId, listId, itemId, page = 0) {
  return unwrap(
    await supabase.rpc("erp_price_list_history", {
      p_company: companyId, p_list: listId, p_item: itemId || null, p_page: page,
    }),
  );
}

export async function listCustomerPriceLists(companyId) {
  return unwrap(
    await supabase
      .from("ventas_clientes")
      .select("customer_id:id, price_list_id:lista_precio_id")
      .eq("empresa_id", companyId)
      .not("lista_precio_id", "is", null)
      .limit(2000),
  );
}

export async function assignCustomerPriceList(companyId, customerId, listId) {
  return unwrap(
    await supabase.rpc("assign_customer_price_list", {
      p_company: companyId, p_customer: customerId, p_list: listId || null,
    }),
  );
}

import { supabase } from "../../../compartido/utilidades/supabase";

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listItems(companyId, { page, search, type, status }) {
  let query = supabase
    .from("stock_items")
    .select(
      "id, code:codigo, name:nombre, item_type:tipo_item, category_id:categoria_id, unit_id:unidad_id, minimum_stock:stock_minimo, infinite_stock:stock_infinito, active:activo",
      {
        count: "exact",
      },
    )
    .eq("empresa_id", companyId)
    .eq("archivado", false)
    .order("nombre", { ascending: true })
    .order("id", { ascending: true })
    .range(page * 25, page * 25 + 24);

  if (search.trim()) query = query.ilike("nombre", `%${search.trim()}%`);
  if (type) query = query.eq("tipo_item", type);
  if (status !== "all") query = query.eq("activo", status === "active");

  const { data, count, error } = await query;
  if (error) throw error;
  return { rows: data ?? [], count: count ?? 0 };
}

export async function getItem(companyId, itemId) {
  return unwrap(
    await supabase.rpc("get_item_detail", {
      p_company: companyId,
      p_item: itemId,
    }),
  );
}

export async function getUntrackedStock(companyId, itemId) {
  return unwrap(
    await supabase
      .from("stock_saldos")
      .select(
        `
      quantity:cantidad,
      warehouse:stock_depositos!stock_saldos_warehouse_company_fk(name:nombre)
    `,
      )
      .eq("empresa_id", companyId)
      .eq("item_id", itemId)
      .gt("cantidad", 0)
      .limit(10),
  );
}

export async function activateItemLots(companyId, itemId) {
  return unwrap(
    await supabase.rpc("activate_item_lots", {
      p_company: companyId,
      p_item: itemId,
    }),
  );
}

export async function searchItemOptions(companyId, resource, term) {
  const table =
    resource === "category"
      ? "stock_categorias"
      : resource === "unit"
        ? "stock_unidades"
        : null;
  if (!table) throw new Error("Catálogo desconocido");

  let query = supabase
    .from(table)
    .select(resource === "unit" ? "id, name:nombre, symbol:simbolo" : "id, name:nombre")
    .eq("empresa_id", companyId)
    .eq("activo", true)
    .order("nombre", { ascending: true })
    .limit(30);

  if (term.trim()) query = query.ilike("nombre", `%${term.trim()}%`);
  return unwrap(await query);
}

export async function saveItem(companyId, itemId, values) {
  const cost = values.purchaseCost;
  const payload = {
    codigo: values.code.trim(),
    nombre: values.name.trim(),
    tipo: values.item_type,
    category_id: values.category_id || null,
    unit_id: values.unit_id,
    codigo_barras: values.barcode.trim(),
    descripcion: values.description.trim(),
    stock_minimo: values.minimum_stock === "" ? "0" : values.minimum_stock,
    seguir_lotes: values.track_lots,
    stock_infinito: values.infinite_stock,
    activo: values.active ?? true,
    precio_venta_ars: "",
    costo_referencia_ars:
      cost?.currency === "USD" ? "" : values.reference_unit_cost,
    costo_usd: cost?.currency === "USD" ? cost.usd : "",
    supplier_id: cost?.supplier?.id ?? "",
    exchange_type_id: cost?.currency === "USD" ? cost.exchangeType : "",
  };
  const id = unwrap(
    await supabase.rpc("save_item_with_cost", {
      p_company: companyId,
      p_item: itemId || null,
      p_row: payload,
      p_expected_updated_at: values.expectedUpdatedAt ?? null,
      p_preserve_cost: Boolean(values.preserveReferenceCost),
    }),
  );
  return { id };
}

export async function getItemCostContext(companyId, itemId) {
  return unwrap(
    await supabase.rpc("item_cost_context", {
      p_company: companyId,
      p_item: itemId,
    }),
  );
}

export async function searchActiveSuppliers(companyId, term) {
  let query = supabase
    .from("compras_proveedores")
    .select("id, name:nombre")
    .eq("empresa_id", companyId)
    .eq("activo", true)
    .order("nombre")
    .order("id")
    .limit(30);
  if (term.trim()) query = query.ilike("nombre", `%${term.trim()}%`);
  return unwrap(await query);
}

export async function setItemActive(companyId, itemId, active) {
  return unwrap(
    await supabase
      .from("stock_items")
      .update({ activo: active })
      .eq("empresa_id", companyId)
      .eq("id", itemId)
      .select("id")
      .single(),
  );
}

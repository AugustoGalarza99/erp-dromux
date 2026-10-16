import { supabase } from "../lib/supabase";

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

const detailColumns = `
  id, company_id, code, name, item_type, category_id, unit_id,
  barcode, description, minimum_stock, track_lots, infinite_stock, active, archived, reference_unit_cost,
  reference_cost_usd, reference_exchange_rate_type_id,
  created_at, updated_at,
  category:item_categories!items_category_company_fk(id, name, active),
  unit:units!items_unit_company_fk(id, name, symbol, active)
`;

export async function listItems(companyId, { page, search, type, status }) {
  let query = supabase
    .from("items")
    .select(
      "id, code, name, item_type, category_id, unit_id, minimum_stock, infinite_stock, active",
      {
        count: "exact",
      },
    )
    .eq("company_id", companyId)
    .eq("archived", false)
    .order("name", { ascending: true })
    .order("id", { ascending: true })
    .range(page * 25, page * 25 + 24);

  if (search.trim()) query = query.ilike("name", `%${search.trim()}%`);
  if (type) query = query.eq("item_type", type);
  if (status !== "all") query = query.eq("active", status === "active");

  const { data, count, error } = await query;
  if (error) throw error;
  return { rows: data ?? [], count: count ?? 0 };
}

export async function getItem(companyId, itemId) {
  return unwrap(
    await supabase
      .from("items")
      .select(detailColumns)
      .eq("company_id", companyId)
      .eq("id", itemId)
      .single(),
  );
}

export async function getUntrackedStock(companyId, itemId) {
  return unwrap(
    await supabase
      .from("stock_balances")
      .select(
        `
      quantity,
      warehouse:warehouses!stock_balances_warehouse_company_fk(name)
    `,
      )
      .eq("company_id", companyId)
      .eq("item_id", itemId)
      .gt("quantity", 0)
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
      ? "item_categories"
      : resource === "unit"
        ? "units"
        : null;
  if (!table) throw new Error("Catálogo desconocido");

  let query = supabase
    .from(table)
    .select(resource === "unit" ? "id, name, symbol" : "id, name")
    .eq("company_id", companyId)
    .eq("active", true)
    .order("name", { ascending: true })
    .limit(30);

  if (term.trim()) query = query.ilike("name", `%${term.trim()}%`);
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
    .from("suppliers")
    .select("id, name")
    .eq("company_id", companyId)
    .eq("active", true)
    .order("name")
    .order("id")
    .limit(30);
  if (term.trim()) query = query.ilike("name", `%${term.trim()}%`);
  return unwrap(await query);
}

export async function setItemActive(companyId, itemId, active) {
  return unwrap(
    await supabase
      .from("items")
      .update({ active })
      .eq("company_id", companyId)
      .eq("id", itemId)
      .select("id")
      .single(),
  );
}

import { supabase } from "../utilidades/supabase";

export const cleanupResources = [
  {
    value: "items",
    label: "Productos, materias primas e insumos",
    permission: "items",
  },
  { value: "tipos_cambio", label: "Tipos de dólar", permission: "compras_proveedores" },
  { value: "formulas", label: "Fórmulas y procesos", permission: "produccion_formulas" },
  { value: "ordenes", label: "Órdenes de producción", permission: "produccion_ordenes" },
  {
    value: "fabricaciones",
    label: "Fabricaciones registradas",
    permission: "produccion_ordenes",
  },
  { value: "planes", label: "Planificaciones", permission: "produccion_planificacion" },
  { value: "remitos", label: "Remitos", permission: "stock_remitos" },
];

async function call(name, args) {
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw error;
  return data;
}

export const cleanupPreview = (company, resource, id) =>
  call("cleanup_preview", {
    p_company: company,
    p_resource: resource,
    p_id: id,
  });
export const cleanupRecord = (company, resource, id, action) =>
  call("cleanup_record", {
    p_company: company,
    p_resource: resource,
    p_id: id,
    p_action: action,
  });
export const restoreArchived = (company, resource, id) =>
  call("restore_archived_record", {
    p_company: company,
    p_resource: resource,
    p_id: id,
  });
export const archivedRecords = (company, resource, search, page) =>
  call("archived_records", {
    p_company: company,
    p_resource: resource,
    p_search: search,
    p_page: page,
  });

export async function refreshCleanupData(client) {
  const keys = new Set([
    "archived-records",
    "items",
    "item-detail",
    "item-cost-context",
    "supplier-catalog",
    "supplier-directory",
    "supplier-quotes",
    "purchase-items",
    "item-supplier-options",
    "exchange-types",
    "exchange-overview",
    "exchange-rates",
    "production-items",
    "production-items-history",
    "production-formulas",
    "production-jobs",
    "production-runs",
    "production-plans",
    "production-reservations",
    "production-reservation-locations",
    "delivery-notes",
    "delivery-items",
    "stock",
    "stock-summary",
    "stock-options",
    "product-costs",
    "erp-dashboard",
    "operational-alerts",
    "replenishment-forecast",
    "planning-availability",
    "production-dashboard",
  ]);
  await client.invalidateQueries({
    predicate: (query) => keys.has(query.queryKey[0]),
  });
}

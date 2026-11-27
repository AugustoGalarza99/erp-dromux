import { supabase } from "../lib/supabase";

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listQuotes(companyId, { search = "", status = "all", page = 0, size = 25 } = {}) {
  return unwrap(
    await supabase.rpc("erp_quotes_page", {
      p_company: companyId, p_search: search.trim(), p_status: status, p_page: page, p_size: size,
    }),
  );
}

export async function getQuote(companyId, quoteId) {
  return unwrap(await supabase.rpc("erp_quote_detail", { p_company: companyId, p_quote: quoteId }));
}

export async function createQuote(companyId, q, requestId) {
  return unwrap(
    await supabase.rpc("create_quote", {
      p_company: companyId,
      p_customer: q.customerId || null,
      p_name: q.customerId ? null : q.name,
      p_tax_id: q.customerId ? null : q.taxId,
      p_email: q.customerId ? null : q.email,
      p_phone: q.customerId ? null : q.phone,
      p_address: q.customerId ? null : q.address,
      p_valid_until: q.validUntil,
      p_note: q.note ?? "",
      p_show_tax: q.showTax,
      // Solo se envía cuando se usa: el servidor anterior a la migración 042 no conoce este parámetro.
      ...(q.taxIncluded ? { p_tax_included: true } : {}),
      p_lines: q.lines.map((line) => ({
        item_id: line.itemId,
        quantity: line.quantity,
        ...(Number(line.discount) > 0
          ? { discount_percent: Number(line.discount), discount_reason: (line.discountReason || "").trim() || null }
          : {}),
      })),
      p_request_id: requestId,
    }),
  );
}

export async function setQuoteStatus(companyId, quoteId, status) {
  return unwrap(
    await supabase.rpc("set_quote_status", { p_company: companyId, p_quote: quoteId, p_status: status }),
  );
}

export async function getCompanyProfile(companyId) {
  const rows = unwrap(await supabase.rpc("erp_company_profile", { p_company: companyId }));
  return rows?.[0] ?? null;
}

export async function saveCompanyProfile(companyId, f) {
  return unwrap(
    await supabase.rpc("save_company_profile", {
      p_company: companyId, p_legal_name: f.legal_name, p_tax_id: f.tax_id, p_tax_condition: f.tax_condition,
      p_address: f.address, p_phone: f.phone, p_email: f.email, p_website: f.website, p_logo: f.logo_data,
    }),
  );
}

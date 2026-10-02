import { supabase } from '../lib/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listExchangeTypes(companyId) {
  return unwrap(await supabase.from('exchange_rate_types')
    .select('id, name, active').eq('company_id', companyId).order('name'));
}

export async function listExchangeRates(companyId) {
  return unwrap(await supabase.from('exchange_rates')
    .select('id, type_id, ars_per_usd, effective_on, created_at')
    .eq('company_id', companyId).order('effective_on', { ascending: false })
    .order('created_at', { ascending: false }).limit(100));
}

export async function addExchangeType(companyId, name) {
  return unwrap(await supabase.rpc('add_exchange_rate_type', {
    p_company: companyId, p_name: name.trim(),
  }));
}

export async function addExchangeRate(companyId, typeId, rate, date) {
  return unwrap(await supabase.rpc('add_exchange_rate', {
    p_company: companyId, p_type: typeId, p_rate: rate, p_date: date,
  }));
}

export async function setPreferredSupplier(companyId, itemId, supplierId) {
  return unwrap(await supabase.rpc('set_preferred_supplier', {
    p_company: companyId, p_item: itemId, p_supplier: supplierId,
  }));
}

export async function adjustSupplierPrices(companyId, supplierId, itemId, percent, requestId) {
  return unwrap(await supabase.rpc('adjust_supplier_prices', {
    p_company: companyId, p_supplier: supplierId || null, p_item: itemId || null,
    p_percent: percent, p_request_id: requestId,
  }));
}

export async function listProductCosts(companyId, search = '') {
  return unwrap(await supabase.rpc('erp_admin_product_costs', {
    p_company: companyId, p_search: search.trim(),
  }));
}

export async function getSalesProfitSummary(companyId) {
  const rows = unwrap(await supabase.rpc('erp_admin_sales_profit_summary', {
    p_company: companyId,
  }));
  return rows?.[0] ?? null;
}

export async function listSalesProfitDetail(companyId, from, to, search = '', page = 0) {
  return unwrap(await supabase.rpc('erp_admin_sales_profit_detail', {
    p_company: companyId,
    p_from: from,
    p_to: to,
    p_search: search.trim(),
    p_page: page,
  }));
}

export async function getOperationalReport(companyId, from, to) {
  return unwrap(await supabase.rpc('erp_operational_report', {
    p_company: companyId,
    p_from: from,
    p_to: to,
  }));
}

export async function listExchangeOverview(companyId) {
  return unwrap(await supabase.rpc('exchange_rate_overview', { p_company: companyId }));
}

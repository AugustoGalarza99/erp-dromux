import { supabase } from '../utilidades/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function getMemberships() {
  const rows = unwrap(await supabase.rpc('my_company_access'));

  return rows.map((row) => ({
    company_id: row.company_id,
    role_id: row.role_id,
    company_active: row.company_active,
    companies: {
      id: row.company_id,
      name: row.company_name,
      slug: row.company_slug,
      active: row.company_active,
    },
    roles: {
      id: row.role_id,
      name: row.role_name,
      code: row.role_code,
    },
  }));
}

const supportResources = [
  'dashboard', 'inventory', 'items', 'stock', 'warehouses', 'units',
  'categories', 'production', 'purchases', 'sales', 'finance',
  'reports', 'settings', 'users', 'roles',
];

export async function getPermissions(roleId, support = false) {
  if (support) {
    // El soporte lee todo lo del catálogo salvo los datos sensibles (costos); sin catálogo, la lista fija.
    const { data } = await supabase.from('permission_catalog').select('resource, module');
    const fromCatalog = (data ?? []).filter((entry) => entry.module !== 'sensitive').map((entry) => entry.resource);
    return [...new Set([...supportResources, ...fromCatalog])].map((resource) => ({ resource, action: 'read' }));
  }
  return unwrap(await supabase
    .from('role_permissions')
    .select('resource, action')
    .eq('role_id', roleId));
}

export async function beginSupportSession(companyId, reason) {
  return unwrap(await supabase.rpc('begin_support_session', {
    p_company: companyId,
    p_reason: reason.trim(),
  }));
}

export async function createCompany(name) {
  return unwrap(await supabase.rpc('create_company', { p_name: name }));
}

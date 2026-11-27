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
      modules: row.company_modules ?? {},
    },
    roles: {
      id: row.role_id,
      name: row.role_name,
      code: row.role_code,
    },
  }));
}

const supportResources = [
  'inicio', 'inventario', 'items', 'stock', 'depositos', 'unidades',
  'categorias', 'produccion', 'compras', 'ventas', 'finanzas',
  'reportes', 'ajustes', 'usuarios', 'roles',
];

export async function getPermissions(roleId, support = false) {
  if (support) {
    // Soporte con sesión abierta: las mismas acciones que un administrador. El servidor lo vuelve a exigir.
    const catalog = unwrap(await supabase
      .from('ajustes_permisos_catalogo')
      .select('resource:recurso, actions:acciones'));
    const fromCatalog = catalog.flatMap((entry) =>
      entry.actions.map((action) => ({ resource: entry.resource, action })));
    const listed = new Set(
      fromCatalog.filter((entry) => entry.action === 'ver').map((entry) => entry.resource),
    );
    return [
      ...fromCatalog,
      ...supportResources
        .filter((resource) => !listed.has(resource))
        .map((resource) => ({ resource, action: 'ver' })),
    ];
  }
  return unwrap(await supabase
    .from('ajustes_roles_permisos')
    .select('resource:recurso, action:accion')
    .eq('rol_id', roleId));
}

export async function beginSupportSession(companyId, reason) {
  return unwrap(await supabase.rpc('begin_support_session', {
    p_company: companyId,
    p_reason: reason.trim(),
  }));
}

export async function endSupportSession() {
  return unwrap(await supabase.rpc('end_support_session'));
}

export async function createCompany(name) {
  return unwrap(await supabase.rpc('create_company', { p_name: name }));
}

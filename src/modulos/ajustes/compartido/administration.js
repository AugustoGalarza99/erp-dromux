import { supabase } from '../../../compartido/utilidades/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listRoles(companyId) {
  return unwrap(await supabase
    .from('roles')
    .select('id, company_id, code, name, created_at')
    .eq('company_id', companyId)
    .order('created_at', { ascending: true }));
}

export async function listRolePermissions(companyId) {
  return unwrap(await supabase
    .from('role_permissions')
    .select('role_id, resource, action')
    .eq('company_id', companyId));
}

export async function listMembers(companyId) {
  return unwrap(await supabase.rpc('company_members', { p_company: companyId }));
}


export async function saveRole(companyId, role, name, code, permissions) {
  if (role) {
    return unwrap(await supabase.rpc('update_company_role', {
      p_company: companyId,
      p_role: role.id,
      p_name: name,
      p_permissions: permissions,
    }));
  }

  return unwrap(await supabase.rpc('create_company_role', {
    p_company: companyId,
    p_name: name,
    p_code: code,
    p_permissions: permissions,
  }));
}



export async function updateMember(companyId, userId, roleId, active) {
  return unwrap(await supabase.rpc('set_company_member', {
    p_company: companyId,
    p_user: userId,
    p_role: roleId,
    p_active: active,
  }));
}

/* Historial de cambios de roles, permisos y miembros (migración 044). Solo administrador; 25 por página. */
export async function listAccessAudit(companyId, page = 0) {
  const rows = unwrap(await supabase.rpc('access_audit_events_list', {
    p_company: companyId,
    p_page: page,
  }));
  return { rows, count: rows[0]?.total_count ? Number(rows[0].total_count) : 0 };
}

/* Catálogo de módulos y pantallas (migración 045). Si todavía no existe, devuelve lista vacía y se usa la grilla anterior. */
export async function listPermissionCatalog() {
  const { data, error } = await supabase
    .from('permission_catalog')
    .select('resource, module, parent, label, help, sort, actions, is_group, admin_only, enforced')
    .order('sort', { ascending: true });
  if (error) return [];
  return data ?? [];
}

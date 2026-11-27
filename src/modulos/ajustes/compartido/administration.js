import { supabase } from '../../../compartido/utilidades/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listRoles(companyId) {
  return unwrap(await supabase
    .from('ajustes_roles')
    .select('id, company_id:empresa_id, code:codigo, name:nombre, created_at:creado_en')
    .eq('empresa_id', companyId)
    .order('creado_en', { ascending: true }));
}

export async function listRolePermissions(companyId) {
  return unwrap(await supabase
    .from('ajustes_roles_permisos')
    .select('role_id:rol_id, resource:recurso, action:accion')
    .eq('empresa_id', companyId));
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

/* Historial de cambios de roles, permisos y miembros. Solo administrador; 25 por página. */
export async function listAccessAudit(companyId, page = 0) {
  const rows = unwrap(await supabase.rpc('access_audit_events_list', {
    p_company: companyId,
    p_page: page,
  }));
  return { rows, count: rows[0]?.total_count ? Number(rows[0].total_count) : 0 };
}

/* Catálogo de módulos y pantallas con permisos. */
export async function listPermissionCatalog() {
  return unwrap(await supabase
    .from('ajustes_permisos_catalogo')
    .select(`resource:recurso, module:modulo, parent:padre, label:etiqueta, help:ayuda,
      sort:orden, actions:acciones, is_group:es_grupo, admin_only:solo_admin, enforced:exigido`)
    .order('orden', { ascending: true }));
}

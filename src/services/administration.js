import { supabase } from '../lib/supabase';

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

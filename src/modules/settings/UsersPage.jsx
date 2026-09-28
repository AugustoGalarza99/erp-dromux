import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { UserRound, UsersRound } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { friendlyError, notifyError, notifySuccess } from '../../lib/notifications';
import { listMembers, listRoles, updateMember } from '../../services/administration';
import './settings.css';

export default function UsersPage() {
  const { activeCompanyId, user, can, role } = useAuth();
  const client = useQueryClient();
  const [saving, setSaving] = useState(null);
  const membersQuery = useQuery({
    queryKey: ['members', user?.id, activeCompanyId],
    queryFn: () => listMembers(activeCompanyId),
    enabled: Boolean(activeCompanyId),
  });
  const rolesQuery = useQuery({
    queryKey: ['roles', user?.id, activeCompanyId],
    queryFn: () => listRoles(activeCompanyId),
    enabled: Boolean(activeCompanyId && can('users', 'update')),
  });
  const members = membersQuery.data ?? [];
  const roles = rolesQuery.data ?? [];

  async function changeRole(member, roleId) {
    if (roleId === member.role_id) return;
    setSaving(member.user_id);
    try {
      await updateMember(activeCompanyId, member.user_id, roleId, member.active);
      await Promise.all([
        client.invalidateQueries({ queryKey: ['members'] }),
        client.invalidateQueries({ queryKey: ['memberships'] }),
        client.invalidateQueries({ queryKey: ['permissions'] }),
      ]);
      notifySuccess('Rol actualizado', 'Los permisos del usuario se actualizaron.');
    } catch (error) {
      notifyError(error);
    } finally {
      setSaving(null);
    }
  }

  return (
    <div className="settings-page">
      <div className="page-head">
        <div>
          <span className="eyebrow">CONFIGURACIÓN / EQUIPO</span>
          <h1>Usuarios</h1>
          <p>Consultá las personas de la empresa y administrá sus roles.</p>
        </div>
        <span className="date-pill">{members.length} USUARIOS</span>
      </div>
      {(membersQuery.error || rolesQuery.error) && (
        <p role="alert" className="error page-feedback">
          {friendlyError(membersQuery.error || rolesQuery.error)}
        </p>
      )}
      <section className="settings-card member-card">
        <div className="settings-card-heading">
          <span className="role-icon"><UsersRound size={20} /></span>
          <div>
            <h2>Equipo de la empresa</h2>
            <p>El administrador puede asignar un rol a cada integrante.</p>
          </div>
        </div>
        {membersQuery.isPending && <p>Cargando usuarios…</p>}
        {!membersQuery.isPending && !membersQuery.error && !members.length && (
          <p>Aún no hay usuarios asignados.</p>
        )}
        <div className="member-list">
          {members.map((member) => (
            <div className="member-row" key={member.user_id}>
              <span className="member-avatar"><UserRound size={19} /></span>
              <div className="member-identity">
                <strong>{member.display_name || member.email?.split('@')[0]}</strong>
                <small>{member.email}</small>
              </div>
              {can('users', 'update') ? (
                <label className="member-role-control">
                  Rol
                  <select
                    value={member.role_id}
                    disabled={saving === member.user_id || rolesQuery.isPending}
                    onChange={(event) => changeRole(member, event.target.value)}
                  >
                    {roles.filter((entry) => role === 'admin' || entry.code !== 'admin'
                      || entry.id === member.role_id).map((entry) => (
                      <option key={entry.id} value={entry.id}>{entry.name}</option>
                    ))}
                  </select>
                </label>
              ) : <span className="member-status">{member.role_name}</span>}
              <span className={`member-status ${member.active ? '' : 'inactive'}`}>
                {member.active ? 'Activo' : 'Suspendido'}
              </span>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}

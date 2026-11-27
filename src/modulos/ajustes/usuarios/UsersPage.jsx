import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Search, UsersRound } from 'lucide-react';
import ConfirmDeleteDialog from '../../../compartido/componentes/ConfirmDeleteDialog';
import { useAuth } from '../../../compartido/contextos/AuthContext';
import { friendlyError, notifyError, notifySuccess } from '../../../compartido/utilidades/notifications';
import { listMembers, listRoles, updateMember } from '../compartido/administration';
import '../compartido/settings.css';

const PAGE = 25;

export default function UsersPage() {
  const { activeCompanyId, user, role } = useAuth();
  const client = useQueryClient();
  const [saving, setSaving] = useState(null);
  const [search, setSearch] = useState('');
  const [roleFilter, setRoleFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [limit, setLimit] = useState(PAGE);
  const [pendingChange, setPendingChange] = useState(null);

  const membersQuery = useQuery({
    queryKey: ['members', user?.id, activeCompanyId],
    queryFn: () => listMembers(activeCompanyId),
    enabled: Boolean(activeCompanyId),
  });
  const rolesQuery = useQuery({
    queryKey: ['roles', user?.id, activeCompanyId],
    queryFn: () => listRoles(activeCompanyId),
    enabled: Boolean(activeCompanyId && role === 'administrador'),
  });
  const members = membersQuery.data ?? [];
  const roles = rolesQuery.data ?? [];

  function askChangeRole(member, roleId) {
    if (roleId === member.role_id || saving) return;
    setPendingChange({ member, roleId });
  }

  async function changeRole() {
    const { member, roleId } = pendingChange;
    setPendingChange(null);
    setSaving(member.user_id);
    try {
      await updateMember(activeCompanyId, member.user_id, roleId, member.active);
      await Promise.all([
        client.invalidateQueries({ queryKey: ['members'] }),
        client.invalidateQueries({ queryKey: ['memberships'] }),
        client.invalidateQueries({ queryKey: ['permissions'] }),
      ]);
      notifySuccess('Rol actualizado', 'Los permisos de la persona se actualizaron.');
    } catch (error) {
      notifyError(error);
    } finally {
      setSaving(null);
    }
  }

  const initials = (member) => (member.display_name || member.email || '?').trim().slice(0, 2).toUpperCase();
  const term = search.trim().toLowerCase();
  const visible = members.filter((member) => (
    (!term || `${member.display_name ?? ''} ${member.email ?? ''}`.toLowerCase().includes(term))
    && (!roleFilter || member.role_id === roleFilter)
    && (!statusFilter || (statusFilter === 'active') === Boolean(member.active))
  ));
  const shown = visible.slice(0, limit);
  const suspended = members.filter((member) => !member.active).length;
  const reset = (setter) => (event) => { setter(event.target.value); setLimit(PAGE); };

  return (
    <div className="settings-page">
      <div className="page-head">
        <div>
          <span className="eyebrow">AJUSTES / EQUIPO</span>
          <h1>Usuarios</h1>
          <p>Las personas de tu empresa y el rol de cada una. El rol define qué pantallas ve y qué puede hacer.</p>
        </div>
      </div>
      {(membersQuery.error || rolesQuery.error) && (
        <p role="alert" className="error page-feedback">
          {friendlyError(membersQuery.error || rolesQuery.error)}
        </p>
      )}
      <section className="settings-card member-card">
        <div className="users-summary" aria-label="Resumen del equipo">
          <span className="chip"><UsersRound size={14} aria-hidden="true" /> {members.length} {members.length === 1 ? 'persona' : 'personas'}</span>
          <span className="chip">{members.length - suspended} activas</span>
          {suspended > 0 && <span className="chip warn">{suspended} suspendidas</span>}
        </div>
        <div className="users-toolbar">
          <label className="roles-search">
            <Search size={16} aria-hidden="true" />
            <span className="sr-only">Buscar persona</span>
            <input type="search" placeholder="Buscar por nombre o correo…" value={search} onChange={reset(setSearch)} />
          </label>
          {role === 'administrador' && (
            <select aria-label="Filtrar por rol" value={roleFilter} onChange={reset(setRoleFilter)}>
              <option value="">Todos los roles</option>
              {roles.map((entry) => <option key={entry.id} value={entry.id}>{entry.name}</option>)}
            </select>
          )}
          <select aria-label="Filtrar por estado" value={statusFilter} onChange={reset(setStatusFilter)}>
            <option value="">Cualquier estado</option>
            <option value="active">Activas</option>
            <option value="suspended">Suspendidas</option>
          </select>
        </div>
        {membersQuery.isPending && <p className="muted">Cargando usuarios…</p>}
        {!membersQuery.isPending && !membersQuery.error && !visible.length && (
          <p className="muted">{members.length ? 'Ninguna persona coincide con la búsqueda.' : 'Todavía no hay personas en el equipo.'}</p>
        )}
        <div className="member-list">
          {shown.map((member) => (
            <div className="member-row v2" key={member.user_id}>
              <span className="member-avatar" aria-hidden="true">{initials(member)}</span>
              <div className="member-identity">
                <strong>{member.display_name || member.email?.split('@')[0]}</strong>
                <small>{member.email}</small>
              </div>
              {role === 'administrador' ? (
                <label className="member-role-control">
                  <span className="sr-only">Rol de {member.display_name || member.email}</span>
                  <select value={member.role_id} disabled={saving === member.user_id || rolesQuery.isPending}
                    onChange={(event) => askChangeRole(member, event.target.value)}>
                    {roles.map((entry) => <option key={entry.id} value={entry.id}>{entry.name}</option>)}
                  </select>
                </label>
              ) : <span className="member-status">{member.role_name}</span>}
              <span className={`member-status ${member.active ? '' : 'inactive'}`}>
                {member.active ? 'Activo' : 'Suspendido'}
              </span>
            </div>
          ))}
        </div>
        {visible.length > shown.length && (
          <div className="users-more">
            <button type="button" className="button outline" onClick={() => setLimit(limit + PAGE)}>
              Mostrar más ({visible.length - shown.length} restantes)
            </button>
          </div>
        )}
      </section>
      <ConfirmDeleteDialog
        open={Boolean(pendingChange)}
        intent="primary"
        title="¿Cambiar el rol de esta persona?"
        description={pendingChange
          ? `${pendingChange.member.display_name || pendingChange.member.email} pasará a "${roles.find((entry) => entry.id === pendingChange.roleId)?.name ?? ''}". Sus permisos cambian de inmediato y queda registrado en el historial de accesos.`
          : ''}
        confirmLabel="Cambiar rol"
        onCancel={() => setPendingChange(null)}
        onConfirm={changeRole}
      />
    </div>
  );
}

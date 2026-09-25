import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Copy, MailPlus, UserRound, UsersRound } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog';
import { notifyError, notifySuccess } from '../../lib/notifications';
import {
  inviteMember,
  listInvitations,
  listMembers,
  listRoles,
  revokeInvitation,
  updateMember,
} from '../../services/administration';
import './settings.css';

export default function UsersPage() {
  const { activeCompanyId, can, user } = useAuth();
  const queryClient = useQueryClient();
  const [email, setEmail] = useState('');
  const [roleId, setRoleId] = useState('');
  const [link, setLink] = useState('');
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [changing, setChanging] = useState(null);
  const [revokeTarget, setRevokeTarget] = useState(null);

  const membersQuery = useQuery({
    queryKey: ['members', user?.id, activeCompanyId],
    queryFn: () => listMembers(activeCompanyId),
    enabled: Boolean(activeCompanyId),
  });

  const invitationsQuery = useQuery({
    queryKey: ['invitations', user?.id, activeCompanyId],
    queryFn: () => listInvitations(activeCompanyId),
    enabled: Boolean(activeCompanyId),
  });

  const rolesQuery = useQuery({
    queryKey: ['roles', user?.id, activeCompanyId],
    queryFn: () => listRoles(activeCompanyId),
    enabled: Boolean(activeCompanyId),
  });

  const roles = rolesQuery.data ?? [];
  const members = membersQuery.data ?? [];
  const invitations = invitationsQuery.data ?? [];

  const refresh = () => Promise.all([
    queryClient.invalidateQueries({ queryKey: ['members', user.id, activeCompanyId] }),
    queryClient.invalidateQueries({ queryKey: ['invitations', user.id, activeCompanyId] }),
    queryClient.invalidateQueries({ queryKey: ['memberships', user.id] }),
    queryClient.invalidateQueries({ queryKey: ['permissions', user.id, activeCompanyId] }),
  ]);

  const handleInvite = async (event) => {
    event.preventDefault();
    setBusy(true);
    setError('');
    setMessage('');
    setLink('');

    try {
      const token = await inviteMember(activeCompanyId, email.trim(), roleId);
      setLink(`${window.location.origin}/invite/${token}`);
      setEmail('');
      await refresh();
      setMessage('Invitación creada. Copiá el enlace ahora: se muestra una sola vez.');
      notifySuccess('Invitación creada', 'Copiá el enlace ahora: se muestra una sola vez.');
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
    }
  };

  const handleUpdate = async (member, nextRole, active) => {
    setChanging(member.user_id);
    setError('');
    setMessage('');
    try {
      await updateMember(activeCompanyId, member.user_id, nextRole, active);
      await refresh();
      setMessage('Acceso actualizado.');
      notifySuccess('Acceso actualizado', member.email);
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setChanging(null);
    }
  };

  const handleRevoke = async () => {
    if (!revokeTarget) return;
    setBusy(true);
    setError('');
    try {
      await revokeInvitation(activeCompanyId, revokeTarget.id);
      await refresh();
      notifySuccess('Invitación revocada', revokeTarget.email);
      setRevokeTarget(null);
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="settings-page">
      <div className="page-head">
        <div>
          <span className="eyebrow">CONFIGURACIÓN / EQUIPO</span>
          <h1>Usuarios</h1>
          <p>Administrá quién puede acceder a este espacio y con qué rol.</p>
        </div>
        <span className="date-pill">{members.length} USUARIOS</span>
      </div>

      {error && <p role="alert" className="error page-feedback">{error}</p>}
      {message && <p role="status" className="success page-feedback">{message}</p>}
      {(membersQuery.error || invitationsQuery.error || rolesQuery.error) && (
        <p role="alert" className="error page-feedback">
          {membersQuery.error?.message || invitationsQuery.error?.message || rolesQuery.error?.message}
        </p>
      )}

      {can('users', 'insert') && (
        <section className="settings-card invitation-card">
          <div className="settings-card-heading">
            <span className="role-icon"><MailPlus size={20} /></span>
            <div>
              <h2>Invitar a una persona</h2>
              <p>La invitación se envía compartiendo el enlace generado.</p>
            </div>
          </div>
          <form className="invite-form" onSubmit={handleInvite}>
            <label>
              Correo electrónico
              <input
                type="email"
                required
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                placeholder="persona@empresa.com"
              />
            </label>
            <label>
              Rol asignado
              <select
                required
                value={roleId}
                onChange={(event) => setRoleId(event.target.value)}
              >
                <option value="">Seleccionar rol</option>
                {roles.map((role) => (
                  <option value={role.id} key={role.id}>{role.name}</option>
                ))}
              </select>
            </label>
            <button className="button primary" disabled={busy || !roleId}>
              {busy ? 'Generando…' : 'Generar enlace'}
            </button>
          </form>
          {link && (
            <div className="generated-link">
              <input readOnly value={link} aria-label="Enlace de invitación" />
              <button
                className="button outline"
                onClick={async () => {
                  try {
                    await navigator.clipboard.writeText(link);
                    setMessage('Enlace copiado.');
                    notifySuccess('Enlace copiado');
                  } catch {
                    setError('No se pudo copiar automáticamente; seleccioná y copiá el enlace.');
                    notifyError(new Error('No se pudo copiar el enlace automáticamente.'));
                  }
                }}
              >
                <Copy size={16} /> Copiar
              </button>
            </div>
          )}
        </section>
      )}

      <section className="settings-card member-card">
        <div className="settings-card-heading">
          <span className="role-icon"><UsersRound size={20} /></span>
          <div>
            <h2>Equipo de la empresa</h2>
            <p>Los cambios de acceso pueden tardar hasta unos segundos en reflejarse en otra sesión.</p>
          </div>
        </div>
        {membersQuery.isPending ? <p>Cargando usuarios…</p> : (
          <div className="member-list">
            {members.map((member) => (
              <div className="member-row" key={member.user_id}>
                <span className="member-avatar"><UserRound size={19} /></span>
                <div className="member-identity">
                  <strong>{member.display_name || member.email?.split('@')[0]}</strong>
                  <small>{member.email}</small>
                </div>
                <span className={`member-status ${member.active ? '' : 'inactive'}`}>
                  {member.active ? 'Activo' : 'Suspendido'}
                </span>
                <select
                  aria-label={`Rol de ${member.email}`}
                  value={member.role_id}
                  disabled={!can('users', 'update') || changing === member.user_id}
                  onChange={(event) => handleUpdate(member, event.target.value, member.active)}
                >
                  {roles.map((role) => (
                    <option value={role.id} key={role.id}>{role.name}</option>
                  ))}
                </select>
                {can('users', 'update') && (
                  <button
                    className="button outline compact"
                    disabled={changing === member.user_id || member.user_id === user.id}
                    onClick={() => handleUpdate(member, member.role_id, !member.active)}
                  >
                    {member.active ? 'Suspender' : 'Activar'}
                  </button>
                )}
              </div>
            ))}
          </div>
        )}
      </section>

      <section className="settings-card member-card">
        <div className="settings-card-heading">
          <span className="role-icon"><MailPlus size={19} /></span>
          <div>
            <h2>Invitaciones</h2>
            <p>Los enlaces vencen a los siete días y se usan una sola vez.</p>
          </div>
        </div>
        {invitationsQuery.isPending ? <p>Cargando invitaciones…</p> : (
          <div className="member-list">
            {invitations.length === 0 && <p>No hay invitaciones todavía.</p>}
            {invitations.map((invitation) => {
              const pending = !invitation.used_at
                && !invitation.revoked_at
                && new Date(invitation.expires_at) > new Date();

              return (
                <div className="member-row" key={invitation.id}>
                  <span className="member-avatar"><MailPlus size={18} /></span>
                  <div className="member-identity">
                    <strong>{invitation.email}</strong>
                    <small>{invitation.role_name}</small>
                  </div>
                  <span className={`member-status ${pending ? '' : 'inactive'}`}>
                    {invitation.used_at ? 'Aceptada' : invitation.revoked_at
                      ? 'Revocada' : pending ? 'Pendiente' : 'Vencida'}
                  </span>
                  {pending && can('users', 'delete') && (
                    <button className="button outline compact" onClick={() => setRevokeTarget(invitation)}>
                      Revocar
                    </button>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </section>
      <ConfirmDeleteDialog
        open={Boolean(revokeTarget)}
        description={revokeTarget
          ? `Se revocará la invitación de ${revokeTarget.email}. El enlace dejará de funcionar.`
          : ''}
        confirmLabel="Revocar invitación"
        busy={busy}
        onCancel={() => setRevokeTarget(null)}
        onConfirm={handleRevoke}
      />
    </div>
  );
}

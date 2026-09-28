import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { ShieldCheck, Plus, Save } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import { listRoles, listRolePermissions, saveRole } from '../../services/administration';
import PermissionsGrid from './PermissionsGrid';
import './settings.css';

export default function RolesPage() {
  const { activeCompanyId, can, user } = useAuth();
  const queryClient = useQueryClient();
  const [selectedId, setSelectedId] = useState(null);
  const [name, setName] = useState('');
  const [code, setCode] = useState('');
  const [permissions, setPermissions] = useState([]);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const rolesQuery = useQuery({
    queryKey: ['roles', user?.id, activeCompanyId],
    queryFn: () => listRoles(activeCompanyId),
    enabled: Boolean(activeCompanyId),
  });

  const permissionsQuery = useQuery({
    queryKey: ['role-permissions', user?.id, activeCompanyId],
    queryFn: () => listRolePermissions(activeCompanyId),
    enabled: Boolean(activeCompanyId),
  });

  const roles = rolesQuery.data ?? [];
  const selected = roles.find((role) => role.id === selectedId);
  const adminSelected = selected?.code === 'admin';
  const canSave = can('roles', selected ? 'update' : 'insert') && !adminSelected;

  useEffect(() => {
    if (!selected) return;

    setName(selected.name);
    setCode(selected.code);
    setPermissions((permissionsQuery.data ?? [])
      .filter((permission) => permission.role_id === selected.id && permission.action !== 'manage')
      .map(({ resource, action }) => ({ resource, action })));
    setMessage('');
    setError('');
  }, [selected, permissionsQuery.data]);

  const startNew = () => {
    setSelectedId(null);
    setName('');
    setCode('');
    setPermissions([{ resource: 'dashboard', action: 'read' }]);
    setError('');
    setMessage('');
  };

  const handleSave = async (event) => {
    event.preventDefault();
    setError('');
    setMessage('');
    setBusy(true);

    try {
      const id = await saveRole(
        activeCompanyId,
        selected,
        name.trim(),
        code.trim().toLowerCase(),
        permissions,
      );
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['roles', user.id, activeCompanyId] }),
        queryClient.invalidateQueries({ queryKey: ['role-permissions', user.id, activeCompanyId] }),
        queryClient.invalidateQueries({ queryKey: ['permissions', user.id, activeCompanyId] }),
      ]);
      if (id) setSelectedId(id);
      setMessage('Rol guardado correctamente.');
      notifySuccess(selected ? 'Rol actualizado' : 'Rol creado', name.trim());
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
          <span className="eyebrow">CONFIGURACIÓN / ACCESOS</span>
          <h1>Roles y permisos</h1>
          <p>Definí qué puede ver y hacer cada equipo dentro de la empresa.</p>
        </div>
        {can('roles', 'insert') && (
          <button className="button primary" onClick={startNew}>
            <Plus size={17} /> Nuevo rol
          </button>
        )}
      </div>

      {(rolesQuery.error || permissionsQuery.error) && (
        <p role="alert" className="error">
          {(rolesQuery.error && friendlyError(rolesQuery.error)) || (permissionsQuery.error && friendlyError(permissionsQuery.error))}
        </p>
      )}

      <div className="settings-columns">
        <section className="settings-card role-list">
          <span className="eyebrow">ROLES DISPONIBLES</span>
          {rolesQuery.isPending && <p>Cargando roles…</p>}
          {roles.map((role) => (
            <button
              key={role.id}
              className={`role-option ${selectedId === role.id ? 'selected' : ''}`}
              onClick={() => setSelectedId(role.id)}
            >
              <span className="role-icon"><ShieldCheck size={19} /></span>
              <span><strong>{role.name}</strong><small>{role.code}</small></span>
            </button>
          ))}
        </section>

        <form className="settings-card role-editor" onSubmit={handleSave}>
          <span className="eyebrow">
            {selected ? 'EDITAR ROL' : 'CONFIGURAR NUEVO ROL'}
          </span>
          {adminSelected && (
            <p className="callout">El rol administrador está protegido y conserva todos los permisos.</p>
          )}
          <div className="form-row">
            <label>
              Nombre del rol
              <input
                required
                maxLength={60}
                disabled={!canSave}
                value={name}
                onChange={(event) => setName(event.target.value)}
                placeholder="Ej.: Responsable de depósito"
              />
            </label>
            <label>
              Código interno
              <input
                required
                pattern="[a-z][a-z0-9_]{1,39}"
                disabled={!canSave || Boolean(selected)}
                value={code}
                onChange={(event) => setCode(event.target.value.toLowerCase())}
                placeholder="ej: deposito"
              />
            </label>
          </div>
          <div className="editor-title">
            <h2>Permisos del módulo</h2>
            <p>Los cambios se aplican a todos los usuarios con este rol.</p>
          </div>
          <PermissionsGrid
            permissions={permissions}
            onChange={setPermissions}
            disabled={!canSave}
          />
          {error && <p role="alert" className="error">{error}</p>}
          {message && <p role="status" className="success">{message}</p>}
          {canSave && (
            <button className="button primary save-button" disabled={busy}>
              <Save size={17} /> {busy ? 'Guardando…' : 'Guardar rol'}
            </button>
          )}
        </form>
      </div>
    </div>
  );
}

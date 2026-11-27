import { useEffect, useMemo, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Eye, Lock, Plus, RotateCcw, Save, Search, ShieldCheck, Users } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import {
  listMembers, listRoles, listRolePermissions, listPermissionCatalog, saveRole,
} from '../../services/administration';
import PermissionsGrid from './PermissionsGrid';
import AccessHistory from './AccessHistory';
import { ROLE_TEMPLATES, applyTemplate } from './roleTemplates';
import './settings.css';

// Clave estable de una lista de permisos, para saber si hay cambios sin guardar.
const keyOf = (list) => [...list].map((p) => `${p.resource}:${p.action}`).sort().join('|');

export default function RolesPage() {
  const { activeCompanyId, role: myRole, user, startViewAs } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [selectedId, setSelectedId] = useState(null);
  const [name, setName] = useState('');
  const [code, setCode] = useState('');
  const [permissions, setPermissions] = useState([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [search, setSearch] = useState('');
  const [baseline, setBaseline] = useState({ name: '', permissions: '' });

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
  const membersQuery = useQuery({
    queryKey: ['members', user?.id, activeCompanyId],
    queryFn: () => listMembers(activeCompanyId),
    enabled: Boolean(activeCompanyId && myRole === 'admin'),
  });
  const catalogQuery = useQuery({
    queryKey: ['permission-catalog', user?.id],
    queryFn: listPermissionCatalog,
    staleTime: 5 * 60_000,
  });

  const catalog = catalogQuery.data ?? [];
  // Los permisos de módulo completo los deriva el servidor: la pantalla solo maneja pantallas.
  const groups = useMemo(
    () => new Set(catalog.filter((entry) => entry.is_group || entry.admin_only).map((entry) => entry.resource)),
    [catalog],
  );
  // "Gestionar" solo se conserva en las pantallas cuyo catálogo lo declara.
  const manageable = useMemo(
    () => new Set(catalog.filter((entry) => (entry.actions ?? []).includes('manage')).map((entry) => entry.resource)),
    [catalog],
  );

  const roles = rolesQuery.data ?? [];
  const memberCount = useMemo(() => {
    const map = new Map();
    (membersQuery.data ?? []).forEach((member) => map.set(member.role_id, (map.get(member.role_id) ?? 0) + 1));
    return map;
  }, [membersQuery.data]);
  const selected = roles.find((role) => role.id === selectedId);
  const adminSelected = selected?.code === 'admin';
  // Solo el administrador gestiona roles (migración 044); el servidor lo exige igual.
  const canSave = myRole === 'admin' && !adminSelected;
  const editing = Boolean(selected) || selectedId === 'new';

  const visibleRoles = useMemo(() => {
    const term = search.trim().toLowerCase();
    return roles.filter((role) => !term || `${role.name} ${role.code}`.toLowerCase().includes(term));
  }, [roles, search]);

  useEffect(() => {
    if (!selected) return;
    const loaded = (permissionsQuery.data ?? [])
      .filter((permission) => permission.role_id === selected.id
        && (permission.action !== 'manage' || manageable.has(permission.resource))
        && !groups.has(permission.resource))
      .map(({ resource, action }) => ({ resource, action }));
    setName(selected.name);
    setCode(selected.code);
    setPermissions(loaded);
    setBaseline({ name: selected.name, permissions: keyOf(loaded) });
    setError('');
  }, [selected, permissionsQuery.data, catalog]);

  const dirty = editing && (name.trim() !== baseline.name || keyOf(permissions) !== baseline.permissions);

  const choose = (id) => {
    if (id === selectedId) return;
    if (dirty && !window.confirm('Tenés cambios sin guardar en este rol. ¿Descartarlos?')) return;
    setSelectedId(id);
    setError('');
    if (id === 'new') startNew();
  };

  function startNew() {
    const initial = [{ resource: 'dashboard', actions: ['read'] }];
    const list = initial.flatMap(({ resource, actions }) => actions.map((action) => ({ resource, action })));
    setSelectedId('new');
    setName('');
    setCode('');
    setPermissions(list);
    setBaseline({ name: '', permissions: keyOf(list) });
    setError('');
  }

  const discard = () => {
    if (selected) {
      const loaded = (permissionsQuery.data ?? [])
        .filter((permission) => permission.role_id === selected.id
          && (permission.action !== 'manage' || manageable.has(permission.resource))
          && !groups.has(permission.resource))
        .map(({ resource, action }) => ({ resource, action }));
      setName(selected.name);
      setPermissions(loaded);
    } else {
      startNew();
    }
    setError('');
  };

  const useTemplate = (id) => {
    const template = ROLE_TEMPLATES.find((entry) => entry.id === id);
    if (!template) return;
    if (permissions.length > 1 && !window.confirm(`Se reemplazan los permisos marcados por los de "${template.label}". ¿Continuar?`)) return;
    setPermissions(applyTemplate(template, catalog));
    if (!name.trim() && selectedId === 'new') setName(template.label);
  };

  const handleSave = async (event) => {
    event.preventDefault();
    if (busy) return;
    setError('');
    setBusy(true);
    try {
      const id = await saveRole(
        activeCompanyId,
        selected ?? null,
        name.trim(),
        (selected ? selected.code : code).trim().toLowerCase(),
        permissions,
      );
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['roles', user.id, activeCompanyId] }),
        queryClient.invalidateQueries({ queryKey: ['role-permissions', user.id, activeCompanyId] }),
        queryClient.invalidateQueries({ queryKey: ['permissions', user.id, activeCompanyId] }),
      ]);
      if (id) setSelectedId(id);
      setBaseline({ name: name.trim(), permissions: keyOf(permissions) });
      notifySuccess(selected ? 'Rol actualizado' : 'Rol creado', name.trim());
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
    }
  };

  const permissionCount = permissions.filter((p) => p.action === 'read' && !groups.has(p.resource)).length;
  const people = selected ? memberCount.get(selected.id) ?? 0 : 0;

  return (
    <div className="settings-page roles-page">
      <div className="page-head">
        <div>
          <span className="eyebrow">AJUSTES / ACCESOS</span>
          <h1>Roles y permisos</h1>
          <p>Elegí un rol para ver o cambiar qué pantallas y acciones tiene su equipo.</p>
        </div>
        {myRole === 'admin' && (
          <button type="button" className="button primary" onClick={() => choose('new')}>
            <Plus size={17} aria-hidden="true" /> Nuevo rol
          </button>
        )}
      </div>

      {(rolesQuery.error || permissionsQuery.error) && (
        <p role="alert" className="error">
          {friendlyError(rolesQuery.error || permissionsQuery.error)}
        </p>
      )}

      <div className="roles-layout">
        <aside className="settings-card roles-list" aria-label="Roles de la empresa">
          <label className="roles-search">
            <Search size={16} aria-hidden="true" />
            <span className="sr-only">Buscar rol</span>
            <input type="search" placeholder="Buscar rol…" value={search} onChange={(event) => setSearch(event.target.value)} />
          </label>
          {rolesQuery.isPending && <p className="muted">Cargando roles…</p>}
          <ul>
            {visibleRoles.map((role) => (
              <li key={role.id}>
                <button
                  type="button"
                  className={`role-card ${selectedId === role.id ? 'selected' : ''}`}
                  aria-pressed={selectedId === role.id}
                  onClick={() => choose(role.id)}
                >
                  <span className="role-icon">{role.code === 'admin' ? <Lock size={17} aria-hidden="true" /> : <ShieldCheck size={17} aria-hidden="true" />}</span>
                  <span className="role-card-text">
                    <strong>{role.name}</strong>
                    <small>
                      {role.code === 'admin' ? 'Acceso total · protegido' : 'Personalizado'}
                      {membersQuery.data ? ` · ${memberCount.get(role.id) ?? 0} ${(memberCount.get(role.id) ?? 0) === 1 ? 'persona' : 'personas'}` : ''}
                    </small>
                  </span>
                </button>
              </li>
            ))}
          </ul>
          {!rolesQuery.isPending && !visibleRoles.length && <p className="muted">No hay roles que coincidan.</p>}
        </aside>

        <form className="roles-editor" onSubmit={handleSave}>
          {!editing && (
            <div className="settings-card roles-empty">
              <ShieldCheck size={30} aria-hidden="true" />
              <h2>Elegí un rol de la lista</h2>
              <p>Vas a ver qué puede hacer y vas a poder cambiarlo. Para crear uno nuevo, usá “Nuevo rol”; podés empezar desde una plantilla.</p>
            </div>
          )}

          {editing && (
            <>
              <section className="settings-card roles-head">
                <div className="roles-head-top">
                  <div>
                    <span className="eyebrow">{selected ? 'EDITAR ROL' : 'NUEVO ROL'}</span>
                    <h2>{selected ? selected.name : (name.trim() || 'Rol sin nombre')}</h2>
                    {selected && (
                      <p className="muted">
                        <Users size={14} aria-hidden="true" /> {people} {people === 1 ? 'persona tiene' : 'personas tienen'} este rol · {permissionCount} pantallas con acceso
                      </p>
                    )}
                  </div>
                  {selected && !adminSelected && myRole === 'admin' && (
                    <button type="button" className="button outline" onClick={() => { startViewAs(selected); navigate('/'); }}>
                      <Eye size={16} aria-hidden="true" /> Ver cómo lo ve este rol
                    </button>
                  )}
                </div>
                {adminSelected && <p className="callout">El rol administrador está protegido: conserva todos los permisos y no se puede editar.</p>}
                <div className="form-row">
                  <label>
                    Nombre del rol
                    <input required maxLength={60} disabled={!canSave} value={name}
                      onChange={(event) => setName(event.target.value)} placeholder="Ej.: Responsable de depósito" />
                  </label>
                  {!selected && (
                    <label>
                      Código interno
                      <input required pattern="[a-z][a-z0-9_]{1,39}" disabled={!canSave} value={code}
                        onChange={(event) => setCode(event.target.value.toLowerCase())} placeholder="ej: deposito" />
                      <small className="muted">Solo letras minúsculas, números y guion bajo. No se puede cambiar después.</small>
                    </label>
                  )}
                  {canSave && (
                    <label>
                      Empezar desde una plantilla
                      <select value="" onChange={(event) => useTemplate(event.target.value)}>
                        <option value="">Elegir plantilla…</option>
                        {ROLE_TEMPLATES.map((template) => <option key={template.id} value={template.id}>{template.label}</option>)}
                      </select>
                      <small className="muted">Solo marca casillas; revisalas antes de guardar.</small>
                    </label>
                  )}
                </div>
              </section>

              <section className="roles-perms" aria-label="Permisos del rol">
                <div className="editor-title">
                  <h2>Qué puede hacer este rol</h2>
                  <p>Para cada módulo, elegí si puede entrar, a qué pantallas y con qué acciones. Los cambios se aplican a todos los que tengan este rol.</p>
                </div>
                <PermissionsGrid permissions={permissions} onChange={setPermissions} disabled={!canSave} catalog={catalog} />
              </section>

              {error && <p role="alert" className="error">{error}</p>}

              {canSave && (
                <div className={`roles-savebar ${dirty ? 'is-dirty' : ''}`} role="region" aria-label="Guardar cambios">
                  <span>{dirty ? 'Tenés cambios sin guardar.' : 'Sin cambios pendientes.'}</span>
                  <div>
                    <button type="button" className="button outline" disabled={!dirty || busy} onClick={discard}>
                      <RotateCcw size={16} aria-hidden="true" /> Descartar
                    </button>
                    <button className="button primary" disabled={busy || !dirty || !name.trim() || (!selected && !code.trim())}>
                      <Save size={16} aria-hidden="true" /> {busy ? 'Guardando…' : selected ? 'Guardar cambios' : 'Crear rol'}
                    </button>
                  </div>
                </div>
              )}
            </>
          )}
        </form>
      </div>
      {myRole === 'admin' && <AccessHistory />}
    </div>
  );
}

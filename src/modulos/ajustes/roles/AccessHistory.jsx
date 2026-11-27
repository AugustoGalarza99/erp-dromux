import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { History } from 'lucide-react';
import { useAuth } from '../../../compartido/contextos/AuthContext';
import { friendlyError } from '../../../compartido/utilidades/notifications';
import { listAccessAudit } from '../compartido/administration';
import { AUDITORIA_ETIQUETA } from '../../../compartido/valores';

const PAGE_SIZE = 25;

const missingMigration = (error) =>
  /Could not find the function|PGRST202|42883/i.test(`${error?.code ?? ''} ${error?.message ?? ''}`);

/* Texto corto de lo que cambió, para personas. */
function summary(row) {
  const d = row.detail ?? {};
  if (row.action === 'rol_creado') {
    return `Rol “${d.name}” con ${(d.permissions ?? []).length} permisos`;
  }
  if (row.action === 'rol_editado') {
    const parts = [];
    if (d.name_before !== d.name_after) parts.push(`nombre: ${d.name_before} → ${d.name_after}`);
    if (d.added?.length) parts.push(`agregó ${d.added.length} permiso(s)`);
    if (d.removed?.length) parts.push(`quitó ${d.removed.length} permiso(s)`);
    return parts.join(' · ') || 'Sin cambios de permisos';
  }
  const before = d.before ?? {};
  const after = d.after ?? {};
  const parts = [];
  if (before.role !== after.role) parts.push(`rol: ${before.role} → ${after.role}`);
  if (before.active !== after.active) parts.push(after.active ? 'reactivado' : 'suspendido');
  return parts.join(' · ') || 'Sin cambios';
}

/* Quién cambió qué y cuándo. Paginado en el servidor. Solo lo ve el administrador. */
export default function AccessHistory() {
  const { activeCompanyId, user } = useAuth();
  const [page, setPage] = useState(0);
  const query = useQuery({
    queryKey: ['access-audit', user?.id, activeCompanyId, page],
    queryFn: () => listAccessAudit(activeCompanyId, page),
    enabled: Boolean(activeCompanyId),
    placeholderData: (old) => old,
  });
  const rows = query.data?.rows ?? [];
  const count = query.data?.count ?? 0;
  const pages = Math.max(1, Math.ceil(count / PAGE_SIZE));

  return (
    <section className="settings-card access-history" aria-labelledby="access-history-title">
      <span className="eyebrow"><History size={14} aria-hidden="true" /> HISTORIAL DE ACCESOS</span>
      <h2 id="access-history-title">Quién cambió roles, permisos y usuarios</h2>
      <p>Cada cambio queda registrado y no se puede borrar. Solo lo ve el administrador.</p>
      {query.isError && (
        <p role="alert" className="error">
          {missingMigration(query.error)
            ? 'El historial necesita la migración 044 en la base.'
            : friendlyError(query.error)}
        </p>
      )}
      {query.isSuccess && !rows.length && <p>Todavía no hay cambios registrados.</p>}
      {rows.length > 0 && (
        <div className="mod-table-wrap">
          <table className="mod-table">
            <thead>
              <tr>
                <th scope="col">Fecha</th>
                <th scope="col">Quién</th>
                <th scope="col">Qué hizo</th>
                <th scope="col">Detalle</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row, index) => (
                <tr key={`${row.created_at}-${index}`}>
                  <td data-label="Fecha">{new Date(row.created_at).toLocaleString('es-AR')}</td>
                  <td data-label="Quién">{row.actor_email ?? 'Usuario'}</td>
                  <td data-label="Qué hizo">
                    {AUDITORIA_ETIQUETA[row.action] ?? row.action}
                    {row.target_email ? ` · ${row.target_email}` : ''}
                    {!row.target_email && row.target_role_name ? ` · ${row.target_role_name}` : ''}
                  </td>
                  <td data-label="Detalle">{summary(row)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {count > PAGE_SIZE && (
        <nav className="mod-pager" aria-label="Paginación del historial">
          <span className="mod-pager-count">
            {page * PAGE_SIZE + 1}–{Math.min(count, (page + 1) * PAGE_SIZE)} de {count} cambios
          </span>
          <div className="mod-pager-buttons">
            <button type="button" aria-label="Página anterior" disabled={page === 0}
              onClick={() => setPage(page - 1)}>‹</button>
            <span aria-live="polite">Página {page + 1} de {pages}</span>
            <button type="button" aria-label="Página siguiente" disabled={page + 1 >= pages}
              onClick={() => setPage(page + 1)}>›</button>
          </div>
        </nav>
      )}
    </section>
  );
}

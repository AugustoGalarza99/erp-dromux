import { useEffect, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { ArchiveRestore, ChevronLeft, ChevronRight, Search } from "lucide-react";
import { useAuth } from "../../contexts/AuthContext";
import { useDebouncedValue } from "../../hooks/useDebouncedValue";
import {
  archivedRecords,
  cleanupResources,
  restoreArchived,
  refreshCleanupData,
} from "../../services/cleanup";
import { notifyError, notifySuccess, friendlyError } from "../../lib/notifications";
import ConfirmDeleteDialog from "../../components/ConfirmDeleteDialog";
import "./settings.css";

const PAGE_SIZE = 25;

export default function ArchivesPage() {
  const { activeCompanyId, user, can } = useAuth();
  const client = useQueryClient();
  const [params, setParams] = useSearchParams();
  const options = cleanupResources.filter((entry) => can(entry.permission, "read"));
  const resource = options.find((entry) => entry.value === params.get("type")) ?? options[0];
  const [search, setSearch] = useState("");
  const term = useDebouncedValue(search);
  const [page, setPage] = useState(0);
  const [target, setTarget] = useState(null);
  const [busy, setBusy] = useState(false);

  const query = useQuery({
    queryKey: ["archived-records", user?.id, activeCompanyId, resource?.value, term, page],
    queryFn: () => archivedRecords(activeCompanyId, resource.value, term, page),
    enabled: Boolean(activeCompanyId && resource),
  });
  const rows = query.data?.rows ?? [];
  const count = query.data?.count ?? 0;

  useEffect(() => {
    setPage(0);
    setTarget(null);
  }, [activeCompanyId, resource?.value, term]);
  useEffect(() => {
    if (query.isSuccess && page > 0 && page * PAGE_SIZE >= count) {
      setPage(Math.max(0, Math.ceil(count / PAGE_SIZE) - 1));
    }
  }, [query.isSuccess, count, page]);

  async function restore() {
    if (busy || !target) return;
    setBusy(true);
    try {
      await restoreArchived(activeCompanyId, resource.value, target.id);
      setTarget(null);
      await refreshCleanupData(client);
      notifySuccess("Registro recuperado", target.label);
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  const canRestore = resource && can(resource.permission, "delete");

  return (
    <div className="settings-page">
      <header className="page-head">
        <div>
          <span className="eyebrow">AJUSTES / HISTORIAL</span>
          <h1>Archivados</h1>
          <p>Registros que se retiraron de las listas. Recuperarlos conserva sus datos y sus vínculos.</p>
        </div>
      </header>

      {!resource ? (
        <section className="settings-card empty-card">
          <h2>No tenés acceso a los archivados</h2>
          <p className="muted">Pedile al administrador que habilite los módulos cuyos registros querés recuperar.</p>
        </section>
      ) : (
        <section className="settings-card">
          <div className="users-toolbar">
            <label className="field-inline">
              <span className="sr-only">Tipo de registro</span>
              <select aria-label="Tipo de registro" value={resource.value}
                onChange={(event) => setParams({ type: event.target.value })}>
                {options.map((entry) => <option key={entry.value} value={entry.value}>{entry.label}</option>)}
              </select>
            </label>
            <label className="roles-search">
              <Search size={16} aria-hidden="true" />
              <span className="sr-only">Buscar archivado</span>
              <input type="search" maxLength={100} value={search} placeholder="Buscar por nombre o número…"
                onChange={(event) => setSearch(event.target.value)} />
            </label>
          </div>

          {query.error && <p className="error" role="alert">{friendlyError(query.error)}</p>}
          {query.isFetching && !rows.length && <p className="muted">Cargando archivados…</p>}
          {query.isSuccess && !rows.length && (
            <p className="muted">No hay registros archivados de este tipo{term ? " con esa búsqueda" : ""}.</p>
          )}

          <ul className="archive-list">
            {rows.map((row) => (
              <li className="archive-row" key={row.id}>
                <div>
                  <strong>{row.label}</strong>
                  {row.created_at && (
                    <small>Registrado el {new Date(row.created_at).toLocaleDateString("es-AR")}</small>
                  )}
                </div>
                {canRestore && (
                  <button type="button" className="button outline" onClick={() => setTarget(row)}>
                    <ArchiveRestore size={16} aria-hidden="true" /> Recuperar
                  </button>
                )}
              </li>
            ))}
          </ul>

          {count > PAGE_SIZE && (
            <nav className="pager" aria-label="Paginación">
              <button type="button" className="button outline" disabled={!page} onClick={() => setPage(page - 1)}>
                <ChevronLeft size={16} aria-hidden="true" /> Anterior
              </button>
              <span>Página {page + 1} de {Math.ceil(count / PAGE_SIZE)} · {count} registros</span>
              <button type="button" className="button outline" disabled={(page + 1) * PAGE_SIZE >= count}
                onClick={() => setPage(page + 1)}>
                Siguiente <ChevronRight size={16} aria-hidden="true" />
              </button>
            </nav>
          )}
        </section>
      )}

      {target && (
        <ConfirmDeleteDialog
          open
          busy={busy}
          title="¿Recuperar este registro?"
          description={`${target.label}. Volverá al listado conservando sus datos y su estado anterior.`}
          confirmLabel="Recuperar"
          intent="primary"
          onCancel={() => setTarget(null)}
          onConfirm={restore}
        />
      )}
    </div>
  );
}

import { useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useAuth } from "../../contexts/AuthContext";
import { useDebouncedValue } from "../../hooks/useDebouncedValue";
import {
  archivedRecords,
  cleanupResources,
  restoreArchived,
  refreshCleanupData,
} from "../../services/cleanup";
import {
  notifyError,
  notifySuccess,
  friendlyError,
} from "../../lib/notifications";
import ConfirmDeleteDialog from "../../components/ConfirmDeleteDialog";
import "../purchases/supplierAccounts.css";

export default function ArchivesPage() {
  const { activeCompanyId, user, can } = useAuth();
  const client = useQueryClient();
  const [params, setParams] = useSearchParams();
  const options = cleanupResources.filter((entry) =>
    can(entry.permission, "read"),
  );
  const resource =
    options.find((entry) => entry.value === params.get("type")) ?? options[0];
  const [search, setSearch] = useState("");
  const term = useDebouncedValue(search);
  const [page, setPage] = useState(0);
  const [target, setTarget] = useState(null);
  const [busy, setBusy] = useState(false);
  const query = useQuery({
    queryKey: [
      "archived-records",
      user?.id,
      activeCompanyId,
      resource?.value,
      term,
      page,
    ],
    queryFn: () => archivedRecords(activeCompanyId, resource.value, term, page),
    enabled: Boolean(activeCompanyId && resource),
  });
  useEffect(() => {
    setPage(0);
    setTarget(null);
  }, [activeCompanyId, resource?.value, term]);
  useEffect(() => {
    if (query.isSuccess && page > 0 && page * 25 >= query.data.count) {
      setPage(Math.max(0, Math.ceil(query.data.count / 25) - 1));
    }
  }, [query.isSuccess, query.data?.count, page]);
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
  return (
    <section className="supplier-finance-page">
      <header className="page-head">
        <div>
          <span className="eyebrow">HISTORIAL</span>
          <h1>Archivados</h1>
          <p>
            Registros retirados de las listas. Recuperarlos conserva su
            identidad y sus vínculos.
          </p>
        </div>
        <Link className="button outline" to="/">
          Volver al inicio
        </Link>
      </header>
      {resource ? (
        <>
          <div className="supplier-finance-filters">
            <label>
              Tipo de registro
              <select
                value={resource.value}
                onChange={(event) => setParams({ type: event.target.value })}
              >
                {options.map((entry) => (
                  <option key={entry.value} value={entry.value}>
                    {entry.label}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Buscar
              <input
                type="search"
                maxLength={100}
                value={search}
                placeholder="Nombre o número"
                onChange={(event) => setSearch(event.target.value)}
              />
            </label>
          </div>
          {query.error && (
            <p className="error" role="alert">
              {friendlyError(query.error)}
            </p>
          )}
          {query.isFetching && <p>Cargando archivos…</p>}
          {query.isSuccess && !query.data.rows.length && (
            <p>No hay registros archivados para este filtro.</p>
          )}
          {(query.data?.rows ?? []).map((row) => (
            <article key={row.id} className="supplier-finance-card">
              <h2>{row.label}</h2>
              {row.created_at && (
                <p>
                  Fecha del registro:{" "}
                  {new Date(row.created_at).toLocaleDateString("es-AR")}
                </p>
              )}
              {can(resource.permission, "delete") && (
                <button
                  type="button"
                  className="button outline"
                  onClick={() => setTarget(row)}
                >
                  Recuperar registro
                </button>
              )}
            </article>
          ))}
          <div className="supplier-finance-pagination">
            <button
              className="button outline"
              disabled={!page}
              onClick={() => setPage(page - 1)}
            >
              Anterior
            </button>
            <span>
              Página {page + 1} · {query.data?.count ?? 0} registros
            </span>
            <button
              className="button outline"
              disabled={(page + 1) * 25 >= (query.data?.count ?? 0)}
              onClick={() => setPage(page + 1)}
            >
              Siguiente
            </button>
          </div>
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
        </>
      ) : (
        <p>No tenés acceso a los archivos de estos módulos.</p>
      )}
    </section>
  );
}

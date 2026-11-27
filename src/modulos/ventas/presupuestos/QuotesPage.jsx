import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useSearchParams } from "react-router-dom";
import { Building2, ChevronLeft, ChevronRight, FileDown, FilePlus2, Search } from "lucide-react";
import ConfirmDeleteDialog from "../../../compartido/componentes/ConfirmDeleteDialog";
import { useAuth } from "../../../compartido/contextos/AuthContext";
import { useDebouncedValue } from "../../../compartido/hooks/useDebouncedValue";
import { hasInternalId } from "../../../compartido/utilidades/display";
import { friendlyError, notifyError, notifySuccess } from "../../../compartido/utilidades/notifications";
import { isMissingFunction } from "../compartido/pricing";
import { getCompanyProfile, getQuote, listQuotes, setQuoteStatus } from "./quotes";
import CompanyProfileDialog from "./CompanyProfileDialog";
import QuoteEditor from "./QuoteEditor";
import SalesShell from "../compartido/SalesShell";

const money = (value) => Number(value ?? 0).toLocaleString("es-AR", { style: "currency", currency: "ARS" });
const dateOnly = (iso) => {
  const [y, m, d] = String(iso).slice(0, 10).split("-");
  return `${d}/${m}/${y}`;
};
const dateTime = (iso) => new Date(iso).toLocaleDateString("es-AR", { timeZone: "America/Argentina/Buenos_Aires" });
const label = { abierto: "Abierto", vencido: "Vencido", aceptado: "Aceptado", rechazado: "Rechazado", cancelado: "Cancelado" };
const chipClass = { abierto: "", vencido: "is-warn", aceptado: "is-ok", rechazado: "is-bad", cancelado: "" };
const FILTERS = [
  ["all", "Todos"], ["abierto", "Abiertos"], ["vencido", "Vencidos"], ["aceptado", "Aceptados"], ["rechazado", "Rechazados"], ["cancelado", "Cancelados"],
];
const SIZE = 25;
/* Si el perfil del autor guarda un identificador interno en lugar de un nombre, no se muestra. */
const authorOf = (label) => (!label || hasInternalId(label) ? "Usuario" : label);

async function printQuote(companyId, quoteId, profile) {
  const [detail, company, pdf] = await Promise.all([
    getQuote(companyId, quoteId),
    profile ?? getCompanyProfile(companyId),
    import("./quotePdf"), // se carga recién al imprimir: no pesa en el resto de la aplicación
  ]);
  pdf.downloadQuotePdf(detail, company);
}

/* Presupuestos: lista paginada, estados y PDF para enviar al cliente. */
export default function QuotesPage() {
  const { activeCompanyId, user, can, role } = useAuth();
  const client = useQueryClient();
  const [params, setParams] = useSearchParams();
  const scope = [user?.id, activeCompanyId];
  const isAdmin = role === "administrador" && can("ventas", "editar");
  const [search, setSearch] = useState("");
  const term = useDebouncedValue(search);
  const [status, setStatus] = useState("all");
  const [page, setPage] = useState(0);
  const [busyId, setBusyId] = useState("");
  const [confirm, setConfirm] = useState(null);
  const [profileOpen, setProfileOpen] = useState(false);
  const editing = params.get("new") === "1";

  useEffect(() => { setPage(0); }, [term, status, activeCompanyId]);
  const query = useQuery({
    queryKey: ["quotes", ...scope, term, status, page],
    queryFn: () => listQuotes(activeCompanyId, { search: term, status, page, size: SIZE }),
    enabled: Boolean(activeCompanyId) && !editing,
    retry: false,
    placeholderData: (previous) => previous,
  });
  const profile = useQuery({
    queryKey: ["company-profile", ...scope],
    queryFn: () => getCompanyProfile(activeCompanyId),
    enabled: Boolean(activeCompanyId) && can("ventas", "ver"),
    retry: false, staleTime: 60_000,
  });
  const rows = query.data ?? [];
  const total = Number(rows[0]?.total_count ?? 0);
  const pages = Math.max(1, Math.ceil(total / SIZE));
  const refresh = () => client.invalidateQueries({ queryKey: ["quotes", ...scope] });
  const setEditing = (value) => {
    const next = new URLSearchParams(params);
    if (value) next.set("new", "1"); else next.delete("new");
    setParams(next, { replace: true });
  };

  async function print(id) {
    setBusyId(id);
    try {
      await printQuote(activeCompanyId, id, profile.data);
    } catch (error) {
      notifyError(error);
    } finally {
      setBusyId("");
    }
  }

  async function changeStatus() {
    const { row, next } = confirm;
    setBusyId(row.id);
    try {
      await setQuoteStatus(activeCompanyId, row.id, next);
      notifySuccess(`Presupuesto ${label[next].toLowerCase()}`, `Nº ${String(row.number).padStart(5, "0")} · ${row.customer_name}`);
      await refresh();
    } catch (error) {
      notifyError(error);
    } finally {
      setBusyId("");
      setConfirm(null);
    }
  }

  if (isMissingFunction(query.error)) {
    return (
      <SalesShell title="Presupuestos" description="Presupuestos para tus clientes en PDF.">
        <p className="mod-hint" role="note">Los presupuestos todavía no están activos en este entorno.</p>
      </SalesShell>
    );
  }

  return (
    <SalesShell
      title="Presupuestos"
      description="Armá un presupuesto con la lista de precios del cliente y descargalo en PDF para enviárselo."
      actions={(
        <>
          {isAdmin && (
            <button type="button" className="button outline" onClick={() => setProfileOpen(true)}>
              <Building2 size={16} aria-hidden="true" /> Datos de la empresa
            </button>
          )}
          {can("ventas", "crear") && !editing && (
            <button type="button" className="button primary" onClick={() => setEditing(true)}>
              <FilePlus2 size={16} aria-hidden="true" /> Nuevo presupuesto
            </button>
          )}
        </>
      )}
    >
      {editing ? (
        <QuoteEditor
          onCancel={() => setEditing(false)}
          onCreated={async (detail, company) => {
            await refresh();
            setEditing(false);
            try {
              const pdf = await import("./quotePdf");
              pdf.downloadQuotePdf(detail, company);
            } catch (error) {
              notifyError(error);
            }
          }}
        />
      ) : (
        <section className="mod-card pl-card" aria-label="Presupuestos">
          {profile.isSuccess && !profile.data?.tax_id && !profile.data?.address && (
            <p className="mod-hint" role="note">
              Completá los datos de la empresa (CUIT, domicilio, teléfono y logo) para que el PDF salga con el membrete completo.
              {!isAdmin && " Pedíselo a la administración."}
            </p>
          )}
          <div className="mod-filters">
            <label className="mod-filter-grow">Buscar presupuesto
              <span className="pl-search"><Search size={17} aria-hidden="true" />
                <input aria-label="Buscar presupuesto" placeholder="Número, cliente o CUIT" value={search} onChange={(event) => setSearch(event.target.value)} />
              </span>
            </label>
          </div>
          <div className="mod-segments" role="group" aria-label="Filtrar por estado">
            {FILTERS.map(([key, text]) => (
              <button key={key} type="button" className="mod-segment" aria-pressed={status === key} onClick={() => setStatus(key)}>{text}</button>
            ))}
          </div>
          {query.error && <p role="alert" className="error">{friendlyError(query.error)}</p>}
          {query.isPending && <p className="mod-muted">Cargando presupuestos…</p>}
          {!query.isPending && !rows.length && !query.error && (
            <p className="mod-muted">{term || status !== "all" ? "No hay presupuestos para esa búsqueda." : "Todavía no hay presupuestos. Creá el primero con “Nuevo presupuesto”."}</p>
          )}
          {rows.length > 0 && (
            <>
              <div className="mod-table-wrap pl-desktop">
                <table className="mod-table">
                  <thead><tr><th>Nº</th><th>Cliente</th><th>Fecha</th><th>Válido hasta</th><th className="is-num">Neto</th><th className="is-num">Con IVA</th><th>Estado</th><th><span className="sr-only">Acciones</span></th></tr></thead>
                  <tbody>
                    {rows.map((row) => (
                      <tr key={row.id}>
                        <td><strong>{String(row.number).padStart(5, "0")}</strong></td>
                        <td className="is-name"><strong>{row.customer_name}</strong><small>{row.line_count} producto{Number(row.line_count) === 1 ? "" : "s"} · {authorOf(row.created_by_label)}</small></td>
                        <td>{dateTime(row.created_at)}</td>
                        <td>{dateOnly(row.valid_until)}</td>
                        <td className="is-num">{money(row.net_total)}</td>
                        <td className="is-num"><strong>{money(row.gross_total)}</strong></td>
                        <td><span className={`pl-chip ${chipClass[row.effective_status]}`}>{label[row.effective_status]}</span></td>
                        <td className="qs-actions">
                          <button type="button" className="button outline" disabled={busyId === row.id} onClick={() => print(row.id)}>
                            <FileDown size={15} aria-hidden="true" /> PDF
                          </button>
                          {can("ventas", "editar") && row.status === "abierto" && <>
                            <button type="button" className="button outline" disabled={busyId === row.id} onClick={() => setConfirm({ row, next: "aceptado" })}>Aceptado</button>
                            <button type="button" className="button outline" disabled={busyId === row.id} onClick={() => setConfirm({ row, next: "rechazado" })}>Rechazado</button>
                            <button type="button" className="button outline" disabled={busyId === row.id} onClick={() => setConfirm({ row, next: "cancelado" })}>Cancelar</button>
                          </>}
                          {isAdmin && row.status !== "abierto" && (
                            <button type="button" className="button outline" disabled={busyId === row.id} onClick={() => setConfirm({ row, next: "abierto" })}>Reabrir</button>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <ul className="pl-cards" aria-label="Presupuestos">
                {rows.map((row) => (
                  <li key={row.id} className="pl-pcard">
                    <div className="pl-pcard-top">
                      <div><strong>Nº {String(row.number).padStart(5, "0")} · {row.customer_name}</strong>
                        <small>{dateTime(row.created_at)} · válido hasta {dateOnly(row.valid_until)}</small></div>
                      <strong className="pl-pcard-price">{money(row.gross_total)}</strong>
                    </div>
                    <span className={`pl-chip ${chipClass[row.effective_status]}`}>{label[row.effective_status]}</span>
                    <div className="qs-actions">
                      <button type="button" className="button outline" disabled={busyId === row.id} onClick={() => print(row.id)}>Descargar PDF</button>
                      {can("ventas", "editar") && row.status === "abierto" && (
                        <button type="button" className="button outline" onClick={() => setConfirm({ row, next: "aceptado" })}>Aceptado</button>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
              <nav className="mod-pager" aria-label="Paginación de presupuestos">
                <span className="mod-pager-count">{page * SIZE + 1}–{Math.min(total, page * SIZE + rows.length)} de {total} presupuestos</span>
                <span className="mod-pager-buttons">
                  <button type="button" aria-label="Página anterior" disabled={page === 0} onClick={() => setPage(page - 1)}><ChevronLeft size={18} /></button>
                  <span aria-live="polite">{page + 1} / {pages}</span>
                  <button type="button" aria-label="Página siguiente" disabled={page + 1 >= pages} onClick={() => setPage(page + 1)}><ChevronRight size={18} /></button>
                </span>
              </nav>
            </>
          )}
        </section>
      )}

      <CompanyProfileDialog open={profileOpen} onClose={() => setProfileOpen(false)}
        onSaved={() => client.invalidateQueries({ queryKey: ["company-profile", ...scope] })} />
      <ConfirmDeleteDialog open={Boolean(confirm)} busy={Boolean(busyId)}
        intent={confirm?.next === "aceptado" || confirm?.next === "abierto" ? "primary" : "danger"}
        confirmLabel={confirm ? { aceptado: "Marcar aceptado", rechazado: "Marcar rechazado", cancelado: "Cancelar presupuesto", abierto: "Reabrir" }[confirm.next] : ""}
        title={confirm ? `¿${{ aceptado: "Marcar como aceptado", rechazado: "Marcar como rechazado", cancelado: "Cancelar", abierto: "Reabrir" }[confirm.next]} el presupuesto Nº ${String(confirm.row.number).padStart(5, "0")}?` : ""}
        description={confirm ? `${confirm.row.customer_name}. Un presupuesto no mueve stock ni dinero: solo cambia su estado.` : ""}
        onCancel={() => setConfirm(null)} onConfirm={changeStatus} />
    </SalesShell>
  );
}

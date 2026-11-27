import CleanupButton from "../../../compartido/componentes/CleanupButton";
import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Link, useSearchParams } from "react-router-dom";
import { FileDown, Plus, RotateCcw } from "lucide-react";
import ActionDialog from "../../../compartido/componentes/ActionDialog";
import { useAuth } from "../../../compartido/contextos/AuthContext";
import {
  friendlyError,
  notifyError,
  notifySuccess,
} from "../../../compartido/utilidades/notifications";
import {
  listDeliveryNotes,
  listDeliveryItems,
  voidDeliveryNote,
} from "./deliveryNotes";
import {
  listProductionJobs,
  listProductionReservationLocations,
  listProductionWarehouses,
} from "../../produccion/compartido/production";
import { formatQuantity } from "../compartido/stockNumber";
import { listSales } from "../../ventas/compartido/sales";
import DeliveryNoteComposer from "./DeliveryNoteComposer";
import StockShell from "../compartido/StockShell";
import { lotLabel } from "../../../compartido/utilidades/display";
import "./deliveryNotes.css";

const kinds = {
  produccion: "Para fabricación",
  materiales: "Materiales",
  productos: "Productos y semielaborados",
  venta: "Entrega de venta",
};

export default function DeliveryNotesPage() {
  const { activeCompanyId, activeCompany, user, can } = useAuth();
  const client = useQueryClient();
  const [params, setParams] = useSearchParams();
  const linkedJobId = params.get("job") ?? "";
  const linkedSaleId = params.get("sale") ?? "";
  const [createOpen, setCreateOpen] = useState(
    Boolean(linkedJobId || linkedSaleId),
  );
  const [voidTarget, setVoidTarget] = useState(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [issuing, setIssuing] = useState(false);
  const [search, setSearch] = useState("");
  const notesQuery = useQuery({
    queryKey: ["delivery-notes", user?.id, activeCompanyId],
    queryFn: () => listDeliveryNotes(activeCompanyId),
    enabled: Boolean(activeCompanyId),
  });
  const itemsQuery = useQuery({
    queryKey: ["delivery-items", user?.id, activeCompanyId],
    queryFn: () => listDeliveryItems(activeCompanyId),
    enabled: Boolean(activeCompanyId && can("items", "ver")),
  });
  const warehousesQuery = useQuery({
    queryKey: ["production-warehouses", user?.id, activeCompanyId],
    queryFn: () => listProductionWarehouses(activeCompanyId),
    enabled: Boolean(activeCompanyId),
  });
  const salesQuery = useQuery({
    queryKey: ["sales-history", user?.id, activeCompanyId],
    queryFn: () => listSales(activeCompanyId),
    enabled: Boolean(activeCompanyId && can("ventas", "ver")),
  });
  const jobsQuery = useQuery({
    queryKey: ["production-jobs", user?.id, activeCompanyId],
    queryFn: () => listProductionJobs(activeCompanyId),
    enabled: Boolean(activeCompanyId && can("produccion_ordenes", "ver")),
  });
  const allocationsQuery = useQuery({
    queryKey: ["production-reservation-locations", user?.id, activeCompanyId],
    queryFn: () => listProductionReservationLocations(activeCompanyId),
    enabled: Boolean(
      activeCompanyId && can("produccion_ordenes", "ver") && can("stock_saldos", "ver"),
    ),
  });
  const items = itemsQuery.data ?? [];
  const jobs = jobsQuery.data ?? [];
  const [statusFilter, setStatusFilter] = useState("all");
  const [kindFilter, setKindFilter] = useState("all");
  const allNotes = notesQuery.data ?? [];
  const rows = allNotes.filter(
    (entry) =>
      (statusFilter === "all" ||
        (statusFilter === "anulado") === (entry.status === "anulado")) &&
      (kindFilter === "all" || entry.kind === kindFilter) &&
      `${entry.number} ${entry.recipient} ${entry.note} ${entry.delivery_note_lines
        ?.map((line) => line.item_name)
        .join(" ")}`
        .toLowerCase()
        .includes(search.toLowerCase()),
  );
  const voidedCount = allNotes.filter((entry) => entry.status === "anulado").length;
  const hasFilters = Boolean(search || statusFilter !== "all" || kindFilter !== "all");
  const clearFilters = () => {
    setSearch("");
    setStatusFilter("all");
    setKindFilter("all");
  };

  useEffect(() => {
    setSearch("");
    setVoidTarget(null);
    setCreateOpen(Boolean(linkedJobId || linkedSaleId));
  }, [activeCompanyId, linkedJobId, linkedSaleId]);

  function closeCreate(force = false) {
    if (issuing && force !== true) return;
    setCreateOpen(false);
    if (linkedJobId || linkedSaleId) setParams({}, { replace: true });
  }

  function refresh() {
    return Promise.all([
      client.invalidateQueries({
        queryKey: ["delivery-notes", user?.id, activeCompanyId],
      }),
      client.invalidateQueries({
        queryKey: ["production-jobs", user?.id, activeCompanyId],
      }),
      client.invalidateQueries({ queryKey: ["stock"] }),
      client.invalidateQueries({ queryKey: ["stock-movements"] }),
      client.invalidateQueries({ queryKey: ["job-material-balance"] }),
      client.invalidateQueries({ queryKey: ["job-material-lots"] }),
      client.invalidateQueries({ queryKey: ["delivery-balance"] }),
      client.invalidateQueries({ queryKey: ["delivery-lots"] }),
      client.invalidateQueries({ queryKey: ["erp-dashboard"] }),
      client.invalidateQueries({ queryKey: ["operational-alerts"] }),
      client.invalidateQueries({ queryKey: ["production-reservations"] }),
      client.invalidateQueries({
        queryKey: ["production-reservation-locations"],
      }),
      client.invalidateQueries({ queryKey: ["planning-availability"] }),
    ]);
  }

  async function printNote(note) {
    try {
      const { downloadDeliveryNotePdf } = await import("./deliveryNotePdf");
      const productName = jobs.find(
        (job) => job.id === note.job_id,
      )?.product_id;
      downloadDeliveryNotePdf(
        note,
        activeCompany?.name,
        items.find((item) => item.id === productName)?.name,
      );
    } catch (error) {
      notifyError(error);
    }
  }

  async function confirmVoid(event) {
    event.preventDefault();
    if (!voidTarget || reason.trim().length < 5 || busy) return;
    setBusy(true);
    try {
      await voidDeliveryNote(activeCompanyId, voidTarget.id, reason);
      setVoidTarget(null);
      setReason("");
      await refresh();
      notifySuccess(
        "Remito anulado",
        voidTarget.kind === "venta"
          ? "Se anuló el documento. El stock de la venta no cambió."
          : "El stock volvió al depósito de origen.",
      );
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <StockShell
      title="Remitos de entrega"
      description="Documentá cada entrega: al confirmar se descuenta el stock, y si se anula vuelve al depósito. Las entregas para fabricación quedan asociadas a su orden."
      actions={(
        <>
          <Link className="button outline" to="/archivados?type=remitos">
            Archivados
          </Link>
          {can("stock", "crear") && can("items", "ver") && (
            <button
              type="button"
              className="button primary"
              onClick={() => setCreateOpen(true)}
            >
              <Plus size={17} aria-hidden="true" /> Nuevo remito
            </button>
          )}
        </>
      )}
    >
    <section className="delivery-page">
      <div className="delivery-filters">
        <label className="delivery-search">
          Buscar número, destinatario o producto
          <input
            type="search"
            value={search}
            placeholder="Buscar en los últimos 100 remitos…"
            onChange={(event) => setSearch(event.target.value)}
          />
        </label>
        <label>
          Estado
          <select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>
            <option value="all">Todos</option>
            <option value="emitido">Entregados</option>
            <option value="anulado">Anulados ({voidedCount})</option>
          </select>
        </label>
        <label>
          Tipo
          <select value={kindFilter} onChange={(event) => setKindFilter(event.target.value)}>
            <option value="all">Todos</option>
            {Object.entries(kinds).map(([value, label]) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </select>
        </label>
        {hasFilters && (
          <button type="button" className="button outline" onClick={clearFilters}>
            Limpiar filtros
          </button>
        )}
      </div>
      <p className="delivery-count" role="status">
        {rows.length} {rows.length === 1 ? "remito" : "remitos"}
        {hasFilters ? " con estos filtros" : ""}
      </p>
      {(notesQuery.error || itemsQuery.error || jobsQuery.error) && (
        <p role="alert" className="error">
          {friendlyError(
            notesQuery.error || itemsQuery.error || jobsQuery.error,
          )}
        </p>
      )}
      {notesQuery.isPending && <p>Cargando remitos…</p>}
      {!notesQuery.isPending && !rows.length && (
        <div className="stock-empty">
          <h2>{hasFilters ? "No hay remitos con esos filtros" : "Todavía no emitiste remitos"}</h2>
          <p>
            {hasFilters
              ? "Probá con otra búsqueda o limpiá los filtros."
              : "Usá «Nuevo remito» para registrar la primera entrega."}
          </p>
        </div>
      )}
      <div className="delivery-list">
        {rows.map((note) => (
          <article
            className={`delivery-card ${note.status === "anulado" ? "is-voided" : ""}`}
            key={note.id}
          >
            <div className="delivery-card-head">
              <div>
                <h2>
                  Remito Nº {note.number} · {note.recipient}
                </h2>
                <p>
                  {kinds[note.kind]} ·{" "}
                  {new Date(note.created_at).toLocaleString("es-AR")}
                </p>
              </div>
              <span className={`delivery-status ${note.status}`}>
                {note.status === "anulado" ? "Anulado" : "Entregado"}
              </span>
            </div>
            {note.sale_id && (
              <p>
                Venta Nº {note.sale?.number ?? "—"}
                {" · "}
                {note.sale?.customer_name ?? note.recipient}
              </p>
            )}
            {note.job_id && can("produccion_ordenes", "ver") && (
              <Link to={`/production/orders?job=${note.job_id}`}>
                Ver orden de fabricación
              </Link>
            )}
            <details>
              <summary>
                {note.delivery_note_lines?.length ?? 0} ítems · Ver detalle
              </summary>
              <ul>
                {[...(note.delivery_note_lines ?? [])]
                  .sort((a, b) => a.line_no - b.line_no)
                  .map((line) => (
                    <li key={line.line_no}>
                      {line.item_name} · {formatQuantity(line.quantity)}{" "}
                      {line.unit_symbol}
                      {" · "}
                      {line.warehouse_name}
                      {line.lot_code && ` · Lote ${lotLabel(line.lot_code)}`}
                    </li>
                  ))}
              </ul>
              <small>{note.note}</small>
              {note.void_reason && (
                <p>Motivo de anulación: {note.void_reason}</p>
              )}
            </details>
            <div className="delivery-card-actions">
              <CleanupButton
                resource="remitos"
                id={note.id}
                label={`Remito ${note.number} · ${note.recipient}`}
              />
              <button
                type="button"
                className="button outline"
                onClick={() => printNote(note)}
              >
                <FileDown size={16} /> Descargar PDF
              </button>
              {note.status === "emitido" && can("stock", "eliminar") && (
                <button
                  type="button"
                  className="button outline"
                  onClick={() => {
                    setVoidTarget(note);
                    setReason("");
                  }}
                >
                  <RotateCcw size={16} /> Anular entrega
                </button>
              )}
            </div>
          </article>
        ))}
      </div>
      <ActionDialog
        open={createOpen}
        busy={issuing}
        title="Nuevo remito de entrega"
        description="Confirmar un remito registra la salida de stock. En fabricación también suma el consumo real."
        onClose={closeCreate}
      >
        {createOpen && (
          <DeliveryNoteComposer
            items={items}
            warehouses={warehousesQuery.data ?? []}
            jobs={jobs}
            allocations={allocationsQuery.data ?? []}
            initialKind={
              linkedJobId ? "produccion" : linkedSaleId ? "venta" : "materiales"
            }
            initialJobId={linkedJobId}
            initialSaleId={linkedSaleId}
            sales={salesQuery.data ?? []}
            notes={notesQuery.data ?? []}
            onCancel={closeCreate}
            onBusyChange={setIssuing}
            onIssued={async () => {
              await refresh();
              closeCreate(true);
            }}
          />
        )}
      </ActionDialog>
      <ActionDialog
        open={!!voidTarget}
        busy={busy}
        title={`¿Seguro que querés anular el remito Nº ${voidTarget?.number ?? ""}?`}
        description={
          voidTarget?.kind === "venta"
            ? "El remito se anula, pero la venta y su descuento de stock siguen vigentes."
            : "La anulación reingresa los ítems al depósito original y queda registrada en el historial."
        }
        onClose={() => setVoidTarget(null)}
      >
        <form className="delivery-void-form" onSubmit={confirmVoid}>
          <p>
            {voidTarget?.kind === "venta"
              ? "Para modificar la venta, usá su gestión de devoluciones. Este botón solo anula el remito."
              : "Si está vinculado a fabricación, la orden debe seguir en proceso y los ítems no pueden haber sido devueltos."}
          </p>
          <label>
            Motivo de anulación
            <textarea
              required
              minLength={5}
              maxLength={300}
              value={reason}
              onChange={(event) => setReason(event.target.value)}
            />
          </label>
          <div className="erp-action-dialog-actions">
            <button
              type="button"
              className="button outline"
              disabled={busy}
              onClick={() => setVoidTarget(null)}
            >
              Volver
            </button>
            <button
              className="button erp-confirm-danger"
              disabled={busy || reason.trim().length < 5}
            >
              {busy
                ? "Anulando…"
                : voidTarget?.kind === "venta"
                  ? "Anular documento"
                  : "Anular y devolver stock"}
            </button>
          </div>
        </form>
      </ActionDialog>
    </section>
    </StockShell>
  );
}

import CleanupButton from "../../../compartido/componentes/CleanupButton";
import WorkDetailsDialog from "./WorkDetailsDialog";
import JobComponentsTable from "./JobComponentsTable";
import ListPager, { usePagedList } from "../../../compartido/componentes/ListPager";
import "../../compras/cuentas-proveedores/supplierAccounts.css";
import { useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import {
  Download,
  PackagePlus,
  RotateCcw,
  CheckCircle2,
  Play,
  Truck,
  XCircle,
} from "lucide-react";
import ActionDialog from "../../../compartido/componentes/ActionDialog";
import ConfirmDeleteDialog from "../../../compartido/componentes/ConfirmDeleteDialog";
import FinishJobDialog from "./FinishJobDialog";
import DeliveryNoteComposer from "../../stock/remitos/DeliveryNoteComposer";
import { useAuth } from "../../../compartido/contextos/AuthContext";
import {
  notifyError,
  notifySuccess,
  friendlyError,
} from "../../../compartido/utilidades/notifications";
import { formatQuantity } from "../../stock/compartido/stockNumber";
import { lotLabel } from "../../../compartido/utilidades/display";
import { listStockLots } from "../../stock/compartido/stock";
import {
  cancelProductionJob,
  issueProductionMaterial,
  listProductionBalances,
  returnProductionMaterial,
  startProductionJob,
} from "../compartido/production";

const defaultIssue = () => ({
  componentId: "",
  warehouseId: "",
  lotCode: "",
  quantity: "",
  note: "Insumo retirado para fabricación",
});
const money = (value) =>
  Number(value).toLocaleString("es-AR", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
const validQuantity = (value) =>
  /^\d+(?:\.\d{1,6})?$/.test(String(value)) &&
  Number(value) > 0 &&
  Number(value) < 1000000000000;

export default function ProductionJobCard({
  job,
  items,
  warehouses,
  allocations = [],
  remitos = [],
  onUpdated,
  onPrint,
}) {
  const { activeCompanyId, can, role } = useAuth();
  const [action, setAction] = useState(null);
  const [issue, setIssue] = useState(defaultIssue);
  const [itemSearch, setItemSearch] = useState("");
  const [returnEntry, setReturnEntry] = useState(null);
  const [returnQuantity, setReturnQuantity] = useState("");
  const [returnNote, setReturnNote] = useState(
    "No utilizado en la fabricación",
  );
  const [cancelReason, setCancelReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [confirm, setConfirm] = useState(null);
  const [issuing, setIssuing] = useState(false);
  const requests = useRef(new Map());
  const itemName = (id) =>
    items.find((item) => item.id === id)?.name ?? "Insumo";
  const product = items.find((item) => item.id === job.product_id);
  const events = [...(job.production_job_events ?? [])].sort(
    (a, b) => new Date(a.created_at) - new Date(b.created_at),
  );
  // Lo más reciente primero y paginado: una orden grande puede tener cientos de movimientos.
  const eventsPager = usePagedList([...events].reverse(), { pageSize: 10 });
  const expected = job.formula_snapshot ?? [];
  const net = new Map();
  for (const event of events) {
    net.set(
      event.component_id,
      (net.get(event.component_id) ?? 0) +
        (event.kind === "issue" ? 1 : -1) * Number(event.quantity),
    );
  }
  const remaining = expected.filter(
    (line) =>
      Number(line.quantity) - (net.get(line.component_id) ?? 0) > 0.000001,
  ).length;
  const actualCost = events.reduce(
    (sum, entry) =>
      sum +
      (entry.kind === "issue" ? 1 : -1) *
        Number(entry.quantity) *
        Number(entry.unit_cost),
    0,
  );
  const chosen = items.find((item) => item.id === issue.componentId);
  const eligible = items.filter(
    (item) =>
      ["raw_material", "semi_finished", "consumable"].includes(
        item.item_type,
      ) && item.active !== false,
  );
  const balanceQuery = useQuery({
    queryKey: ["job-material-balance", activeCompanyId, issue.componentId],
    queryFn: () => listProductionBalances(activeCompanyId, [issue.componentId]),
    enabled: Boolean(
      activeCompanyId && action === "issue" && issue.componentId,
    ),
  });
  const lotsQuery = useQuery({
    queryKey: [
      "job-material-lots",
      activeCompanyId,
      issue.componentId,
      issue.warehouseId,
    ],
    queryFn: () =>
      listStockLots(activeCompanyId, issue.componentId, issue.warehouseId),
    enabled: Boolean(
      activeCompanyId &&
      action === "issue" &&
      chosen?.track_lots &&
      issue.warehouseId,
    ),
  });
  const available = chosen?.infinite_stock
    ? Infinity
    : chosen?.track_lots
      ? Number(
          (lotsQuery.data ?? []).find((lot) => lot.code === issue.lotCode)
            ?.available ?? 0,
        )
      : Number(
          (balanceQuery.data ?? []).find(
            (balance) => balance.warehouse_id === issue.warehouseId,
          )?.quantity ?? 0,
        );
  const canDeliver = can("production_orders", "insert") && can("stock", "insert");

  function requestFor(key, fingerprint) {
    const previous = requests.current.get(key);
    if (previous?.fingerprint === fingerprint) return previous.id;
    const id = crypto.randomUUID();
    requests.current.set(key, { fingerprint, id });
    return id;
  }

  function chooseIssue(id) {
    const line = expected.find((entry) => entry.component_id === id);
    const remainingAmount = Math.max(
      0,
      Number(line?.quantity ?? 0) - Number(net.get(id) ?? 0),
    );
    const suggested = allocations.find((entry) => entry.component_id === id);
    setIssue((current) => ({
      ...current,
      componentId: id,
      warehouseId: suggested?.warehouse_id ?? "",
      lotCode: suggested?.lot_code ?? "",
      quantity: remainingAmount
        ? String(
            Number(
              Math.min(
                remainingAmount,
                Number(suggested?.quantity ?? remainingAmount),
              ).toFixed(6),
            ),
          )
        : "",
    }));
  }

  function askIssue(event) {
    event.preventDefault();
    if (busy || !validQuantity(issue.quantity) || !issue.warehouseId || issue.note.trim().length < 3 || (!chosen?.infinite_stock && Number(issue.quantity) > available) || (chosen?.track_lots && !issue.lotCode)) {
      notifyError(new Error("Revisá stock, cantidad, depósito y lote."));
      return;
    }
    setConfirm("issue");
  }

  async function saveIssue() {
    if (
      busy ||
      !validQuantity(issue.quantity) ||
      !issue.warehouseId ||
      issue.note.trim().length < 3 ||
      (!chosen?.infinite_stock && Number(issue.quantity) > available) ||
      (chosen?.track_lots && !issue.lotCode)
    ) {
      notifyError(new Error("Revisá stock, cantidad, depósito y lote."));
      return;
    }
    setBusy(true);
    try {
      await issueProductionMaterial(
        activeCompanyId,
        job.id,
        issue,
        requestFor("issue", JSON.stringify(issue)),
      );
      requests.current.delete("issue");
      setIssue(defaultIssue());
      setAction(null);
      await onUpdated();
      notifySuccess(
        "Insumo retirado",
        "Se descontó del stock y quedó asociado a esta orden.",
      );
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  function openReturn(entry) {
    setReturnEntry(entry);
    setReturnQuantity("");
    setReturnNote("No utilizado en la fabricación");
    setAction("return");
  }

  function askReturn(event) {
    event.preventDefault();
    if (!returnEntry || !validQuantity(returnQuantity) || busy) return;
    setConfirm("return");
  }

  async function saveReturn() {
    if (!returnEntry || !validQuantity(returnQuantity) || busy) return;
    const returned = events
      .filter((row) => row.kind === "return" && row.issue_id === returnEntry.id)
      .reduce((sum, row) => sum + Number(row.quantity), 0);
    if (Number(returnQuantity) > Number(returnEntry.quantity) - returned) {
      notifyError(new Error("La devolución supera lo entregado."));
      return;
    }
    setBusy(true);
    try {
      const payload = {
        id: returnEntry.id,
        quantity: returnQuantity,
        note: returnNote,
      };
      await returnProductionMaterial(
        activeCompanyId,
        job.id,
        returnEntry.id,
        returnQuantity,
        returnNote,
        requestFor(`return:${returnEntry.id}`, JSON.stringify(payload)),
      );
      requests.current.delete(`return:${returnEntry.id}`);
      setAction(null);
      await onUpdated();
      notifySuccess("Insumo devuelto", "Volvió al depósito y lote originales.");
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  async function start() {
    setBusy(true);
    try {
      await startProductionJob(activeCompanyId, job.id);
      await onUpdated();
      notifySuccess("Fabricación iniciada");
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  async function cancel(event) {
    event.preventDefault();
    if (cancelReason.trim().length < 5 || busy) return;
    setBusy(true);
    try {
      await cancelProductionJob(activeCompanyId, job.id, cancelReason);
      setAction(null);
      await onUpdated();
      notifySuccess("Orden cancelada");
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  const active = ["queued", "in_progress"].includes(job.status);
  const options = eligible.filter((item) =>
    `${item.code} ${item.name}`
      .toLowerCase()
      .includes(itemSearch.toLowerCase()),
  );
  if (chosen && !options.some((item) => item.id === chosen.id))
    options.unshift(chosen);

  return (
    <article className="production-job">
      <header className="production-job-head">
        <div>
          <strong>
            OF {job.number} · {product?.name ?? "Producto"}
          </strong>
          <small>
            {new Date(job.created_at).toLocaleDateString("es-AR")}
            {" · "}Fórmula v{job.formula_version}
            {job.due_on &&
              ` · Prevista ${new Date(`${job.due_on}T12:00:00`).toLocaleDateString("es-AR")}`}
          </small>
        </div>
        <span className={`production-badge ${job.status}`}>
          {
            {
              queued: "En cola",
              in_progress: "En proceso",
              completed: "Terminada",
              cancelled: "Cancelada",
            }[job.status]
          }
        </span>
      </header>
      <div className="production-job-summary">
        <span>
          Planificado{" "}
          <strong>
            {formatQuantity(job.planned_quantity)} {product?.units?.symbol}
          </strong>
        </span>
        <span>
          Salida esperada{" "}
          <strong>
            {formatQuantity(job.expected_output ?? job.planned_quantity)}{" "}
            {product?.units?.symbol}
          </strong>
        </span>
        <span>
          Obtenido{" "}
          <strong>
            {job.actual_quantity == null
              ? "Pendiente"
              : `${formatQuantity(job.actual_quantity)} ${product?.units?.symbol ?? ""}`}
          </strong>
        </span>
        <span>
          Insumos pendientes{" "}
          <strong>
            {remaining} de {expected.length}
          </strong>
        </span>
        {(role === "admin" || can("costs_production", "read")) && (
          <span>
            Costo consumido <strong>$ {money(actualCost)}</strong>
          </span>
        )}
      </div>
      <JobComponentsTable
        expected={expected}
        net={net}
        allocations={allocations}
        warehouses={warehouses}
        items={items}
        active={active}
      />
      {remitos.length > 0 && (
        <p className="production-linked-notes">
          Remitos:{" "}
          {remitos.map((note, index) => (
            <span key={note.id}>
              {index > 0 && " · "}
              {can("stock_levels", "read") ? (
                <Link to="/inventory/delivery-notes">Nº {note.number}</Link>
              ) : (
                `Nº ${note.number}`
              )}
              {note.status === "voided" && " (anulado)"}
            </span>
          ))}
        </p>
      )}
      {action === "details" && (
        <WorkDetailsDialog
          job={job}
          onUpdated={onUpdated}
          onClose={() => setAction(null)}
        />
      )}
      <div className="production-job-buttons">
        <CleanupButton
          resource="jobs"
          id={job.id}
          label={`OF ${job.number} · ${product?.name ?? "Producto"}`}
          onRemoved={onUpdated}
        />
        {job.status !== "cancelled" && can("production_orders", "update") && (
          <button
            type="button"
            className="button outline"
            onClick={() => setAction("details")}
          >
            Envasado y controles
          </button>
        )}
        <button
          type="button"
          className="button outline"
          onClick={() => onPrint(job)}
        >
          <Download size={16} /> PDF del proceso
        </button>
        {job.status === "queued" && can("production_orders", "update") && (
          <button
            type="button"
            className="button outline"
            disabled={busy}
            onClick={start}
          >
            <Play size={16} /> Iniciar
          </button>
        )}
        {active && canDeliver && (
          <>
            <button
              type="button"
              className="button primary"
              onClick={() => setAction("remito")}
            >
              <Truck size={16} /> Remito de entrega
            </button>
            <button
              type="button"
              className="button outline"
              onClick={() => setAction("issue")}
            >
              <PackagePlus size={16} /> Agregar insumo sin remito
            </button>
          </>
        )}
        {job.status === "in_progress" &&
          can("production_orders", "insert") &&
          can("stock", "insert") && (
            <button
              type="button"
              className="button outline"
              onClick={() => setAction("finish")}
            >
              <CheckCircle2 size={16} /> Terminar fabricación
            </button>
          )}
        {active && can("production_orders", "update") && (
          <button
            type="button"
            className="button outline"
            onClick={() => setAction("cancel")}
          >
            <XCircle size={16} /> Cancelar orden
          </button>
        )}
      </div>
      <details className="production-movements">
        <summary>Historial de insumos ({events.length} movimientos)</summary>
        {events.length === 0 && <p>Todavía no se entregaron materiales.</p>}
        {eventsPager.visible.map((entry) => {
          const returned = events
            .filter((row) => row.kind === "return" && row.issue_id === entry.id)
            .reduce((sum, row) => sum + Number(row.quantity), 0);
          const open =
            entry.kind === "issue" ? Number(entry.quantity) - returned : 0;
          return (
            <div className="production-job-event" key={entry.id}>
              <span>
                {entry.kind === "issue" ? "Entregado" : "Devuelto"} ·{" "}
                {itemName(entry.component_id)}
                {" · "}
                {formatQuantity(entry.quantity)}
                {entry.lot_code && ` · Lote ${lotLabel(entry.lot_code)}`}
              </span>
              <small>
                {entry.note} ·{" "}
                {new Date(entry.created_at).toLocaleString("es-AR")}
              </small>
              {open > 0.000001 &&
                job.status === "in_progress" &&
                can("production_orders", "update") &&
                can("stock", "insert") && (
                  <button
                    type="button"
                    className="production-link"
                    onClick={() => openReturn(entry)}
                  >
                    <RotateCcw size={15} /> Devolver hasta{" "}
                    {formatQuantity(open)}
                  </button>
                )}
            </div>
          );
        })}
        <ListPager pager={eventsPager} noun="movimientos" sizes={[10, 25, 50]} />
      </details>
      <ActionDialog
        open={action === "remito"}
        title="Entrega de materiales para fabricación"
        description="Un remito vinculado registra los consumos y descuenta stock una sola vez."
        busy={issuing}
        onClose={() => {
          if (!issuing) setAction(null);
        }}
      >
        {action === "remito" && (
          <DeliveryNoteComposer
            items={items}
            warehouses={warehouses}
            jobs={[job]}
            allocations={allocations}
            initialKind="production"
            initialJobId={job.id}
            onCancel={() => {
              if (!issuing) setAction(null);
            }}
            onBusyChange={setIssuing}
            onIssued={async () => {
              setAction(null);
              await onUpdated();
            }}
          />
        )}
      </ActionDialog>
      <ActionDialog
        open={action === "issue"}
        title="Agregar insumo sin remito"
        description="La entrega descuenta stock y se suma al consumo de la orden."
        busy={busy}
        onClose={() => setAction(null)}
      >
        <form onSubmit={askIssue}>
          <label>
            Buscar insumo
            <input
              type="search"
              value={itemSearch}
              placeholder="Filtrar por nombre o código"
              onChange={(event) => setItemSearch(event.target.value)}
            />
          </label>
          <label>
            Material o semielaborado
            <select
              required
              value={issue.componentId}
              onChange={(event) => chooseIssue(event.target.value)}
            >
              <option value="">Seleccionar…</option>
              {options.map((item) => (
                <option value={item.id} key={item.id}>
                  {item.code} · {item.name}
                </option>
              ))}
            </select>
          </label>
          <div className="production-two-columns">
            <label>
              Depósito de origen
              <select
                required
                value={issue.warehouseId}
                onChange={(event) =>
                  setIssue((current) => ({
                    ...current,
                    warehouseId: event.target.value,
                    lotCode: "",
                  }))
                }
              >
                <option value="">Seleccionar…</option>
                {warehouses.map((entry) => (
                  <option key={entry.id} value={entry.id}>
                    {entry.name}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Cantidad entregada
              <input
                required
                type="number"
                min="0.000001"
                step="0.000001"
                value={issue.quantity}
                onChange={(event) =>
                  setIssue((current) => ({
                    ...current,
                    quantity: event.target.value,
                  }))
                }
              />
            </label>
          </div>
          {chosen?.track_lots && (
            <label>
              Lote de origen
              <select
                required
                value={issue.lotCode}
                onChange={(event) =>
                  setIssue((current) => ({
                    ...current,
                    lotCode: event.target.value,
                  }))
                }
              >
                <option value="">Seleccionar…</option>
                {(lotsQuery.data ?? [])
                  .filter((lot) => Number(lot.available) > 0)
                  .map((lot) => (
                    <option key={lot.id} value={lot.code}>
                      {lotLabel(lot.code)} · {formatQuantity(lot.available)} disponibles
                    </option>
                  ))}
              </select>
            </label>
          )}
          {chosen && issue.warehouseId && (
            <small>Disponible: {formatQuantity(available)}</small>
          )}
          <label>
            Motivo / detalle
            <input
              required
              minLength={3}
              maxLength={300}
              value={issue.note}
              onChange={(event) =>
                setIssue((current) => ({
                  ...current,
                  note: event.target.value,
                }))
              }
            />
          </label>
          {(balanceQuery.error || lotsQuery.error) && (
            <p role="alert" className="error">
              {friendlyError(balanceQuery.error || lotsQuery.error)}
            </p>
          )}
          <div className="erp-action-dialog-actions">
            <button
              type="button"
              className="button outline"
              disabled={busy}
              onClick={() => setAction(null)}
            >
              Volver
            </button>
            <button
              className="button primary"
              disabled={
                busy ||
                !canDeliver ||
                !issue.componentId ||
                !issue.warehouseId ||
                !validQuantity(issue.quantity) ||
                (!chosen?.infinite_stock &&
                  Number(issue.quantity) > available) ||
                (chosen?.track_lots && !issue.lotCode)
              }
            >
              Registrar entrega
            </button>
          </div>
        </form>
      </ActionDialog>
      <ActionDialog
        open={action === "return"}
        title="Devolver insumo"
        description="El material vuelve al mismo depósito y lote del que salió."
        busy={busy}
        onClose={() => setAction(null)}
      >
        <form onSubmit={askReturn}>
          <p>{returnEntry && itemName(returnEntry.component_id)}</p>
          <label>
            Cantidad a devolver
            <input
              required
              type="number"
              min="0.000001"
              step="0.000001"
              value={returnQuantity}
              onChange={(event) => setReturnQuantity(event.target.value)}
            />
          </label>
          <label>
            Motivo
            <input
              required
              minLength={3}
              maxLength={300}
              value={returnNote}
              onChange={(event) => setReturnNote(event.target.value)}
            />
          </label>
          <div className="erp-action-dialog-actions">
            <button
              type="button"
              className="button outline"
              disabled={busy}
              onClick={() => setAction(null)}
            >
              Volver
            </button>
            <button
              className="button primary"
              disabled={busy || !validQuantity(returnQuantity)}
            >
              Devolver al stock
            </button>
          </div>
        </form>
      </ActionDialog>
      {action === "finish" && (
        <FinishJobDialog
          job={job}
          product={product}
          items={items}
          warehouses={warehouses}
          events={events}
          allocations={allocations}
          companyId={activeCompanyId}
          onClose={() => setAction(null)}
          onFinished={async () => {
            setAction(null);
            await onUpdated();
          }}
        />
      )}
      <ConfirmDeleteDialog
        open={confirm === "issue"}
        intent="primary"
        title="¿Confirmás la entrega del insumo?"
        description={`Se descontarán ${formatQuantity(issue.quantity || 0)} de ${chosen?.name ?? "insumo"} del stock y quedarán asociados a esta orden.`}
        confirmLabel="Confirmar y descontar stock"
        busy={busy}
        onCancel={() => setConfirm(null)}
        onConfirm={async () => {
          await saveIssue();
          setConfirm(null);
        }}
      />
      <ConfirmDeleteDialog
        open={confirm === "return"}
        intent="primary"
        title="¿Confirmás la devolución al stock?"
        description={`Volverán ${formatQuantity(returnQuantity || 0)} de ${returnEntry ? itemName(returnEntry.component_id) : "insumo"} al depósito y lote de origen.`}
        confirmLabel="Confirmar y sumar stock"
        busy={busy}
        onCancel={() => setConfirm(null)}
        onConfirm={async () => {
          await saveReturn();
          setConfirm(null);
        }}
      />
      <ActionDialog
        open={action === "cancel"}
        title="¿Seguro que querés cancelar la orden?"
        description="Devolvé todos los insumos pendientes antes de cancelar."
        busy={busy}
        onClose={() => setAction(null)}
      >
        <form onSubmit={cancel}>
          <label>
            Motivo de cancelación
            <textarea
              required
              minLength={5}
              maxLength={300}
              value={cancelReason}
              onChange={(event) => setCancelReason(event.target.value)}
            />
          </label>
          <div className="erp-action-dialog-actions">
            <button
              type="button"
              className="button outline"
              disabled={busy}
              onClick={() => setAction(null)}
            >
              Volver
            </button>
            <button
              className="button erp-confirm-danger"
              disabled={busy || cancelReason.trim().length < 5}
            >
              Cancelar orden
            </button>
          </div>
        </form>
      </ActionDialog>
    </article>
  );
}

import { useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Download, PackagePlus, RotateCcw, CheckCircle2, Play, Truck, XCircle } from 'lucide-react';
import ActionDialog from '../../components/ActionDialog';
import DeliveryNoteComposer from '../inventory/DeliveryNoteComposer';
import { useAuth } from '../../contexts/AuthContext';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import { formatQuantity } from '../inventory/stockNumber';
import { listStockLots } from '../../services/stock';
import {
  cancelProductionJob, finishProductionJob, issueProductionMaterial,
  listProductionBalances, returnProductionMaterial, startProductionJob,
} from '../../services/production';

const defaultIssue = () => ({ componentId: '', warehouseId: '', lotCode: '',
  quantity: '', note: 'Insumo retirado para fabricación' });
const money = (value) => Number(value).toLocaleString('es-AR', {
  minimumFractionDigits: 2, maximumFractionDigits: 2,
});
const validQuantity = (value) => /^\d+(?:\.\d{1,6})?$/.test(String(value))
  && Number(value) > 0 && Number(value) < 1000000000000;

export default function ProductionJobCard({
  job, items, warehouses, remitos = [], onUpdated, onPrint,
}) {
  const { activeCompanyId, can, role } = useAuth();
  const [action, setAction] = useState(null);
  const [issue, setIssue] = useState(defaultIssue);
  const [itemSearch, setItemSearch] = useState('');
  const [returnEntry, setReturnEntry] = useState(null);
  const [returnQuantity, setReturnQuantity] = useState('');
  const [returnNote, setReturnNote] = useState('No utilizado en la fabricación');
  const [actual, setActual] = useState(String(job.actual_quantity ?? job.planned_quantity));
  const [outputLot, setOutputLot] = useState(job.output_lot ?? '');
  const [expiresOn, setExpiresOn] = useState(job.output_expiry ?? '');
  const [varianceNote, setVarianceNote] = useState(job.variance_note ?? '');
  const [cancelReason, setCancelReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [issuing, setIssuing] = useState(false);
  const requests = useRef(new Map());
  const itemName = (id) => items.find((item) => item.id === id)?.name ?? 'Insumo';
  const product = items.find((item) => item.id === job.product_id);
  const events = [...(job.production_job_events ?? [])].sort((a, b) =>
    new Date(a.created_at) - new Date(b.created_at));
  const expected = job.formula_snapshot ?? [];
  const net = new Map();
  for (const event of events) {
    net.set(event.component_id, (net.get(event.component_id) ?? 0)
      + (event.kind === 'issue' ? 1 : -1) * Number(event.quantity));
  }
  const remaining = expected.filter((line) =>
    Number(line.quantity) - (net.get(line.component_id) ?? 0) > 0.000001).length;
  const actualCost = events.reduce((sum, entry) => sum
    + (entry.kind === 'issue' ? 1 : -1)
    * Number(entry.quantity) * Number(entry.unit_cost), 0);
  const mismatch = Math.abs(Number(actual) - Number(job.planned_quantity)) > 0.000001
    || expected.some((line) => Math.abs((net.get(line.component_id) ?? 0)
      - Number(line.quantity)) > 0.000001)
    || [...net].some(([id, quantity]) => quantity > 0.000001
      && !expected.some((line) => line.component_id === id));
  const chosen = items.find((item) => item.id === issue.componentId);
  const eligible = items.filter((item) => ['raw_material', 'semi_finished']
    .includes(item.item_type));
  const balanceQuery = useQuery({
    queryKey: ['job-material-balance', activeCompanyId, issue.componentId],
    queryFn: () => listProductionBalances(activeCompanyId, [issue.componentId]),
    enabled: Boolean(activeCompanyId && action === 'issue' && issue.componentId),
  });
  const lotsQuery = useQuery({
    queryKey: ['job-material-lots', activeCompanyId, issue.componentId, issue.warehouseId],
    queryFn: () => listStockLots(activeCompanyId, issue.componentId, issue.warehouseId),
    enabled: Boolean(activeCompanyId && action === 'issue'
      && chosen?.track_lots && issue.warehouseId),
  });
  const available = chosen?.track_lots
    ? Number((lotsQuery.data ?? []).find((lot) => lot.code === issue.lotCode)?.available ?? 0)
    : Number((balanceQuery.data ?? []).find((balance) =>
      balance.warehouse_id === issue.warehouseId)?.quantity ?? 0);
  const canDeliver = can('production', 'insert') && can('stock', 'insert');

  function requestFor(key, fingerprint) {
    const previous = requests.current.get(key);
    if (previous?.fingerprint === fingerprint) return previous.id;
    const id = crypto.randomUUID();
    requests.current.set(key, { fingerprint, id });
    return id;
  }

  function chooseIssue(id) {
    const line = expected.find((entry) => entry.component_id === id);
    const remainingAmount = Math.max(0, Number(line?.quantity ?? 0)
      - Number(net.get(id) ?? 0));
    setIssue((current) => ({ ...current, componentId: id,
      warehouseId: '', lotCode: '',
      quantity: remainingAmount ? String(Number(remainingAmount.toFixed(6))) : '' }));
  }

  async function saveIssue(event) {
    event.preventDefault();
    if (busy || !validQuantity(issue.quantity) || !issue.warehouseId
      || issue.note.trim().length < 3 || Number(issue.quantity) > available
      || (chosen?.track_lots && !issue.lotCode)) {
      notifyError(new Error('Revisá stock, cantidad, depósito y lote.'));
      return;
    }
    setBusy(true);
    try {
      await issueProductionMaterial(activeCompanyId, job.id, issue,
        requestFor('issue', JSON.stringify(issue)));
      requests.current.delete('issue');
      setIssue(defaultIssue());
      setAction(null);
      await onUpdated();
      notifySuccess('Insumo retirado', 'Se descontó del stock y quedó asociado a esta orden.');
    } catch (error) { notifyError(error); } finally { setBusy(false); }
  }

  function openReturn(entry) {
    setReturnEntry(entry);
    setReturnQuantity('');
    setReturnNote('No utilizado en la fabricación');
    setAction('return');
  }

  async function saveReturn(event) {
    event.preventDefault();
    if (!returnEntry || !validQuantity(returnQuantity) || busy) return;
    const returned = events.filter((row) => row.kind === 'return'
      && row.issue_id === returnEntry.id)
      .reduce((sum, row) => sum + Number(row.quantity), 0);
    if (Number(returnQuantity) > Number(returnEntry.quantity) - returned) {
      notifyError(new Error('La devolución supera lo entregado.'));
      return;
    }
    setBusy(true);
    try {
      const payload = { id: returnEntry.id, quantity: returnQuantity, note: returnNote };
      await returnProductionMaterial(activeCompanyId, job.id,
        returnEntry.id, returnQuantity, returnNote,
        requestFor(`return:${returnEntry.id}`, JSON.stringify(payload)));
      requests.current.delete(`return:${returnEntry.id}`);
      setAction(null);
      await onUpdated();
      notifySuccess('Insumo devuelto', 'Volvió al depósito y lote originales.');
    } catch (error) { notifyError(error); } finally { setBusy(false); }
  }

  async function finish(event) {
    event.preventDefault();
    if (!validQuantity(actual) || busy || (product?.track_lots && !outputLot.trim())
      || (mismatch && varianceNote.trim().length < 5)) return;
    setBusy(true);
    try {
      const values = { actualQuantity: actual, outputLot, expiresOn, varianceNote };
      await finishProductionJob(activeCompanyId, job.id, values,
        requestFor('finish', JSON.stringify(values)));
      requests.current.delete('finish');
      setAction(null);
      await onUpdated();
      notifySuccess('Fabricación completada', 'Ingresó al stock la cantidad real producida.');
    } catch (error) { notifyError(error); } finally { setBusy(false); }
  }

  async function start() {
    setBusy(true);
    try {
      await startProductionJob(activeCompanyId, job.id);
      await onUpdated();
      notifySuccess('Fabricación iniciada');
    } catch (error) { notifyError(error); } finally { setBusy(false); }
  }

  async function cancel(event) {
    event.preventDefault();
    if (cancelReason.trim().length < 5 || busy) return;
    setBusy(true);
    try {
      await cancelProductionJob(activeCompanyId, job.id, cancelReason);
      setAction(null);
      await onUpdated();
      notifySuccess('Orden cancelada');
    } catch (error) { notifyError(error); } finally { setBusy(false); }
  }

  const active = ['queued', 'in_progress'].includes(job.status);
  const options = eligible.filter((item) => `${item.code} ${item.name}`
    .toLowerCase().includes(itemSearch.toLowerCase()));
  if (chosen && !options.some((item) => item.id === chosen.id)) options.unshift(chosen);

  return (
    <article className="production-job">
      <header className="production-job-head">
        <div>
          <strong>{product?.name ?? 'Producto'}</strong>
          <small>{new Date(job.created_at).toLocaleDateString('es-AR')}
            {' · '}Fórmula v{job.formula_version}
            {job.due_on && ` · Prevista ${new Date(`${job.due_on}T12:00:00`)
              .toLocaleDateString('es-AR')}`}
          </small>
        </div>
        <span className={`production-badge ${job.status}`}>
          {{ queued: 'En cola', in_progress: 'En proceso', completed: 'Terminada',
            cancelled: 'Cancelada' }[job.status]}
        </span>
      </header>
      <div className="production-job-summary">
        <span>Planificado <strong>{formatQuantity(job.planned_quantity)} {product?.units?.symbol}</strong></span>
        <span>Obtenido <strong>{job.actual_quantity == null ? 'Pendiente'
          : `${formatQuantity(job.actual_quantity)} ${product?.units?.symbol ?? ''}`}</strong></span>
        <span>Insumos pendientes <strong>{remaining} de {expected.length}</strong></span>
        {role === 'admin' && can('finance', 'read') &&
          <span>Costo consumido <strong>$ {money(actualCost)}</strong></span>}
      </div>
      <div className="production-job-expected" aria-label="Avance de insumos">
        {expected.map((entry) => {
          const issued = net.get(entry.component_id) ?? 0;
          const pending = Math.max(0, Number(entry.quantity) - issued);
          return <div className="production-job-progress" key={entry.component_id}>
            <strong>{itemName(entry.component_id)}</strong>
            <span>Previsto: {formatQuantity(entry.quantity)}</span>
            <span>Entregado: {formatQuantity(issued.toFixed(6))}</span>
            <span className={pending > 0.000001 ? 'production-awaiting' : 'production-ok'}>
              {pending > 0.000001 ? `Falta: ${formatQuantity(pending.toFixed(6))}`
                : 'Entrega cubierta'}
            </span>
          </div>;
        })}
        {[...net].filter(([id, quantity]) => quantity > 0.000001
          && !expected.some((entry) => entry.component_id === id)).map(([id, quantity]) => (
          <div className="production-job-progress" key={id}>
            <strong>{itemName(id)} · adicional</strong>
            <span>Entregado: {formatQuantity(quantity.toFixed(6))}</span>
          </div>
        ))}
      </div>
      {remitos.length > 0 && <p className="production-linked-notes">
        Remitos: {remitos.map((note, index) => <span key={note.id}>
          {index > 0 && ' · '}
          {can('stock', 'read') ? <Link to="/inventory/delivery-notes">
            Nº {note.number}</Link> : `Nº ${note.number}`}
          {note.status === 'voided' && ' (anulado)'}
        </span>)}
      </p>}
      <div className="production-job-buttons">
        <button type="button" className="button outline" onClick={() => onPrint(job)}>
          <Download size={16} /> PDF del proceso
        </button>
        {job.status === 'queued' && can('production', 'update') &&
          <button type="button" className="button outline" disabled={busy} onClick={start}>
            <Play size={16} /> Iniciar
          </button>}
        {active && canDeliver && <>
          <button type="button" className="button primary" onClick={() => setAction('remito')}>
            <Truck size={16} /> Remito de entrega
          </button>
          <button type="button" className="button outline" onClick={() => setAction('issue')}>
            <PackagePlus size={16} /> Agregar insumo sin remito
          </button>
        </>}
        {job.status === 'in_progress' && can('production', 'insert')
          && can('stock', 'insert') &&
          <button type="button" className="button outline" onClick={() => setAction('finish')}>
            <CheckCircle2 size={16} /> Terminar fabricación
          </button>}
        {active && can('production', 'update') &&
          <button type="button" className="button outline" onClick={() => setAction('cancel')}>
            <XCircle size={16} /> Cancelar orden
          </button>}
      </div>
      <details className="production-movements">
        <summary>Historial de insumos ({events.length} movimientos)</summary>
        {events.length === 0 && <p>Todavía no se entregaron materiales.</p>}
        {events.map((entry) => {
          const returned = events.filter((row) => row.kind === 'return'
            && row.issue_id === entry.id).reduce((sum, row) => sum + Number(row.quantity), 0);
          const open = entry.kind === 'issue' ? Number(entry.quantity) - returned : 0;
          return <div className="production-job-event" key={entry.id}>
            <span>{entry.kind === 'issue' ? 'Entregado' : 'Devuelto'} · {itemName(entry.component_id)}
              {' · '}{formatQuantity(entry.quantity)}
              {entry.lot_code && ` · Lote ${entry.lot_code}`}
            </span>
            <small>{entry.note} · {new Date(entry.created_at).toLocaleString('es-AR')}</small>
            {open > 0.000001 && job.status === 'in_progress'
              && can('production', 'update') && can('stock', 'insert') &&
              <button type="button" className="production-link" onClick={() => openReturn(entry)}>
                <RotateCcw size={15} /> Devolver hasta {formatQuantity(open)}
              </button>}
          </div>;
        })}
      </details>
      <ActionDialog open={action === 'remito'} title="Entrega de materiales para fabricación"
        description="Un remito vinculado registra los consumos y descuenta stock una sola vez."
        busy={issuing} onClose={() => { if (!issuing) setAction(null); }}>
        {action === 'remito' && <DeliveryNoteComposer
          items={items} warehouses={warehouses} jobs={[job]}
          initialKind="production" initialJobId={job.id}
          onCancel={() => { if (!issuing) setAction(null); }}
          onBusyChange={setIssuing}
          onIssued={async () => { setAction(null); await onUpdated(); }} />}
      </ActionDialog>
      <ActionDialog open={action === 'issue'} title="Agregar insumo sin remito"
        description="La entrega descuenta stock y se suma al consumo de la orden."
        busy={busy} onClose={() => setAction(null)}>
        <form onSubmit={saveIssue}>
          <label>Buscar insumo
            <input type="search" value={itemSearch}
              placeholder="Filtrar por nombre o código"
              onChange={(event) => setItemSearch(event.target.value)} />
          </label>
          <label>Material o semielaborado
            <select required value={issue.componentId}
              onChange={(event) => chooseIssue(event.target.value)}>
              <option value="">Seleccionar…</option>
              {options.map((item) => <option value={item.id} key={item.id}>
                {item.code} · {item.name}
              </option>)}
            </select>
          </label>
          <div className="production-two-columns">
            <label>Depósito de origen
              <select required value={issue.warehouseId}
                onChange={(event) => setIssue((current) => ({ ...current,
                  warehouseId: event.target.value, lotCode: '' }))}>
                <option value="">Seleccionar…</option>
                {warehouses.map((entry) => <option key={entry.id} value={entry.id}>
                  {entry.name}
                </option>)}
              </select>
            </label>
            <label>Cantidad entregada
              <input required type="number" min="0.000001" step="0.000001"
                value={issue.quantity} onChange={(event) => setIssue((current) => ({
                  ...current, quantity: event.target.value,
                }))} />
            </label>
          </div>
          {chosen?.track_lots && <label>Lote de origen
            <select required value={issue.lotCode} onChange={(event) =>
              setIssue((current) => ({ ...current, lotCode: event.target.value }))}>
              <option value="">Seleccionar…</option>
              {(lotsQuery.data ?? []).filter((lot) => Number(lot.available) > 0)
                .map((lot) => <option key={lot.id} value={lot.code}>
                  {lot.code} · {formatQuantity(lot.available)} disponibles
                </option>)}
            </select>
          </label>}
          {chosen && issue.warehouseId && <small>Disponible: {formatQuantity(available)}</small>}
          <label>Motivo / detalle
            <input required minLength={3} maxLength={300} value={issue.note}
              onChange={(event) => setIssue((current) => ({ ...current,
                note: event.target.value,
              }))} />
          </label>
          {(balanceQuery.error || lotsQuery.error) &&
            <p role="alert" className="error">{friendlyError(balanceQuery.error || lotsQuery.error)}</p>}
          <div className="erp-action-dialog-actions">
            <button type="button" className="button outline" disabled={busy}
              onClick={() => setAction(null)}>Volver</button>
            <button className="button primary" disabled={busy || !canDeliver
              || !issue.componentId || !issue.warehouseId || !validQuantity(issue.quantity)
              || Number(issue.quantity) > available || (chosen?.track_lots && !issue.lotCode)}>
              Registrar entrega
            </button>
          </div>
        </form>
      </ActionDialog>
      <ActionDialog open={action === 'return'} title="Devolver insumo"
        description="El material vuelve al mismo depósito y lote del que salió."
        busy={busy} onClose={() => setAction(null)}>
        <form onSubmit={saveReturn}>
          <p>{returnEntry && itemName(returnEntry.component_id)}</p>
          <label>Cantidad a devolver
            <input required type="number" min="0.000001" step="0.000001"
              value={returnQuantity} onChange={(event) => setReturnQuantity(event.target.value)} />
          </label>
          <label>Motivo
            <input required minLength={3} maxLength={300} value={returnNote}
              onChange={(event) => setReturnNote(event.target.value)} />
          </label>
          <div className="erp-action-dialog-actions">
            <button type="button" className="button outline" disabled={busy}
              onClick={() => setAction(null)}>Volver</button>
            <button className="button primary" disabled={busy || !validQuantity(returnQuantity)}>
              Devolver al stock
            </button>
          </div>
        </form>
      </ActionDialog>
      <ActionDialog open={action === 'finish'} title="Terminar fabricación"
        description="Se ingresará al stock solamente la cantidad real obtenida."
        busy={busy} onClose={() => setAction(null)}>
        <form onSubmit={finish}>
          <label>Cantidad real fabricada
            <input required type="number" min="0.000001" step="0.000001"
              value={actual} onChange={(event) => setActual(event.target.value)} />
          </label>
          <div className="production-two-columns">
            <label>Lote del producto {product?.track_lots ? '(obligatorio)' : '(no aplica)'}
              <input required={!!product?.track_lots} disabled={!product?.track_lots}
                maxLength={80} value={outputLot} placeholder="Ej.: FAB-2026-001"
                onChange={(event) => setOutputLot(event.target.value)} />
            </label>
            <label>Vencimiento (opcional)
              <input type="date" disabled={!product?.track_lots} value={expiresOn}
                onChange={(event) => setExpiresOn(event.target.value)} />
            </label>
          </div>
          {mismatch && <label>Motivo de la diferencia frente a la fórmula
            <textarea required minLength={5} maxLength={400} value={varianceNote}
              onChange={(event) => setVarianceNote(event.target.value)} />
          </label>}
          <div className="erp-action-dialog-actions">
            <button type="button" className="button outline" disabled={busy}
              onClick={() => setAction(null)}>Volver</button>
            <button className="button primary" disabled={busy || !validQuantity(actual)
              || (mismatch && varianceNote.trim().length < 5)}>
              Ingresar producto al stock
            </button>
          </div>
        </form>
      </ActionDialog>
      <ActionDialog open={action === 'cancel'} title="¿Seguro que querés cancelar la orden?"
        description="Devolvé todos los insumos pendientes antes de cancelar."
        busy={busy} onClose={() => setAction(null)}>
        <form onSubmit={cancel}>
          <label>Motivo de cancelación
            <textarea required minLength={5} maxLength={300} value={cancelReason}
              onChange={(event) => setCancelReason(event.target.value)} />
          </label>
          <div className="erp-action-dialog-actions">
            <button type="button" className="button outline" disabled={busy}
              onClick={() => setAction(null)}>Volver</button>
            <button className="button erp-confirm-danger"
              disabled={busy || cancelReason.trim().length < 5}>Cancelar orden</button>
          </div>
        </form>
      </ActionDialog>
    </article>
  );
}

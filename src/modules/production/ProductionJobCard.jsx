import { useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Download, Plus, RotateCcw, CheckCircle2 } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import { formatQuantity } from '../inventory/stockNumber';
import { listStockLots } from '../../services/stock';
import {
  cancelProductionJob, finishProductionJob, issueProductionMaterial,
  listProductionBalances, returnProductionMaterial, startProductionJob,
} from '../../services/production';

const initialIssue = () => ({ componentId: '', warehouseId: '', lotCode: '',
  quantity: '', note: 'Insumo retirado para fabricación' });
const amount = (value) => Number(value).toLocaleString('es-AR', {
  minimumFractionDigits: 2, maximumFractionDigits: 2,
});
const validQuantity = (value) => /^\d+(?:\.\d{1,6})?$/.test(value)
  && Number(value) > 0 && Number(value) < 1000000000000;

export default function ProductionJobCard({ job, items, warehouses, onUpdated, onPrint }) {
  const { activeCompanyId, can } = useAuth();
  const [issue, setIssue] = useState(initialIssue);
  const [itemSearch, setItemSearch] = useState('');
  const [returnDraft, setReturnDraft] = useState({});
  const [actual, setActual] = useState(String(job.actual_quantity ?? job.planned_quantity));
  const [outputLot, setOutputLot] = useState(job.output_lot ?? '');
  const [expiresOn, setExpiresOn] = useState(job.output_expiry ?? '');
  const [varianceNote, setVarianceNote] = useState(job.variance_note ?? '');
  const [cancelReason, setCancelReason] = useState('');
  const [confirmCancel, setConfirmCancel] = useState(false);
  const [busy, setBusy] = useState(false);
  const requests = useRef(new Map());
  const events = [...(job.production_job_events ?? [])].sort((a, b) =>
    new Date(a.created_at) - new Date(b.created_at));
  const eligible = items.filter((item) => item.item_type === 'raw_material'
    || item.item_type === 'semi_finished');
  const chosen = items.find((item) => item.id === issue.componentId);
  const expected = job.formula_snapshot ?? [];
  const net = new Map();
  for (const event of events) {
    net.set(event.component_id, (net.get(event.component_id) ?? 0)
      + (event.kind === 'issue' ? 1 : -1) * Number(event.quantity));
  }
  const mismatch = Math.abs(Number(actual) - Number(job.planned_quantity)) > 0.000001
    || expected.some((line) => Math.abs((net.get(line.component_id) ?? 0)
      - Number(line.quantity)) > 0.000001)
    || [...net].some(([id, quantity]) => quantity > 0.000001
      && !expected.some((line) => line.component_id === id));
  const actualCost = events.reduce((sum, event) => sum
    + (event.kind === 'issue' ? 1 : -1)
    * Number(event.quantity) * Number(event.unit_cost), 0);
  const balanceQuery = useQuery({
    queryKey: ['job-material-balance', activeCompanyId, issue.componentId],
    queryFn: () => listProductionBalances(activeCompanyId, [issue.componentId]),
    enabled: Boolean(activeCompanyId && issue.componentId),
  });
  const lotsQuery = useQuery({
    queryKey: ['job-material-lots', activeCompanyId, issue.componentId, issue.warehouseId],
    queryFn: () => listStockLots(activeCompanyId, issue.componentId, issue.warehouseId),
    enabled: Boolean(activeCompanyId && chosen?.track_lots && issue.warehouseId),
  });
  const stock = chosen?.track_lots
    ? Number((lotsQuery.data ?? []).find((entry) => entry.code === issue.lotCode)?.available ?? 0)
    : Number((balanceQuery.data ?? []).find((entry) => entry.warehouse_id === issue.warehouseId)?.quantity ?? 0);
  const issueReady = issue.componentId && issue.warehouseId && validQuantity(issue.quantity)
    && issue.note.trim().length >= 3 && Number(issue.quantity) <= stock
    && (!chosen?.track_lots || issue.lotCode);

  function requestFor(key, fingerprint) {
    const old = requests.current.get(key);
    if (old?.fingerprint === fingerprint) return old.id;
    const id = crypto.randomUUID();
    requests.current.set(key, { fingerprint, id });
    return id;
  }

  async function saveIssue(event) {
    event.preventDefault();
    if (!issueReady || busy) return;
    setBusy(true);
    try {
      const key = 'issue';
      await issueProductionMaterial(activeCompanyId, job.id, issue,
        requestFor(key, JSON.stringify(issue)));
      requests.current.delete(key);
      setIssue(initialIssue());
      await onUpdated();
      notifySuccess('Insumo retirado', 'Se descontó del stock y quedó asociado a la orden.');
    } catch (error) { notifyError(error); } finally { setBusy(false); }
  }

  async function saveReturn(entry, openQuantity) {
    const draft = returnDraft[entry.id] ?? {};
    if (!validQuantity(draft.quantity ?? '') || Number(draft.quantity) > openQuantity
      || (draft.note ?? '').trim().length < 3 || busy) {
      notifyError(new Error('Revisá la cantidad y el motivo de la devolución.'));
      return;
    }
    setBusy(true);
    try {
      const key = `return:${entry.id}`;
      await returnProductionMaterial(activeCompanyId, job.id, entry.id,
        draft.quantity, draft.note, requestFor(key, JSON.stringify(draft)));
      requests.current.delete(key);
      setReturnDraft((current) => ({ ...current, [entry.id]: undefined }));
      await onUpdated();
      notifySuccess('Insumo devuelto', 'Volvió al depósito y lote originales.');
    } catch (error) { notifyError(error); } finally { setBusy(false); }
  }

  async function finish(event) {
    event.preventDefault();
    if (!validQuantity(actual) || (mismatch && varianceNote.trim().length < 5)
      || (items.find((item) => item.id === job.product_id)?.track_lots && !outputLot.trim())
      || busy) return;
    setBusy(true);
    try {
      const values = { actualQuantity: actual, outputLot, expiresOn, varianceNote };
      await finishProductionJob(activeCompanyId, job.id, values,
        requestFor('finish', JSON.stringify(values)));
      requests.current.delete('finish');
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

  async function cancel() {
    if (cancelReason.trim().length < 5 || busy) return;
    setBusy(true);
    try {
      await cancelProductionJob(activeCompanyId, job.id, cancelReason);
      setConfirmCancel(false);
      await onUpdated();
      notifySuccess('Orden cancelada');
    } catch (error) { notifyError(error); } finally { setBusy(false); }
  }

  return (
    <article className="production-job">
      <header className="production-job-head">
        <div>
          <strong>{items.find((item) => item.id === job.product_id)?.name ?? 'Producto'}</strong>
          <small>Orden {job.id.slice(0, 8).toUpperCase()} · Fórmula v{job.formula_version}</small>
        </div>
        <span className={`production-badge ${job.status}`}>
          {{ queued: 'En cola', in_progress: 'En proceso', completed: 'Terminada',
            cancelled: 'Cancelada' }[job.status]}
        </span>
      </header>
      <p className="production-job-summary">
        Objetivo: <strong>{formatQuantity(job.planned_quantity)}</strong> ·
        Real: <strong>{job.actual_quantity == null ? 'Pendiente'
          : formatQuantity(job.actual_quantity)}</strong> ·
        Costo real: <strong>$ {amount(actualCost)}</strong>
      </p>
      <div className="production-job-buttons">
        <button type="button" className="button outline" onClick={() => onPrint(job)}>
          <Download size={15} /> Descargar PDF
        </button>
        {job.status === 'queued' && can('production', 'update') && (
          <button className="button outline" type="button" disabled={busy} onClick={start}>
            Iniciar fabricación
          </button>
        )}
      </div>
      <details>
        <summary>Ver insumos y movimientos</summary>
        <div className="production-job-expected">
          {expected.map((entry) => (
            <p key={entry.component_id}>
              {items.find((item) => item.id === entry.component_id)?.name ?? 'Insumo'}:
              {' '}previsto {formatQuantity(entry.quantity)} ·
              aplicado {formatQuantity((net.get(entry.component_id) ?? 0).toFixed(6))}
            </p>
          ))}
          {[...net].filter(([id, quantity]) => quantity > 0
            && !expected.some((entry) => entry.component_id === id)).map(([id, quantity]) => (
            <p key={id}>Extra: {items.find((item) => item.id === id)?.name ?? 'Insumo'} ·
              {' '}{formatQuantity(quantity.toFixed(6))}</p>
          ))}
        </div>
        {events.map((entry) => {
          const open = entry.kind === 'issue' ? Number(entry.quantity)
            - events.filter((row) => row.kind === 'return' && row.issue_id === entry.id)
              .reduce((total, row) => total + Number(row.quantity), 0) : 0;
          return <div className="production-job-event" key={entry.id}>
            <span>{entry.kind === 'issue' ? 'Consumido' : 'Devuelto'} ·
              {' '}{items.find((item) => item.id === entry.component_id)?.name ?? 'Insumo'} ·
              {' '}{formatQuantity(entry.quantity)}
              {entry.lot_code ? ` · Lote ${entry.lot_code}` : ''}</span>
            <small>{entry.note} · {new Date(entry.created_at).toLocaleString('es-AR')}</small>
            {open > 0.000001 && job.status === 'in_progress'
              && can('production', 'update') && can('stock', 'insert') && (
              <div className="production-return-form">
                <label>Devolver al depósito original
                  <input type="number" min="0.000001" step="0.000001" max={open}
                    placeholder={`Hasta ${formatQuantity(open)}`}
                    value={returnDraft[entry.id]?.quantity ?? ''}
                    onChange={(event) => setReturnDraft((current) => ({
                      ...current,
                      [entry.id]: { ...current[entry.id], quantity: event.target.value },
                    }))} />
                </label>
                <label>Motivo
                  <input placeholder="No utilizado en la fabricación"
                    maxLength={300} value={returnDraft[entry.id]?.note ?? ''}
                    onChange={(event) => setReturnDraft((current) => ({
                      ...current,
                      [entry.id]: { ...current[entry.id], note: event.target.value },
                    }))} />
                </label>
                <button type="button" className="button outline" disabled={busy}
                  onClick={() => saveReturn(entry, open)}>
                  <RotateCcw size={15} /> Devolver
                </button>
              </div>
            )}
          </div>;
        })}
      </details>
      {['queued', 'in_progress'].includes(job.status) && (
        <div className="production-job-work">
          <h3>Registrar insumos realmente utilizados</h3>
          <p>Podés añadir componentes de la fórmula o insumos extra. Cada salida
            descuenta stock; los no utilizados se devuelven desde el movimiento.</p>
          <form onSubmit={saveIssue}>
            <label>Buscar insumo
              <input value={itemSearch} onChange={(event) => setItemSearch(event.target.value)}
                placeholder="Filtrar por nombre o código" />
            </label>
            <label>Materia prima o semielaborado
              <select required value={issue.componentId} onChange={(event) => {
                const componentId = event.target.value;
                const expectedRow = expected.find((row) => row.component_id === componentId);
                const remaining = Number(expectedRow?.quantity ?? 0)
                  - Number(net.get(componentId) ?? 0);
                setIssue((current) => ({ ...current, componentId, warehouseId: '',
                  lotCode: '', quantity: remaining > 0 ? String(Number(remaining.toFixed(6))) : '' }));
              }}>
                <option value="">Seleccionar insumo…</option>
                {eligible.filter((item) => `${item.code} ${item.name}`.toLowerCase()
                  .includes(itemSearch.toLowerCase())).map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.code} · {item.name}
                  </option>
                ))}
                {chosen && !`${chosen.code} ${chosen.name}`.toLowerCase()
                  .includes(itemSearch.toLowerCase()) && (
                  <option value={chosen.id}>{chosen.code} · {chosen.name}</option>
                )}
              </select>
            </label>
            <div className="production-two-columns">
              <label>Depósito de origen
                <select required value={issue.warehouseId} onChange={(event) =>
                  setIssue((current) => ({ ...current, warehouseId: event.target.value,
                    lotCode: '' }))}>
                  <option value="">Seleccionar…</option>
                  {warehouses.map((warehouse) => <option key={warehouse.id}
                    value={warehouse.id}>{warehouse.name}</option>)}
                </select>
              </label>
              <label>Cantidad retirada
                <input type="number" required min="0.000001" step="0.000001"
                  value={issue.quantity} onChange={(event) =>
                    setIssue((current) => ({ ...current, quantity: event.target.value }))} />
              </label>
            </div>
            {chosen?.track_lots && <label>Lote a retirar
              <select required value={issue.lotCode} onChange={(event) =>
                setIssue((current) => ({ ...current, lotCode: event.target.value }))}>
                <option value="">Seleccionar lote…</option>
                {(lotsQuery.data ?? []).filter((entry) => Number(entry.available) > 0)
                  .map((entry) => <option key={entry.id} value={entry.code}>
                    {entry.code} · {formatQuantity(entry.available)} disponibles
                  </option>)}
              </select>
            </label>}
            {issue.componentId && issue.warehouseId && <small className={
              Number(issue.quantity) <= stock ? 'production-ok' : 'production-error'}>
              Disponible: {formatQuantity(stock.toFixed(6))} {chosen?.units?.symbol}
            </small>}
            <label>Nota del consumo
              <input required minLength={3} maxLength={300} value={issue.note}
                onChange={(event) => setIssue((current) => ({
                  ...current, note: event.target.value,
                }))} />
            </label>
            {(balanceQuery.error || lotsQuery.error) && <p role="alert" className="production-error">
              {friendlyError(balanceQuery.error || lotsQuery.error)}
            </p>}
            <button className="button outline" disabled={busy || !issueReady}>
              <Plus size={15} /> Registrar consumo parcial
            </button>
          </form>
        </div>
      )}
      {job.status === 'in_progress' && (
        <form className="production-job-finish" onSubmit={finish}>
          <h3>Terminar fabricación</h3>
          <p>El stock del producto aparecerá recién al confirmar el rendimiento real.</p>
          <label>Cantidad real obtenida
            <input required type="number" min="0.000001" step="0.000001"
              value={actual} onChange={(event) => setActual(event.target.value)} />
          </label>
          <div className="production-two-columns">
            <label>Lote del producto fabricado
              <input value={outputLot} required={Boolean(items.find((item) =>
                item.id === job.product_id)?.track_lots)}
                disabled={!items.find((item) => item.id === job.product_id)?.track_lots}
                maxLength={80}
                placeholder="Ej. FAB-2026-001"
                onChange={(event) => setOutputLot(event.target.value)} />
            </label>
            <label>Vencimiento del lote (opcional)
              <input type="date" value={expiresOn}
                disabled={!items.find((item) => item.id === job.product_id)?.track_lots}
                onChange={(event) => setExpiresOn(event.target.value)} />
            </label>
          </div>
          {mismatch && <label>¿Por qué cambió el rendimiento o el consumo?
            <input required minLength={5} maxLength={400} value={varianceNote}
              onChange={(event) => setVarianceNote(event.target.value)}
              placeholder="Ej. merma de 10 kg durante el secado" />
          </label>}
          <button className="button primary" disabled={busy || !validQuantity(actual)
            || (mismatch && varianceNote.trim().length < 5)}>
            <CheckCircle2 size={16} /> Ingresar {formatQuantity(actual || 0)} al stock
          </button>
        </form>
      )}
      {['queued', 'in_progress'].includes(job.status) && can('production', 'update') && (
        <div className="production-job-cancel">
          <label>Motivo para cancelar (mín. 5 caracteres)
            <input maxLength={300} value={cancelReason}
              onChange={(event) => setCancelReason(event.target.value)} />
          </label>
          <button type="button" className="production-link"
            disabled={busy || cancelReason.trim().length < 5}
            onClick={() => setConfirmCancel(true)}>Cancelar orden</button>
          <small>Antes de cancelar, devolvé todos los insumos retirados.</small>
        </div>
      )}
      <ConfirmDeleteDialog open={confirmCancel} busy={busy}
        title="¿Seguro que querés cancelar la orden?"
        description="Los insumos deben estar devueltos al depósito. La orden quedará en el historial."
        confirmLabel="Cancelar orden" onCancel={() => setConfirmCancel(false)}
        onConfirm={cancel} />
    </article>
  );
}

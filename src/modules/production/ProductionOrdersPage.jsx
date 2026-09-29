import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { Factory, Plus, Truck } from 'lucide-react';
import ActionDialog from '../../components/ActionDialog';
import { listDeliveryNotes } from '../../services/deliveryNotes';
import { useAuth } from '../../contexts/AuthContext';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import { formatQuantity } from '../inventory/stockNumber';
import { listStockLots } from '../../services/stock';
import {
  completeProductionNow, createProductionJob, listFormulas,
  listProductionBalances, listProductionItems, listProductionJobs,
  listProductionPlans, listProductionRuns, listProductionReservationLocations,
  listProductionWarehouses,
} from '../../services/production';
import ProductionJobCard from './ProductionJobCard';
import './production.css';

const freshInput = (componentId = '') => ({
  rowId: crypto.randomUUID(), componentId, warehouseId: '', lotCode: '', quantity: '',
});
const validQuantity = (value) => /^\d+(?:\.\d{1,6})?$/.test(String(value))
  && Number(value) > 0 && Number(value) < 1000000000000;

function MaterialRow({ companyId, row, line, item, items, warehouses, onChange, onRemove }) {
  const balancesQuery = useQuery({
    queryKey: ['production-balances', companyId, row.componentId],
    queryFn: () => listProductionBalances(companyId, [row.componentId]),
    enabled: Boolean(companyId && row.componentId),
  });
  const lotsQuery = useQuery({
    queryKey: ['production-lots', companyId, row.componentId, row.warehouseId],
    queryFn: () => listStockLots(companyId, row.componentId, row.warehouseId),
    enabled: Boolean(companyId && item?.track_lots && row.warehouseId),
  });
  const available = item?.track_lots
    ? Number((lotsQuery.data ?? []).find((lot) => lot.code === row.lotCode)?.available ?? 0)
    : Number((balancesQuery.data ?? []).find((balance) =>
      balance.warehouse_id === row.warehouseId)?.quantity ?? 0);
  return (
    <div className="production-material">
      <div className="production-material-header">
        {line ? <strong>{item?.code} · {item?.name}</strong> : (
          <label>Insumo adicional
            <select value={row.componentId} required onChange={(event) =>
              onChange({ componentId: event.target.value, warehouseId: '', lotCode: '' })}>
              <option value="">Elegir insumo…</option>
              {items.filter((entry) => ['raw_material', 'semi_finished'].includes(entry.item_type))
                .map((entry) => <option value={entry.id} key={entry.id}>
                  {entry.code} · {entry.name}
                </option>)}
            </select>
          </label>
        )}
        {line && <span>Teórico: {formatQuantity(line.expected.toFixed(6))} {item?.units?.symbol}</span>}
        {onRemove && <button type="button" className="production-link" onClick={onRemove}>
          Quitar
        </button>}
      </div>
      <div className="production-three-columns">
        <label>Cantidad realmente consumida
          <input type="number" required min="0.000001" step="0.000001"
            value={row.quantity} onChange={(event) => onChange({ quantity: event.target.value })} />
        </label>
        <label>Depósito de origen
          <select required value={row.warehouseId} onChange={(event) =>
            onChange({ warehouseId: event.target.value, lotCode: '' })}>
            <option value="">Elegir depósito…</option>
            {warehouses.map((warehouse) => <option key={warehouse.id} value={warehouse.id}>
              {warehouse.name}
            </option>)}
          </select>
        </label>
        {item?.track_lots && <label>Lote del insumo
          <select required value={row.lotCode} onChange={(event) =>
            onChange({ lotCode: event.target.value })}>
            <option value="">Elegir lote…</option>
            {(lotsQuery.data ?? []).filter((lot) => Number(lot.available) > 0)
              .map((lot) => <option key={lot.id} value={lot.code}>
                {lot.code} · {formatQuantity(lot.available)}
              </option>)}
          </select>
        </label>}
      </div>
      {row.warehouseId && row.componentId && <small className={
        validQuantity(row.quantity) && Number(row.quantity) <= available
          ? 'production-ok' : 'production-error'
      }>
        {formatQuantity(available.toFixed(6))} disponible
        {validQuantity(row.quantity) && Number(row.quantity) > available && ' · falta stock'}
      </small>}
    </div>
  );
}

export default function ProductionOrdersPage() {
  const { activeCompanyId, activeCompany, user, can, role } = useAuth();
  const client = useQueryClient();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const planId = params.get('plan');
  const focusJob = params.get('job');
  const [productId, setProductId] = useState('');
  const [quantity, setQuantity] = useState('1');
  const [actual, setActual] = useState('1');
  const [warehouseId, setWarehouseId] = useState('');
  const [mode, setMode] = useState('queue');
  const [dueOn, setDueOn] = useState('');
  const [note, setNote] = useState('Orden de fabricación');
  const [varianceNote, setVarianceNote] = useState('');
  const [outputLot, setOutputLot] = useState('');
  const [expiresOn, setExpiresOn] = useState('');
  const [inputs, setInputs] = useState([]);
  const [busy, setBusy] = useState(false);
  const [createOpen, setCreateOpen] = useState(Boolean(planId));
  const [requestId, setRequestId] = useState(() => crypto.randomUUID());
  const [finishRequestId, setFinishRequestId] = useState(() => crypto.randomUUID());

  const itemsQuery = useQuery({
    queryKey: ['production-items', user?.id, activeCompanyId],
    queryFn: () => listProductionItems(activeCompanyId), enabled: !!activeCompanyId,
  });
  const formulasQuery = useQuery({
    queryKey: ['production-formulas', user?.id, activeCompanyId],
    queryFn: () => listFormulas(activeCompanyId), enabled: !!activeCompanyId,
  });
  const warehousesQuery = useQuery({
    queryKey: ['production-warehouses', user?.id, activeCompanyId],
    queryFn: () => listProductionWarehouses(activeCompanyId), enabled: !!activeCompanyId,
  });
  const jobsQuery = useQuery({
    queryKey: ['production-jobs', user?.id, activeCompanyId],
    queryFn: () => listProductionJobs(activeCompanyId), enabled: !!activeCompanyId,
  });
  const runsQuery = useQuery({
    queryKey: ['production-runs', user?.id, activeCompanyId],
    queryFn: () => listProductionRuns(activeCompanyId), enabled: !!activeCompanyId,
  });
  const deliveryQuery = useQuery({
    queryKey: ['delivery-notes', user?.id, activeCompanyId],
    queryFn: () => listDeliveryNotes(activeCompanyId),
    enabled: Boolean(activeCompanyId),
  });
  const locationsQuery = useQuery({
    queryKey: ['production-reservation-locations', user?.id, activeCompanyId],
    queryFn: () => listProductionReservationLocations(activeCompanyId),
    enabled: Boolean(activeCompanyId && can('stock', 'read')),
  });
  const plansQuery = useQuery({
    queryKey: ['production-plans', user?.id, activeCompanyId],
    queryFn: () => listProductionPlans(activeCompanyId), enabled: !!(activeCompanyId && planId),
  });
  const items = itemsQuery.data ?? [];
  const formulas = formulasQuery.data ?? [];
  const warehouses = warehousesQuery.data ?? [];
  const jobs = jobsQuery.data ?? [];
  const plan = plansQuery.data?.find((entry) => entry.id === planId);
  const product = items.find((entry) => entry.id === productId);
  const formula = formulas.find((entry) => entry.product_id === productId);
  const byId = Object.fromEntries(items.map((item) => [item.id, item]));
  const theoretical = formula?.production_formula_lines.map((line) => ({
    componentId: line.component_id,
    expected: Number(line.quantity) * Number(quantity) / Number(formula.batch_quantity),
  })) ?? [];

  useEffect(() => {
    setProductId('');
    setWarehouseId('');
    setQuantity('1');
    setActual('1');
    setInputs([]);
    setRequestId(crypto.randomUUID());
    setFinishRequestId(crypto.randomUUID());
  }, [activeCompanyId]);

  useEffect(() => {
    if (!plan) return;
    setProductId(plan.product_id);
    setQuantity(String(plan.quantity));
    setActual(String(plan.quantity));
    setWarehouseId(plan.warehouse_id);
    setDueOn(plan.due_on ?? '');
    setNote(plan.note);
    setInputs([]);
  }, [plan?.id, activeCompanyId]);

  useEffect(() => {
    if (mode !== 'complete' || !formula) return;
    setInputs((current) => {
      const standard = formula.production_formula_lines.map((line) => {
        const previous = current.find((row) => row.componentId === line.component_id);
        return previous ?? {
          ...freshInput(line.component_id),
          quantity: String(Number((Number(line.quantity) * Number(quantity)
            / Number(formula.batch_quantity)).toFixed(6))),
        };
      });
      return [...standard, ...current.filter((row) => row.rowId && !formula.production_formula_lines
        .some((line) => line.component_id === row.componentId))];
    });
  }, [mode, productId, formula?.version, quantity]);

  function refresh() {
    return Promise.all([
      client.invalidateQueries({ queryKey: ['production-jobs', user?.id, activeCompanyId] }),
      client.invalidateQueries({ queryKey: ['production-reservations', user?.id, activeCompanyId] }),
      client.invalidateQueries({ queryKey: ['production-reservation-locations', user?.id, activeCompanyId] }),
      client.invalidateQueries({ queryKey: ['production-dashboard', user?.id, activeCompanyId] }),
      client.invalidateQueries({ queryKey: ['planning-availability'] }),
      client.invalidateQueries({ queryKey: ['production-runs', user?.id, activeCompanyId] }),
      client.invalidateQueries({ queryKey: ['production-plans', user?.id, activeCompanyId] }),
      client.invalidateQueries({ queryKey: ['production-balances'] }),
      client.invalidateQueries({ queryKey: ['planning-balances'] }),
      client.invalidateQueries({ queryKey: ['production-lots'] }),
      client.invalidateQueries({ queryKey: ['job-material-balance'] }),
      client.invalidateQueries({ queryKey: ['job-material-lots'] }),
      client.invalidateQueries({ queryKey: ['stock'] }),
      client.invalidateQueries({ queryKey: ['product-costs'] }),
      client.invalidateQueries({ queryKey: ['delivery-notes', user?.id, activeCompanyId] }),
      client.invalidateQueries({ queryKey: ['erp-dashboard'] }),
      client.invalidateQueries({ queryKey: ['operational-alerts'] }),
      client.invalidateQueries({ queryKey: ['operational-report'] }),
    ]);
  }

  async function submit(event) {
    event.preventDefault();
    if (busy || !formula || !validQuantity(quantity) || !warehouseId
      || !can('production', 'insert') || (mode === 'complete' && !can('stock', 'insert'))
      || (planId && (plan?.status !== 'planned' || jobs.some((job) => job.plan_id === planId)))) return;
    if (mode === 'complete') {
      const mismatch = Math.abs(Number(actual) - Number(quantity)) > 0.000001
        || inputs.some((input) => {
          const expected = theoretical.find((line) => line.componentId === input.componentId);
          return !expected || Math.abs(Number(input.quantity) - expected.expected) > 0.000001;
        });
      if (!validQuantity(actual) || (product?.track_lots && !outputLot.trim())
        || !inputs.length || new Set(inputs.map((input) => input.componentId)).size !== inputs.length
        || inputs.some((input) => !validQuantity(input.quantity)
          || !input.warehouseId || !input.componentId
          || (byId[input.componentId]?.track_lots && !input.lotCode))
        || (mismatch && varianceNote.trim().length < 5)) {
        notifyError(new Error('Revisá cantidades reales, lotes y motivo de las diferencias.'));
        return;
      }
    }
    setBusy(true);
    try {
      if (mode === 'queue') {
        await createProductionJob(activeCompanyId, {
          productId, quantity, warehouseId, dueOn, note, planId,
        }, requestId);
        notifySuccess('Orden creada', 'Se asignó el stock libre a la orden; verificá los faltantes en Disponibilidad.');
      } else {
        await completeProductionNow(activeCompanyId, {
          productId, plannedQuantity: quantity, actualQuantity: actual,
          warehouseId, outputLot, expiresOn, note, varianceNote, inputs, planId,
        }, requestId, finishRequestId);
        notifySuccess('Fabricación completada',
          'Se descontaron los insumos reales y se ingresó la cantidad real fabricada.');
      }
      setRequestId(crypto.randomUUID());
      setFinishRequestId(crypto.randomUUID());
      setProductId('');
      setQuantity('1');
      setActual('1');
      setInputs([]);
      setOutputLot('');
      setVarianceNote('');
      await refresh();
      setCreateOpen(false);
      if (planId) navigate('/production/orders');
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  async function printJob(job) {
    try {
      const { downloadProductionJobPdf } = await import('./productionJobPdf');
      downloadProductionJobPdf(job, items, warehouses, activeCompany?.name);
    } catch (error) { notifyError(error); }
  }

  const planTaken = jobs.some((job) => job.plan_id === planId);
  const canSubmit = can('production', 'insert')
    && (mode === 'queue' || can('stock', 'insert')) && !busy && !!formula && validQuantity(quantity) && !!warehouseId
    && (!planId || (plan?.status === 'planned' && !planTaken
      && formula.version === plan.formula_version));
  const activeJobs = jobs.filter((job) => ['queued', 'in_progress'].includes(job.status));
  const closedJobs = jobs.filter((job) => ['completed', 'cancelled'].includes(job.status));
  const historicRuns = (runsQuery.data ?? []).filter((run) =>
    !jobs.some((job) => job.run_id === run.id));

  return (
    <section className="production-page">
      <div className="production-heading">
        <div>
          <span className="eyebrow">PRODUCCIÓN / ÓRDENES</span>
          <h1>Órdenes de fabricación</h1>
          <p>Programá el trabajo o registrá la fabricación con consumo y rendimiento reales.</p>
        </div>
        <Link className="button" to="/production/formulas">Gestionar fórmulas</Link>
      </div>
      <div className="production-toolbar">
        <button type="button" className="button primary" onClick={() => setCreateOpen(true)}>
          <Plus size={17} /> Nueva orden
        </button>
        {can('stock', 'read') && <Link className="button outline" to="/inventory/delivery-notes">
          <Truck size={17} /> Abrir remitero
        </Link>}
        <Link className="button outline" to="/production/planning">Ver planificación</Link>
      </div>
      <div className="production-overview">
        <article><strong>{activeJobs.filter((job) => job.status === 'queued').length}</strong>
          <span>En cola</span></article>
        <article><strong>{activeJobs.filter((job) => job.status === 'in_progress').length}</strong>
          <span>En proceso</span></article>
        <article><strong>{closedJobs.filter((job) => job.status === 'completed').length}</strong>
          <span>Completadas recientes</span></article>
      </div>
      <div className="production-jobs-heading">
        <h2>Procesos activos</h2>
        <p>Consultá insumos entregados, faltantes y movimientos de cada fabricación.</p>
      </div>
      {jobsQuery.isError && <p className="production-form-error">{friendlyError(jobsQuery.error)}</p>}
      {jobsQuery.isPending && <p className="production-muted">Cargando órdenes…</p>}
      {!jobsQuery.isPending && !activeJobs.length &&
        <p className="production-muted">No hay procesos activos. Creá una orden para comenzar.</p>}
      {activeJobs.map((job) => <div key={job.id} id={`job-${job.id}`}
        className={job.id === focusJob ? 'production-job-focused' : ''}>
        <ProductionJobCard job={job} items={items} warehouses={warehouses}
          allocations={(locationsQuery.data ?? []).filter((row) => row.job_id === job.id)}
          remitos={(deliveryQuery.data ?? []).filter((note) => note.job_id === job.id)}
          onUpdated={refresh} onPrint={printJob} />
      </div>)}
      {!!closedJobs.length && <details className="production-closed"
        open={closedJobs.some((job) => job.id === focusJob) || undefined}>
        <summary>Órdenes finalizadas o canceladas ({closedJobs.length})</summary>
        {closedJobs.map((job) => <div key={job.id} id={`job-${job.id}`}
          className={job.id === focusJob ? 'production-job-focused' : ''}>
          <ProductionJobCard job={job} items={items} warehouses={warehouses}
            remitos={(deliveryQuery.data ?? []).filter((note) => note.job_id === job.id)}
            onUpdated={refresh} onPrint={printJob} />
        </div>)}
      </details>}
      <ActionDialog open={createOpen} busy={busy} title="Nueva orden de fabricación"
        description="Creá una orden en cola o registrá una fabricación ya completada."
        onClose={() => { setCreateOpen(false); if (planId) navigate('/production/orders'); }}>
        <form className="production-card production-create-form" onSubmit={submit}>
          <h2><Factory size={20} /> Nueva orden</h2>
          {planId && <p className="production-muted">Orden basada en un plan de fabricación.</p>}
          {planId && (!plan || plan.status !== 'planned' || planTaken
            || (formula && formula.version !== plan.formula_version)) &&
            <p className="production-form-error" role="alert">
              {plansQuery.isPending ? 'Cargando el plan…' : plansQuery.isError
                ? friendlyError(plansQuery.error)
                : planTaken ? 'Este plan ya tiene una orden vinculada.'
                  : 'El plan no está pendiente o su fórmula cambió.'}
            </p>}
          <label>Producto con fórmula
            <select required value={productId} disabled={!!planId} onChange={(event) => {
              setProductId(event.target.value);
              setInputs([]);
              setRequestId(crypto.randomUUID());
            }}>
              <option value="">Elegir producto…</option>
              {formulas.map((entry) => <option key={entry.product_id} value={entry.product_id}>
                {byId[entry.product_id]?.code} · {byId[entry.product_id]?.name}
              </option>)}
            </select>
          </label>
          <div className="production-two-columns">
            <label>Cantidad teórica a fabricar
              <input required type="number" min="0.000001" step="0.000001"
                disabled={!!planId} value={quantity} onChange={(event) => {
                  setQuantity(event.target.value);
                  setActual(event.target.value);
                  setInputs([]);
                }} />
            </label>
            <label>Depósito de destino
              <select required disabled={!!planId} value={warehouseId}
                onChange={(event) => setWarehouseId(event.target.value)}>
                <option value="">Elegir depósito…</option>
                {warehouses.map((warehouse) => <option key={warehouse.id} value={warehouse.id}>
                  {warehouse.name}
                </option>)}
              </select>
            </label>
          </div>
          <label>Observaciones
            <input required minLength={3} maxLength={400} value={note}
              onChange={(event) => setNote(event.target.value)} />
          </label>
          <div className="production-mode" role="group" aria-label="Modo de fabricación">
            <button type="button" className={mode === 'queue' ? 'selected' : ''}
              onClick={() => setMode('queue')}>Dejar en la cola</button>
            <button type="button" className={mode === 'complete' ? 'selected' : ''}
              onClick={() => setMode('complete')}>Ya está fabricado</button>
          </div>
          {mode === 'queue' ? <>
            <label>Fecha prevista (opcional)
              <input type="date" value={dueOn}
                onChange={(event) => setDueOn(event.target.value)} />
            </label>
            <p className="production-muted">Crear la orden reserva el stock libre sin descontarlo físicamente. Podés crearla aunque falte material; consultá el detalle en «¿Tengo stock para fabricar?». El descuento se produce al entregar insumos.</p>
          </> : <>
            <div className="production-subtitle">Consumo real de insumos</div>
            {inputs.map((row, index) => {
              const line = theoretical.find((entry) => entry.componentId === row.componentId);
              return <MaterialRow key={row.rowId ?? row.componentId}
                companyId={activeCompanyId} row={row} line={line}
                item={byId[row.componentId]} items={items} warehouses={warehouses}
                onChange={(change) => setInputs((current) => current.map((entry, at) =>
                  at === index ? { ...entry, ...change } : entry))}
                onRemove={!line ? () => setInputs((current) => current.filter((_, at) => at !== index)) : null} />;
            })}
            {formula && <button type="button" className="production-link" onClick={() =>
              setInputs((current) => [...current, freshInput()])}>
              <Plus size={16} /> Agregar otro insumo
            </button>}
            <div className="production-subtitle">Resultado de fabricación</div>
            <div className="production-two-columns">
              <label>Cantidad realmente obtenida
                <input required type="number" min="0.000001" step="0.000001"
                  value={actual} onChange={(event) => setActual(event.target.value)} />
              </label>
              <label>Lote del producto terminado {product?.track_lots ? '(obligatorio)' : '(no aplica)'}
                <input value={outputLot} required={!!product?.track_lots}
                  disabled={!product?.track_lots} maxLength={80}
                  placeholder="Ej.: FAB-2026-001" onChange={(event) => setOutputLot(event.target.value)} />
              </label>
            </div>
            <label>Vencimiento del lote (opcional)
              <input type="date" value={expiresOn} disabled={!product?.track_lots}
                onChange={(event) => setExpiresOn(event.target.value)} />
            </label>
            <label>Motivo de diferencias en rendimiento o consumo
              <textarea value={varianceNote} maxLength={400}
                placeholder="Indicá qué cambió respecto de la fórmula prevista"
                onChange={(event) => setVarianceNote(event.target.value)} />
            </label>
          </>}
          <div className="production-actions">
            <span>La fórmula queda guardada con la orden.</span>
            <button className="button primary" disabled={!canSubmit}>
              {busy ? 'Guardando…' : mode === 'queue' ? 'Crear orden' : 'Completar fabricación'}
            </button>
          </div>
        </form>
      </ActionDialog>
      {!!historicRuns.length && <details className="production-card production-archive">
        <summary>Fabricaciones anteriores ({historicRuns.length})</summary>
        {historicRuns.map((run) => <div className="production-history" key={run.id}>
          <strong>{byId[run.product_id]?.name ?? 'Producto'}</strong>
          <span>{formatQuantity(run.quantity)} · {new Date(run.created_at).toLocaleString('es-AR')}</span>
          {role === 'admin' && can('finance', 'read') &&
            <small>Costo registrado: $ {Number(run.estimated_cost).toLocaleString('es-AR')}</small>}
        </div>)}
      </details>}
    </section>
  );
}

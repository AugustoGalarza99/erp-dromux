import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { CalendarDays, ClipboardList, Plus, XCircle } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import { formatQuantity } from '../inventory/stockNumber';
import {
  cancelProductionPlan, checkManufacturingAvailability, createProductionPlan, listFormulas,
  listProductionItems, listProductionJobs, listProductionPlans,
  listProductionWarehouses,
} from '../../services/production';
import './production.css';

const money = (value) => Number(value).toLocaleString('es-AR', { minimumFractionDigits: 2 });

export default function ProductionPlanningPage() {
  const { activeCompanyId, user, can, role } = useAuth();
  const client = useQueryClient();
  const [productId, setProductId] = useState('');
  const [quantity, setQuantity] = useState('1');
  const [warehouseId, setWarehouseId] = useState('');
  const [dueOn, setDueOn] = useState('');
  const [note, setNote] = useState('Orden planificada');
  const [busy, setBusy] = useState(false);
  const [cancelTarget, setCancelTarget] = useState(null);
  const [requestId, setRequestId] = useState(() => crypto.randomUUID());

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
  const plansQuery = useQuery({
    queryKey: ['production-plans', user?.id, activeCompanyId],
    queryFn: () => listProductionPlans(activeCompanyId), enabled: !!activeCompanyId,
  });
  const jobsQuery = useQuery({
    queryKey: ['production-jobs', user?.id, activeCompanyId],
    queryFn: () => listProductionJobs(activeCompanyId), enabled: !!activeCompanyId,
  });
  const jobs = jobsQuery.data ?? [];
  const items = itemsQuery.data ?? [];
  const formulas = formulasQuery.data ?? [];
  const plans = plansQuery.data ?? [];
  const warehouses = warehousesQuery.data ?? [];
  const byId = Object.fromEntries(items.map((item) => [item.id, item]));
  const formula = formulas.find((entry) => entry.product_id === productId);
  const required = formula?.production_formula_lines.map((line) => ({
    componentId: line.component_id,
    quantity: Number(line.quantity) * Number(quantity) / Number(formula.batch_quantity),
  })) ?? [];
  const balancesQuery = useQuery({
    queryKey: ['planning-availability', activeCompanyId, productId, quantity],
    queryFn: () => checkManufacturingAvailability(activeCompanyId, productId, quantity),
    enabled: Boolean(activeCompanyId && formula && can('stock', 'read')
      && Number(quantity) > 0 && Number(quantity) < 1000000000000),
  });
  const balances = balancesQuery.data?.lines ?? [];

  useEffect(() => {
    setProductId('');
    setQuantity('1');
    setWarehouseId('');
    setDueOn('');
    setNote('Orden planificada');
    setRequestId(crypto.randomUUID());
    setCancelTarget(null);
  }, [activeCompanyId]);

  const refresh = () => client.invalidateQueries({
    queryKey: ['production-plans', user?.id, activeCompanyId],
  });

  async function submit(event) {
    event.preventDefault();
    setBusy(true);
    try {
      await createProductionPlan(activeCompanyId, {
        productId, quantity, warehouseId, dueOn, note,
      }, requestId);
      setRequestId(crypto.randomUUID());
      setProductId('');
      setQuantity('1');
      setDueOn('');
      setNote('Orden planificada');
      await refresh();
      notifySuccess('Fabricación planificada', 'Podés abrir una orden y registrar los consumos reales.');
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  async function cancelPlan() {
    if (!cancelTarget) return;
    setBusy(true);
    try {
      await cancelProductionPlan(activeCompanyId, cancelTarget.id);
      await refresh();
      setCancelTarget(null);
      notifySuccess('Plan cancelado');
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="production-page">
      <div className="production-heading">
        <div>
          <span className="eyebrow">PRODUCCIÓN / PLANIFICACIÓN</span>
          <h1>Plan de fabricación</h1>
          <p>Prepará cantidades y fechas. Los insumos se descuentan al retirarlos en fabricación.</p>
        </div>
        <Link className="button" to="/production/orders">Ver órdenes de fabricación</Link>
      </div>
      <div className="production-grid">
        <form className="production-card" onSubmit={submit}>
          <h2><CalendarDays size={20} /> Nueva planificación</h2>
          <label>Producto con fórmula
            <select required value={productId} onChange={(event) => {
              setProductId(event.target.value);
              setRequestId(crypto.randomUUID());
            }}>
              <option value="">Seleccionar producto…</option>
              {formulas.map((entry) => <option key={entry.product_id} value={entry.product_id}>
                {byId[entry.product_id]?.code} · {byId[entry.product_id]?.name}
              </option>)}
            </select>
          </label>
          <div className="production-two-columns">
            <label>Cantidad a fabricar
              <input required type="number" min="0.000001" step="0.000001"
                value={quantity} onChange={(event) => {
                  setQuantity(event.target.value);
                  setRequestId(crypto.randomUUID());
                }} />
            </label>
            <label>Fecha prevista (opcional)
              <input type="date" value={dueOn} onChange={(event) => {
                setDueOn(event.target.value);
                setRequestId(crypto.randomUUID());
              }} />
            </label>
          </div>
          <label>Depósito donde ingresarás el producto
            <select required value={warehouseId} onChange={(event) => {
              setWarehouseId(event.target.value);
              setRequestId(crypto.randomUUID());
            }}>
              <option value="">Seleccionar depósito…</option>
              {warehouses.map((warehouse) => <option key={warehouse.id} value={warehouse.id}>
                {warehouse.name}
              </option>)}
            </select>
          </label>
          {formula && <>
            <div className="production-subtitle">Necesidades previstas</div>
            {balancesQuery.error && <p role="alert" className="production-error">
              {friendlyError(balancesQuery.error)}
            </p>}
            {required.map((line) => {
              const balance = balances.find((entry) => entry.item_id === line.componentId);
              const available = Number(balance?.free ?? 0);
              return <div className="production-planning-line" key={line.componentId}>
                <strong>{byId[line.componentId]?.name}</strong>
                <span>Necesitás {Number.isFinite(line.quantity) ? formatQuantity(line.quantity.toFixed(6)) : '—'} {byId[line.componentId]?.units?.symbol}</span>
                {can('stock', 'read') && <small className={available >= line.quantity ? 'production-ok' : 'production-error'}>
                  {balancesQuery.isPending ? 'Calculando disponibilidad…' :
                    `${formatQuantity(available.toFixed(6))} libre · ${formatQuantity(Number(balance?.reserved ?? 0).toFixed(6))} reservado · ${available >= line.quantity ? 'alcanza' : 'falta stock'}`}
                </small>}
              </div>;
            })}
            <p className="production-muted">El plan todavía no reserva stock. La reserva se asigna al crear la orden de fabricación; el depósito y el lote reales se eligen al entregar insumos.</p>
          </>}
          <label>Observaciones
            <input required minLength={3} maxLength={400} value={note}
              onChange={(event) => { setNote(event.target.value); setRequestId(crypto.randomUUID()); }} />
          </label>
          <div className="production-actions">
            <span>Guardar el plan no modifica existencias.</span>
            <button className="button primary" disabled={busy || !can('production', 'insert')}>
              <Plus size={17} /> {busy ? 'Guardando…' : 'Crear plan'}
            </button>
          </div>
        </form>
        <aside className="production-card">
          <h2><ClipboardList size={20} /> Planes recientes</h2>
          {plansQuery.isError && <p className="production-error">{friendlyError(plansQuery.error)}</p>}
          {!plans.length && <p className="production-muted">Todavía no hay órdenes planificadas.</p>}
          {plans.map((plan) => {
            const currentFormula = formulas.find((entry) => entry.product_id === plan.product_id);
            const changed = currentFormula?.version !== plan.formula_version;
            const job = jobs.find((entry) => entry.plan_id === plan.id);
            return <div className="production-history" key={plan.id}>
              <div className="production-plan-title">
                <strong>{byId[plan.product_id]?.name ?? 'Producto'}</strong>
                <span className={`production-badge ${plan.status}`}>{
                  { planned: 'Pendiente', completed: 'Completado', cancelled: 'Cancelado' }[plan.status]
                }</span>
              </div>
              <span>{formatQuantity(plan.quantity)} {byId[plan.product_id]?.units?.symbol} · {plan.due_on ? `Previsto: ${new Date(`${plan.due_on}T12:00:00`).toLocaleDateString('es-AR')}` : 'Sin fecha'}</span>
              <small>Fórmula v{plan.formula_version}
        {role === 'admin' && can('finance', 'read')
          ? ` · Costo previsto $ ${money(plan.estimated_cost)}` : ''}
      </small>
              <details><summary>Insumos previstos</summary>
                {plan.component_snapshot.map((line) => <p key={line.component_id}>
                  {byId[line.component_id]?.name ?? 'Insumo'} · {formatQuantity(line.quantity)}
                </p>)}
              </details>
              {plan.status === 'planned' && <div className="production-plan-actions">
                {job ? <Link className="button primary" to={`/production/orders?job=${job.id}`}>
                  Ver orden · {job.status === 'queued' ? 'En cola' : 'En proceso'}
                </Link> : changed ? <small className="production-error">La fórmula cambió. Creá un plan nuevo.</small> :
                  <Link className="button primary" to={`/production/orders?plan=${plan.id}`}>
                    Crear orden de fabricación
                  </Link>}
                {!job && can('production', 'update') && <button type="button" className="production-link"
                  onClick={() => setCancelTarget(plan)}><XCircle size={15} /> Cancelar plan</button>}
              </div>}
            </div>;
          })}
        </aside>
      </div>
      <ConfirmDeleteDialog open={!!cancelTarget} title="¿Seguro que quieres cancelar este plan?"
        description="El plan quedará en el historial como cancelado. No se modificará el stock."
        confirmLabel="Cancelar plan" busy={busy} onCancel={() => setCancelTarget(null)}
        onConfirm={cancelPlan} />
    </section>
  );
}

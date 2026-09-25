import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { CalendarDays, ClipboardList, Plus, XCircle } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog';
import { notifyError, notifySuccess } from '../../lib/notifications';
import { formatQuantity } from '../inventory/stockNumber';
import {
  cancelProductionPlan, createProductionPlan, listFormulas,
  listProductionBalances, listProductionItems, listProductionPlans,
  listProductionWarehouses,
} from '../../services/production';
import './production.css';

const money = (value) => Number(value).toLocaleString('es-AR', { minimumFractionDigits: 2 });

export default function ProductionPlanningPage() {
  const { activeCompanyId, user, can } = useAuth();
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
    queryKey: ['planning-balances', activeCompanyId, productId],
    queryFn: () => listProductionBalances(activeCompanyId, required.map((line) => line.componentId)),
    enabled: !!(activeCompanyId && formula),
  });
  const balances = balancesQuery.data ?? [];

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
      notifySuccess('Fabricación planificada', 'Podés completarla cuando tengas los insumos.');
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
          <p>Prepará cantidades y fechas. El stock se descuenta al completar la orden.</p>
        </div>
        <Link className="button" to="/production/orders">Fabricación directa</Link>
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
            {required.map((line) => {
              const available = balances.filter((balance) => balance.item_id === line.componentId)
                .reduce((sum, balance) => sum + Number(balance.quantity), 0);
              return <div className="production-planning-line" key={line.componentId}>
                <strong>{byId[line.componentId]?.name}</strong>
                <span>Necesitás {Number.isFinite(line.quantity) ? formatQuantity(line.quantity.toFixed(6)) : '—'} {byId[line.componentId]?.units?.symbol}</span>
                <small className={available >= line.quantity ? 'production-ok' : 'production-error'}>
                  {formatQuantity(available.toFixed(6))} en todos los depósitos ·
                  {available >= line.quantity ? ' disponible' : ' falta stock'}
                </small>
              </div>;
            })}
            <p className="production-muted">El stock total es orientativo. Al completar elegirás el depósito y un lote por cada insumo.</p>
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
          {plansQuery.isError && <p className="production-error">{plansQuery.error.message}</p>}
          {!plans.length && <p className="production-muted">Todavía no hay órdenes planificadas.</p>}
          {plans.map((plan) => {
            const currentFormula = formulas.find((entry) => entry.product_id === plan.product_id);
            const changed = currentFormula?.version !== plan.formula_version;
            return <div className="production-history" key={plan.id}>
              <div className="production-plan-title">
                <strong>{byId[plan.product_id]?.name ?? 'Producto'}</strong>
                <span className={`production-badge ${plan.status}`}>{
                  { planned: 'Pendiente', completed: 'Completado', cancelled: 'Cancelado' }[plan.status]
                }</span>
              </div>
              <span>{formatQuantity(plan.quantity)} {byId[plan.product_id]?.units?.symbol} · {plan.due_on ? `Previsto: ${new Date(`${plan.due_on}T12:00:00`).toLocaleDateString('es-AR')}` : 'Sin fecha'}</span>
              <small>Fórmula v{plan.formula_version} · Costo previsto $ {money(plan.estimated_cost)}</small>
              <details><summary>Insumos previstos</summary>
                {plan.component_snapshot.map((line) => <p key={line.component_id}>
                  {byId[line.component_id]?.name ?? 'Insumo'} · {formatQuantity(line.quantity)}
                </p>)}
              </details>
              {plan.status === 'planned' && <div className="production-plan-actions">
                {changed ? <small className="production-error">La fórmula cambió. Creá un plan nuevo.</small> :
                  <Link className="button primary" to={`/production/orders?plan=${plan.id}`}>
                    Completar fabricación
                  </Link>}
                {can('production', 'update') && <button type="button" className="production-link"
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

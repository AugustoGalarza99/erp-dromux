import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { Factory, PackageCheck } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { notifyError, notifySuccess } from '../../lib/notifications';
import { formatQuantity } from '../inventory/stockNumber';
import { listStockLots } from '../../services/stock';
import {
  completeProductionPlan, listFormulas, listProductionBalances, listProductionItems,
  listProductionPlans, listProductionRuns, listProductionWarehouses, postProductionRun,
} from '../../services/production';
import './production.css';

function ComponentInput({ companyId, line, item, warehouses, warehouseId, value, onChange, requiredQuantity }) {
  const lotsQuery = useQuery({
    queryKey: ['production-lots', companyId, line.component_id, value.warehouseId],
    queryFn: () => listStockLots(companyId, line.component_id, value.warehouseId),
    enabled: !!(companyId && value.warehouseId && item?.track_lots),
  });
  const lots = (lotsQuery.data ?? []).filter((lot) => Number(lot.available) > 0);
  const selectedLot = lots.find((lot) => lot.code === value.lotCode);
  const available = item?.track_lots ? Number(selectedLot?.available ?? 0) : Number(warehouseId ?? 0);
  const enough = Number.isFinite(requiredQuantity) && requiredQuantity > 0 && available >= requiredQuantity;
  return (
    <div className="production-material">
      <div className="production-material-header">
        <strong>{item?.code} · {item?.name}</strong>
        <span>Requiere {Number.isFinite(requiredQuantity) ? formatQuantity(requiredQuantity.toFixed(6)) : '—'} {item?.units?.symbol}</span>
      </div>
      <div className="production-material-fields">
        <label>Depósito de origen
          <select value={value.warehouseId || ''} required onChange={(event) => onChange({ warehouseId: event.target.value, lotCode: '', lotAvailable: 0 })}>
            <option value="">Seleccionar…</option>
            {warehouses.map((warehouse) => <option key={warehouse.id} value={warehouse.id}>{warehouse.name}</option>)}
          </select>
        </label>
        {item?.track_lots && <label>Lote a consumir
          <select required value={value.lotCode || ''} onChange={(event) => {
            const lot = lots.find((entry) => entry.code === event.target.value);
            onChange({ lotCode: event.target.value, lotAvailable: Number(lot?.available ?? 0) });
          }}>
            <option value="">Seleccionar lote…</option>
            {lots.map((lot) => <option key={lot.id} value={lot.code}>{lot.code} · {formatQuantity(lot.available)} disponibles</option>)}
          </select>
        </label>}
      </div>
      {value.warehouseId && <small className={enough ? 'production-ok' : 'production-error'}>
        {enough ? 'Stock suficiente' : `Stock insuficiente: ${formatQuantity(available.toFixed(6))} disponible`}
      </small>}
    </div>
  );
}

export default function ProductionOrdersPage() {
  const { activeCompanyId, user, can } = useAuth();
  const client = useQueryClient();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const planId = searchParams.get('plan');
  const [productId, setProductId] = useState('');
  const [quantity, setQuantity] = useState('1');
  const [warehouseId, setWarehouseId] = useState('');
  const [inputs, setInputs] = useState({});
  const [outputLot, setOutputLot] = useState('');
  const [expiresOn, setExpiresOn] = useState('');
  const [note, setNote] = useState('Fabricación completada');
  const [busy, setBusy] = useState(false);
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
  const runsQuery = useQuery({
    queryKey: ['production-runs', user?.id, activeCompanyId],
    queryFn: () => listProductionRuns(activeCompanyId), enabled: !!activeCompanyId,
  });
  const plansQuery = useQuery({
    queryKey: ['production-plans', user?.id, activeCompanyId],
    queryFn: () => listProductionPlans(activeCompanyId),
    enabled: !!(activeCompanyId && planId),
  });
  const plan = plansQuery.data?.find((entry) => entry.id === planId);
  const items = itemsQuery.data ?? [];
  const formulas = formulasQuery.data ?? [];
  const warehouses = warehousesQuery.data ?? [];
  const formula = formulas.find((entry) => entry.product_id === productId);
  const product = items.find((entry) => entry.id === productId);
  const byId = Object.fromEntries(items.map((item) => [item.id, item]));
  const componentIds = formula?.production_formula_lines.map((line) => line.component_id) ?? [];
  const balancesQuery = useQuery({
    queryKey: ['production-balances', activeCompanyId, productId],
    queryFn: () => listProductionBalances(activeCompanyId, componentIds),
    enabled: !!(activeCompanyId && formula),
  });
  const balances = balancesQuery.data ?? [];

  useEffect(() => {
    setProductId('');
    setWarehouseId('');
    setQuantity('1');
    setInputs({});
    setRequestId(crypto.randomUUID());
  }, [activeCompanyId]);

  useEffect(() => {
    if (!plan) return;
    setProductId(plan.product_id);
    setQuantity(String(plan.quantity));
    setWarehouseId(plan.warehouse_id);
    setNote(plan.note);
    setInputs({});
    setRequestId(crypto.randomUUID());
  }, [plan?.id, activeCompanyId]);

  function chooseProduct(id) {
    setProductId(id);
    setInputs({});
    setOutputLot('');
    setRequestId(crypto.randomUUID());
  }

  function updateInput(componentId, value) {
    setInputs((current) => ({ ...current, [componentId]: { ...current[componentId], ...value } }));
    setRequestId(crypto.randomUUID());
  }

  function needed(line) {
    return Number(line.quantity) * Number(quantity) / Number(formula.batch_quantity);
  }

  const ready = !!formula && (!planId || (plan?.status === 'planned' &&
    formula.version === plan.formula_version)) && Number(quantity) > 0 && !!warehouseId &&
    formula.production_formula_lines.every((line) => {
      const input = inputs[line.component_id] ?? {};
      const item = byId[line.component_id];
      const required = needed(line);
      const available = Number(balances.find((row) =>
        row.item_id === line.component_id && row.warehouse_id === input.warehouseId)?.quantity ?? 0);
      return !!input.warehouseId && (!item?.track_lots ||
        (!!input.lotCode && Number(input.lotAvailable) >= required)) &&
        required > 0 && Math.abs(Number(required.toFixed(6)) - required) < 1e-9 && available >= required;
    });

  async function submit(event) {
    event.preventDefault();
    if (!ready || (product?.track_lots && !outputLot.trim())) {
      notifyError(new Error('Revisá cantidades, depósitos, lotes y stock disponible.'));
      return;
    }
    setBusy(true);
    try {
      const selectedInputs = formula.production_formula_lines.map((line) => ({
          componentId: line.component_id,
          warehouseId: inputs[line.component_id].warehouseId,
          lotCode: inputs[line.component_id].lotCode,
      }));
      if (planId) {
        await completeProductionPlan(activeCompanyId, planId, selectedInputs,
          outputLot, expiresOn, requestId);
      } else {
        await postProductionRun(activeCompanyId, {
          productId, quantity, warehouseId, outputLot, expiresOn, note,
          inputs: selectedInputs,
        }, requestId);
      }
      setRequestId(crypto.randomUUID());
      setQuantity('1');
      setInputs({});
      setOutputLot('');
      setExpiresOn('');
      await Promise.all([
        client.invalidateQueries({ queryKey: ['production-runs', user?.id, activeCompanyId] }),
        client.invalidateQueries({ queryKey: ['production-balances', activeCompanyId] }),
        client.invalidateQueries({ queryKey: ['production-lots', activeCompanyId] }),
        client.invalidateQueries({ queryKey: ['stock'] }),
        client.invalidateQueries({ queryKey: ['production-plans', user?.id, activeCompanyId] }),
      ]);
      notifySuccess('Fabricación registrada', 'Se descontaron insumos y se ingresó el producto terminado.');
      if (planId) navigate('/production/planning');
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="production-page">
      <div className="production-heading">
        <div><span className="eyebrow">PRODUCCIÓN / ÓRDENES</span><h1>Fabricar productos</h1>
          <p>Revisá el stock de cada componente antes de confirmar la fabricación.</p></div>
        <Link className="button" to={planId ? '/production/planning' : '/production/formulas'}>
          {planId ? 'Volver al plan' : 'Gestionar fórmulas'}
        </Link>
      </div>
      <div className="production-grid">
        <form className="production-card" onSubmit={submit}>
          <h2><Factory size={20} /> Nueva fabricación</h2>
          {planId && (!plan || plan.status !== 'planned' ||
            formula?.version !== plan.formula_version) &&
            <p className="production-form-error" role="alert">
              {plansQuery.isPending ? 'Cargando planificación…' :
                plansQuery.isError ? plansQuery.error.message :
                  !plan ? 'El plan no existe o ya no está disponible.' :
                    plan.status !== 'planned' ? 'Este plan ya no está pendiente.' :
                      'La fórmula cambió. Creá un plan nuevo para revisar los insumos.'}
            </p>}
          {planId && plan?.status === 'planned' && <p className="production-muted">
            Planificación pendiente: elegí origen y lote de cada insumo para completarla.
          </p>}
          <label>Producto
            <select value={productId} required disabled={!!planId}
              onChange={(event) => chooseProduct(event.target.value)}>
              <option value="">Elegir producto con fórmula…</option>
              {formulas.map((entry) => <option key={entry.product_id} value={entry.product_id}>
                {byId[entry.product_id]?.code} · {byId[entry.product_id]?.name}
              </option>)}
            </select>
          </label>
          <div className="production-two-columns">
            <label>Cantidad a producir
              <input required type="number" min="0.000001" step="0.000001" value={quantity}
                disabled={!!planId}
                onChange={(event) => { setQuantity(event.target.value); setRequestId(crypto.randomUUID()); }} />
            </label>
            <label>Depósito de destino
              <select required value={warehouseId} disabled={!!planId} onChange={(event) => {
                setWarehouseId(event.target.value);
                setRequestId(crypto.randomUUID());
              }}>
                <option value="">Seleccionar…</option>
                {warehouses.map((warehouse) => <option key={warehouse.id} value={warehouse.id}>{warehouse.name}</option>)}
              </select>
            </label>
          </div>
          {formula && <>
            <div className="production-subtitle">Insumos a consumir</div>
            {formula.production_formula_lines.map((line) => {
              const input = inputs[line.component_id] ?? {};
              const balance = balances.find((row) => row.item_id === line.component_id && row.warehouse_id === input.warehouseId)?.quantity ?? 0;
              return <ComponentInput key={line.component_id} companyId={activeCompanyId}
                line={line} item={byId[line.component_id]} warehouses={warehouses}
                warehouseId={balance} value={input} requiredQuantity={needed(line)}
                onChange={(value) => updateInput(line.component_id, value)} />;
            })}
          </>}
          {product?.track_lots && <div className="production-two-columns">
            <label>Lote nuevo del producto
              <input required maxLength={80} value={outputLot} onChange={(event) => {
                setOutputLot(event.target.value); setRequestId(crypto.randomUUID());
              }} placeholder="Ej. PROD-001" />
            </label>
            <label>Vencimiento (opcional)
              <input type="date" value={expiresOn} onChange={(event) => {
                setExpiresOn(event.target.value); setRequestId(crypto.randomUUID());
              }} />
            </label>
          </div>}
          <label>Nota de fabricación
            <input required minLength={3} maxLength={400} value={note} disabled={!!planId}
              onChange={(event) => { setNote(event.target.value); setRequestId(crypto.randomUUID()); }} />
          </label>
          <div className="production-actions">
            <span>La operación se confirma completa o no se registra.</span>
            <button className="button primary" disabled={busy || !ready || !can('production', 'insert') || !can('stock', 'insert')}>
              <PackageCheck size={17} /> {busy ? 'Registrando…' :
                planId ? 'Completar plan y fabricar' : 'Confirmar fabricación'}
            </button>
          </div>
        </form>
        <aside className="production-card">
          <h2>Últimas fabricaciones</h2>
          {runsQuery.isError && <p className="production-error">{runsQuery.error.message}</p>}
          {!runsQuery.data?.length && <p className="production-muted">Aún no se registraron fabricaciones.</p>}
          {runsQuery.data?.map((run) => <div className="production-history" key={run.id}>
            <strong>{byId[run.product_id]?.name ?? 'Producto'}</strong>
            <span>{formatQuantity(run.quantity)} · {new Date(run.created_at).toLocaleString('es-AR')}</span>
            <small>Fórmula v{run.formula_version} · Costo estimado $ {Number(run.estimated_cost).toLocaleString('es-AR', { minimumFractionDigits: 2 })}</small>
            <details><summary>Componentes consumidos</summary>
              {run.production_run_lines.map((line) => <p key={line.component_id}>
                {byId[line.component_id]?.name ?? 'Insumo'} · {formatQuantity(line.quantity)}
                {line.lot_code ? ` · Lote ${line.lot_code}` : ''}
              </p>)}
            </details>
          </div>)}
        </aside>
      </div>
    </section>
  );
}

import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { AlertTriangle, ArrowUpRight, CheckCircle2, RefreshCw } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { friendlyError, notifyError, notifySuccess } from '../../lib/notifications';
import {
  checkManufacturingAvailability, listFormulas, listProductionItems,
  listProductionJobs, listProductionReservations, recalculateProductionReservations,
} from '../../services/production';
import { formatQuantity } from '../inventory/stockNumber';
import './availability.css';

const validQuantity = (value) => /^\d+(?:\.\d{1,6})?$/.test(String(value))
  && Number(value) > 0 && Number(value) < 1000000000000;

export default function ManufacturingAvailabilityPage() {
  const { activeCompanyId, user, can } = useAuth();
  const client = useQueryClient();
  const [productId, setProductId] = useState('');
  const [quantity, setQuantity] = useState('1');
  const [result, setResult] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const allowed = can('stock', 'read');
  const itemsQuery = useQuery({
    queryKey: ['production-items', user?.id, activeCompanyId],
    queryFn: () => listProductionItems(activeCompanyId),
    enabled: Boolean(activeCompanyId && allowed),
  });
  const formulasQuery = useQuery({
    queryKey: ['production-formulas', user?.id, activeCompanyId],
    queryFn: () => listFormulas(activeCompanyId),
    enabled: Boolean(activeCompanyId && allowed),
  });
  const jobsQuery = useQuery({
    queryKey: ['production-jobs', user?.id, activeCompanyId],
    queryFn: () => listProductionJobs(activeCompanyId),
    enabled: Boolean(activeCompanyId && allowed),
  });
  const reservationsQuery = useQuery({
    queryKey: ['production-reservations', user?.id, activeCompanyId],
    queryFn: () => listProductionReservations(activeCompanyId),
    enabled: Boolean(activeCompanyId && allowed),
  });

  useEffect(() => {
    setProductId('');
    setQuantity('1');
    setResult(null);
    setError('');
  }, [activeCompanyId]);

  const items = itemsQuery.data ?? [];
  const jobs = (jobsQuery.data ?? []).filter((entry) =>
    ['queued', 'in_progress'].includes(entry.status));
  const reservations = (reservationsQuery.data ?? []).filter((entry) =>
    jobs.some((job) => job.id === entry.job_id));
  const formulaProducts = (formulasQuery.data ?? []).map((entry) =>
    items.find((item) => item.id === entry.product_id)).filter(Boolean);
  const lines = result?.lines ?? [];
  const missing = lines.filter((line) => Number(line.required) > Number(line.free) + 0.000001);
  const part = (value) => formatQuantity(Number(value).toFixed(6));

  async function simulate(event) {
    event.preventDefault();
    if (!productId || !validQuantity(quantity) || busy) return;
    setBusy(true);
    setError('');
    setResult(null);
    try {
      const next = await checkManufacturingAvailability(activeCompanyId, productId, quantity);
      setResult(next);
    } catch (cause) {
      setError(friendlyError(cause));
      notifyError(cause);
    } finally {
      setBusy(false);
    }
  }

  async function recalculate() {
    if (busy) return;
    setBusy(true);
    setError('');
    try {
      await recalculateProductionReservations(activeCompanyId);
      await Promise.all([
        client.invalidateQueries({ queryKey: ['production-reservations', user?.id, activeCompanyId] }),
        client.invalidateQueries({ queryKey: ['production-reservation-locations', user?.id, activeCompanyId] }),
        client.invalidateQueries({ queryKey: ['production-dashboard', user?.id, activeCompanyId] }),
        client.invalidateQueries({ queryKey: ['operational-alerts'] }),
      ]);
      if (result && productId && validQuantity(quantity)) {
        setResult(await checkManufacturingAvailability(activeCompanyId, productId, quantity));
      }
      notifySuccess('Reservas actualizadas', 'Se reasignó el stock libre por fecha prevista de las órdenes.');
    } catch (cause) {
      setError(friendlyError(cause));
      notifyError(cause);
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="manufacturing-availability">
      <div className="page-head">
        <div>
          <span className="eyebrow">PRODUCCIÓN / DISPONIBILIDAD</span>
          <h1>¿Tengo stock para fabricar?</h1>
          <p>Simulá una cantidad antes de crear la orden. Consultamos existencias y reservas vigentes.</p>
        </div>
      </div>
      {!allowed && <p role="alert" className="error">Tu rol necesita permiso de lectura de stock para esta consulta.</p>}
      {(error || itemsQuery.error || formulasQuery.error || reservationsQuery.error) && (
        <p role="alert" className="error">{error || friendlyError(itemsQuery.error
          || formulasQuery.error || reservationsQuery.error)}</p>
      )}
      {allowed && <>
        <form className="manufacturing-check" onSubmit={simulate}>
          <label>Producto con fórmula
            <select required value={productId} onChange={(event) => {
              setProductId(event.target.value);
              setResult(null);
            }}>
              <option value="">Elegir producto…</option>
              {formulaProducts.map((item) => <option key={item.id} value={item.id}>
                {item.code} · {item.name}
              </option>)}
            </select>
          </label>
          <label>Cantidad a fabricar
            <input type="number" required min="0.000001" step="0.000001"
              value={quantity} onChange={(event) => {
                setQuantity(event.target.value);
                setResult(null);
              }} />
          </label>
          <button className="button primary" disabled={busy || !productId || !validQuantity(quantity)}>
            {busy ? 'Calculando…' : 'Comprobar materiales'}
          </button>
        </form>
        {result && <section className="manufacturing-result">
          <div className={`manufacturing-result-head ${missing.length ? 'shortage' : 'ready'}`}>
            {missing.length ? <AlertTriangle size={23} /> : <CheckCircle2 size={23} />}
            <div>
              <h2>{missing.length ? `Faltan ${missing.length} componentes`
                : 'Hay stock libre suficiente'}</h2>
              <p>Simulación de {part(result.quantity)} unidades · Fórmula v{result.formula_version}.</p>
            </div>
          </div>
          <div className="manufacturing-table-wrap">
            <table>
              <thead><tr><th>Componente y ubicación</th><th>Necesario</th><th>Físico</th>
                <th>Utilizable</th><th>Reservado</th><th>Libre</th><th>Faltante</th></tr></thead>
              <tbody>{lines.map((line) => {
                const shortage = Math.max(0, Number(line.required) - Number(line.free));
                return <tr key={line.item_id}>
                  <td><strong>{line.item_name}</strong><small>{line.item_code} · {line.unit_symbol}</small>
                    {!!line.locations?.length && <details className="manufacturing-slots">
                      <summary>Ver {line.locations.length} ubicaciones disponibles</summary>
                      {line.locations.map((slot) => <small
                        key={`${slot.warehouse_id}:${slot.lot_code ?? ''}`}>
                        {slot.warehouse_name}{slot.lot_code && ` · Lote ${slot.lot_code}`}
                        {slot.expires_on && ` · Vence ${slot.expires_on.split('-').reverse().join('/')}`}
                        {' · '}{part(slot.free)} libre de {part(slot.physical)}
                      </small>)}
                    </details>}
                  </td>
                  <td>{part(line.required)}</td><td>{line.infinite_stock ? '∞' : part(line.physical)}</td>
                  <td>{line.infinite_stock ? '∞' : part(line.usable ?? line.physical)}</td>
                  <td>{part(line.reserved)}</td><td>{line.infinite_stock ? '∞' : part(line.free)}</td>
                  <td className={shortage > 0.000001 ? 'manufacturing-shortage' : ''}>
                    {shortage > 0.000001 ? part(shortage) : '—'}
                  </td>
                </tr>;
              })}</tbody>
            </table>
          </div>
          <p className="manufacturing-note">Esta simulación no aparta stock: la reserva por depósito y
            lote se asigna al confirmar la orden, priorizando lotes próximos a vencer.
            Los semielaborados se consideran ítems existentes; si necesitás producirlos,
            simulá su fórmula por separado. Los lotes vencidos quedan fuera del utilizable.
            Las salidas independientes respetan el stock asignado a cada ubicación.</p>
          <Link className="button outline" to="/production/orders">
            Abrir órdenes de fabricación <ArrowUpRight size={16} />
          </Link>
        </section>}
        <section className="manufacturing-commitments">
          <div className="manufacturing-commitments-head">
            <div><span className="eyebrow">COMPROMISOS VIGENTES</span><h2>Reservas de órdenes activas</h2></div>
            <button type="button" className="button outline" onClick={recalculate} disabled={busy}>
              <RefreshCw size={16} /> Recalcular
            </button>
          </div>
          <p>Las órdenes con fecha más próxima reciben prioridad. Las entradas y salidas
            recalculan las reservas. También podés pulsar Recalcular para actualizar el reparto.</p>
          {!jobs.length && <p>No hay órdenes activas.</p>}
          <div className="manufacturing-reservations">
            {jobs.map((job) => {
              const entries = reservations.filter((entry) => entry.job_id === job.id);
              const unresolved = entries.filter((entry) => {
                const consumed = (job.production_job_events ?? [])
                  .filter((event) => event.component_id === entry.component_id)
                  .reduce((sum, event) => sum + Number(event.quantity)
                    * (event.kind === 'issue' ? 1 : -1), 0);
                return Number(entry.required_quantity) - consumed
                  > Number(entry.reserved_quantity) + 0.000001;
              });
              return <Link key={job.id} className="manufacturing-reservation" to={`/production/orders?job=${job.id}`}>
                <div><strong>{items.find((item) => item.id === job.product_id)?.name ?? 'Orden de fabricación'}</strong>
                  <small>{job.due_on ? `Prevista ${job.due_on.split('-').reverse().join('/')}`
                    : 'Sin fecha'} · {entries.length} componentes</small></div>
                <span className={unresolved.length ? 'manufacturing-shortage' : ''}>
                  {unresolved.length ? `${unresolved.length} con faltante` : 'Material asignado'}
                </span><ArrowUpRight size={16} />
              </Link>;
            })}
          </div>
        </section>
      </>}
    </section>
  );
}

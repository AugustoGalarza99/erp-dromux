import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { ArrowUpRight, RefreshCcw } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { friendlyError } from '../../lib/notifications';
import { getOperationalReport } from '../../services/costing';
import './reports.css';

const today = () => new Intl.DateTimeFormat('sv-SE', {
  timeZone: 'America/Argentina/Buenos_Aires',
}).format(new Date());
const firstDay = () => `${today().slice(0, 7)}-01`;
const money = (value) => Number(value).toLocaleString('es-AR', {
  style: 'currency', currency: 'ARS', maximumFractionDigits: 2,
});

export default function ReportsPage() {
  const { activeCompanyId, user, can, role } = useAuth();
  const [from, setFrom] = useState(firstDay);
  const [to, setTo] = useState(today);
  const validRange = !!from && !!to && to >= from
    && (new Date(`${to}T12:00:00`) - new Date(`${from}T12:00:00`)) <= 366 * 86400000;
  const report = useQuery({
    queryKey: ['operational-report', user?.id, activeCompanyId, from, to],
    queryFn: () => getOperationalReport(activeCompanyId, from, to),
    enabled: Boolean(activeCompanyId && validRange),
  });
  const data = report.data ?? {};
  const cards = [
    { name: 'Ventas registradas', value: data.sales, permission: 'sales' },
    { name: 'Importe neto vendido', value: data.revenue == null ? null : money(data.revenue), permission: 'sales' },
    { name: 'Fabricaciones terminadas', value: data.finished_jobs, permission: 'production' },
    { name: 'Órdenes en cola o en proceso', value: data.jobs_in_progress, permission: 'production' },
    { name: 'Órdenes de compra creadas', value: data.purchase_orders, permission: 'purchases' },
  ].filter((entry) => can(entry.permission, 'read') && entry.value != null);

  return (
    <section className="reports-page">
      <div className="page-head">
        <div>
          <span className="eyebrow">REPORTES / ACTIVIDAD</span>
          <h1>Resumen por período</h1>
          <p>Consultá lo vendido y la actividad de compras y producción. Cada área muestra sus datos permitidos.</p>
        </div>
      </div>
      <div className="reports-filters">
        <label>Desde
          <input type="date" value={from} max={to || undefined}
            onChange={(event) => setFrom(event.target.value)} />
        </label>
        <label>Hasta
          <input type="date" value={to} min={from || undefined}
            onChange={(event) => setTo(event.target.value)} />
        </label>
        <button type="button" className="button outline" disabled={!validRange || report.isFetching}
          onClick={() => report.refetch()}>
          <RefreshCcw size={16} /> Actualizar
        </button>
      </div>
      {!validRange && <p className="error" role="alert">Elegí fechas válidas dentro de un año.</p>}
      {report.isPending && validRange && <p>Preparando el informe…</p>}
      {report.error && <p role="alert" className="error">{friendlyError(report.error)}</p>}
      {report.data && <>
        {!cards.length && <p>Tu rol permite abrir Reportes, pero no consultar datos de ventas, compras ni producción. Pedí al administrador que revise tus permisos.</p>}
        <div className="reports-grid">
          {cards.map((card) => <article key={card.name} className="reports-card">
            <span>{card.name}</span>
            <strong>{card.value}</strong>
          </article>)}
        </div>
        {can('sales', 'read') && <section className="reports-card">
          <h2>Productos más vendidos</h2>
          {(data.top_products ?? []).length ? <ol className="reports-products">
            {data.top_products.map((product) => <li key={product.name}>
              <span>{product.name}</span><strong>{Number(product.quantity).toLocaleString('es-AR')}</strong>
            </li>)}
          </ol> : <p>No se registraron productos vendidos en este período.</p>}
        </section>}
      </>}
      {role === 'admin' && can('finance', 'read') && can('sales', 'read') && (
        <Link className="reports-profit-link" to="/finance/costs#ventas">
          Analizar costo y ganancia por venta <ArrowUpRight size={16} />
        </Link>
      )}
      <p className="reports-note">Los importes de ventas contemplan devoluciones y anulaciones.
        Las órdenes en proceso muestran su estado actual, independiente del período seleccionado.</p>
    </section>
  );
}

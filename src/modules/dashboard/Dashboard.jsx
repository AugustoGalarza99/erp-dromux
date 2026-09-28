import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import {
  ArrowUpRight, AlertTriangle, CalendarClock, Factory,
  PackageCheck, Play, RefreshCw, Truck,
} from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { friendlyError } from '../../lib/notifications';
import { useOperationalAlerts } from '../operations/useOperationalAlerts';
import './dashboard.css';

export default function Dashboard() {
  const { activeCompany, activeCompanyId, user, can } = useAuth();
  const hasProduction = can('production', 'read');
  const { alerts, unread, isPending: alertsPending, error: alertsError,
    refetch: refetchAlerts } = useOperationalAlerts();
  const summary = useQuery({
    queryKey: ['erp-dashboard', user?.id, activeCompanyId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('erp_operational_dashboard', {
        p_company: activeCompanyId,
      });
      if (error) throw error;
      return data;
    },
    enabled: Boolean(activeCompanyId),
    refetchInterval: 60_000,
  });
  const jobsQuery = useQuery({
    queryKey: ['production-dashboard', user?.id, activeCompanyId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('erp_production_dashboard', {
        p_company: activeCompanyId,
      });
      if (error) throw error;
      return data;
    },
    enabled: Boolean(activeCompanyId && hasProduction),
    refetchInterval: 60_000,
  });
  const jobs = jobsQuery.data?.next ?? [];
  const critical = alerts.filter((alert) => alert.severity === 'critical').length;
  const metrics = [
    { title: 'Órdenes en proceso', value: jobsQuery.data?.in_progress,
      icon: Play, to: '/production/orders', allowed: hasProduction },
    { title: 'En cola para fabricar', value: jobsQuery.data?.queued,
      icon: Factory, to: '/production/orders', allowed: hasProduction },
    { title: 'Fuera de plazo', value: jobsQuery.data?.overdue,
      icon: CalendarClock, to: '/production/orders', allowed: hasProduction },
    { title: 'Materiales bajo mínimo', value: summary.data?.low_stock,
      icon: AlertTriangle, to: '/inventory/stock',
      allowed: can('stock', 'read') && summary.data?.low_stock != null },
    { title: 'Compras abiertas', value: summary.data?.open_orders,
      icon: PackageCheck, to: '/purchases/orders',
      allowed: can('purchases', 'read') && summary.data?.open_orders != null },
  ].filter((entry) => entry.allowed);
  const shortcuts = [
    { label: 'Nueva orden de fabricación', to: '/production/orders', resource: 'production', action: 'insert' },
    { label: 'Planificar fabricación', to: '/production/planning', resource: 'production', action: 'read' },
    { label: 'Ver fórmulas', to: '/production/formulas', resource: 'production', action: 'read' },
    { label: 'Consultar stock', to: '/inventory/stock', resource: 'stock', action: 'read' },
    { label: 'Emitir remito', to: '/inventory/delivery-notes', resource: 'stock', action: 'insert' },
    { label: 'Órdenes de compra', to: '/purchases/orders', resource: 'purchases', action: 'read' },
  ].filter((entry) => can(entry.resource, entry.action));

  async function refresh() {
    await Promise.all([summary.refetch(),
      ...(hasProduction ? [jobsQuery.refetch()] : []), refetchAlerts()]);
  }

  return (
    <section className="erp-home">
      <div className="page-head">
        <div>
          <span className="eyebrow">CENTRO OPERATIVO / PRODUCCIÓN</span>
          <h1>Lo que pasa en tu fábrica</h1>
          <p>{activeCompany?.name} · Órdenes, materiales y tareas que requieren atención.</p>
        </div>
        <button type="button" className="erp-home-refresh" onClick={refresh}>
          <RefreshCw size={16} /> Actualizar
        </button>
      </div>

      <div className="erp-home-hero">
        <div>
          <span className="eyebrow light">ESTADO DE LA OPERACIÓN</span>
          <h2>{critical ? `${critical} situaciones requieren atención`
            : hasProduction ? 'Controlá cada orden desde un mismo lugar'
              : 'Tu operación está a mano'}</h2>
          <p>{critical
            ? 'Revisá los materiales agotados y los plazos vencidos antes de continuar la producción.'
            : 'Consultá las órdenes abiertas, las existencias y las próximas entregas.'}</p>
          {hasProduction && <Link to="/production/orders">
            Abrir procesos de fabricación <ArrowUpRight size={16} />
          </Link>}
        </div>
        <div className="erp-home-hero-art" aria-hidden="true" />
      </div>

      {(summary.error || jobsQuery.error || alertsError) && (
        <p role="alert" className="error">{friendlyError(summary.error || jobsQuery.error || alertsError)}</p>
      )}

      <div className="erp-home-section">
        <div><span className="eyebrow">EN ESTE MOMENTO</span><h2>Indicadores de fábrica</h2></div>
      </div>
      <div className="erp-home-grid">
        {metrics.map(({ title, value, icon: Icon, to }) => (
          <Link to={to} className="erp-home-card" key={title}>
            <span className="erp-home-card-icon"><Icon size={22} /></span>
            <strong className="erp-home-value">{(summary.isPending || jobsQuery.isPending)
              && value == null ? '…' : value ?? '—'}</strong>
            <span className="erp-home-label">{title} <ArrowUpRight size={16} /></span>
          </Link>
        ))}
      </div>

      <div className="erp-home-columns">
        <section className="erp-home-panel">
          <div className="erp-home-panel-heading">
            <div><span className="eyebrow">ATENCIÓN</span><h2>Avisos operativos</h2></div>
            <span className="erp-home-count">{unread} sin leer</span>
          </div>
          {alertsPending && <p className="erp-home-empty">Revisando avisos…</p>}
          {!alertsPending && !alerts.length && !alertsError && (
            <p className="erp-home-empty">Sin alertas activas de mínimos o fechas próximas.</p>
          )}
          {alerts.slice(0, 5).map((alert) => (
            <Link key={alert.alert_key} className="erp-home-alert" to={alert.destination}>
              <AlertTriangle size={18} />
              <span><strong>{alert.title}</strong><small>{alert.detail}</small></span>
              <ArrowUpRight size={16} />
            </Link>
          ))}
          <p className="erp-home-explain">Los mínimos comparan existencias físicas. Todavía no descuentan
            materiales reservados para otras órdenes ni predicen fechas de agotamiento.</p>
        </section>
        <section className="erp-home-panel">
          <div className="erp-home-panel-heading">
            <div><span className="eyebrow">TRABAJO EN CURSO</span><h2>Próximas órdenes</h2></div>
          </div>
          {!hasProduction && <p className="erp-home-empty">Tu rol no consulta órdenes de fabricación.</p>}
          {hasProduction && !jobs.length && !jobsQuery.isPending && (
            <p className="erp-home-empty">No hay órdenes activas. Podés iniciar una desde Producción.</p>
          )}
          {jobs.slice().sort((a, b) => (a.due_on ?? '9999').localeCompare(b.due_on ?? '9999'))
            .slice(0, 5).map((job) => (
              <Link key={job.id} className="erp-home-job" to={`/production/orders?job=${job.id}`}>
                <span className="erp-home-job-dot" />
                <span><strong>{job.product_name} · {job.planned_quantity}</strong>
                  <small>{job.status === 'queued' ? 'En cola' : 'En fabricación'} · 
                    {job.due_on ? `Entrega prevista ${job.due_on.split('-').reverse().join('/')}`
                      : 'Sin fecha límite'} · {job.note}</small></span>
                <ArrowUpRight size={16} />
              </Link>
            ))}
          {hasProduction && <Link className="erp-home-all" to="/production/orders">
            Ver todos los procesos <ArrowUpRight size={16} />
          </Link>}
        </section>
      </div>

      <section className="erp-home-shortcuts">
        <h2>Continuar trabajando</h2>
        <div>{shortcuts.map((entry) => (
          <Link key={entry.to} to={entry.to}>
            {entry.label} {entry.label === 'Emitir remito' ? <Truck size={16} /> : <ArrowUpRight size={16} />}
          </Link>
        ))}</div>
      </section>
    </section>
  );
}

import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import {
  AlertOctagon, AlertTriangle, ArrowUpRight, Banknote, CalendarClock,
  CheckCircle2, Clock3, Factory, HandCoins, PackageCheck, Play, RefreshCw,
  Lock, ShoppingBag, TrendingUp, Truck, Wallet,
} from 'lucide-react';
import { useAuth } from '../../compartido/contextos/AuthContext';
import { supabase } from '../../compartido/utilidades/supabase';
import { friendlyError } from '../../compartido/utilidades/notifications';
import { money } from '../compras/compartido/supplierUi';
import { getReplenishmentForecast } from '../produccion/reposicion/replenishment';
import { getTreasuryBalances } from '../finanzas/tesoreria/treasury';
import { useOperationalAlerts } from './avisos/useOperationalAlerts';
import './dashboard.css';

const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
const day = (iso) => iso?.split('-').reverse().join('/');

function greeting() {
  const hour = new Date().getHours();
  if (hour < 12) return 'Buenos días';
  if (hour < 20) return 'Buenas tardes';
  return 'Buenas noches';
}

async function rpc(name, companyId) {
  const { data, error } = await supabase.rpc(name, { p_company: companyId });
  if (error) throw error;
  return data;
}

/* Lo que el servidor devuelve ya viene filtrado por permiso: una clave ausente
   significa "este rol no la ve", no cero. */
export default function Dashboard() {
  const { activeCompany, activeCompanyId, user, can, role, planIncluye } = useAuth();
  const hasProduction = can('produccion_resumen', 'ver') || can('produccion_ordenes', 'ver');
  const hasFinance = can('finanzas', 'ver');
  const enabled = Boolean(activeCompanyId);
  const scope = [user?.id, activeCompanyId];

  const { alerts, unread, isPending: alertsPending, error: alertsError,
    refetch: refetchAlerts } = useOperationalAlerts();
  const summary = useQuery({
    queryKey: ['erp-dashboard', ...scope],
    queryFn: () => rpc('erp_operational_dashboard', activeCompanyId),
    enabled,
    refetchInterval: 60_000,
  });
  const jobsQuery = useQuery({
    queryKey: ['production-dashboard', ...scope],
    queryFn: () => rpc('erp_production_dashboard', activeCompanyId),
    enabled: enabled && hasProduction,
    refetchInterval: 60_000,
  });
  const forecast = useQuery({
    queryKey: ['replenishment-forecast', ...scope],
    queryFn: () => getReplenishmentForecast(activeCompanyId),
    enabled: enabled && hasProduction,
    staleTime: 60_000,
  });
  const balances = useQuery({
    queryKey: ['treasury-balances', ...scope],
    queryFn: () => getTreasuryBalances(activeCompanyId),
    enabled: enabled && hasFinance,
    staleTime: 60_000,
  });

  const data = summary.data ?? {};
  const jobs = jobsQuery.data?.next ?? [];
  const criticalAlerts = alerts.filter((alert) => alert.severity === 'critical').length;
  const needBuying = (forecast.data ?? [])
    .filter((row) => row.alert_level === 'critical')
    .sort((a, b) => Number(a.days_left ?? 9999) - Number(b.days_left ?? 9999));
  const cash = balances.data
    ? balances.data.filter((row) => row.active !== false)
      .reduce((total, row) => total + Number(row.balance ?? 0), 0)
    : null;
  const isAdmin = role === 'administrador';

  /* Decisiones: cada una dice qué pasa, qué hay que resolver y a dónde ir. */
  const decisions = [];
  const overdue = Number(jobsQuery.data?.overdue ?? 0);
  if (overdue > 0) {
    decisions.push({
      key: 'overdue', level: 'urgent', icon: CalendarClock, to: '/production/orders',
      title: `${plural(overdue, 'orden de fabricación fuera de plazo', 'órdenes de fabricación fuera de plazo')}`,
      ask: 'Decidí si las priorizás, reprogramás la entrega o avisás al cliente.',
    });
  }
  if (needBuying.length > 0) {
    const names = needBuying.slice(0, 3).map((row) => row.item_name).join(', ');
    decisions.push({
      key: 'buy', level: 'urgent', icon: AlertOctagon, to: '/production/replenishment',
      title: `${plural(needBuying.length, 'material se agota', 'materiales se agotan')} antes de que llegue una compra`,
      ask: `Decidí qué comprar hoy: ${names}${needBuying.length > 3 ? '…' : ''}.`,
    });
  } else if (Number(data.low_stock) > 0) {
    decisions.push({
      key: 'low', level: 'attention', icon: AlertTriangle, to: '/inventory/stock',
      title: `${plural(Number(data.low_stock), 'material bajo el mínimo', 'materiales bajo el mínimo')}`,
      ask: 'Revisá si conviene reponerlos o ajustar el mínimo.',
    });
  }
  if (Number(data.receivables) > 0) {
    decisions.push({
      key: 'collect', level: 'attention', icon: HandCoins, to: '/finance/receivables',
      title: `${money(data.receivables)} pendientes de cobro`,
      ask: 'Decidí a qué clientes reclamar primero.',
    });
  }
  if (Number(data.open_orders) > 0) {
    decisions.push({
      key: 'receive', level: 'attention', icon: PackageCheck, to: '/purchases/orders',
      title: `${plural(Number(data.open_orders), 'compra esperando recepción', 'compras esperando recepción')}`,
      ask: 'Confirmá qué llegó y reclamá lo que se demora.',
    });
  }
  if (Number(data.planned_runs) > 0) {
    decisions.push({
      key: 'plans', level: 'info', icon: Factory, to: '/production/planning',
      title: `${plural(Number(data.planned_runs), 'plan de fabricación sin lanzar', 'planes de fabricación sin lanzar')}`,
      ask: 'Decidí cuáles pasan a fabricación esta semana.',
    });
  }
  if (Number(jobsQuery.data?.queued) > 0 && Number(jobsQuery.data?.in_progress) === 0) {
    decisions.push({
      key: 'idle', level: 'info', icon: Clock3, to: '/production/orders',
      title: 'Hay órdenes en cola y ninguna en fabricación',
      ask: 'Definí cuál se inicia primero.',
    });
  }
  const levelRank = { urgent: 0, attention: 1, info: 2 };
  decisions.sort((a, b) => levelRank[a.level] - levelRank[b.level]);
  const levelText = { urgent: 'Urgente', attention: 'Requiere atención', info: 'Para planificar' };
  const urgent = decisions.filter((entry) => entry.level === 'urgent').length;
  const loading = summary.isPending || (hasProduction && jobsQuery.isPending);

  const kpis = [
    { key: 'revenue', label: 'Ventas de los últimos 30 días', icon: ShoppingBag,
      value: data.revenue_30d != null ? money(data.revenue_30d) : null,
      note: data.sales_30d != null ? plural(Number(data.sales_30d), 'venta', 'ventas') : null,
      to: '/sales/orders' },
    { key: 'receivables', label: 'Por cobrar a clientes', icon: HandCoins,
      value: data.receivables != null ? money(data.receivables) : null,
      note: 'Saldo de ventas no cobradas', to: '/finance/receivables' },
    { key: 'cash', label: 'Saldo en tesorería', icon: Wallet,
      value: cash != null ? money(cash) : null,
      note: 'Suma de cuentas activas', to: '/finance/treasury' },
    { key: 'profit', label: 'Ganancia bruta, 30 días', icon: TrendingUp,
      value: isAdmin && data.profit_30d != null ? money(data.profit_30d) : null,
      note: 'Sin impuestos ni gastos indirectos', to: '/finance/costs' },
  ].map((entry) => ({
    ...entry,
    // Lo que el rol no puede ver se muestra bloqueado (candado), no se esconde.
    locked: entry.key === 'revenue' ? !can('ventas', 'ver')
      : entry.key === 'profit' ? !isAdmin : !hasFinance,
    outOfPlan: !planIncluye(entry.key === 'revenue' ? 'ventas' : 'finanzas'),
  })).filter((entry) => entry.locked || entry.value != null || entry.key === 'revenue'
    || (entry.key === 'cash' && balances.isPending));

  const production = [
    { label: 'En fabricación', value: jobsQuery.data?.in_progress, icon: Play },
    { label: 'En cola', value: jobsQuery.data?.queued, icon: Factory },
    { label: 'Fuera de plazo', value: jobsQuery.data?.overdue, icon: CalendarClock, warn: true },
    { label: 'Planes sin lanzar', value: data.planned_runs, icon: Clock3 },
  ];

  const shortcuts = [
    { label: 'Registrar venta', to: '/sales/orders', resource: 'ventas', action: 'crear' },
    { label: 'Nueva orden de fabricación', to: '/production/orders', resource: 'produccion_ordenes', action: 'crear' },
    { label: '¿Tengo stock para fabricar?', to: '/production/availability', resource: 'produccion_disponibilidad', action: 'ver' },
    { label: 'Emitir remito', to: '/inventory/delivery-notes', resource: 'stock_remitos', action: 'crear', icon: Truck },
    { label: 'Consultar stock', to: '/inventory/stock', resource: 'stock_saldos', action: 'ver' },
    { label: 'Órdenes de compra', to: '/purchases/orders', resource: 'compras_ordenes', action: 'ver' },
    { label: 'Cobrar a un cliente', to: '/finance/receivables', resource: 'finanzas', action: 'ver', icon: Banknote },
  ].map((entry) => ({ ...entry, locked: !can(entry.resource, entry.action) }))
    .sort((a, b) => Number(a.locked) - Number(b.locked));

  const firstError = summary.error || jobsQuery.error || alertsError
    || forecast.error || balances.error;

  async function refresh() {
    await Promise.all([
      summary.refetch(),
      ...(hasProduction ? [jobsQuery.refetch(), forecast.refetch()] : []),
      ...(hasFinance ? [balances.refetch()] : []),
      refetchAlerts(),
    ]);
  }

  const name = (user?.user_metadata?.full_name || '').split(' ')[0];
  const today = new Date().toLocaleDateString('es-AR', {
    weekday: 'long', day: 'numeric', month: 'long',
  });

  return (
    <section className="home">
      <header className="home-head">
        <div>
          <span className="home-date">{today}</span>
          <h1>{greeting()}{name ? `, ${name}` : ''}</h1>
          <p>{activeCompany?.name} · Esto es lo que necesita tu decisión hoy.</p>
        </div>
        <button type="button" className="home-refresh" onClick={refresh}
          disabled={summary.isFetching}>
          <RefreshCw size={16} aria-hidden="true" className={summary.isFetching ? 'spin' : ''} />
          {summary.isFetching ? 'Actualizando…' : 'Actualizar'}
        </button>
      </header>

      {firstError && <p role="alert" className="home-error">{friendlyError(firstError)}</p>}

      <section className="home-decisions" aria-labelledby="home-decisions-title">
        <div className="home-decisions-head">
          <h2 id="home-decisions-title">Decisiones de hoy</h2>
          <span className={`home-chip ${urgent ? 'is-urgent' : 'is-ok'}`}>
            {loading ? 'Revisando…' : urgent
              ? plural(urgent, 'urgente', 'urgentes')
              : decisions.length ? plural(decisions.length, 'pendiente', 'pendientes') : 'Al día'}
          </span>
        </div>
        {!loading && !decisions.length && (
          <p className="home-allgood">
            <CheckCircle2 size={20} aria-hidden="true" />
            <span><strong>No hay nada urgente.</strong> Sin vencimientos, faltantes ni
              cobros que requieran una decisión ahora.</span>
          </p>
        )}
        <ul className="home-decision-list">
          {decisions.map(({ key, level, icon: Icon, to, title, ask }) => (
            <li key={key}>
              <Link to={to} className={`home-decision is-${level}`}>
                <span className="home-decision-icon"><Icon size={20} aria-hidden="true" /></span>
                <span className="home-decision-text">
                  <small>{levelText[level]}</small>
                  <strong>{title}</strong>
                  <span>{ask}</span>
                </span>
                <ArrowUpRight size={18} aria-hidden="true" />
              </Link>
            </li>
          ))}
        </ul>
      </section>

      {kpis.length > 0 && (
        <section aria-label="Resumen del negocio">
          <div className="home-kpis">
            {kpis.map(({ key, label, icon: Icon, value, note, to, locked, outOfPlan }) => (locked ? (
              <div className="home-kpi is-locked" key={key} aria-label={`${label}: acceso restringido`}>
                <span className="home-kpi-top">
                  <span className="home-kpi-icon"><Icon size={18} aria-hidden="true" /></span>
                  <span>{label}</span>
                </span>
                <strong>
                  <Lock size={16} aria-hidden="true" /> {outOfPlan ? 'No incluido en tu plan' : 'Acceso restringido'}
                </strong>
                <small>{outOfPlan ? 'Tu empresa no tiene activado este módulo.' : 'Tu rol no incluye este dato.'}</small>
              </div>
            ) : (
              <Link to={to} className="home-kpi" key={key}>
                <span className="home-kpi-top">
                  <span className="home-kpi-icon"><Icon size={18} aria-hidden="true" /></span>
                  <span>{label}</span>
                </span>
                <strong>{value ?? '…'}</strong>
                {note && <small>{note}</small>}
              </Link>
            )))}
          </div>
        </section>
      )}

      <div className="home-columns">
        {!hasProduction && (
          <section className="home-panel is-locked" aria-label="Producción: acceso restringido">
            <div className="home-panel-head"><h2><Lock size={16} aria-hidden="true" /> Producción</h2></div>
            <p className="home-empty">
              {planIncluye('produccion')
                ? 'Acceso restringido: tu rol no incluye Producción.'
                : 'No incluido en tu plan: tu empresa no tiene activado Producción.'}
            </p>
          </section>
        )}
        {hasProduction && (
          <section className="home-panel" aria-labelledby="home-prod-title">
            <div className="home-panel-head">
              <h2 id="home-prod-title">Producción</h2>
              <Link to="/production/orders">Ver órdenes <ArrowUpRight size={14} aria-hidden="true" /></Link>
            </div>
            <dl className="home-stats">
              {production.map(({ label, value, icon: Icon, warn }) => (
                <div key={label} className={warn && Number(value) > 0 ? 'is-warn' : ''}>
                  <dt><Icon size={14} aria-hidden="true" /> {label}</dt>
                  <dd>{value ?? '—'}</dd>
                </div>
              ))}
            </dl>
            <h3 className="home-sub">Próximas entregas</h3>
            {!jobs.length && !jobsQuery.isPending && (
              <p className="home-empty">No hay órdenes activas. Podés iniciar una desde Producción.</p>
            )}
            {jobs.slice().sort((a, b) => (a.due_on ?? '9999').localeCompare(b.due_on ?? '9999'))
              .slice(0, 5).map((job) => (
                <Link key={job.id} className="home-row" to={`/production/orders?job=${job.id}`}>
                  <span>
                    <strong>{job.product_name} · {job.planned_quantity}</strong>
                    <small>
                      {job.status === 'pendiente' ? 'En cola' : 'En fabricación'} ·{' '}
                      {job.due_on ? `Entrega ${day(job.due_on)}` : 'Sin fecha límite'}
                    </small>
                  </span>
                  <ArrowUpRight size={16} aria-hidden="true" />
                </Link>
              ))}
          </section>
        )}

        <section className="home-panel" aria-labelledby="home-alerts-title">
          <div className="home-panel-head">
            <h2 id="home-alerts-title">Avisos del sistema</h2>
            <span className="home-chip">{unread} sin leer</span>
          </div>
          {alertsPending && <p className="home-empty">Revisando avisos…</p>}
          {!alertsPending && !alerts.length && !alertsError && (
            <p className="home-empty">Sin avisos de mínimos ni de fechas próximas.</p>
          )}
          {alerts.slice(0, 6).map((alert) => (
            <Link key={alert.alert_key} className="home-row" to={alert.destination}>
              <span>
                <strong>
                  {alert.severity === 'critical' && <em className="home-tag">Crítico</em>}
                  {alert.title}
                </strong>
                <small>{alert.detail}</small>
              </span>
              <ArrowUpRight size={16} aria-hidden="true" />
            </Link>
          ))}
          {criticalAlerts > 0 && (
            <p className="home-note">
              {criticalAlerts === 1 ? '1 aviso crítico abierto.' : `${criticalAlerts} avisos críticos abiertos.`}
            </p>
          )}
          <p className="home-note">Los mínimos comparan existencias físicas; todavía no descuentan
            materiales reservados para otras órdenes.</p>
        </section>
      </div>

      {shortcuts.length > 0 && (
        <section className="home-shortcuts" aria-labelledby="home-short-title">
          <h2 id="home-short-title">Acciones rápidas</h2>
          <div>
            {shortcuts.map((entry) => {
              const Icon = entry.icon ?? ArrowUpRight;
              return entry.locked ? (
                <span key={entry.to + entry.label} className="is-locked" aria-label={`${entry.label}: acceso restringido`}>
                  {entry.label} <Lock size={15} aria-hidden="true" />
                </span>
              ) : (
                <Link key={entry.to + entry.label} to={entry.to}>
                  {entry.label} <Icon size={16} aria-hidden="true" />
                </Link>
              );
            })}
          </div>
        </section>
      )}
    </section>
  );
}

import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { ArrowUpRight, AlertTriangle, CalendarClock, Factory, ShoppingCart, Wallet, ShoppingBag, TrendingUp } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import './dashboard.css';

const money = (value) => Number(value).toLocaleString('es-AR', {
  style: 'currency', currency: 'ARS', maximumFractionDigits: 0,
});

export default function Dashboard() {
  const { activeCompany, activeCompanyId, user, can, role } = useAuth();
  const { data = {}, isPending, error, refetch } = useQuery({
    queryKey: ['erp-dashboard', user?.id, activeCompanyId],
    queryFn: async () => {
      const result = await supabase.rpc('erp_operational_dashboard', { p_company: activeCompanyId });
      if (result.error) throw result.error;
      return result.data;
    },
    enabled: Boolean(activeCompanyId),
  });
  const cards = [
    { label: 'Ventas · 30 días', value: data.sales_30d, icon: ShoppingBag,
      to: '/sales/orders', resource: 'sales' },
    { label: 'Facturación · 30 días', value: data.revenue_30d == null ? null : money(data.revenue_30d),
      icon: TrendingUp, to: '/sales/orders', resource: 'sales' },
    { label: 'Pendiente de cobro', value: data.receivables == null ? null : money(data.receivables),
      icon: Wallet, to: '/finance/receivables', resource: 'finance' },
    { label: 'Compras abiertas', value: data.open_orders, icon: ShoppingCart,
      to: '/purchases/orders', resource: 'purchases' },
    { label: 'Fabricaciones planificadas', value: data.planned_runs, icon: CalendarClock,
      to: '/production/planning', resource: 'production' },
    { label: 'Productos bajo mínimo', value: data.low_stock, icon: AlertTriangle,
      to: '/inventory/stock', resource: 'stock' },
    { label: 'Ganancia estimada · 30 días', value: data.profit_30d == null ? null : money(data.profit_30d),
      icon: Factory, to: '/finance/costs', resource: 'finance', adminOnly: true },
  ].filter((card) => (!card.adminOnly || role === 'admin') && can(card.resource, 'read')
    && card.value != null);
  const shortcuts = [
    { label: 'Registrar venta', to: '/sales/orders', resource: 'sales', action: 'insert' },
    { label: 'Nueva compra', to: '/purchases/orders', resource: 'purchases', action: 'insert' },
    { label: 'Planificar fabricación', to: '/production/planning', resource: 'production', action: 'insert' },
    { label: 'Lista de precios', to: '/sales/lista-precios', resource: 'sales', action: 'read' },
    { label: 'Costos y márgenes', to: '/finance/costs', resource: 'finance', action: 'read', adminOnly: true },
  ].filter((link) => (!link.adminOnly || role === 'admin') && can(link.resource, link.action));

  return <section className="erp-home">
    <div className="page-head"><div>
      <span className="eyebrow">VISTA GENERAL / INICIO</span>
      <h1>Tu operación, en un solo lugar</h1>
      <p>{activeCompany?.name} · Indicadores recientes y tareas pendientes.</p>
    </div></div>
    <div className="erp-home-hero">
      <div><span className="eyebrow light">RESUMEN OPERATIVO</span>
        <h2>Lo que necesitás, a mano.</h2>
        <p>Consultá tus movimientos y continuá el trabajo desde cada módulo.</p>
        {can('finance', 'read') && <Link to="/finance/treasury">Abrir tesorería <ArrowUpRight size={16} /></Link>}
      </div><div className="erp-home-hero-art" aria-hidden="true" />
    </div>
    <div className="erp-home-section"><div>
      <span className="eyebrow">ACTIVIDAD Y PENDIENTES</span>
      <h2>Indicadores principales</h2>
    </div><button type="button" onClick={() => refetch()} disabled={isPending}>Actualizar</button></div>
    {error && <p role="alert" className="error">No pudimos cargar el resumen.
      <button type="button" onClick={() => refetch()}>Reintentar</button></p>}
    <div className="erp-home-grid">{cards.map(({ label, value, icon: Icon, to }) =>
      <Link to={to} className="erp-home-card" key={label}>
        <span className="erp-home-card-icon"><Icon size={22} /></span>
        <span className="erp-home-value">{isPending ? '…' : value ?? '—'}</span>
        <span className="erp-home-label">{label} <ArrowUpRight size={16} /></span>
      </Link>)}</div>
    <div className="erp-home-shortcuts">
      <h2>Accesos directos</h2>
      <div>{shortcuts.map((link) => (
        <Link key={link.to} to={link.to}>{link.label} <ArrowUpRight size={16} /></Link>
      ))}</div>
    </div>
    <div className="erp-home-tip">Los costos por producto se actualizan al cambiar el proveedor
      principal o la cotización vigente. Los comprobantes anteriores conservan sus importes.</div>
  </section>;
}

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { AlertTriangle, ArrowUpRight, RefreshCw, ShoppingCart } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { friendlyError } from '../../lib/notifications';
import { getReplenishmentForecast } from '../../services/replenishment';
import { formatQuantity } from '../inventory/stockNumber';
import './replenishment.css';

const quantity = (value) => formatQuantity(Number(value ?? 0).toFixed(6));

export default function ReplenishmentPage() {
  const { activeCompanyId, user, can } = useAuth();
  const [filter, setFilter] = useState('attention');
  const [search, setSearch] = useState('');
  const allowed = can('stock', 'read') && can('purchases', 'read')
    && can('production', 'read');
  const query = useQuery({
    queryKey: ['replenishment-forecast', user?.id, activeCompanyId],
    queryFn: () => getReplenishmentForecast(activeCompanyId),
    enabled: Boolean(activeCompanyId && allowed),
    staleTime: 60_000,
  });
  const rows = query.data ?? [];
  const visible = rows.filter((row) => (filter === 'all' || row.alert_level !== 'ok')
    && `${row.item_code} ${row.item_name} ${row.supplier_name ?? ''}`
      .toLowerCase().includes(search.toLowerCase()));
  const critical = rows.filter((row) => row.alert_level === 'critical').length;
  const warning = rows.filter((row) => row.alert_level === 'warning').length;

  return (
    <section className="replenishment-page">
      <header className="page-head">
        <div>
          <span className="eyebrow">PRODUCCIÓN / ABASTECIMIENTO</span>
          <h1>Pronóstico y reposición</h1>
          <p>Anticipá faltantes usando el consumo registrado, el stock libre, las órdenes
            de compra pendientes y los plazos habituales de entrega.</p>
        </div>
      </header>
      {!allowed && <p role="alert" className="error">
        Necesitás permiso de lectura de producción, stock y compras.
      </p>}
      {allowed && <>
        <div className="replenishment-summary">
          <article><strong>{critical}</strong><span>Atención inmediata</span></article>
          <article><strong>{warning}</strong><span>Planificar compra</span></article>
          <article><strong>{rows.length}</strong><span>Insumos analizados</span></article>
        </div>
        <div className="replenishment-toolbar">
          <label>Buscar material o proveedor
            <input type="search" value={search} placeholder="Nombre o código"
              onChange={(event) => setSearch(event.target.value)} />
          </label>
          <label>Mostrar
            <select value={filter} onChange={(event) => setFilter(event.target.value)}>
              <option value="attention">Requieren atención</option>
              <option value="all">Todos los insumos</option>
            </select>
          </label>
          <button type="button" className="button outline" onClick={() => query.refetch()}
            disabled={query.isFetching}><RefreshCw size={16} /> Actualizar</button>
        </div>
        {query.isPending && <p>Cargando pronóstico…</p>}
        {query.isError && <p role="alert" className="error">{friendlyError(query.error)}</p>}
        {!query.isPending && !query.isError && !visible.length &&
          <p className="replenishment-empty">No hay materiales para este filtro.
            Si acabás de empezar, cargá stock mínimo y consumos para obtener estimaciones.</p>}
        <div className="replenishment-list">
          {visible.map((row) => {
            const haveHistory = row.history_days >= 14;
            const buy = Number(row.suggested_quantity) > 0;
            const params = new URLSearchParams({ item: row.item_id,
              quantity: String(row.suggested_quantity) });
            if (row.supplier_id) params.set('supplier', row.supplier_id);
            return <article className="replenishment-card" key={row.item_id}>
              <div className="replenishment-card-head">
                <div>
                  <small>{row.item_code}</small>
                  <h2>{row.item_name}</h2>
                </div>
                <span className={`replenishment-level ${row.alert_level}`}>
                  {row.alert_level === 'critical' ? <><AlertTriangle size={15} /> Urgente</>
                    : row.alert_level === 'warning' ? 'Planificar' : 'En nivel adecuado'}
                </span>
              </div>
              <div className="replenishment-values">
                <span>Físico <strong>{quantity(row.physical)}</strong></span>
                <span>Utilizable <strong>{quantity(row.usable)}</strong></span>
                <span>Asignado <strong>{quantity(row.reserved)}</strong></span>
                <span>Libre <strong>{quantity(row.free)}</strong></span>
                <span>Pedido pendiente <strong>{quantity(row.pending_purchase)}</strong></span>
                <span>Mínimo <strong>{quantity(row.minimum_stock)}</strong></span>
              </div>
              <p className="replenishment-detail">
                {haveHistory ? <>
                  Consumo: {quantity(row.daily_use)} {row.unit_symbol}/día ·
                  {row.days_left == null ? ' sin fecha estimada de agotamiento'
                    : ` aproximadamente ${row.days_left} días de stock libre`}
                </> : 'Historial insuficiente para estimar días de cobertura.'}
                {' · '}{row.supplier_name
                  ? `${row.supplier_name}: ${row.lead_time_days} días habituales`
                  : 'Sin proveedor asociado'}
              </p>
              {buy && <div className="replenishment-action">
                <span>Compra sugerida: <strong>{quantity(row.suggested_quantity)} {row.unit_symbol}</strong></span>
                {can('purchases', 'insert') && <Link className="button primary"
                  to={`/purchases/orders?${params}`}>
                  <ShoppingCart size={16} /> Preparar orden <ArrowUpRight size={15} />
                </Link>}
              </div>}
              {!buy && row.alert_level === 'critical' && !Number(row.minimum_stock)
                && !haveHistory && <p className="replenishment-detail">
                  Definí un stock mínimo o registrá consumos para calcular cuánto reponer.
                </p>}
            </article>;
          })}
        </div>
        <p className="replenishment-method">Estimación orientativa: se usan las salidas de los
          últimos 60 días, el stock utilizable libre y el mínimo configurado.
          El consumo diario aparece al contar con al menos 14 días de historial.
          La sugerencia descuenta lo ya pedido y agrega siete días de margen al plazo del
          proveedor. Revisá fecha de entrega, precio y cantidad antes de emitir la compra.</p>
      </>}
    </section>
  );
}

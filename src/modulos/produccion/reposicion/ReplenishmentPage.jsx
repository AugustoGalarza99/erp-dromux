import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import {
  AlertOctagon, ArrowUpRight, Boxes, CalendarClock, RefreshCw, ShoppingCart, X,
} from 'lucide-react';
import { useAuth } from '../../../compartido/contextos/AuthContext';
import ListPager, { usePagedList } from '../../../compartido/componentes/ListPager';
import { friendlyError } from '../../../compartido/utilidades/notifications';
import { getReplenishmentForecast } from './replenishment';
import { formatQuantity } from '../../stock/compartido/stockNumber';
import ProductionShell from '../compartido/ProductionShell';
import './replenishment.css';

const quantity = (value) => formatQuantity(Number(value ?? 0).toFixed(6));
const levelRank = { critical: 0, warning: 1, ok: 2 };
const levelText = { critical: 'Urgente', warning: 'Planificar', ok: 'En nivel' };
const normalize = (text) => String(text ?? '').toLowerCase()
  .normalize('NFD').replace(/[̀-ͯ]/g, '');

export default function ReplenishmentPage() {
  const { activeCompanyId, user, can } = useAuth();
  const [level, setLevel] = useState('attention');
  const [supplier, setSupplier] = useState('');
  const [search, setSearch] = useState('');
  const allowed = can('stock_saldos', 'ver') && can('produccion_reposicion', 'ver');
  const query = useQuery({
    queryKey: ['replenishment-forecast', user?.id, activeCompanyId],
    queryFn: () => getReplenishmentForecast(activeCompanyId),
    enabled: Boolean(activeCompanyId && allowed),
    staleTime: 60_000,
  });
  const rows = query.data ?? [];

  const counts = useMemo(() => ({
    critical: rows.filter((row) => row.alert_level === 'critical').length,
    warning: rows.filter((row) => row.alert_level === 'warning').length,
    ok: rows.filter((row) => row.alert_level === 'ok').length,
  }), [rows]);

  const suppliers = useMemo(() => [...new Map(rows
    .filter((row) => row.supplier_id)
    .map((row) => [row.supplier_id, row.supplier_name])).entries()]
    .sort((a, b) => String(a[1]).localeCompare(String(b[1]))), [rows]);

  const filtered = useMemo(() => {
    const words = normalize(search).split(/\s+/).filter(Boolean);
    return rows
      .filter((row) => (level === 'all'
        || (level === 'attention' ? row.alert_level !== 'ok' : row.alert_level === level))
        && (!supplier || row.supplier_id === supplier)
        && words.every((word) => normalize(
          `${row.item_code} ${row.item_name} ${row.supplier_name ?? ''}`).includes(word)))
      .sort((a, b) => (levelRank[a.alert_level] ?? 3) - (levelRank[b.alert_level] ?? 3)
        || Number(a.days_left ?? 99999) - Number(b.days_left ?? 99999)
        || String(a.item_name).localeCompare(String(b.item_name)));
  }, [rows, level, supplier, search]);

  const pager = usePagedList(filtered, { pageSize: 25, resetKey: `${level}|${supplier}|${search}` });
  const hasFilters = Boolean(search || supplier || level !== 'attention');
  const toBuy = filtered.filter((row) => Number(row.suggested_quantity) > 0).length;

  const segments = [
    ['attention', 'Requieren atención', counts.critical + counts.warning],
    ['critical', 'Urgentes', counts.critical],
    ['warning', 'A planificar', counts.warning],
    ['ok', 'En nivel adecuado', counts.ok],
    ['all', 'Todos', rows.length],
  ];

  return (
    <ProductionShell
      title="Pronóstico y reposición"
      description="Anticipá faltantes con el consumo registrado, el stock libre, las compras pendientes y los plazos habituales de entrega. Primero aparece lo más urgente."
      actions={(
        <button type="button" className="button outline" onClick={() => query.refetch()}
          disabled={query.isFetching || !allowed}>
          <RefreshCw size={16} aria-hidden="true" className={query.isFetching ? 'spin' : ''} />
          {query.isFetching ? 'Actualizando…' : 'Actualizar'}
        </button>
      )}
    >
    <section className="replenishment-page">
      {!allowed && <p role="alert" className="error">
        Necesitás permiso de lectura de producción, stock y compras.
      </p>}
      {allowed && <>
        <div className="mod-kpis">
          <article className={`mod-kpi ${counts.critical ? 'is-warn' : ''}`}>
            <span className="mod-kpi-top"><span className="mod-kpi-icon"><AlertOctagon size={18} aria-hidden="true" /></span>Urgentes</span>
            <strong>{query.isPending ? '…' : counts.critical}</strong>
            <small>Se agotan antes de que llegue una compra</small>
          </article>
          <article className="mod-kpi">
            <span className="mod-kpi-top"><span className="mod-kpi-icon"><CalendarClock size={18} aria-hidden="true" /></span>A planificar</span>
            <strong>{query.isPending ? '…' : counts.warning}</strong>
            <small>Conviene comprar pronto</small>
          </article>
          <article className="mod-kpi">
            <span className="mod-kpi-top"><span className="mod-kpi-icon"><Boxes size={18} aria-hidden="true" /></span>Insumos analizados</span>
            <strong>{query.isPending ? '…' : rows.length}</strong>
            <small>{counts.ok} en nivel adecuado</small>
          </article>
        </div>

        <div className="mod-segments" role="group" aria-label="Filtrar por estado">
          {segments.map(([value, label, count]) => (
            <button key={value} type="button" className="mod-segment"
              aria-pressed={level === value} onClick={() => setLevel(value)}>
              {label} <b>{count}</b>
            </button>
          ))}
        </div>

        <div className="mod-filters">
          <label className="mod-filter-grow">Buscar material o proveedor
            <input type="search" value={search} placeholder="Nombre, código o proveedor"
              onChange={(event) => setSearch(event.target.value)} />
          </label>
          <label>Proveedor
            <select value={supplier} onChange={(event) => setSupplier(event.target.value)}>
              <option value="">Todos los proveedores</option>
              {suppliers.map(([id, name]) => <option key={id} value={id}>{name}</option>)}
            </select>
          </label>
          {hasFilters && (
            <button type="button" className="button outline"
              onClick={() => { setSearch(''); setSupplier(''); setLevel('attention'); }}>
              <X size={15} aria-hidden="true" /> Limpiar filtros
            </button>
          )}
        </div>

        {query.isPending && <p className="mod-muted">Cargando pronóstico…</p>}
        {query.isError && <p role="alert" className="error">{friendlyError(query.error)}</p>}
        {!query.isPending && !query.isError && !filtered.length && (
          <p className="replenishment-empty">
            {rows.length
              ? 'No hay materiales con estos filtros. Probá con otro estado o limpiá los filtros.'
              : 'Todavía no hay datos para estimar. Cargá stock mínimo y registrá consumos.'}
          </p>
        )}

        {filtered.length > 0 && (
          <>
            <p className="mod-muted" role="status">
              {filtered.length} {filtered.length === 1 ? 'material' : 'materiales'}
              {toBuy ? ` · ${toBuy} con compra sugerida` : ''}
            </p>
            <div className="mod-table-wrap">
              <table className="mod-table">
                <thead>
                  <tr>
                    <th scope="col">Material</th>
                    <th scope="col">Estado</th>
                    <th scope="col" className="is-num">Libre</th>
                    <th scope="col" className="is-num">Cobertura</th>
                    <th scope="col" className="is-num">Compra sugerida</th>
                    <th scope="col">Proveedor</th>
                    <th scope="col"><span className="sr-only">Acción</span></th>
                  </tr>
                </thead>
                <tbody>
                  {pager.visible.map((row) => {
                    const haveHistory = row.history_days >= 14;
                    const buy = Number(row.suggested_quantity) > 0;
                    const params = new URLSearchParams({
                      item: row.item_id, quantity: String(row.suggested_quantity),
                    });
                    if (row.supplier_id) params.set('supplier', row.supplier_id);
                    const rowClass = row.alert_level === 'critical' ? 'is-urgent'
                      : row.alert_level === 'warning' ? 'is-attention' : '';
                    return (
                      <tr key={row.item_id} className={rowClass}>
                        <td className="is-name" data-label="Material">
                          <strong>{row.item_name}</strong>
                          <small>{row.item_code}</small>
                          <details className="mod-row-detail">
                            <summary>Ver detalle</summary>
                            <dl>
                              <div><dt>Físico</dt><dd>{quantity(row.physical)} {row.unit_symbol}</dd></div>
                              <div><dt>Utilizable</dt><dd>{quantity(row.usable)} {row.unit_symbol}</dd></div>
                              <div><dt>Asignado a órdenes</dt><dd>{quantity(row.reserved)} {row.unit_symbol}</dd></div>
                              <div><dt>Compra pendiente</dt><dd>{quantity(row.pending_purchase)} {row.unit_symbol}</dd></div>
                              <div><dt>Mínimo</dt><dd>{quantity(row.minimum_stock)} {row.unit_symbol}</dd></div>
                              <div><dt>Consumo diario</dt><dd>{haveHistory ? `${quantity(row.daily_use)} ${row.unit_symbol}` : 'Historial insuficiente'}</dd></div>
                            </dl>
                            {!buy && row.alert_level === 'critical' && !Number(row.minimum_stock) && !haveHistory && (
                              <p className="mod-muted">Definí un stock mínimo o registrá consumos para calcular cuánto reponer.</p>
                            )}
                          </details>
                        </td>
                        <td data-label="Estado">
                          <span className={`replenishment-level ${row.alert_level}`}>
                            {levelText[row.alert_level] ?? 'Sin dato'}
                          </span>
                        </td>
                        <td className="is-num" data-label="Libre">{quantity(row.free)} {row.unit_symbol}</td>
                        <td className="is-num" data-label="Cobertura">
                          {haveHistory && row.days_left != null ? `~${row.days_left} días` : 'Sin estimar'}
                        </td>
                        <td className="is-num" data-label="Compra sugerida">
                          {buy ? <strong>{quantity(row.suggested_quantity)} {row.unit_symbol}</strong> : '—'}
                        </td>
                        <td data-label="Proveedor">
                          <span>
                            {row.supplier_name
                              ? <>{row.supplier_name}<small className="replenishment-lead"> · {row.lead_time_days} días</small></>
                              : 'Sin proveedor'}
                          </span>
                        </td>
                        <td data-label="">
                          {buy && can('compras_ordenes', 'crear') && (
                            <Link className="button primary replenishment-buy" to={`/purchases/orders?${params}`}>
                              <ShoppingCart size={15} aria-hidden="true" /> Preparar orden <ArrowUpRight size={14} aria-hidden="true" />
                            </Link>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            <ListPager pager={pager} noun="materiales" />
          </>
        )}

        <details className="replenishment-method">
          <summary>Cómo se calcula esta estimación</summary>
          <p>Es orientativa: usa las salidas de los últimos 60 días, el stock utilizable libre y el
            mínimo configurado. El consumo diario aparece con al menos 14 días de historial. La
            sugerencia descuenta lo ya pedido y agrega siete días de margen al plazo del proveedor.
            Revisá fecha de entrega, precio y cantidad antes de emitir la compra.</p>
        </details>
      </>}
    </section>
    </ProductionShell>
  );
}

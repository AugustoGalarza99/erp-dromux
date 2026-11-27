import { friendlyError } from '../../lib/notifications';
import { useEffect, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link, useSearchParams } from 'react-router-dom';
import {
  ArrowDownToLine,
  ArrowRightLeft,
  ArrowUpFromLine,
  ChevronLeft,
  ChevronRight,
  X,
} from 'lucide-react';
import StockShell from './StockShell';
import { dateEs, lotLabel } from '../../lib/display';
import { useAuth } from '../../contexts/AuthContext';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import {
  findStockItems,
  findStockWarehouses,
  listStockMovements,
} from '../../services/stock';
import { formatQuantity } from './stockNumber';
import { findSalesByIds } from '../../services/sales';
import { readableMovementNote, saleIdFromNote } from './movementLabels';
import './stock.css';

const labels = {
  receipt: ['Entrada', ArrowDownToLine],
  issue: ['Salida', ArrowUpFromLine],
  transfer_out: ['Transferencia · salida', ArrowRightLeft],
  transfer_in: ['Transferencia · entrada', ArrowRightLeft],
};

export default function MovementsPage() {
  const { user, activeCompanyId, can } = useAuth();
  const [params, setParams] = useSearchParams();
  const isDate = (value) => /^\d{4}-\d{2}-\d{2}$/.test(value ?? '');
  const [page, setPage] = useState(0);
  const [itemId, setItemId] = useState(params.get('item') ?? '');
  const [warehouseId, setWarehouseId] = useState('');
  const [kind, setKind] = useState('');
  const [from, setFrom] = useState(isDate(params.get('from')) ? params.get('from') : '');
  const [to, setTo] = useState(isDate(params.get('to')) ? params.get('to') : '');
  const [selectedItem, setSelectedItem] = useState(null);
  const [selectedWarehouse, setSelectedWarehouse] = useState(null);
  // Si llegamos desde un ítem, el código precarga la lista de opciones del selector.
  const [itemSearch, setItemSearch] = useState(params.get('code') ?? '');
  const [warehouseSearch, setWarehouseSearch] = useState('');
  const itemTerm = useDebouncedValue(itemSearch);
  const warehouseTerm = useDebouncedValue(warehouseSearch);
  const hasFilters = Boolean(itemId || warehouseId || kind || from || to);

  useEffect(() => {
    if (params.toString()) setParams({}, { replace: true });
  }, []);

  const isFirstCompany = useRef(true);
  useEffect(() => {
    if (isFirstCompany.current) {
      isFirstCompany.current = false;
      return;
    }
    clearFilters();
  }, [activeCompanyId]);

  function clearFilters() {
    setPage(0);
    setItemId('');
    setWarehouseId('');
    setKind('');
    setFrom('');
    setTo('');
    setItemSearch('');
    setWarehouseSearch('');
    setSelectedItem(null);
    setSelectedWarehouse(null);
  }

  function setRange(days) {
    const end = new Date();
    const start = new Date();
    start.setDate(end.getDate() - days);
    const iso = (date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    setFrom(iso(start));
    setTo(iso(end));
    setPage(0);
  }

  const query = useQuery({
    queryKey: ['stock-movements', user?.id, activeCompanyId, page, itemId, warehouseId, kind, from, to],
    queryFn: () => listStockMovements(activeCompanyId, {
      page, itemId, warehouseId, kind, from, to,
    }),
    enabled: Boolean(activeCompanyId),
    staleTime: 15_000,
  });

  const itemsQuery = useQuery({
    queryKey: ['stock-options', user?.id, activeCompanyId, 'items', itemTerm],
    queryFn: () => findStockItems(activeCompanyId, itemTerm),
    enabled: Boolean(activeCompanyId),
  });

  const warehousesQuery = useQuery({
    queryKey: ['stock-options', user?.id, activeCompanyId, 'warehouses', warehouseTerm],
    queryFn: () => findStockWarehouses(activeCompanyId, warehouseTerm),
    enabled: Boolean(activeCompanyId),
  });

  const rows = query.data?.rows ?? [];
  const saleIds = [...new Set(rows.map((row) => saleIdFromNote(row.note)).filter(Boolean))];
  const linkedSales = useQuery({
    queryKey: ['movement-sale-labels', user?.id, activeCompanyId, saleIds.join(',')],
    queryFn: () => findSalesByIds(activeCompanyId, saleIds),
    enabled: Boolean(activeCompanyId && saleIds.length && can('sales', 'read')),
  });
  const saleNames = Object.fromEntries((linkedSales.data ?? []).map((sale) => [sale.id, sale]));
  const count = query.data?.count ?? 0;
  const pages = Math.max(1, Math.ceil(count / 25));
  const itemOptions = selectedItem
    && !(itemsQuery.data ?? []).some((item) => item.id === selectedItem.id)
    ? [selectedItem, ...(itemsQuery.data ?? [])] : (itemsQuery.data ?? []);
  const warehouseOptions = selectedWarehouse
    && !(warehousesQuery.data ?? []).some((entry) => entry.id === selectedWarehouse.id)
    ? [selectedWarehouse, ...(warehousesQuery.data ?? [])]
    : (warehousesQuery.data ?? []);

  return (
    <StockShell
      title="Movimientos"
      description="Historial de cada entrada, salida y transferencia, con fecha, depósito y saldo resultante. No se puede editar: es el respaldo del stock."
    >
    <div className="stock-page">
      <section className="stock-card">
        <div className="movement-ranges" role="group" aria-label="Rangos de fecha rápidos">
          <button type="button" className="button outline" onClick={() => setRange(0)}>Hoy</button>
          <button type="button" className="button outline" onClick={() => setRange(7)}>Últimos 7 días</button>
          <button type="button" className="button outline" onClick={() => setRange(30)}>Últimos 30 días</button>
          {hasFilters && (
            <button type="button" className="button outline" onClick={clearFilters}>
              <X size={15} aria-hidden="true" /> Limpiar filtros
            </button>
          )}
        </div>
        <div className="movement-filters">
          <label>
            Buscar ítem
            <input
              value={itemSearch}
              onChange={(event) => setItemSearch(event.target.value)}
              placeholder="Nombre, código o código de barras"
            />
            <select value={itemId} onChange={(event) => {
              setItemId(event.target.value);
              setSelectedItem((itemsQuery.data ?? []).find(
                (item) => item.id === event.target.value,
              ) ?? null);
              setPage(0);
            }}>
              <option value="">Todos los ítems</option>
              {itemOptions.map((item) => (
                <option value={item.id} key={item.id}>{item.code} · {item.name}</option>
              ))}
            </select>
          </label>
          <label>
            Buscar depósito
            <input
              value={warehouseSearch}
              onChange={(event) => setWarehouseSearch(event.target.value)}
              placeholder="Nombre o código"
            />
            <select value={warehouseId} onChange={(event) => {
              setWarehouseId(event.target.value);
              setSelectedWarehouse((warehousesQuery.data ?? []).find(
                (entry) => entry.id === event.target.value,
              ) ?? null);
              setPage(0);
            }}>
              <option value="">Todos los depósitos</option>
              {warehouseOptions.map((warehouse) => (
                <option value={warehouse.id} key={warehouse.id}>
                  {warehouse.name}
                </option>
              ))}
            </select>
          </label>
          <label>
            Tipo de movimiento
            <select value={kind} onChange={(event) => {
              setKind(event.target.value);
              setPage(0);
            }}>
              <option value="">Todos</option>
              {Object.entries(labels).map(([key, [label]]) => (
                <option value={key} key={key}>{label}</option>
              ))}
            </select>
          </label>
          <label>
            Desde
            <input
              type="date"
              value={from}
              max={to || undefined}
              onChange={(event) => { setFrom(event.target.value); setPage(0); }}
            />
          </label>
          <label>
            Hasta
            <input
              type="date"
              value={to}
              min={from || undefined}
              onChange={(event) => { setTo(event.target.value); setPage(0); }}
            />
          </label>
        </div>

        {(query.error || itemsQuery.error || warehousesQuery.error) && (
          <p role="alert" className="error">
            {(query.error && friendlyError(query.error)) || (itemsQuery.error && friendlyError(itemsQuery.error))
              || (warehousesQuery.error && friendlyError(warehousesQuery.error))}
          </p>
        )}
        {query.isPending && <p className="stock-muted">Cargando movimientos…</p>}
        {!query.isPending && rows.length === 0 && (
          <div className="stock-empty">
            <h2>Sin movimientos para este filtro</h2>
            <p>Las entradas, salidas y transferencias aparecerán acá.</p>
          </div>
        )}
        {rows.map((row) => {
          const [label, Icon] = labels[row.kind];
          const positive = !String(row.delta).startsWith('-');

          return (
            <article className="movement-row" key={row.id}>
              <span className={`movement-icon ${positive ? 'positive' : 'negative'}`}>
                <Icon size={19} />
              </span>
              <div className="movement-description">
                <strong>
                  {label} ·{' '}
                  {can('items', 'read')
                    ? <Link className="movement-item-link" to={`/inventory/items/${row.item_id}`}>{row.item_code}</Link>
                    : row.item_code}
                </strong>
                <small>
                  {row.warehouse_code} · {new Date(row.created_at).toLocaleString('es-AR')}
                </small>
                <p>{readableMovementNote(row.note, saleNames)}</p>
                {row.lot_code && (
                  <small>
                    Lote {lotLabel(row.lot_code)}
                    {row.lot_expires_on ? ` · vence ${dateEs(row.lot_expires_on)}` : ''}
                  </small>
                )}

              </div>
              <div className="movement-amount">
                <strong className={positive ? 'positive' : 'negative'}>
                  {positive ? '+' : '−'}{formatQuantity(String(row.delta).replace('-', ''))} {row.unit_symbol}
                </strong>
                <small>Saldo después: {formatQuantity(row.balance_after)} {row.unit_symbol}</small>
              </div>
            </article>
          );
        })}
        <div className="stock-pagination">
          <span>{count} movimientos · página {page + 1} de {pages}</span>
          <div>
            <button
              aria-label="Página anterior"
              disabled={page === 0}
              onClick={() => setPage((value) => value - 1)}
            ><ChevronLeft size={18} /></button>
            <button
              aria-label="Página siguiente"
              disabled={page + 1 >= pages}
              onClick={() => setPage((value) => value + 1)}
            ><ChevronRight size={18} /></button>
          </div>
        </div>
      </section>
    </div>
    </StockShell>
  );
}

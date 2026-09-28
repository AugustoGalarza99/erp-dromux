import { friendlyError } from '../../lib/notifications';
import { useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import {
  ArrowDownToLine,
  ArrowLeft,
  ArrowRightLeft,
  ArrowUpFromLine,
  ChevronLeft,
  ChevronRight,
} from 'lucide-react';
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
  const [page, setPage] = useState(0);
  const [itemId, setItemId] = useState('');
  const [warehouseId, setWarehouseId] = useState('');
  const [kind, setKind] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [selectedItem, setSelectedItem] = useState(null);
  const [selectedWarehouse, setSelectedWarehouse] = useState(null);
  const [itemSearch, setItemSearch] = useState('');
  const [warehouseSearch, setWarehouseSearch] = useState('');
  const itemTerm = useDebouncedValue(itemSearch);
  const warehouseTerm = useDebouncedValue(warehouseSearch);

  useEffect(() => {
    setPage(0);
    setItemId('');
    setWarehouseId('');
    setKind('');
    setFrom('');
    setTo('');
    setSelectedItem(null);
    setSelectedWarehouse(null);
  }, [activeCompanyId]);

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
    <div className="stock-page">
      <Link to="/inventory/stock" className="back-link">
        <ArrowLeft size={17} /> Volver a stock
      </Link>
      <div className="page-head">
        <div>
          <span className="eyebrow">INVENTARIO / AUDITORÍA</span>
          <h1>Movimientos de stock</h1>
          <p>Cada fila representa una variación real en un depósito.</p>
        </div>
      </div>

      <section className="stock-card">
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
                <strong>{label} · {row.item_code}</strong>
                <small>
                  {row.warehouse_code} · {new Date(row.created_at).toLocaleString('es-AR')}
                </small>
                <p>{readableMovementNote(row.note, saleNames)}</p>
                {row.lot_code && (
                  <small>
                    Lote {row.lot_code}
                    {row.lot_expires_on ? ` · vence ${row.lot_expires_on}` : ''}
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
  );
}

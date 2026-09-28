import { friendlyError } from '../../lib/notifications';
import { useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Boxes, ChevronLeft, ChevronRight, Search } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import {
  listStock,
  listStockBalances,
  listStockLotBreakdown,
} from '../../services/stock';
import PostStockOperation from './PostStockOperation';
import { formatQuantity, isAtOrBelow } from './stockNumber';
import './stock.css';

export default function StockPage() {
  const { activeCompanyId, user } = useAuth();
  const [page, setPage] = useState(0);
  const [search, setSearch] = useState('');
  const [inputSearch, setInputSearch] = useState('');
  const [selected, setSelected] = useState(null);

  useEffect(() => {
    setPage(0);
    setSelected(null);
  }, [activeCompanyId]);

  const stockQuery = useQuery({
    queryKey: ['stock-summary', user?.id, activeCompanyId, page, search],
    queryFn: () => listStock(activeCompanyId, page, search),
    enabled: Boolean(activeCompanyId),
    staleTime: 15_000,
  });

  const balanceQuery = useQuery({
    queryKey: ['stock-balances', user?.id, activeCompanyId, selected?.item_id],
    queryFn: () => listStockBalances(activeCompanyId, selected.item_id),
    enabled: Boolean(activeCompanyId && selected?.item_id),
    staleTime: 15_000,
  });

  const lotBreakdownQuery = useQuery({
    queryKey: ['stock-lot-breakdown', user?.id, activeCompanyId, selected?.item_id],
    queryFn: () => listStockLotBreakdown(activeCompanyId, selected.item_id),
    enabled: Boolean(activeCompanyId && selected?.item_id && selected.track_lots),
    staleTime: 15_000,
  });

  const rows = stockQuery.data?.rows ?? [];
  const count = stockQuery.data?.count ?? 0;
  const pages = Math.max(1, Math.ceil(count / 25));
  const balances = balanceQuery.data ?? [];

  const submitSearch = () => {
    setPage(0);
    setSearch(inputSearch.trim());
    setSelected(null);
  };

  return (
    <div className="stock-page">
      <div className="page-head">
        <div>
          <span className="eyebrow">INVENTARIO / EXISTENCIAS</span>
          <h1>Stock actual</h1>
          <p>Consultá lo disponible por ítem y por depósito.</p>
        </div>
        <Link to="/inventory/movements" className="button stock-outline">
          Ver historial
        </Link>
      </div>

      <div className="stock-intro">
        <Boxes size={21} />
        <div>
          <strong>Una sola fuente de stock</strong>
          <p>
            Los saldos se actualizan al registrar movimientos. El valor inicial
            se carga como una entrada con motivo “Conteo inicial”.
          </p>
        </div>
      </div>

      <div className="stock-layout">
        <div className="stock-left">
          <section className="stock-card">
            <div className="stock-toolbar">
              <div className="stock-search">
                <Search size={18} />
                <input
                  aria-label="Buscar por nombre o código"
                  placeholder="Buscar por nombre o código"
                  value={inputSearch}
                  onChange={(event) => setInputSearch(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === 'Enter') submitSearch();
                  }}
                />
              </div>
              <button className="button stock-search-button" onClick={submitSearch}>
                Buscar
              </button>
            </div>
            {stockQuery.error && (
              <p role="alert" className="error">{friendlyError(stockQuery.error)}</p>
            )}
            {stockQuery.isPending && <p className="stock-muted">Cargando saldos…</p>}
            {!stockQuery.isPending && !stockQuery.error && rows.length === 0 && (
              <div className="stock-empty">
                <Boxes size={28} />
                <h2>No se encontraron ítems</h2>
                <p>Creá un ítem o cambiá la búsqueda.</p>
              </div>
            )}
            {rows.map((row) => {
              const low = !isAtOrBelow(row.minimum_stock, '0')
                && isAtOrBelow(row.total_quantity, row.minimum_stock);

              return (
                <button
                  key={row.item_id}
                  className={`stock-row ${selected?.item_id === row.item_id ? 'selected' : ''}`}
                  onClick={() => setSelected(row)}
                >
                  <span className="stock-row-icon"><Boxes size={19} /></span>
                  <span className="stock-row-name">
                    <strong>{row.item_name}</strong>
                    <small>{row.item_code} · mínimo {formatQuantity(row.minimum_stock)} {row.unit_symbol}</small>
                  </span>
                  <span className="stock-row-total">
                    <strong>{formatQuantity(row.total_quantity)} {row.unit_symbol}</strong>
                    <small className={low ? 'low' : ''}>
                      {low ? 'En mínimo' : `${row.warehouse_count} depósitos`}
                    </small>
                  </span>
                </button>
              );
            })}
            <div className="stock-pagination">
              <span>{count} ítems · página {page + 1} de {pages}</span>
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

          {selected && (
            <section className="stock-card stock-detail">
              <span className="eyebrow">DESGLOSE POR DEPÓSITO</span>
              <h2>{selected.item_name}</h2>
              <p>
                Total actual: {formatQuantity(
                  rows.find((row) => row.item_id === selected.item_id)?.total_quantity
                    ?? selected.total_quantity,
                )} {selected.unit_symbol}
              </p>
              {balanceQuery.error && (
                <p role="alert" className="error">{friendlyError(balanceQuery.error)}</p>
              )}
              {balanceQuery.isPending && <p>Cargando depósitos…</p>}
              {!balanceQuery.isPending && balances.length === 0 && (
                <p>Todavía no hay unidades disponibles en ningún depósito.</p>
              )}
              {balances.map((balance) => (
                <div className="stock-warehouse-row" key={balance.warehouse_id}>
                  <span>{balance.warehouse?.name ?? balance.warehouse_id}</span>
                  <strong>{formatQuantity(balance.quantity)} {selected.unit_symbol}</strong>
                </div>
              ))}
              {selected.track_lots && (
                <div className="stock-lot-breakdown">
                  <h3>Existencias por lote</h3>
                  {lotBreakdownQuery.error && (
                    <p role="alert" className="error">
                      {friendlyError(lotBreakdownQuery.error)}
                    </p>
                  )}
                  {lotBreakdownQuery.isPending && <p>Cargando lotes…</p>}
                  {!lotBreakdownQuery.isPending
                    && (lotBreakdownQuery.data ?? []).length === 0 && (
                      <p>Aún no hay lotes con existencias.</p>
                    )}
                  {(lotBreakdownQuery.data ?? []).map((lot) => (
                    <div
                      className="stock-lot-row"
                      key={`${lot.warehouse_id}-${lot.lot_code}`}
                    >
                      <span>
                        <strong>{lot.lot_code}</strong> · {lot.warehouse_name}
                        {lot.expires_on ? ` · vence ${lot.expires_on}` : ''}
                      </span>
                      <strong>{formatQuantity(lot.quantity)} {selected.unit_symbol}</strong>
                    </div>
                  ))}
                </div>
              )}
            </section>
          )}
        </div>
        <PostStockOperation initialItem={selected} />
      </div>
    </div>
  );
}

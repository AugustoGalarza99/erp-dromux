import { friendlyError } from '../../../compartido/utilidades/notifications';
import { useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link, useSearchParams } from 'react-router-dom';
import {
  ArrowRightLeft, Boxes, ChevronLeft, ChevronRight, Pencil, Search, X,
} from 'lucide-react';
import { useAuth } from '../../../compartido/contextos/AuthContext';
import {
  listStock,
  listStockBalances,
  listStockLotBreakdown,
} from '../compartido/stock';
import PostStockOperation from './PostStockOperation';
import StockShell from '../compartido/StockShell';
import { dateEs, lotLabel } from '../../../compartido/utilidades/display';
import { formatQuantity, isAtOrBelow } from '../compartido/stockNumber';
import '../compartido/stock.css';

export default function StockPage() {
  const { activeCompanyId, user, can } = useAuth();
  const [params, setParams] = useSearchParams();
  const initialSearch = params.get('q') ?? '';
  const [page, setPage] = useState(0);
  const [search, setSearch] = useState(initialSearch);
  const [inputSearch, setInputSearch] = useState(initialSearch);
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

  const submitSearch = (term = inputSearch) => {
    const clean = term.trim();
    setPage(0);
    setSearch(clean);
    setSelected(null);
    const next = new URLSearchParams(params);
    if (clean) next.set('q', clean); else next.delete('q');
    setParams(next, { replace: true });
  };

  // Llegando desde Ítems con ?q=código: si hay un único resultado, se abre su detalle.
  useEffect(() => {
    if (!selected && initialSearch && rows.length === 1 && search === initialSearch) {
      setSelected(rows[0]);
    }
  }, [rows, search]);

  return (
    <StockShell
      title="Stock por depósito"
      description="Consultá lo disponible por ítem y por depósito, y registrá entradas, salidas y transferencias."
      actions={(
        <Link to="/inventory/movements" className="button outline">
          <ArrowRightLeft size={16} aria-hidden="true" /> Ver historial
        </Link>
      )}
    >
      <div className="stock-page">
      <p className="stock-hint">
        <Boxes size={17} aria-hidden="true" />
        Los saldos cambian solo al registrar movimientos. La existencia inicial se carga
        como una entrada con motivo “Conteo inicial”.
      </p>

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
              <button type="button" className="button stock-search-button" onClick={() => submitSearch()}>
                Buscar
              </button>
              {search && (
                <button
                  type="button"
                  className="button outline"
                  onClick={() => { setInputSearch(''); submitSearch(''); }}
                >
                  <X size={15} aria-hidden="true" /> Limpiar
                </button>
              )}
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
              const low = !row.infinite_stock && !isAtOrBelow(row.minimum_stock, '0')
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
                    <small>{row.item_code} · {row.infinite_stock ? 'stock infinito' : `mínimo ${formatQuantity(row.minimum_stock)} ${row.unit_symbol}`}</small>
                  </span>
                  <span className="stock-row-total">
                    <strong>{row.infinite_stock ? '∞' : `${formatQuantity(row.total_quantity)} ${row.unit_symbol}`}</strong>
                    <small className={low ? 'low' : ''}>
                      {row.infinite_stock ? 'Sin control de existencias' : low ? 'En mínimo' : `${row.warehouse_count} depósitos`}
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
                Total actual: {selected.infinite_stock ? '∞ · stock infinito' : `${formatQuantity(rows.find((row) => row.item_id === selected.item_id)?.total_quantity ?? selected.total_quantity)} ${selected.unit_symbol}`}
              </p>
              <div className="stock-detail-links">
                <Link
                  className="button outline"
                  to={`/inventory/movements?item=${selected.item_id}&code=${encodeURIComponent(selected.item_code)}`}
                >
                  <ArrowRightLeft size={15} aria-hidden="true" /> Ver movimientos
                </Link>
                {can('items', 'read') && (
                  <Link className="button outline" to={`/inventory/items/${selected.item_id}`}>
                    <Pencil size={15} aria-hidden="true" /> Ver ficha del ítem
                  </Link>
                )}
              </div>
              {balanceQuery.error && (
                <p role="alert" className="error">{friendlyError(balanceQuery.error)}</p>
              )}
              {!selected.infinite_stock && balanceQuery.isPending && <p>Cargando depósitos…</p>}
              {!selected.infinite_stock && !balanceQuery.isPending && balances.length === 0 && (
                <p>Todavía no hay unidades disponibles en ningún depósito.</p>
              )}
              {balances.map((balance) => (
                <div className="stock-warehouse-row" key={balance.warehouse_id}>
                  <span>{balance.warehouse?.name ?? 'Depósito'}</span>
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
                        <strong>{lotLabel(lot.lot_code)}</strong> · {lot.warehouse_name}
                        {lot.expires_on ? ` · vence ${dateEs(lot.expires_on)}` : ''}
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
    </StockShell>
  );
}

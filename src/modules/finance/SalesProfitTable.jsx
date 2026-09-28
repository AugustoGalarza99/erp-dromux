import { useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import { friendlyError } from '../../lib/notifications';
import { listSalesProfitDetail } from '../../services/costing';

const today = () => new Intl.DateTimeFormat('sv-SE', {
  timeZone: 'America/Argentina/Buenos_Aires',
}).format(new Date());
const currency = (value) => value == null ? 'Sin costo' : Number(value).toLocaleString('es-AR', {
  style: 'currency', currency: 'ARS',
});

export default function SalesProfitTable() {
  const { activeCompanyId, user } = useAuth();
  const [from, setFrom] = useState(() => `${today().slice(0, 7)}-01`);
  const [to, setTo] = useState(today);
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(0);
  const term = useDebouncedValue(search);
  const valid = !!from && !!to && to >= from
    && (new Date(`${to}T12:00:00`) - new Date(`${from}T12:00:00`)) <= 366 * 86400000;
  const query = useQuery({
    queryKey: ['sales-profit-detail', user?.id, activeCompanyId, from, to, term, page],
    queryFn: () => listSalesProfitDetail(activeCompanyId, from, to, term, page),
    enabled: Boolean(activeCompanyId && valid),
  });
  useEffect(() => setPage(0), [activeCompanyId, from, to, term]);
  const rows = query.data ?? [];
  const total = Number(rows[0]?.total_rows ?? 0);
  const pageRevenue = rows.reduce((sum, row) => sum + Number(row.net_revenue), 0);
  const pageCost = rows.reduce((sum, row) => sum + Number(row.known_cost ?? 0), 0);
  const missing = rows.reduce((sum, row) => sum + Number(row.missing_lines), 0);

  return (
    <section className="finance-extra-card profit-detail" id="ventas">
      <h2>Ganancia por venta</h2>
      <p className="finance-extra-note">Cada venta conserva el precio y el costo estimado vigentes al confirmarla.
        Las devoluciones ajustan el importe vendido; los productos devueltos al stock dejan de contar en el costo.</p>
      <div className="profit-filters">
        <label>Desde<input type="date" value={from} max={to || undefined}
          onChange={(event) => setFrom(event.target.value)} /></label>
        <label>Hasta<input type="date" value={to} min={from || undefined}
          onChange={(event) => setTo(event.target.value)} /></label>
        <label>Buscar cliente, número o producto
          <input type="search" value={search} placeholder="Buscar venta…"
            onChange={(event) => setSearch(event.target.value)} />
        </label>
      </div>
      {!valid && <p role="alert" className="error">Elegí un período válido de hasta un año.</p>}
      {query.isPending && valid && <p>Buscando ventas…</p>}
      {query.error && <p role="alert" className="error">{friendlyError(query.error)}</p>}
      {query.data && !rows.length && <p>No se encontraron ventas para este período.</p>}
      {!!rows.length && <>
        <div className="profit-page-summary">
          <span>En esta página: vendido <strong>{currency(pageRevenue)}</strong></span>
          <span>Costo identificado <strong>{currency(pageCost)}</strong></span>
          {missing > 0 && <span className="finance-negative">{missing} productos sin costo</span>}
        </div>
        <div className="finance-extra-table-wrap" role="region" aria-label="Detalle de rentabilidad por venta" tabIndex={0}>
          <table className="finance-extra-table profit-table">
            <thead><tr>
              <th>Venta y cliente</th><th>Productos</th><th>Vendido neto</th>
              <th>Costo</th><th>Ganancia bruta</th>
            </tr></thead>
            <tbody>{rows.map((row) => <tr key={row.sale_id}>
              <td><strong>Venta Nº {row.sale_number}</strong>
                <small>{row.customer_name} · {new Date(row.sold_at).toLocaleDateString('es-AR')}</small>
                {row.cancelled && <small className="finance-negative">Anulada</small>}
              </td>
              <td>{row.product_summary}</td>
              <td>{currency(row.net_revenue)}</td>
              <td>{row.missing_lines > 0
                ? <span title="Costo parcial: faltan productos sin costo">{currency(row.known_cost)}*</span>
                : currency(row.known_cost)}</td>
              <td className={Number(row.gross_profit) < 0 ? 'finance-negative' : ''}>
                {row.gross_profit == null ? 'Sin calcular' : currency(row.gross_profit)}
              </td>
            </tr>)}</tbody>
          </table>
        </div>
        <nav className="profit-pagination" aria-label="Páginas de ventas">
          <span>{total} ventas · Página {page + 1} de {Math.ceil(total / 25)}</span>
          <button type="button" className="button outline" disabled={page === 0 || query.isFetching}
            onClick={() => setPage((current) => current - 1)} aria-label="Página anterior">
            <ChevronLeft size={17} /> Anterior
          </button>
          <button type="button" className="button outline"
            disabled={(page + 1) * 25 >= total || query.isFetching}
            onClick={() => setPage((current) => current + 1)} aria-label="Página siguiente">
            Siguiente <ChevronRight size={17} />
          </button>
        </nav>
        {missing > 0 && <p className="finance-extra-note">* El costo mostrado es parcial.
          La ganancia de esa venta queda sin calcular hasta revisar su costo histórico.</p>}
      </>}
      <p className="finance-extra-note">Ganancia bruta = importe vendido neto − costo de los productos no devueltos al stock.
        No incluye impuestos, comisiones ni gastos indirectos. Si se mezclan lotes con costos distintos,
        el costo guardado al vender puede no coincidir con el costo del lote entregado.</p>
    </section>
  );
}

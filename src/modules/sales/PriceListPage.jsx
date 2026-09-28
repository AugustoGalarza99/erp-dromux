import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { ArrowUpRight, Search, Tags } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import { friendlyError } from '../../lib/notifications';
import { listPublicPrices } from '../../services/sales';
import './sales.css';

const money = (value) => Number(value).toLocaleString('es-AR', {
  style: 'currency', currency: 'ARS',
});

export default function PriceListPage() {
  const { activeCompanyId, user, can } = useAuth();
  const [search, setSearch] = useState('');
  const term = useDebouncedValue(search);
  const query = useQuery({
    queryKey: ['public-price-list', user?.id, activeCompanyId, term],
    queryFn: () => listPublicPrices(activeCompanyId, term),
    enabled: Boolean(activeCompanyId),
  });

  return <section className="sales-page price-list-page">
    <div className="sales-heading">
      <div><span className="eyebrow">VENTAS / CONSULTA</span>
        <h1>Lista de precios</h1>
        <p>Precios finales vigentes por unidad para consultar antes de vender.</p>
      </div>
      {can('sales', 'insert') && <Link className="button primary" to="/sales/orders">
        Registrar venta <ArrowUpRight size={17} />
      </Link>}
    </div>
    <div className="sales-card sales-wide">
      <label className="sales-search"><Search size={18} />
        <input aria-label="Buscar producto" placeholder="Buscar por código o producto"
          value={search} onChange={(event) => setSearch(event.target.value)} />
      </label>
      {query.isPending && <p className="sales-muted">Cargando precios…</p>}
      {query.error && <p role="alert" className="sales-error">{friendlyError(query.error)}</p>}
      {!query.isPending && !query.error && !query.data?.length && (
        <p className="sales-muted">No hay productos para esta búsqueda.</p>
      )}
      <div className="erp-table-scroll">
        <table className="erp-data-table">
          <thead><tr><th>Producto</th><th>Unidad</th><th>Precio final</th></tr></thead>
          <tbody>{(query.data ?? []).map((item) => (
            <tr key={item.id}>
              <td><strong>{item.name}</strong><small>{item.code}</small></td>
              <td>{item.unit_symbol}</td>
              <td className="erp-price-value">{item.price == null
                ? <span className="erp-price-missing"><Tags size={14} /> Sin precio</span>
                : money(item.price)}</td>
            </tr>
          ))}</tbody>
        </table>
      </div>
    </div>
  </section>;
}

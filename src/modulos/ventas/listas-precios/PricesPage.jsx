import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Search, Tags } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import { listSaleProducts, saveSalePrice } from '../../services/sales';
import './sales.css';

const money = (value) => Number(value).toLocaleString('es-AR', { minimumFractionDigits: 2 });

function ProductPrice({ item, companyId, onSaved, canEdit }) {
  const [price, setPrice] = useState(item.sale_unit_price == null ? '' : String(item.sale_unit_price));
  const [busy, setBusy] = useState(false);
  async function submit(event) {
    event.preventDefault();
    setBusy(true);
    try {
      await saveSalePrice(companyId, item.id, price);
      await onSaved();
      notifySuccess('Precio actualizado', item.name);
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }
  return <form className="sales-price-row" onSubmit={submit}>
    <div><strong>{item.code} · {item.name}</strong>
      <small>{item.units?.symbol} · {item.active ? 'Activo' : 'Inactivo'}</small>
    </div>
    <label>Precio por {item.units?.symbol}
      <input aria-label={`Precio de ${item.name}`} type="number" min="0" step="0.01"
        value={price} onChange={(event) => setPrice(event.target.value)} />
    </label>
    <button type="submit" className="button primary" disabled={busy || !canEdit || !item.active ||
      price === (item.sale_unit_price == null ? '' : String(item.sale_unit_price))}>
      {busy ? 'Guardando…' : 'Guardar precio'}
    </button>
    {item.reference_unit_cost != null && <small className="sales-price-hint">
      Costo de referencia: $ {money(item.reference_unit_cost)}
    </small>}
  </form>;
}

export default function PricesPage() {
  const { activeCompanyId, user, can } = useAuth();
  const client = useQueryClient();
  const [search, setSearch] = useState('');
  const query = useQuery({
    queryKey: ['sales-products', user?.id, activeCompanyId],
    queryFn: () => listSaleProducts(activeCompanyId),
    enabled: !!activeCompanyId,
  });
  const filtered = (query.data ?? []).filter((item) =>
    `${item.name} ${item.code}`.toLowerCase().includes(search.toLowerCase()));
  const refresh = () => client.invalidateQueries({
    queryKey: ['sales-products', user?.id, activeCompanyId],
  });
  return <section className="sales-page">
    <div className="sales-heading"><div>
      <span className="eyebrow">VENTAS / PRECIOS</span><h1>Precios de venta</h1>
      <p>Definí el precio por unidad de cada producto terminado antes de venderlo.</p>
    </div><Link className="button" to="/sales/orders">Registrar venta</Link></div>
    <div className="sales-card sales-wide">
      <h2><Tags size={19} /> Productos terminados</h2>
      <div className="sales-search"><Search size={17} />
        <input aria-label="Buscar producto" placeholder="Buscar producto…" value={search}
          onChange={(event) => setSearch(event.target.value)} />
      </div>
      {!can('items', 'update') && <p className="sales-muted">
        Para editar precios necesitás el permiso Ítems → Editar.
      </p>}
      {query.isError && <p className="sales-error">{friendlyError(query.error)}</p>}
      {!filtered.length && !query.isPending && <p className="sales-muted">
        No hay productos terminados para mostrar.
      </p>}
      {filtered.map((item) => <ProductPrice key={`${activeCompanyId}-${item.id}`} item={item}
        companyId={activeCompanyId} onSaved={refresh} canEdit={can('items', 'update')} />)}
    </div>
  </section>;
}

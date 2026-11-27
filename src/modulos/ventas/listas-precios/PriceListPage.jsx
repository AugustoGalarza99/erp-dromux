import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Search, Tags } from 'lucide-react';
import { useAuth } from '../../../compartido/contextos/AuthContext';
import { useDebouncedValue } from '../../../compartido/hooks/useDebouncedValue';
import { friendlyError } from '../../../compartido/utilidades/notifications';
import { listPublicPrices } from '../compartido/sales';

const money = (value) => Number(value).toLocaleString('es-AR', {
  style: 'currency', currency: 'ARS',
});

/*
 * Consulta del precio único por producto. Se muestra mientras la base no tiene las listas de precios
 * múltiples (migración 039); después la reemplaza PriceListsPage.
 */
export default function LegacyPriceList() {
  const { activeCompanyId, user } = useAuth();
  const [search, setSearch] = useState('');
  const term = useDebouncedValue(search);
  const query = useQuery({
    queryKey: ['public-price-list', user?.id, activeCompanyId, term],
    queryFn: () => listPublicPrices(activeCompanyId, term),
    enabled: Boolean(activeCompanyId),
  });

  return <section className="mod-card">
    <div className="mod-card-head"><h2>Precios vigentes por unidad</h2></div>
    <label className="pl-search"><Search size={18} aria-hidden="true" />
      <input aria-label="Buscar producto" placeholder="Buscar por código o producto"
        value={search} onChange={(event) => setSearch(event.target.value)} />
    </label>
    {query.isPending && <p className="mod-muted">Cargando precios…</p>}
    {query.error && <p role="alert" className="error">{friendlyError(query.error)}</p>}
    {!query.isPending && !query.error && !query.data?.length && (
      <p className="mod-muted">No hay productos para esta búsqueda.</p>
    )}
    <div className="mod-table-wrap">
      <table className="mod-table">
        <thead><tr><th>Producto</th><th>Unidad</th><th className="is-num">Precio final</th></tr></thead>
        <tbody>{(query.data ?? []).slice(0, 200).map((item) => (
          <tr key={item.id}>
            <td className="is-name"><strong>{item.name}</strong><small>{item.code}</small></td>
            <td>{item.unit_symbol}</td>
            <td className="is-num">{item.price == null
              ? <span className="pl-chip is-warn"><Tags size={13} /> Sin precio</span>
              : money(item.price)}</td>
          </tr>
        ))}</tbody>
      </table>
    </div>
    {(query.data?.length ?? 0) > 200 && <p className="mod-muted">Se muestran 200 productos: afiná la búsqueda para ver el resto.</p>}
  </section>;
}

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { ChevronLeft, ChevronRight, Plus, Search, TrendingUp } from 'lucide-react';
import { Link } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import { friendlyError } from '../../lib/notifications';
import { findPurchaseItems, listSupplierCatalog } from '../../services/purchases';
import { money, typeNames } from './supplierUi';

export function SupplierPagination({ page, count, onChange }) {
  const pages = Math.max(1, Math.ceil(Number(count) / 25));
  return (
    <div className="supplier-pagination">
      <span>{count} resultado(s) · página {page + 1} de {pages}</span>
      <div>
        <button className="button outline" type="button" aria-label="Página anterior"
          disabled={page === 0} onClick={() => onChange(page - 1)}><ChevronLeft size={17} /></button>
        <button className="button outline" type="button" aria-label="Página siguiente"
          disabled={page + 1 >= pages} onClick={() => onChange(page + 1)}><ChevronRight size={17} /></button>
      </div>
    </div>
  );
}

export function SupplierQuoteRows({ rows, comparison = false, onAction, onPreferred }) {
  const { can } = useAuth();
  return (
    <div className="supplier-quote-list">
      {rows.map((quote) => {
        const supplier = { id: quote.supplier_id, name: quote.supplier_name, active: quote.supplier_active };
        const editable = can('purchases', 'update') && quote.supplier_active && quote.item_active;
        return <article className="supplier-quote" key={`${quote.supplier_id}:${quote.item_id}`}>
          <div className="supplier-quote-title">
            <strong>{comparison ? quote.supplier_name : quote.item_name}</strong>
            <small>{quote.item_code} · {comparison ? quote.item_name : typeNames[quote.item_type]}
              {!quote.supplier_active ? ' · Proveedor inactivo' : ''}
              {!quote.item_active ? ' · Ítem inactivo' : ''}</small>
            {quote.supplier_sku && <small>Código del proveedor: {quote.supplier_sku}</small>}
            <div className="supplier-badges">
              {quote.preferred && <span>Proveedor principal</span>}
              {quote.is_best_price && <span>Menor costo registrado</span>}
            </div>
          </div>
          <div className="supplier-quote-cost">
            <strong>{quote.unit_cost_ars == null ? 'Falta cotización del dólar' : money(quote.unit_cost_ars)}</strong>
            <small>por {quote.unit_symbol}</small>
            <small>Base: {money(quote.unit_price, quote.currency_code)}
              {Number(quote.adjustment_percent) !== 0 ? ` · Ajuste ${quote.adjustment_percent} %` : ''}</small>
            {quote.currency_code === 'USD' && <small>Dólar {quote.exchange_rate_type}
              {' · '}{quote.exchange_rate == null ? 'sin cotización vigente' : money(quote.exchange_rate)}</small>}
          </div>
          <div className="supplier-quote-actions">
            {editable && <>
              <button type="button" className="button outline" onClick={() => onAction('quote', supplier, quote)}>Editar precio</button>
              <button type="button" className="button outline" onClick={() => onAction('adjust', supplier, quote)}>Ajustar %</button>
            </>}
            {!comparison && <button type="button" className="button outline"
              onClick={() => onAction('compare', supplier, quote)}>Comparar proveedores</button>}
            {editable && !quote.preferred && <button type="button" className="button outline"
              disabled={quote.unit_cost_ars == null} onClick={() => onPreferred(quote)}>Elegir principal</button>}
            {can('purchases', 'insert') && quote.supplier_active && quote.item_active &&
              quote.unit_cost_ars != null && <Link className="button outline"
                to={`/purchases/orders?supplier=${quote.supplier_id}&item=${quote.item_id}`}>Comprar</Link>}
            {can('purchases', 'update') && <button type="button" className="supplier-remove"
              disabled={quote.preferred} title={quote.preferred ? 'Elegí otro proveedor principal antes de quitar este ítem' : ''}
              onClick={() => onAction('remove', supplier, quote)}>Quitar relación</button>}
          </div>
        </article>;
      })}
    </div>
  );
}

export function SupplierCatalog({ supplier, onAction, onPreferred }) {
  const { activeCompanyId, user, can } = useAuth();
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(0);
  const term = useDebouncedValue(search);
  const query = useQuery({
    queryKey: ['supplier-catalog', user?.id, activeCompanyId, supplier.id, null, term, page],
    queryFn: () => listSupplierCatalog(activeCompanyId, supplier.id, null, term, page),
    enabled: Boolean(activeCompanyId),
  });
  const rows = query.data ?? [];
  return (
    <div className="supplier-catalog">
      <div className="supplier-catalog-head">
        <div>
          <h3>Ítems que nos provee</h3>
          <small>Precios por unidad de inventario · sin impuestos ni flete</small>
        </div>
        <div className="supplier-header-actions">
          {supplier.active && can('purchases', 'update') && <>
            <button type="button" className="button outline" onClick={() => onAction('adjust', supplier)}>
              <TrendingUp size={16} /> Ajustar todos los precios
            </button>
            <button type="button" className="button primary" onClick={() => onAction('quote', supplier)}>
              <Plus size={16} /> Agregar ítem
            </button>
          </>}
        </div>
      </div>
      <label className="purchase-search">
        <Search size={17} /><input maxLength={100} value={search}
          aria-label={`Buscar ítems de ${supplier.name}`} placeholder="Buscar en este proveedor por nombre o código"
          onChange={(event) => { setSearch(event.target.value); setPage(0); }} />
      </label>
      {query.isPending && <p className="purchase-muted">Cargando ítems…</p>}
      {query.error && <p className="error" role="alert">{friendlyError(query.error)}</p>}
      {!query.isPending && !query.error && !rows.length && <p className="supplier-empty">
        {search ? 'No hay ítems para esta búsqueda.' : 'Todavía no hay ítems asociados. Usá «Agregar ítem» para cargar el primero con su precio.'}
      </p>}
      <SupplierQuoteRows rows={rows} onAction={onAction} onPreferred={onPreferred} />
      <SupplierPagination page={page} count={rows[0]?.total_count ?? 0} onChange={setPage} />
    </div>
  );
}

export function SupplierComparison({ selected, onSelected, onAction, onPreferred }) {
  const { activeCompanyId, user } = useAuth();
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(0);
  const term = useDebouncedValue(search);
  const materials = useQuery({
    queryKey: ['purchase-items', user?.id, activeCompanyId, term, null],
    queryFn: () => findPurchaseItems(activeCompanyId, term),
    enabled: Boolean(activeCompanyId),
  });
  const query = useQuery({
    queryKey: ['supplier-catalog', user?.id, activeCompanyId, null, selected?.id, '', page],
    queryFn: () => listSupplierCatalog(activeCompanyId, null, selected.id, '', page),
    enabled: Boolean(activeCompanyId && selected),
  });
  const choices = [selected, ...(materials.data ?? [])].filter((entry, index, all) => entry &&
    all.findIndex((option) => option?.id === entry.id) === index);
  const rows = query.data ?? [];
  return (
    <section className="purchase-card">
      <h2>Comparar precios de un ítem</h2>
      <p className="purchase-muted">Elegí el material o producto. Verás los proveedores ordenados por costo en pesos, usando la misma unidad de medida.</p>
      <div className="purchase-form supplier-compare-picker">
        <label>Buscar ítem
          <input value={search} maxLength={100} placeholder="Nombre o código"
            onChange={(event) => setSearch(event.target.value)} />
        </label>
        <label>Ítem a comparar
          <select value={selected?.id ?? ''} onChange={(event) => {
            onSelected(choices.find((item) => item.id === event.target.value) ?? null);
            setPage(0);
          }}>
            <option value="">Seleccionar ítem</option>
            {choices.map((item) => <option key={item.id} value={item.id}>{item.code} · {item.name}</option>)}
          </select>
        </label>
      </div>
      {materials.error && <p role="alert" className="error">{friendlyError(materials.error)}</p>}
      {!selected && <p className="supplier-empty">Seleccioná un ítem para ver sus precios.</p>}
      {selected && query.isPending && <p className="purchase-muted">Buscando proveedores…</p>}
      {query.error && <p role="alert" className="error">{friendlyError(query.error)}</p>}
      {selected && !query.isPending && !query.error && !rows.length &&
        <p className="supplier-empty">Este ítem todavía no tiene proveedores asociados.</p>}
      <SupplierQuoteRows rows={rows} comparison onAction={onAction} onPreferred={onPreferred} />
      {selected && <SupplierPagination page={page} count={rows[0]?.total_count ?? 0} onChange={setPage} />}
      <p className="purchase-muted">El proveedor principal define el costo de referencia. El menor costo registrado no contempla flete, impuestos ni condiciones comerciales.</p>
    </section>
  );
}

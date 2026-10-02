import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Building2, ChevronDown, Plus, Search } from 'lucide-react';
import { Link } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import { listSupplierDirectory, removeSupplierQuote, setSupplierActive } from '../../services/purchases';
import { listExchangeOverview, setPreferredSupplier } from '../../services/costing';
import { SupplierCatalog, SupplierComparison, SupplierPagination } from './SupplierCatalog';
import { SupplierEditDialog, SupplierQuoteDialog, SupplierAdjustDialog } from './SupplierDialogs';
import SupplierExchangePanel from './SupplierExchangePanel';
import { refreshSupplierData } from './supplierUi';
import './purchases.css';
import './suppliers.css';

export default function SuppliersPage() {
  const { activeCompanyId, user, can } = useAuth();
  const client = useQueryClient();
  const [tab, setTab] = useState('directory');
  const [search, setSearch] = useState('');
  const term = useDebouncedValue(search);
  const [page, setPage] = useState(0);
  const [openId, setOpenId] = useState(null);
  const [action, setAction] = useState(null);
  const [comparisonItem, setComparisonItem] = useState(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    setAction(null); setOpenId(null); setComparisonItem(null);
    setSearch(''); setPage(0); setTab('directory');
  }, [activeCompanyId]);

  const directory = useQuery({
    queryKey: ['supplier-directory', user?.id, activeCompanyId, term, page],
    queryFn: () => listSupplierDirectory(activeCompanyId, term, page),
    enabled: Boolean(activeCompanyId && tab === 'directory'),
  });
  const overview = useQuery({
    queryKey: ['exchange-overview', user?.id, activeCompanyId],
    queryFn: () => listExchangeOverview(activeCompanyId),
    enabled: Boolean(activeCompanyId && (tab === 'currency' || action?.kind === 'quote')),
  });
  const rows = directory.data ?? [];
  const refresh = () => refreshSupplierData(client);

  function openAction(kind, supplier, quote = null) {
    if (kind === 'compare') {
      setComparisonItem({ id: quote.item_id, name: quote.item_name,
        code: quote.item_code, unit_symbol: quote.unit_symbol });
      setTab('comparison');
      return;
    }
    setAction({ kind, supplier, quote });
  }
  async function run(operation, title) {
    if (busy) return;
    setBusy(true);
    try {
      await operation();
      notifySuccess(title);
      await refresh();
    } catch (err) {
      notifyError(err);
    } finally {
      setBusy(false);
    }
  }
  function preferred(quote) {
    return run(() => setPreferredSupplier(activeCompanyId, quote.item_id, quote.supplier_id),
      'Proveedor principal actualizado');
  }
  function remove() {
    if (!action?.quote) return;
    return run(async () => {
      await removeSupplierQuote(activeCompanyId, action.quote.supplier_id, action.quote.item_id);
      setAction(null);
    }, 'Ítem retirado del proveedor');
  }

  return (
    <div className="purchase-page suppliers-page" aria-busy={busy}>
      <div className="page-head">
        <div>
          <span className="eyebrow">COMPRAS</span>
          <h1>Proveedores</h1>
          <p>Encontrá quién te provee cada ítem, compará costos y mantené sus precios al día.</p>
        </div>
        <div className="supplier-header-actions">
          <Link to="/purchases/orders" className="button outline">Órdenes de compra</Link>
          {can('purchases', 'insert') && <button type="button" className="button primary"
            onClick={() => openAction('supplier', null)}><Plus size={17} /> Nuevo proveedor</button>}
        </div>
      </div>
      <div className="purchase-tabs" role="tablist" aria-label="Vistas de proveedores">
        {[
          ['directory', 'Proveedores e ítems'], ['comparison', 'Comparar precios'], ['currency', 'Cotizaciones del dólar'],
        ].map(([value, label]) => <button key={value} type="button" role="tab"
          aria-selected={tab === value} className={tab === value ? 'selected' : ''}
          onClick={() => setTab(value)}>{label}</button>)}
      </div>

      {tab === 'directory' && <section className="purchase-card supplier-directory">
        <label className="purchase-search">
          <Search size={17} /><input maxLength={100} value={search}
            aria-label="Buscar proveedor por nombre, CUIT o lo que provee"
            placeholder="Buscar por nombre, CUIT o lo que nos provee"
            onChange={(event) => { setSearch(event.target.value); setPage(0); setOpenId(null); }} />
        </label>
        <p className="purchase-muted">Abrí un proveedor para ver y gestionar sus ítems y precios.</p>
        {directory.isPending && <p className="purchase-muted">Cargando proveedores…</p>}
        {directory.error && <p role="alert" className="error">{friendlyError(directory.error)}</p>}
        {!directory.isPending && !directory.error && !rows.length && <p className="supplier-empty">
          {search ? 'No hay proveedores para esta búsqueda.' : 'Todavía no hay proveedores. Creá el primero y agregá los ítems que te provee.'}
        </p>}
        {rows.map((supplier) => <article className="supplier-card" key={supplier.id}>
          <div className="supplier-card-header">
            <button type="button" className="supplier-open" disabled={busy}
              aria-expanded={openId === supplier.id} aria-controls={`supplier-${supplier.id}`}
              onClick={() => setOpenId(openId === supplier.id ? null : supplier.id)}>
              <span className="purchase-icon"><Building2 size={20} /></span>
              <span className="supplier-name">
                <strong>{supplier.name}</strong>
                <span>{supplier.supplies_description || 'Sin descripción de lo que provee'}</span>
                <small>{supplier.item_count} ítem(s) · Entrega habitual: {supplier.lead_time_days} días
                  {!supplier.active ? ' · Inactivo' : ''}</small>
              </span>
              <ChevronDown className={openId === supplier.id ? 'supplier-chevron open' : 'supplier-chevron'} size={19} />
            </button>
            {can('purchases', 'update') && <div className="supplier-header-actions">
              <button type="button" className="button outline" disabled={busy}
                onClick={() => openAction('supplier', supplier)}>Editar datos</button>
              <button type="button" className="button outline" disabled={busy}
                onClick={() => run(() => setSupplierActive(activeCompanyId, supplier.id, !supplier.active),
                  supplier.active ? 'Proveedor desactivado' : 'Proveedor activado')}>
                {supplier.active ? 'Desactivar' : 'Activar'}
              </button>
            </div>}
          </div>
          {openId === supplier.id && <div id={`supplier-${supplier.id}`}>
            <div className="supplier-contact">
              {supplier.tax_id && <span>CUIT: {supplier.tax_id}</span>}
              {supplier.phone && <span>Teléfono: {supplier.phone}</span>}
              {supplier.email && <span>{supplier.email}</span>}
              {supplier.notes && <p>{supplier.notes}</p>}
            </div>
            <SupplierCatalog key={supplier.id} supplier={supplier} onAction={openAction} onPreferred={preferred} />
          </div>}
        </article>)}
        <SupplierPagination page={page} count={rows[0]?.total_count ?? 0} onChange={(value) => {
          setPage(value); setOpenId(null);
        }} />
      </section>}

      {tab === 'comparison' && <SupplierComparison selected={comparisonItem}
        onSelected={setComparisonItem} onAction={openAction} onPreferred={preferred} />}
      {tab === 'currency' && <>
        {overview.isPending && <p className="purchase-muted">Cargando cotizaciones…</p>}
        {overview.error && <p className="error" role="alert">{friendlyError(overview.error)}</p>}
        {!overview.isPending && !overview.error && <SupplierExchangePanel key={activeCompanyId} types={overview.data ?? []} />}
      </>}

      {action?.kind === 'supplier' && <SupplierEditDialog key={action.supplier?.id ?? 'new'}
        supplier={action.supplier} onClose={() => setAction(null)} onSaved={refresh} />}
      {action?.kind === 'quote' && <SupplierQuoteDialog key={`${action.supplier.id}:${action.quote?.item_id ?? 'new'}`}
        supplier={action.supplier} quote={action.quote} exchangeTypes={overview.data ?? []}
        onClose={() => setAction(null)} onSaved={refresh} />}
      {action?.kind === 'adjust' && <SupplierAdjustDialog key={`${action.supplier.id}:${action.quote?.item_id ?? 'all'}`}
        supplier={action.supplier} quote={action.quote} onClose={() => setAction(null)} onSaved={refresh} />}
      <ConfirmDeleteDialog open={action?.kind === 'remove'} busy={busy}
        description={action?.quote ? `Se quitará ${action.quote.item_name} de ${action.supplier.name}. El ítem, el stock y las órdenes anteriores se conservan.` : ''}
        confirmLabel="Quitar relación" onCancel={() => setAction(null)} onConfirm={remove} />
    </div>
  );
}

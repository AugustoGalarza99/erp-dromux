import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Building2, Plus, Search } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog';
import { notifyError, notifySuccess } from '../../lib/notifications';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import {
  findPurchaseItems,
  listSuppliers,
  listSupplierQuotes,
  removeSupplierQuote,
  saveSupplier,
  saveSupplierQuote,
  setSupplierActive,
} from '../../services/purchases';
import './purchases.css';

const empty = { name: '', tax_id: '', email: '', phone: '', notes: '' };

export default function SuppliersPage() {
  const { activeCompanyId, user, can } = useAuth();
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(empty);
  const [search, setSearch] = useState('');
  const [busy, setBusy] = useState(false);
  const [tab, setTab] = useState('directory');
  const [supplierFilter, setSupplierFilter] = useState('');
  const [itemFilter, setItemFilter] = useState('');
  const [itemSearch, setItemSearch] = useState('');
  const [selectedMaterial, setSelectedMaterial] = useState(null);
  const [quotePrice, setQuotePrice] = useState('');
  const [supplierSku, setSupplierSku] = useState('');
  const [deleteTarget, setDeleteTarget] = useState(null);
  const itemTerm = useDebouncedValue(itemSearch);

  useEffect(() => {
    setEditing(null);
    setForm(empty);
    setSearch('');
    setSupplierFilter('');
    setItemFilter('');
    setSelectedMaterial(null);
    setDeleteTarget(null);
  }, [activeCompanyId]);

  const query = useQuery({
    queryKey: ['purchase-suppliers', user?.id, activeCompanyId, search],
    queryFn: () => listSuppliers(activeCompanyId, search),
    enabled: Boolean(activeCompanyId),
  });

  const allSuppliersQuery = useQuery({
    queryKey: ['purchase-suppliers', user?.id, activeCompanyId, ''],
    queryFn: () => listSuppliers(activeCompanyId),
    enabled: Boolean(activeCompanyId && tab === 'comparison'),
  });

  const quotesQuery = useQuery({
    queryKey: ['supplier-quotes', user?.id, activeCompanyId,
      supplierFilter || null, itemFilter || null],
    queryFn: () => listSupplierQuotes(activeCompanyId,
      supplierFilter || null, itemFilter || null),
    enabled: Boolean(activeCompanyId && tab === 'comparison'),
  });

  const materialsQuery = useQuery({
    queryKey: ['purchase-items', user?.id, activeCompanyId, itemTerm, null],
    queryFn: () => findPurchaseItems(activeCompanyId, itemTerm),
    enabled: Boolean(activeCompanyId && tab === 'comparison'),
  });

  const refresh = () => queryClient.invalidateQueries({
    queryKey: ['purchase-suppliers', user?.id, activeCompanyId],
  });

  const refreshQuotes = () => Promise.all([
    queryClient.invalidateQueries({ queryKey: ['supplier-quotes', user?.id, activeCompanyId] }),
    queryClient.invalidateQueries({ queryKey: ['purchase-items', user?.id, activeCompanyId] }),
  ]);

  const saveQuote = async (event) => {
    event.preventDefault();
    setBusy(true);
    try {
      await saveSupplierQuote(activeCompanyId, supplierFilter, itemFilter,
        quotePrice, supplierSku);
      await refreshQuotes();
      notifySuccess('Cotización guardada');
      setQuotePrice('');
      setSupplierSku('');
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  };

  const deleteQuote = async () => {
    if (!deleteTarget) return;
    setBusy(true);
    try {
      await removeSupplierQuote(activeCompanyId,
        deleteTarget.supplier_id, deleteTarget.item_id);
      await refreshQuotes();
      notifySuccess('Relación eliminada', 'Las órdenes guardadas conservan su precio.');
      setDeleteTarget(null);
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  };

  const save = async (event) => {
    event.preventDefault();
    setBusy(true);
    try {
      await saveSupplier(activeCompanyId, editing?.id, form);
      await refresh();
      notifySuccess(editing ? 'Proveedor actualizado' : 'Proveedor creado', form.name);
      setEditing(null);
      setForm(empty);
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  };

  const toggle = async (supplier) => {
    setBusy(true);
    try {
      await setSupplierActive(activeCompanyId, supplier.id, !supplier.active);
      await refresh();
      notifySuccess(supplier.active ? 'Proveedor desactivado' : 'Proveedor activado', supplier.name);
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="purchase-page">
      <div className="page-head">
        <div>
          <span className="eyebrow">COMPRAS / CONTACTOS</span>
          <h1>Proveedores</h1>
          <p>Contactos, materias primas y precios comparables por unidad.</p>
        </div>
      </div>

      <div className="purchase-tabs" role="tablist" aria-label="Vista de proveedores">
        <button type="button" role="tab" aria-selected={tab === 'directory'}
          className={tab === 'directory' ? 'selected' : ''}
          onClick={() => setTab('directory')}>Directorio</button>
        <button type="button" role="tab" aria-selected={tab === 'comparison'}
          className={tab === 'comparison' ? 'selected' : ''}
          onClick={() => setTab('comparison')}>Materias primas y precios</button>
      </div>

      {tab === 'directory' && (
      <div className="purchase-grid">
        <section className="purchase-card">
          <div className="purchase-card-heading">
            <h2>Directorio de proveedores</h2>
            {can('purchases', 'insert') && (
              <button
                type="button"
                className="button purchase-soft-button"
                onClick={() => { setEditing(null); setForm(empty); }}
              >
                <Plus size={16} /> Nuevo
              </button>
            )}
          </div>
          <label className="purchase-search">
            <Search size={17} />
            <input
              aria-label="Buscar proveedor"
              placeholder="Buscar por nombre"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
          </label>
          {query.isPending && <p className="purchase-muted">Cargando proveedores…</p>}
          {query.error && <p role="alert" className="error">{query.error.message}</p>}
          {!query.isPending && !query.error && !query.data?.length && (
            <p className="purchase-muted">No hay proveedores para esta búsqueda.</p>
          )}
          {(query.data ?? []).map((supplier) => (
            <div className="purchase-list-row" key={supplier.id}>
              <span className="purchase-icon"><Building2 size={17} /></span>
              <div className="purchase-row-main">
                <strong>{supplier.name}</strong>
                <small>
                  {supplier.tax_id || supplier.email || supplier.phone || 'Sin datos de contacto'}
                  {!supplier.active ? ' · Inactivo' : ''}
                </small>
              </div>
              {can('purchases', 'update') && (
                <div className="purchase-row-actions">
                  <button type="button" disabled={busy} onClick={() => {
                    setEditing(supplier);
                    setForm({
                      name: supplier.name,
                      tax_id: supplier.tax_id,
                      email: supplier.email,
                      phone: supplier.phone,
                      notes: supplier.notes,
                    });
                  }}>Editar</button>
                  <button type="button" disabled={busy} onClick={() => toggle(supplier)}>
                    {supplier.active ? 'Desactivar' : 'Activar'}
                  </button>
                </div>
              )}
            </div>
          ))}
          <p className="purchase-muted">Se muestran hasta 100 proveedores. Usá la búsqueda para filtrar.</p>
        </section>

        {(can('purchases', 'insert') || can('purchases', 'update')) && (
          <section className="purchase-card">
            <span className="eyebrow">FICHA COMERCIAL</span>
            <h2>{editing ? `Editar ${editing.name}` : 'Nuevo proveedor'}</h2>
            <form className="purchase-form" onSubmit={save}>
              <label>Nombre *
                <input required minLength={2} maxLength={160} value={form.name}
                  onChange={(event) => setForm({ ...form, name: event.target.value })} />
              </label>
              <div className="purchase-form-pair">
                <label>CUIT / identificación
                  <input maxLength={30} value={form.tax_id}
                    onChange={(event) => setForm({ ...form, tax_id: event.target.value })} />
                </label>
                <label>Teléfono
                  <input maxLength={40} value={form.phone}
                    onChange={(event) => setForm({ ...form, phone: event.target.value })} />
                </label>
              </div>
              <label>Correo
                <input type="email" maxLength={160} value={form.email}
                  onChange={(event) => setForm({ ...form, email: event.target.value })} />
              </label>
              <label>Notas
                <textarea maxLength={500} rows={3} value={form.notes}
                  onChange={(event) => setForm({ ...form, notes: event.target.value })} />
              </label>
              <button className="button primary" disabled={busy || !can('purchases', editing ? 'update' : 'insert')}>
                {busy ? 'Guardando…' : editing ? 'Guardar cambios' : 'Crear proveedor'}
              </button>
            </form>
          </section>
        )}
      </div>
      )}

      {tab === 'comparison' && (
        <section className="purchase-card">
          <div className="purchase-card-heading">
            <div>
              <span className="eyebrow">COMPARADOR</span>
              <h2>¿Quién provee cada materia prima?</h2>
            </div>
          </div>
          <div className="purchase-compare-filters">
            <label>Proveedor
              <select value={supplierFilter} onChange={(event) => setSupplierFilter(event.target.value)}>
                <option value="">Todos los proveedores</option>
                {(allSuppliersQuery.data ?? []).map((entry) => (
                  <option key={entry.id} value={entry.id}>{entry.name}</option>
                ))}
              </select>
            </label>
            <label>Buscar materia prima
              <input value={itemSearch} onChange={(event) => setItemSearch(event.target.value)}
                placeholder="Nombre o código" />
            </label>
            <label>Materia prima
              <select value={itemFilter} onChange={(event) => {
                setItemFilter(event.target.value);
                setSelectedMaterial((materialsQuery.data ?? []).find(
                  (entry) => entry.id === event.target.value,
                ) ?? null);
              }}>
                <option value="">Todas las materias primas</option>
                {[selectedMaterial, ...(materialsQuery.data ?? [])]
                  .filter((entry, index, all) => entry?.item_type === 'raw_material'
                    && all.findIndex((value) => value?.id === entry.id) === index)
                  .map((entry) => (
                    <option key={entry.id} value={entry.id}>{entry.code} · {entry.name}</option>
                  ))}
              </select>
            </label>
          </div>
          {(quotesQuery.error || materialsQuery.error) && (
            <p role="alert" className="error">
              {quotesQuery.error?.message || materialsQuery.error?.message}
            </p>
          )}
          {quotesQuery.isPending && <p className="purchase-muted">Cargando precios…</p>}
          {!quotesQuery.isPending && !quotesQuery.data?.length && (
            <p className="purchase-muted">Todavía no hay cotizaciones para estos filtros.</p>
          )}
          {(quotesQuery.data ?? []).map((quote, index, all) => {
            const comparable = all.filter((entry) => entry.item_id === quote.item_id
              && entry.supplier_active);
            const minimum = Math.min(...comparable.map((entry) => Number(entry.unit_price)));
            const cheapest = comparable.length > 1 && quote.supplier_active
              && Number(quote.unit_price) === minimum;
            return (
              <div className="purchase-quote-row" key={`${quote.supplier_id}-${quote.item_id}`}>
                <div>
                  <strong>{quote.item_name}</strong>
                  <small>{quote.item_code} · {quote.supplier_name}
                    {quote.supplier_sku ? ` · Ref. proveedor ${quote.supplier_sku}` : ''}
                    {!quote.supplier_active ? ' · Inactivo' : ''}</small>
                </div>
                <div className="purchase-quote-price">
                  <strong>{Number(quote.unit_price).toLocaleString('es-AR', {
                    style: 'currency', currency: 'ARS',
                  })} / {quote.unit_symbol}</strong>
                  <small>Referencia interna: {quote.reference_unit_cost == null ? 'sin cargar'
                    : Number(quote.reference_unit_cost).toLocaleString('es-AR', {
                      style: 'currency', currency: 'ARS',
                    })}</small>
                  {cheapest && <span className="purchase-best-price">Mejor precio registrado</span>}
                </div>
                {can('purchases', 'update') && (
                  <button type="button" className="purchase-text-button"
                    onClick={() => setDeleteTarget(quote)}>Quitar relación</button>
                )}
              </div>
            );
          })}
          <p className="purchase-muted">Los precios son referencias comparables en la unidad
            del ítem, no incluyen automáticamente impuestos ni flete.</p>

          {can('purchases', 'update') && (
            <form className="purchase-quote-form" onSubmit={saveQuote}>
              <strong>Agregar o actualizar precio</strong>
              <p className="purchase-muted">Seleccioná arriba un proveedor y una materia prima.</p>
              <label>Precio por unidad *
                <input type="number" min="0" step="0.01" required
                  value={quotePrice}
                  onChange={(event) => setQuotePrice(event.target.value)} />
              </label>
              <label>Código del proveedor (opcional)
                <input maxLength={80} value={supplierSku}
                  onChange={(event) => setSupplierSku(event.target.value)} />
              </label>
              <button className="button primary" disabled={busy || !supplierFilter || !itemFilter}>
                {busy ? 'Guardando…' : 'Guardar precio'}
              </button>
            </form>
          )}
        </section>
      )}

      <ConfirmDeleteDialog
        open={Boolean(deleteTarget)}
        description={deleteTarget
          ? `Se quitará ${deleteTarget.item_name} de ${deleteTarget.supplier_name}. Las órdenes existentes no cambian.`
          : ''}
        busy={busy}
        onCancel={() => setDeleteTarget(null)}
        onConfirm={deleteQuote}
      />
    </div>
  );
}

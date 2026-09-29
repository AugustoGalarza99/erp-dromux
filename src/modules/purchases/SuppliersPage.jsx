import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Building2, Plus, Search } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
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
import {
  addExchangeRate, addExchangeType, adjustSupplierPrices,
  listExchangeRates, listExchangeTypes, setPreferredSupplier,
} from '../../services/costing';
import './purchases.css';

const empty = { name: '', tax_id: '', email: '', phone: '', notes: '', lead_time_days: '7' };
const argentinaToday = () => new Intl.DateTimeFormat('sv-SE', {
  timeZone: 'America/Argentina/Buenos_Aires',
}).format(new Date());

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
  const [currency, setCurrency] = useState('ARS');
  const [exchangeTypeId, setExchangeTypeId] = useState('');
  const [adjustment, setAdjustment] = useState('0');
  const [newType, setNewType] = useState('');
  const [rateType, setRateType] = useState('');
  const [rateValue, setRateValue] = useState('');
  const [rateDate, setRateDate] = useState(() => argentinaToday());
  const [bulkPercent, setBulkPercent] = useState('');
  const [bulkTarget, setBulkTarget] = useState(null);
  const [bulkRequestId, setBulkRequestId] = useState(() => crypto.randomUUID());
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

  const exchangeTypesQuery = useQuery({
    queryKey: ['exchange-types', user?.id, activeCompanyId],
    queryFn: () => listExchangeTypes(activeCompanyId),
    enabled: Boolean(activeCompanyId && tab !== 'directory'),
  });
  const exchangeRatesQuery = useQuery({
    queryKey: ['exchange-rates', user?.id, activeCompanyId],
    queryFn: () => listExchangeRates(activeCompanyId),
    enabled: Boolean(activeCompanyId && tab !== 'directory'),
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
    queryClient.invalidateQueries({ queryKey: ['items', user?.id, activeCompanyId] }),
    queryClient.invalidateQueries({ queryKey: ['item-detail', user?.id, activeCompanyId] }),
    queryClient.invalidateQueries({ queryKey: ['product-costs', user?.id, activeCompanyId] }),
  ]);

  useEffect(() => {
    if (!supplierFilter || !itemFilter || !quotesQuery.data) return;
    const current = quotesQuery.data.find((quote) => quote.supplier_id === supplierFilter
      && quote.item_id === itemFilter);
    setQuotePrice(current ? String(current.unit_price) : '');
    setSupplierSku(current?.supplier_sku ?? '');
    setCurrency(current?.currency_code ?? 'ARS');
    setExchangeTypeId(current?.exchange_rate_type_id ?? '');
    setAdjustment(String(current?.adjustment_percent ?? 0));
  }, [supplierFilter, itemFilter, quotesQuery.data]);

  const saveQuote = async (event) => {
    event.preventDefault();
    setBusy(true);
    try {
      await saveSupplierQuote(activeCompanyId, supplierFilter, itemFilter,
        quotePrice, supplierSku, currency, currency === 'USD' ? exchangeTypeId : null, adjustment);
      await refreshQuotes();
      notifySuccess('Cotización guardada');
      // La cotización queda visible para revisarla o cambiar el proveedor principal.
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  };

  const withBusy = async (operation, message) => {
    if (busy) return;
    setBusy(true);
    try {
      await operation();
      notifySuccess(message);
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  };

  const saveType = (event) => {
    event.preventDefault();
    withBusy(async () => {
      await addExchangeType(activeCompanyId, newType);
      await queryClient.invalidateQueries({ queryKey: ['exchange-types', user?.id, activeCompanyId] });
      setNewType('');
    }, 'Tipo de dólar creado');
  };

  const saveRate = (event) => {
    event.preventDefault();
    withBusy(async () => {
      await addExchangeRate(activeCompanyId, rateType, rateValue, rateDate);
      await queryClient.invalidateQueries({ queryKey: ['exchange-rates', user?.id, activeCompanyId] });
      await refreshQuotes();
      setRateValue('');
    }, 'Cotización registrada y costos actualizados');
  };

  const confirmBulk = () => {
    if (!supplierFilter && !itemFilter) {
      notifyError(new Error('Elegí un proveedor o una materia prima antes de aplicar el ajuste.'));
      return;
    }
    if (!bulkPercent || Number(bulkPercent) === 0) {
      notifyError(new Error('Indicá un porcentaje distinto de cero.'));
      return;
    }
    setBulkTarget({ supplierId: supplierFilter || null, itemId: itemFilter || null,
      percent: bulkPercent });
  };

  const applyBulk = () => withBusy(async () => {
    await adjustSupplierPrices(activeCompanyId, bulkTarget.supplierId,
      bulkTarget.itemId, bulkTarget.percent, bulkRequestId);
    await refreshQuotes();
    setBulkRequestId(crypto.randomUUID());
    setBulkTarget(null);
    setBulkPercent('');
  }, 'Ajuste finalizado');

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
        <button type="button" role="tab" aria-selected={tab === 'currency'}
          className={tab === 'currency' ? 'selected' : ''}
          onClick={() => setTab('currency')}>Tipos de dólar</button>
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
          {query.error && <p role="alert" className="error">{friendlyError(query.error)}</p>}
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
                  {' · '}Entrega habitual: {supplier.lead_time_days} días
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
                      lead_time_days: String(supplier.lead_time_days),
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
              <label>Plazo habitual de entrega (días)
                <input type="number" required min="0" max="365" step="1"
                  value={form.lead_time_days}
                  onChange={(event) => setForm({ ...form,
                    lead_time_days: event.target.value })} />
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
              {(quotesQuery.error && friendlyError(quotesQuery.error)) || (materialsQuery.error && friendlyError(materialsQuery.error))}
            </p>
          )}
          {quotesQuery.isPending && <p className="purchase-muted">Cargando precios…</p>}
          {!quotesQuery.isPending && !quotesQuery.data?.length && (
            <p className="purchase-muted">Todavía no hay cotizaciones para estos filtros.</p>
          )}
          {(quotesQuery.data ?? []).map((quote, index, all) => {
            const comparable = all.filter((entry) => entry.item_id === quote.item_id
              && entry.supplier_active);
            const minimum = Math.min(...comparable.filter((entry) => entry.unit_cost_ars != null).map((entry) => Number(entry.unit_cost_ars)));
            const cheapest = comparable.length > 1 && quote.supplier_active
              && Number(quote.unit_cost_ars) === minimum;
            return (
              <div className="purchase-quote-row" key={`${quote.supplier_id}-${quote.item_id}`}>
                <div>
                  <strong>{quote.item_name}</strong>
                  <small>{quote.item_code} · {quote.supplier_name}
                    {quote.supplier_sku ? ` · Ref. proveedor ${quote.supplier_sku}` : ''}
                    {!quote.supplier_active ? ' · Inactivo' : ''}</small>
                </div>
                <div className="purchase-quote-price">
                  <strong>{quote.unit_cost_ars == null ? 'Falta cotización del dólar'
                    : Number(quote.unit_cost_ars).toLocaleString('es-AR', {
                      style: 'currency', currency: 'ARS',
                    })} / {quote.unit_symbol}</strong>
                  <small>{Number(quote.unit_price).toLocaleString('es-AR', {
                    style: 'currency', currency: quote.currency_code,
                  })} · {quote.currency_code === 'USD'
                    ? `Dólar ${quote.exchange_rate_type || 'sin tipo'} · $ ${quote.exchange_rate ?? 'sin cotización'}`
                    : 'Pesos'} {Number(quote.adjustment_percent) !== 0
                    ? ` · Ajuste ${quote.adjustment_percent} %` : ''}</small>
                  {quote.preferred && <span className="purchase-best-price">Proveedor principal · costo de producción</span>}
                  {cheapest && <span className="purchase-best-price">Mejor precio registrado</span>}
                </div>
                {can('purchases', 'update') && quote.supplier_active && !quote.preferred && (
                  <button type="button" className="purchase-text-button" disabled={busy || quote.unit_cost_ars == null}
                    onClick={() => withBusy(async () => {
                      await setPreferredSupplier(activeCompanyId, quote.item_id, quote.supplier_id);
                      await refreshQuotes();
                    }, 'Proveedor principal actualizado')}>Elegir principal</button>
                )}
                {can('purchases', 'update') && (
                  <button type="button" className="purchase-text-button"
                    onClick={() => setDeleteTarget(quote)}>Quitar relación</button>
                )}
              </div>
            );
          })}
          <p className="purchase-muted">Los importes en pesos se recalculan con la última cotización vigente.
            Las órdenes anteriores conservan su precio. No incluyen impuestos ni flete.</p>
          {can('purchases', 'update') && <div className="purchase-quote-form">
            <strong>Ajustar precios en lote</strong>
            <p className="purchase-muted">Aplicá un porcentaje a las cotizaciones del proveedor o
              materia prima seleccionados arriba. El cambio se registra una sola vez.</p>
            <label>Variación porcentual
              <input type="number" min="-99.99" max="1000" step="0.01"
                value={bulkPercent} onChange={(event) => {
                  setBulkPercent(event.target.value);
                  setBulkRequestId(crypto.randomUUID());
                }} placeholder="Ej.: 10 para aumentar, -5 para reducir" />
            </label>
            <button type="button" className="button" disabled={busy} onClick={confirmBulk}>
              Revisar ajuste
            </button>
          </div>}

          {can('purchases', 'update') && (
            <form className="purchase-quote-form" onSubmit={saveQuote}>
              <strong>Agregar o actualizar precio</strong>
              <p className="purchase-muted">Seleccioná arriba un proveedor y una materia prima.</p>
              <label>Precio por unidad *
                <input type="number" min="0" step="0.01" required
                  value={quotePrice}
                  onChange={(event) => setQuotePrice(event.target.value)} />
              </label>
              <label>Moneda
                <select value={currency} onChange={(event) => setCurrency(event.target.value)}>
                  <option value="ARS">Pesos argentinos</option>
                  <option value="USD">Dólares estadounidenses</option>
                </select>
              </label>
              {currency === 'USD' && <label>Tipo de dólar *
                <select required value={exchangeTypeId}
                  onChange={(event) => setExchangeTypeId(event.target.value)}>
                  <option value="">Elegí un tipo</option>
                  {(exchangeTypesQuery.data ?? []).filter((entry) => entry.active).map((entry) => (
                    <option key={entry.id} value={entry.id}>{entry.name}</option>
                  ))}
                </select>
              </label>}
              <label>Ajuste adicional (%)
                <input type="number" min="-99.99" max="1000" step="0.01" required
                  value={adjustment} onChange={(event) => setAdjustment(event.target.value)} />
              </label>
              <label>Código del proveedor (opcional)
                <input maxLength={80} value={supplierSku}
                  onChange={(event) => setSupplierSku(event.target.value)} />
              </label>
              <button className="button primary" disabled={busy || !supplierFilter || !itemFilter || (currency === 'USD' && !exchangeTypeId)}>
                {busy ? 'Guardando…' : 'Guardar precio'}
              </button>
            </form>
          )}
        </section>
      )}

      {tab === 'currency' && <section className="purchase-card">
        <span className="eyebrow">COTIZACIONES</span>
        <h2>Tipos de dólar</h2>
        <p className="purchase-muted">Creá los tipos que utilice tu empresa y cargá cuántos pesos
          vale un dólar para cada uno. La última fecha vigente se aplica a cada insumo asociado.</p>
        {exchangeTypesQuery.error && <p role="alert" className="error">{friendlyError(exchangeTypesQuery.error)}</p>}
        {exchangeRatesQuery.error && <p role="alert" className="error">{friendlyError(exchangeRatesQuery.error)}</p>}
        {(exchangeTypesQuery.data ?? []).map((entry) => {
          const latest = (exchangeRatesQuery.data ?? []).find((rate) =>
            rate.type_id === entry.id && rate.effective_on <= argentinaToday());
          return <div className="purchase-quote-row" key={entry.id}>
            <strong>Dólar {entry.name}</strong>
            <span>{latest ? `$ ${Number(latest.ars_per_usd).toLocaleString('es-AR')} · ${latest.effective_on}`
              : 'Sin cotización vigente'}</span>
          </div>;
        })}
        {can('purchases', 'update') && <div className="purchase-grid">
          <form className="purchase-quote-form" onSubmit={saveType}>
            <strong>Nuevo tipo</strong>
            <label>Nombre (ej.: Oficial, MEP)
              <input required minLength={2} maxLength={60} value={newType}
                onChange={(event) => setNewType(event.target.value)} />
            </label>
            <button className="button primary" disabled={busy}>Crear tipo</button>
          </form>
          <form className="purchase-quote-form" onSubmit={saveRate}>
            <strong>Registrar cotización</strong>
            <label>Tipo de dólar
              <select required value={rateType} onChange={(event) => setRateType(event.target.value)}>
                <option value="">Elegí un tipo</option>
                {(exchangeTypesQuery.data ?? []).filter((entry) => entry.active).map((entry) =>
                  <option key={entry.id} value={entry.id}>{entry.name}</option>)}
              </select>
            </label>
            <label>Pesos por dólar
              <input required type="number" min="0.000001" step="0.000001" value={rateValue}
                onChange={(event) => setRateValue(event.target.value)} />
            </label>
            <label>Fecha de vigencia
              <input required type="date" max={argentinaToday()}
                value={rateDate} onChange={(event) => setRateDate(event.target.value)} />
            </label>
            <button className="button primary" disabled={busy}>Guardar cotización</button>
          </form>
        </div>}
      </section>}

      <ConfirmDeleteDialog
        open={Boolean(bulkTarget)}
        title="¿Confirmás el ajuste de precios?"
        confirmLabel="Aplicar ajuste"
        description={bulkTarget ? `Se aplicará ${bulkTarget.percent} % a todos los precios del filtro seleccionado. ¿Confirmás el cambio?` : ''}
        busy={busy}
        onCancel={() => setBulkTarget(null)}
        onConfirm={applyBulk}
      />
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

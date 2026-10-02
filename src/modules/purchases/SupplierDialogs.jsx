import { useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import ActionDialog from '../../components/ActionDialog';
import { useAuth } from '../../contexts/AuthContext';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import { notifyError, notifySuccess } from '../../lib/notifications';
import {
  findPurchaseItems, saveSupplier, saveSupplierCatalogQuote, previewSupplierAdjustment,
} from '../../services/purchases';
import { adjustSupplierPrices } from '../../services/costing';
import { money } from './supplierUi';
import { Link } from 'react-router-dom';

export function SupplierEditDialog({ supplier, onClose, onSaved }) {
  const { activeCompanyId, can } = useAuth();
  const [form, setForm] = useState({
    name: supplier?.name ?? '', tax_id: supplier?.tax_id ?? '',
    email: supplier?.email ?? '', phone: supplier?.phone ?? '',
    notes: supplier?.notes ?? '', supplies_description: supplier?.supplies_description ?? '',
    lead_time_days: String(supplier?.lead_time_days ?? 7),
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const set = (field, value) => setForm((current) => ({ ...current, [field]: value }));
  async function submit(event) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError('');
    try {
      await saveSupplier(activeCompanyId, supplier?.id, form);
      notifySuccess(supplier ? 'Proveedor actualizado' : 'Proveedor creado', form.name);
      await onSaved();
      onClose();
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
    }
  }
  return (
    <ActionDialog open title={supplier ? 'Editar proveedor' : 'Nuevo proveedor'} busy={busy}
      description="Guardá sus datos y una breve descripción de lo que te provee." onClose={onClose}>
      <form className="purchase-form" onSubmit={submit}>
        <label>Nombre del proveedor *
          <input required minLength={2} maxLength={160} value={form.name}
            onChange={(event) => set('name', event.target.value)} autoFocus />
        </label>
        <label>¿Qué nos provee?
          <input maxLength={200} value={form.supplies_description}
            placeholder="Ej.: Hierros, perfiles y caños estructurales"
            onChange={(event) => set('supplies_description', event.target.value)} />
          <small className="purchase-muted">Se muestra debajo del nombre en el directorio.</small>
        </label>
        <div className="purchase-form-pair">
          <label>CUIT / identificación
            <input maxLength={30} value={form.tax_id} onChange={(event) => set('tax_id', event.target.value)} />
          </label>
          <label>Teléfono
            <input maxLength={40} value={form.phone} onChange={(event) => set('phone', event.target.value)} />
          </label>
        </div>
        <div className="purchase-form-pair">
          <label>Correo electrónico
            <input type="email" maxLength={160} value={form.email}
              onChange={(event) => set('email', event.target.value)} />
          </label>
          <label>Entrega habitual (días)
            <input type="number" required min="0" max="365" step="1" value={form.lead_time_days}
              onChange={(event) => set('lead_time_days', event.target.value)} />
          </label>
        </div>
        <label>Notas internas
          <textarea maxLength={500} rows={3} value={form.notes}
            onChange={(event) => set('notes', event.target.value)} />
        </label>
        {error && <p className="error" role="alert">{error}</p>}
        <div className="erp-action-dialog-actions">
          <button type="button" className="button outline" disabled={busy} onClick={onClose}>Cancelar</button>
          <button className="button primary" disabled={busy || !can('purchases', supplier ? 'update' : 'insert')}>
            {busy ? 'Guardando…' : 'Guardar proveedor'}
          </button>
        </div>
      </form>
    </ActionDialog>
  );
}

export function SupplierQuoteDialog({ supplier, quote, exchangeTypes, onClose, onSaved }) {
  const { activeCompanyId, user, can } = useAuth();
  const [search, setSearch] = useState('');
  const term = useDebouncedValue(search);
  const [selected, setSelected] = useState(quote ? {
    id: quote.item_id, code: quote.item_code, name: quote.item_name, unit_symbol: quote.unit_symbol,
  } : null);
  const [form, setForm] = useState({
    price: quote ? String(quote.unit_price) : '', sku: quote?.supplier_sku ?? '',
    currency: quote?.currency_code ?? 'ARS', exchangeType: quote?.exchange_rate_type_id ?? '',
    adjustment: String(quote?.adjustment_percent ?? 0),
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const query = useQuery({
    queryKey: ['purchase-items', user?.id, activeCompanyId, term, null],
    queryFn: () => findPurchaseItems(activeCompanyId, term),
    enabled: Boolean(activeCompanyId && !quote),
  });
  const set = (field, value) => setForm((current) => ({ ...current, [field]: value }));
  const options = [selected, ...(query.data ?? [])].filter((entry, index, all) => entry &&
    all.findIndex((option) => option?.id === entry.id) === index);
  const rate = exchangeTypes.find((type) => type.id === form.exchangeType)?.current_rate;
  const effectiveRate = form.currency === 'ARS' ? 1 : rate == null ? null : Number(rate);
  const preview = form.price !== '' && effectiveRate != null
    ? Number(form.price) * effectiveRate * (1 + Number(form.adjustment || 0) / 100) : null;

  async function submit(event) {
    event.preventDefault();
    if (busy || !selected) return;
    setBusy(true);
    setError('');
    try {
      await saveSupplierCatalogQuote(activeCompanyId, supplier.id, selected.id, form, quote);
      notifySuccess(quote ? 'Precio actualizado' : 'Ítem agregado al proveedor', selected.name);
      await onSaved();
      onClose();
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
    }
  }
  return (
    <ActionDialog open title={quote ? 'Editar precio del ítem' : 'Agregar ítem al proveedor'}
      description={supplier.name} busy={busy} onClose={onClose}>
      <form className="purchase-form" onSubmit={submit}>
        {quote ? <div className="supplier-selected-item">
          <strong>{selected.name}</strong><small>{selected.code} · Precio por {selected.unit_symbol}</small>
        </div> : <>
          <label>Buscar ítem
            <input autoFocus maxLength={100} value={search} placeholder="Nombre, código o código de barras"
              onChange={(event) => setSearch(event.target.value)} />
          </label>
          <label>Ítem que nos provee *
            <select required value={selected?.id ?? ''} onChange={(event) => {
              setSelected(options.find((item) => item.id === event.target.value) ?? null);
              setError('');
            }}>
              <option value="">{query.isPending ? 'Buscando…' : 'Seleccionar ítem'}</option>
              {options.map((item) => <option key={item.id} value={item.id}>
                {item.code} · {item.name} ({item.unit_symbol})
              </option>)}
            </select>
          </label>
          {query.error && <p className="error" role="alert">No se pudieron cargar los ítems. Volvé a intentar.</p>}
          <p className="purchase-muted">El ítem debe existir en Inventario. Su unidad de medida se conserva.
            {can('items', 'insert') && <> <Link to="/inventory/items/new" target="_blank" rel="noopener noreferrer">Crear un ítem en Inventario</Link>.</>}
          </p>
        </>}
        <div className="purchase-form-pair">
          <label>Precio por {selected?.unit_symbol ?? 'unidad'} *
            <input required type="number" min="0" max="99999999999999" step="0.01"
              value={form.price} onChange={(event) => set('price', event.target.value)} />
          </label>
          <label>Moneda
            <select value={form.currency} onChange={(event) => set('currency', event.target.value)}>
              <option value="ARS">Pesos argentinos</option>
              <option value="USD">Dólares estadounidenses</option>
            </select>
          </label>
        </div>
        {form.currency === 'USD' && <label>Tipo de dólar *
          <select required value={form.exchangeType} onChange={(event) => set('exchangeType', event.target.value)}>
            <option value="">Seleccionar tipo de dólar</option>
            {exchangeTypes.filter((entry) => entry.active || entry.id === form.exchangeType)
              .map((entry) => <option key={entry.id} value={entry.id}>
                {entry.name}{entry.current_rate == null ? ' · sin cotización' : ` · ${money(entry.current_rate)}`}
              </option>)}
          </select>
        </label>}
        <div className="supplier-cost-preview">
          <span>Costo en pesos por {selected?.unit_symbol ?? 'unidad'}</span>
          <strong>{preview == null ? 'Completá precio y cotización' : money(preview)}</strong>
          <small>No incluye impuestos ni flete.</small>
        </div>
        <details className="supplier-advanced">
          <summary>Código del proveedor y ajuste adicional</summary>
          <label>Código del proveedor (opcional)
            <input maxLength={80} value={form.sku} onChange={(event) => set('sku', event.target.value)} />
          </label>
          <label>Ajuste adicional (%)
            <input required type="number" min="-99.99" max="1000" step="0.01"
              value={form.adjustment} onChange={(event) => set('adjustment', event.target.value)} />
          </label>
        </details>
        {quote?.preferred && <p className="supplier-info">Este proveedor es principal: al guardar se actualiza el costo de referencia del ítem.</p>}
        {error && <p className="error" role="alert">{error}</p>}
        <div className="erp-action-dialog-actions">
          <button type="button" className="button outline" disabled={busy} onClick={onClose}>Cancelar</button>
          <button className="button primary" disabled={busy || !selected || !can('purchases', 'update')}>
            {busy ? 'Guardando…' : quote ? 'Guardar precio' : 'Agregar ítem'}
          </button>
        </div>
      </form>
    </ActionDialog>
  );
}

export function SupplierAdjustDialog({ supplier, quote, onClose, onSaved }) {
  const { activeCompanyId } = useAuth();
  const [percent, setPercent] = useState('');
  const [preview, setPreview] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const request = useRef(crypto.randomUUID());
  async function review(event) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError('');
    try {
      const result = await previewSupplierAdjustment(activeCompanyId, supplier.id, quote?.item_id, percent);
      if (!Number(result.count)) throw new Error('Este proveedor no tiene ítems activos para ajustar.');
      setPreview(result);
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
    }
  }
  async function apply() {
    if (busy || !preview) return;
    setBusy(true);
    setError('');
    try {
      const count = await adjustSupplierPrices(activeCompanyId, supplier.id, quote?.item_id, percent, request.current);
      notifySuccess('Precios ajustados', `${count} precio(s) actualizados en ${supplier.name}.`);
      await onSaved();
      onClose();
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
    }
  }
  return (
    <ActionDialog open title={quote ? 'Ajustar precio de este ítem' : 'Ajustar todos los precios'}
      description={`${supplier.name}${quote ? ` · ${quote.item_name}` : ''}`} busy={busy} onClose={onClose}>
      <form className="purchase-form" onSubmit={review}>
        <label>Variación porcentual
          <input autoFocus required type="number" min="-99.99" max="1000" step="0.01"
            value={percent} placeholder="10 para aumentar o -5 para reducir"
            onChange={(event) => {
              setPercent(event.target.value);
              setPreview(null);
              request.current = crypto.randomUUID();
            }} />
        </label>
        <p className="purchase-muted">Modifica el precio base en la moneda de cada ítem. El ajuste adicional se conserva y los costos en pesos se recalculan.</p>
        {!preview && <button className="button outline" disabled={busy || !Number(percent)}>
          {busy ? 'Preparando…' : 'Revisar cambios'}
        </button>}
      </form>
      {preview && <div className="supplier-adjust-review">
        <strong>{Number(percent) > 0 ? 'Aumento' : 'Reducción'} del {Math.abs(Number(percent))} % · {preview.count} ítem(s)</strong>
        {(preview.examples ?? []).map((item) => <div key={item.name}>
          <span>{item.name}</span><span>{money(item.unit_price, item.currency_code)} → <strong>{money(item.next_price, item.currency_code)}</strong></span>
        </div>)}
        {Number(preview.count) > 5 && <small>Se muestran cinco ejemplos. El ajuste afecta todos los ítems activos del proveedor.</small>}
        <p>Las órdenes y recepciones anteriores conservan sus precios.</p>
      </div>}
      {error && <p className="error" role="alert">{error}</p>}
      <div className="erp-action-dialog-actions">
        <button type="button" className="button outline" disabled={busy} onClick={onClose}>Cancelar</button>
        <button type="button" className="button primary" disabled={busy || !preview} onClick={apply}>
          {busy ? 'Procesando…' : 'Confirmar ajuste'}
        </button>
      </div>
    </ActionDialog>
  );
}

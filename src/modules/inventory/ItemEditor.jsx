import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Save, Tag } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import {
  activateItemLots,
  getItem,
  getUntrackedStock,
  saveItem,
  searchItemOptions,
  setItemActive,
} from '../../services/items';
import { notifyError, notifySuccess } from '../../lib/notifications';
import {
  listSupplierQuotes,
  listSuppliers,
  saveSupplierQuote,
} from '../../services/purchases';
import './items.css';

const emptyForm = {
  code: '',
  name: '',
  item_type: 'raw_material',
  category_id: '',
  unit_id: '',
  barcode: '',
  description: '',
  minimum_stock: '0',
  track_lots: false,
  reference_unit_cost: '',
};

const itemTypes = [
  ['raw_material', 'Materia prima'],
  ['semi_finished', 'Semielaborado'],
  ['finished_product', 'Producto terminado'],
  ['consumable', 'Insumo'],
];

function SelectCatalog({ label, value, onChange, query, selected }) {
  const options = query.data ?? [];
  const chosen = selected && !options.some((option) => option.id === selected.id)
    ? [selected, ...options]
    : options;

  return (
    <label>
      {label}
      <select required={label.includes('*')} value={value} onChange={onChange}>
        <option value="">Seleccionar</option>
        {chosen.map((option) => (
          <option key={option.id} value={option.id}>
            {option.name}{option.symbol ? ` (${option.symbol})` : ''}
            {option.active === false ? ' · inactiva' : ''}
          </option>
        ))}
      </select>
      {query.error && <small className="error">{query.error.message}</small>}
    </label>
  );
}

export default function ItemEditor() {
  const { itemId } = useParams();
  const isNew = !itemId;
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { user, activeCompanyId, can } = useAuth();
  const [form, setForm] = useState(emptyForm);
  const [categorySearch, setCategorySearch] = useState('');
  const [unitSearch, setUnitSearch] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [supplierSearch, setSupplierSearch] = useState('');
  const [supplierPrices, setSupplierPrices] = useState([]);

  const detailQuery = useQuery({
    queryKey: ['item-detail', user?.id, activeCompanyId, itemId],
    queryFn: () => getItem(activeCompanyId, itemId),
    enabled: Boolean(activeCompanyId && itemId),
  });

  const categoryQuery = useQuery({
    queryKey: ['item-options', user?.id, activeCompanyId, 'category', categorySearch],
    queryFn: () => searchItemOptions(activeCompanyId, 'category', categorySearch),
    enabled: Boolean(activeCompanyId),
  });

  const unitQuery = useQuery({
    queryKey: ['item-options', user?.id, activeCompanyId, 'unit', unitSearch],
    queryFn: () => searchItemOptions(activeCompanyId, 'unit', unitSearch),
    enabled: Boolean(activeCompanyId),
  });

  const suppliersQuery = useQuery({
    queryKey: ['purchase-suppliers', user?.id, activeCompanyId, supplierSearch],
    queryFn: () => listSuppliers(activeCompanyId, supplierSearch),
    enabled: Boolean(activeCompanyId && can('purchases', 'read')),
  });

  const quotesQuery = useQuery({
    queryKey: ['supplier-quotes', user?.id, activeCompanyId, null, itemId],
    queryFn: () => listSupplierQuotes(activeCompanyId, null, itemId),
    enabled: Boolean(activeCompanyId && itemId && can('purchases', 'read')),
  });

  useEffect(() => {
    if (!quotesQuery.data) return;
    setSupplierPrices(quotesQuery.data.map((quote) => ({
      supplier_id: quote.supplier_id,
      supplier_name: quote.supplier_name,
      unit_price: String(quote.unit_price),
    })));
  }, [quotesQuery.data]);

  useEffect(() => {
    if (!detailQuery.data) return;
    const item = detailQuery.data;

    setForm({
      code: item.code,
      name: item.name,
      item_type: item.item_type,
      category_id: item.category_id ?? '',
      unit_id: item.unit_id,
      barcode: item.barcode ?? '',
      description: item.description ?? '',
      minimum_stock: String(item.minimum_stock ?? 0),
      track_lots: item.track_lots,
      reference_unit_cost: item.reference_unit_cost == null
        ? '' : String(item.reference_unit_cost),
    });
  }, [detailQuery.data]);

  useEffect(() => {
    if (isNew) {
      setForm(emptyForm);
      setSupplierPrices([]);
    }
    setError('');
    setMessage('');
  }, [isNew, activeCompanyId]);

  const item = detailQuery.data;
  const canSave = can('items', isNew ? 'insert' : 'update');

  const setField = (name, value) => {
    setForm((current) => ({ ...current, [name]: value }));
  };

  const invalidate = () => Promise.all([
    queryClient.invalidateQueries({ queryKey: ['items', user?.id, activeCompanyId] }),
    queryClient.invalidateQueries({ queryKey: ['item-detail', user?.id, activeCompanyId] }),
    queryClient.invalidateQueries({ queryKey: ['stock-options', user?.id, activeCompanyId, 'items'] }),
    queryClient.invalidateQueries({ queryKey: ['stock-summary', user?.id, activeCompanyId] }),
    queryClient.invalidateQueries({ queryKey: ['supplier-quotes', user?.id, activeCompanyId] }),
    queryClient.invalidateQueries({ queryKey: ['purchase-items', user?.id, activeCompanyId] }),
  ]);

  const handleSubmit = async (event) => {
    event.preventDefault();
    setBusy(true);
    setError('');
    setMessage('');

    let convertedStock = false;
    let savedId = itemId;
    try {
      if (itemId && !item?.track_lots && form.track_lots) {
        const balances = await getUntrackedStock(activeCompanyId, itemId);
        if (balances.length) {
          await activateItemLots(activeCompanyId, itemId);
          convertedStock = true;
        }
      }
      const saved = await saveItem(activeCompanyId, itemId, form);
      savedId = saved.id;
      if (form.item_type === 'raw_material' && can('purchases', 'update')) {
        for (const quote of supplierPrices) {
          const previous = (quotesQuery.data ?? []).find(
            (entry) => entry.supplier_id === quote.supplier_id,
          );
          if (previous && Number(previous.unit_price) === Number(quote.unit_price)) {
            continue;
          }
          await saveSupplierQuote(activeCompanyId, quote.supplier_id,
            saved.id, quote.unit_price);
        }
      }
      await invalidate();
      if (isNew) navigate(`/inventory/items/${saved.id}`, { replace: true });
      else setMessage('Ficha actualizada correctamente.');
      notifySuccess(
        isNew ? 'Ítem creado' : convertedStock
          ? 'Lotes activados con saldos iniciales' : 'Ítem actualizado',
        form.name.trim(),
      );
    } catch (err) {
      const detail = convertedStock
        ? new Error(`Los lotes se activaron, pero no se guardaron los otros cambios: ${err.message}. Reabrí la ficha y guardá nuevamente.`)
        : err;
      const finalError = !itemId && savedId
        ? new Error(`La ficha se creó, pero no se guardaron todas las cotizaciones: ${detail.message}. Abrí el ítem para completarlas.`)
        : detail;
      setError(notifyError(finalError));
      if (!itemId && savedId) navigate(`/inventory/items/${savedId}`, { replace: true });
      if (convertedStock) await invalidate().catch(() => {});
    } finally {
      setBusy(false);
    }
  };

  const handleActive = async () => {
    setBusy(true);
    setError('');
    setMessage('');
    try {
      await setItemActive(activeCompanyId, itemId, !item.active);
      await invalidate();
      setMessage(item.active ? 'Ítem desactivado.' : 'Ítem activado.');
      notifySuccess(item.active ? 'Ítem desactivado' : 'Ítem activado', item.name);
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
    }
  };

  if (!isNew && detailQuery.isPending) {
    return <div className="items-page"><p>Cargando ficha…</p></div>;
  }

  if (!isNew && detailQuery.error) {
    return <div className="items-page"><p role="alert" className="error">{detailQuery.error.message}</p></div>;
  }

  return (
    <div className="item-editor-page">
      <Link to="/inventory/items" className="back-link">
        <ArrowLeft size={17} /> Volver a ítems
      </Link>
      <div className="page-head">
        <div>
          <span className="eyebrow">INVENTARIO / ÍTEMS / {isNew ? 'ALTA' : 'DETALLE'}</span>
          <h1>{isNew ? 'Nuevo ítem' : item?.name}</h1>
          <p>Definí la identidad del ítem; el stock se registrará mediante movimientos.</p>
        </div>
        {!isNew && (
          <span className={`item-status ${item.active ? '' : 'inactive'}`}>
            {item.active ? 'Activo' : 'Inactivo'}
          </span>
        )}
      </div>

      {error && <p role="alert" className="error item-feedback">{error}</p>}
      {message && <p role="status" className="success item-feedback">{message}</p>}

      <div className="item-editor-grid">
        <form className="item-form" onSubmit={handleSubmit}>
          <div className="form-section-heading">
            <span className="item-form-icon"><Tag size={19} /></span>
            <div>
              <h2>Identificación</h2>
              <p>Campos principales para clasificar el ítem.</p>
            </div>
          </div>

          <div className="item-form-pair">
            <label>
              Código interno *
              <input
                required
                maxLength={50}
                pattern="[A-Za-z0-9][A-Za-z0-9._-]*"
                placeholder="Ej.: MP-001"
                value={form.code}
                onChange={(event) => setField('code', event.target.value)}
              />
            </label>
            <label>
              Tipo *
              <select
                required
                value={form.item_type}
                onChange={(event) => setField('item_type', event.target.value)}
              >
                {itemTypes.map(([value, label]) => (
                  <option key={value} value={value}>{label}</option>
                ))}
              </select>
            </label>
          </div>

          <label>
            Nombre *
            <input
              required
              maxLength={160}
              placeholder="Ej.: Acero inoxidable AISI 304"
              value={form.name}
              onChange={(event) => setField('name', event.target.value)}
            />
          </label>

          <div className="item-form-pair">
            <div className="item-lookup">
              <span>Buscar categoría</span>
              <input
                value={categorySearch}
                onChange={(event) => setCategorySearch(event.target.value)}
                placeholder="Filtrar categorías"
              />
              <SelectCatalog
                label="Categoría"
                value={form.category_id}
                onChange={(event) => setField('category_id', event.target.value)}
                query={categoryQuery}
                selected={item?.category}
              />
            </div>
            <div className="item-lookup">
              <span>Buscar unidad</span>
              <input
                value={unitSearch}
                onChange={(event) => setUnitSearch(event.target.value)}
                placeholder="Filtrar unidades"
              />
              <SelectCatalog
                label="Unidad de medida *"
                value={form.unit_id}
                onChange={(event) => setField('unit_id', event.target.value)}
                query={unitQuery}
                selected={item?.unit}
              />
            </div>
          </div>

          <div className="form-section-heading divided">
            <span className="item-form-icon"><Tag size={19} /></span>
            <div>
              <h2>Datos adicionales</h2>
              <p>Referencias para búsquedas y control posterior.</p>
            </div>
          </div>

          <div className="item-form-pair">
            <label>
              Código de barras
              <input
                maxLength={80}
                placeholder="Opcional"
                value={form.barcode}
                onChange={(event) => setField('barcode', event.target.value)}
              />
            </label>
            <label>
              Stock mínimo de referencia
              <input
                type="number"
                min="0"
                step="0.000001"
                required
                value={form.minimum_stock}
                onChange={(event) => setField('minimum_stock', event.target.value)}
              />
            </label>
          </div>

          <label>
            Descripción
            <textarea
              maxLength={1500}
              rows={4}
              placeholder="Especificaciones técnicas o notas"
              value={form.description}
              onChange={(event) => setField('description', event.target.value)}
            />
          </label>

          {form.item_type === 'raw_material' && (
            <div className="item-supplier-section">
              <div className="form-section-heading divided">
                <span className="item-form-icon"><Tag size={19} /></span>
                <div>
                  <h2>Costos y proveedores</h2>
                  <p>Precio por {item?.unit?.symbol ?? 'unidad seleccionada'}.
                    Las cotizaciones se pueden comparar en Compras.</p>
                </div>
              </div>
              <label>
                Costo de referencia por unidad *
                <input
                  type="number"
                  required
                  min="0"
                  step="0.01"
                  value={form.reference_unit_cost}
                  onChange={(event) => setField('reference_unit_cost', event.target.value)}
                  placeholder="Ej.: 1250.00"
                />
                <small>Referencia interna. Las órdenes guardan el precio pactado.</small>
              </label>

              {can('purchases', 'read') && (
                <>
                  <label>
                    Buscar proveedor
                    <input
                      value={supplierSearch}
                      onChange={(event) => setSupplierSearch(event.target.value)}
                      placeholder="Filtrar por nombre"
                    />
                  </label>
                  <label>
                    Agregar proveedor de esta materia prima
                    <select
                      value=""
                      disabled={!can('purchases', 'update')}
                      onChange={(event) => {
                        const supplier = (suppliersQuery.data ?? []).find(
                          (entry) => entry.id === event.target.value,
                        );
                        if (!supplier || supplierPrices.some(
                          (entry) => entry.supplier_id === supplier.id,
                        )) return;
                        setSupplierPrices((current) => [...current, {
                          supplier_id: supplier.id,
                          supplier_name: supplier.name,
                          unit_price: form.reference_unit_cost,
                        }]);
                      }}
                    >
                      <option value="">Seleccionar proveedor</option>
                      {(suppliersQuery.data ?? []).filter((entry) => entry.active).map((entry) => (
                        <option value={entry.id} key={entry.id}>{entry.name}</option>
                      ))}
                    </select>
                  </label>
                  {supplierPrices.map((quote) => (
                    <label className="item-supplier-price" key={quote.supplier_id}>
                      {quote.supplier_name} · precio por unidad
                      <input
                        type="number"
                        min="0"
                        step="0.01"
                        required
                        disabled={!can('purchases', 'update')}
                        value={quote.unit_price}
                        onChange={(event) => setSupplierPrices((current) => current.map(
                          (entry) => entry.supplier_id === quote.supplier_id
                            ? { ...entry, unit_price: event.target.value } : entry,
                        ))}
                      />
                    </label>
                  ))}
                  <small>Para quitar una relación, usá Compras → Proveedores,
                    con confirmación de eliminación.</small>
                </>
              )}
            </div>
          )}

          <label className="item-checkbox">
            <input
              type="checkbox"
              checked={form.track_lots}
              onChange={(event) => setField('track_lots', event.target.checked)}
            />
            <span>
              <strong>Seguir por lotes</strong>
              <small>
                Cada entrada tendrá un lote; salidas y transferencias descontarán de uno.
                Si ya tiene stock, se abrirá un lote inicial por depósito
                con el saldo actual y quedará registrado quién hizo la apertura.
              </small>
            </span>
          </label>

          {canSave && (
            <button
              className="button primary item-save"
              disabled={busy || unitQuery.isPending || categoryQuery.isPending}
            >
              <Save size={17} /> {busy ? 'Guardando…' : 'Guardar ítem'}
            </button>
          )}
        </form>

        <aside className="item-side-card">
          <span className="eyebrow">CONTROL DE INVENTARIO</span>
          <h2>Preparado para stock</h2>
          <p>
            El stock mínimo es un umbral de referencia. Las existencias no se
            cargan en esta ficha: se registrarán por depósito con entradas,
            salidas y transferencias.
          </p>
          {!isNew && can('items', 'update') && (
            <button className="item-active-action" disabled={busy} onClick={handleActive}>
              {item.active ? 'Desactivar ítem' : 'Volver a activar ítem'}
            </button>
          )}
        </aside>
      </div>
    </div>
  );
}

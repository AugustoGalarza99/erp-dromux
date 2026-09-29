import { useEffect, useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useSearchParams } from 'react-router-dom';
import { Download, Plus, ShoppingCart, X } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import ReceiveOrderPanel from './ReceiveOrderPanel';
import { subtractQuantity } from '../inventory/stockNumber';
import {
  cancelPurchaseOrder,
  createPurchaseOrder,
  findPurchaseItems,
  getPurchaseSuggestion,
  listPurchaseOrders,
  listSuppliers,
  listSupplierQuotes,
  listPurchaseSuppliersForItems,
} from '../../services/purchases';
import './purchases.css';

function newLine() {
  return { id: crypto.randomUUID(), item_id: '', item: null, quantity: '', unit_price: '' };
}

function PurchaseItemPicker({ companyId, userId, supplierId, line, onChange, disabled }) {
  const [search, setSearch] = useState('');
  const term = useDebouncedValue(search);
  const query = useQuery({
    queryKey: ['purchase-item-choices', userId, companyId, supplierId, term],
    queryFn: () => findPurchaseItems(companyId, term, supplierId || null),
    enabled: Boolean(companyId && !disabled),
  });
  const choices = line.item && !(query.data ?? []).some((item) => item.id === line.item.id)
    ? [line.item, ...(query.data ?? [])] : (query.data ?? []);
  return (
    <div className="purchase-item-picker">
      <label>Buscar ítem en esta línea
        <input value={search} maxLength={100}
          onChange={(event) => setSearch(event.target.value)}
          placeholder="Código, nombre o código de barras"
          disabled={disabled} />
      </label>
      <label>Ítem *
        <select required value={line.item_id} disabled={disabled}
          onChange={(event) => {
            const item = choices.find((entry) => entry.id === event.target.value);
            onChange({ item_id: event.target.value, item: item ?? null,
              unit_price: supplierId
                ? item?.supplier_unit_price ?? ''
                : item?.reference_unit_cost ?? '' });
          }}>
          <option value="">{query.isPending ? 'Buscando…' : 'Seleccionar ítem'}</option>
          {choices.map((item) => (
            <option key={item.id} value={item.id}>
              {item.code} · {item.name} ({item.unit_symbol})
            </option>
          ))}
        </select>
      </label>
      {query.error && <small className="error">{friendlyError(query.error)}</small>}
      {supplierId && !query.isPending && !query.error && choices.length === 0 && (
        <small className="purchase-muted">Este proveedor no tiene otros ítems asociados.
          Cargá la cotización en Proveedores para ofrecerlo aquí.</small>
      )}
    </div>
  );
}

export default function PurchaseOrdersPage() {
  const { activeCompanyId, activeCompany, user, can } = useAuth();
  const queryClient = useQueryClient();
  const [params, setParams] = useSearchParams();
  const suggestedItem = params.get('item');
  const suggestedSupplier = params.get('supplier');
  const suggestedQuantity = params.get('quantity');
  const loadedSuggestion = useRef('');
  const mayBuy = can('purchases', 'insert');
  const [supplierId, setSupplierId] = useState('');
  const [selectedSupplier, setSelectedSupplier] = useState(null);
  const [supplierSearch, setSupplierSearch] = useState('');
  const [note, setNote] = useState('');
  const [choosingSupplier, setChoosingSupplier] = useState(false);
  const [lines, setLines] = useState([newLine()]);
  const [busy, setBusy] = useState(false);
  const [cancelTarget, setCancelTarget] = useState(null);
  const [receivingOrderId, setReceivingOrderId] = useState(null);
  const receiptPanelRef = useRef(null);
  const purchaseRequestRef = useRef({ fingerprint: null, id: crypto.randomUUID() });
  const supplierTerm = useDebouncedValue(supplierSearch);

  useEffect(() => {
    purchaseRequestRef.current = { fingerprint: null, id: crypto.randomUUID() };
    setSupplierId('');
    setSelectedSupplier(null);
    setSupplierSearch('');
    setLines([newLine()]);
    setNote('');
    setCancelTarget(null);
    setReceivingOrderId(null);
  }, [activeCompanyId]);

  useEffect(() => {
    if (!activeCompanyId || !suggestedItem || !mayBuy) return;
    const key = `${activeCompanyId}:${suggestedItem}:${suggestedSupplier ?? ''}:${suggestedQuantity ?? ''}`;
    if (loadedSuggestion.current === key) return;
    loadedSuggestion.current = key;
    let mounted = true;
    getPurchaseSuggestion(activeCompanyId, suggestedItem, suggestedSupplier)
      .then(({ item, supplier, price }) => {
        if (!mounted) return;
        setLines([{ ...newLine(), item_id: item.id,
          item: { ...item, supplier_unit_price: price },
          quantity: Number(suggestedQuantity) > 0 ? suggestedQuantity : '',
          unit_price: price == null ? '' : String(price) }]);
        setSupplierId(supplier?.active ? supplier.id : '');
        setSelectedSupplier(supplier?.active ? supplier : null);
        setSupplierSearch('');
        setNote('Reposición sugerida por pronóstico');
      })
      .catch((error) => { if (mounted) notifyError(error); });
    return () => { mounted = false; };
  }, [activeCompanyId, suggestedItem, suggestedSupplier, suggestedQuantity, mayBuy]);

  useEffect(() => {
    if (receivingOrderId) receiptPanelRef.current?.scrollIntoView({
      behavior: 'smooth',
      block: 'start',
    });
  }, [receivingOrderId]);

  const ordersQuery = useQuery({
    queryKey: ['purchase-orders', user?.id, activeCompanyId],
    queryFn: () => listPurchaseOrders(activeCompanyId),
    enabled: Boolean(activeCompanyId),
  });
  const suppliersQuery = useQuery({
    queryKey: ['purchase-suppliers', user?.id, activeCompanyId, supplierTerm],
    queryFn: () => listSuppliers(activeCompanyId, supplierTerm),
    enabled: Boolean(activeCompanyId),
  });
  const selectedItemIds = [...new Set(lines.map((line) => line.item_id).filter(Boolean))];
  const supplierQuotesQuery = useQuery({
    queryKey: ['purchase-providers-for-items', user?.id, activeCompanyId,
      [...selectedItemIds].sort().join(',')],
    queryFn: () => listPurchaseSuppliersForItems(activeCompanyId, selectedItemIds),
    enabled: Boolean(activeCompanyId && !supplierId && selectedItemIds.length),
  });


  async function chooseSupplier(nextId, options) {
    if (!nextId) {
      setSupplierId('');
      setSelectedSupplier(null);
      setLines((current) => current.map((line) => ({ ...line, unit_price: '' })));
      return;
    }
    setChoosingSupplier(true);
    try {
      const quotes = await Promise.all(selectedItemIds.map((itemId) =>
        listSupplierQuotes(activeCompanyId, nextId, itemId)));
      if (quotes.some((rows) => !rows.some((row) => row.supplier_active
        && row.unit_cost_ars != null))) {
        throw new Error('Falta una cotización vigente para alguno de los ítems.');
      }
      const prices = new Map(quotes.map((rows, index) =>
        [selectedItemIds[index], String(rows[0].unit_cost_ars)]));
      setLines((current) => current.map((line) => ({
        ...line,
        unit_price: line.item_id ? prices.get(line.item_id) ?? '' : '',
        item: line.item && line.item_id
          ? { ...line.item, supplier_unit_price: prices.get(line.item_id) }
          : line.item,
      })));
      setSupplierId(nextId);
      setSelectedSupplier(options.find((entry) => entry.id === nextId) ?? null);
    } catch (error) {
      notifyError(error);
    } finally {
      setChoosingSupplier(false);
    }
  }

  const updateLine = (id, values) => {
    setLines((current) => current.map((line) => (
      line.id === id ? { ...line, ...values } : line
    )));
  };

  const refresh = () => Promise.all([
    queryClient.invalidateQueries({ queryKey: ['purchase-orders', user?.id, activeCompanyId] }),
    queryClient.invalidateQueries({ queryKey: ['replenishment-forecast', user?.id, activeCompanyId] }),
    queryClient.invalidateQueries({ queryKey: ['operational-report'] }),
  ]);

  const submit = async (event) => {
    event.preventDefault();
    if (!supplierId || choosingSupplier || lines.some((line) => !line.item_id)) {
      notifyError(new Error('Seleccioná un proveedor y todos los ítems de la orden.'));
      return;
    }
    if (new Set(lines.map((line) => line.item_id)).size !== lines.length) {
      notifyError(new Error('Cada ítem puede aparecer una sola vez en la orden.'));
      return;
    }
    setBusy(true);
    try {
      const fingerprint = JSON.stringify({ supplierId, note: note.trim(),
        lines: lines.map((line) => [line.item_id, line.quantity, line.unit_price]) });
      if (purchaseRequestRef.current.fingerprint !== fingerprint) {
        purchaseRequestRef.current = { fingerprint, id: crypto.randomUUID() };
      }
      await createPurchaseOrder(activeCompanyId, supplierId, note, lines,
        purchaseRequestRef.current.id);
      purchaseRequestRef.current = { fingerprint: null, id: crypto.randomUUID() };
      await refresh();
      setSupplierId('');
      setSelectedSupplier(null);
      setSupplierSearch('');
      setLines([newLine()]);
      setNote('');
      notifySuccess('Orden de compra creada');
      if (suggestedItem) setParams({}, { replace: true });
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  };

  const cancel = async () => {
    if (!cancelTarget) return;
    setBusy(true);
    try {
      await cancelPurchaseOrder(activeCompanyId, cancelTarget.id);
      await refresh();
      notifySuccess(`Orden #${cancelTarget.number} cancelada`);
      setCancelTarget(null);
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  };

  const total = lines.reduce((sum, line) => (
    sum + Number(line.quantity || 0) * Number(line.unit_price || 0)
  ), 0);
  const availableSuppliers = selectedItemIds.length
    ? (supplierQuotesQuery.data ?? []).filter((entry) =>
      entry.name.toLowerCase().includes(supplierSearch.toLowerCase()))
      .map((entry) => ({ ...entry, active: true }))
    : (suppliersQuery.data ?? []);
  const supplierOptions = selectedSupplier && !availableSuppliers.some(
    (entry) => entry.id === selectedSupplier.id,
  ) ? [selectedSupplier, ...availableSuppliers] : availableSuppliers;
  const receivingOrder = (ordersQuery.data ?? []).find((entry) => (
    entry.id === receivingOrderId
  ));
  const statusLabels = {
    open: 'Abierta',
    partial: 'Parcial',
    received: 'Recibida',
    cancelled: 'Cancelada',
  };

  return (
    <div className="purchase-page">
      <div className="page-head">
        <div>
          <span className="eyebrow">COMPRAS / PLANIFICACIÓN</span>
          <h1>Órdenes de compra</h1>
          <p>Planificá cantidades y costos antes de recibir mercadería.</p>
        </div>
        <Link to="/purchases/suppliers" className="button purchase-soft-button">
          Ver proveedores
        </Link>
      </div>

      <div className="purchase-grid">
        {can('purchases', 'insert') && (
          <section className="purchase-card">
            <span className="eyebrow">NUEVA ORDEN</span>
            <h2>Preparar compra</h2>
            <form className="purchase-form" onSubmit={submit}>
              <label>Buscar proveedor
                <input value={supplierSearch} onChange={(event) => setSupplierSearch(event.target.value)}
                  placeholder="Nombre del proveedor" />
              </label>
              <label>Proveedor *
                <select required value={supplierId} disabled={choosingSupplier}
                  onChange={(event) => chooseSupplier(event.target.value, supplierOptions)}>
                  <option value="">{choosingSupplier ? 'Verificando cotizaciones…'
                    : 'Seleccionar proveedor'}</option>
                  {supplierOptions.filter((entry) => entry.active).map((entry) => (
                    <option value={entry.id} key={entry.id}>{entry.name}</option>
                  ))}
                </select>
              </label>
              {!supplierId && selectedItemIds.length > 0 && (
                <small className="purchase-price-hint">Se muestran los proveedores que cotizan
                  todos los ítems seleccionados.</small>
              )}
              {supplierQuotesQuery.error && (
                <small className="error">{friendlyError(supplierQuotesQuery.error)}</small>
              )}
              {suppliersQuery.error && <small className="error">{friendlyError(suppliersQuery.error)}</small>}
              {lines.map((line, index) => {
                return (
                  <div className="purchase-line" key={line.id}>
                    <div className="purchase-line-title">
                      <strong>Ítem {index + 1}</strong>
                      {lines.length > 1 && (
                        <button type="button" aria-label="Quitar línea"
                          onClick={() => setLines((current) => current.filter((entry) => entry.id !== line.id))}>
                          <X size={16} />
                        </button>
                      )}
                    </div>
                    <PurchaseItemPicker
                      companyId={activeCompanyId}
                      userId={user?.id}
                      supplierId={supplierId}
                      line={line}
                      disabled={choosingSupplier}
                      onChange={(values) => updateLine(line.id, values)}
                    />
                    {line.item?.item_type === 'raw_material' && (
                      <small className={line.item.supplier_unit_price == null
                        ? 'purchase-price-hint' : 'purchase-price-hint matched'}>
                        {line.item.supplier_unit_price == null
                          ? 'Elegí un proveedor con cotización vigente para cargar su precio.'
                          : 'Precio del proveedor cargado automáticamente; podés ajustarlo para esta orden.'}
                      </small>
                    )}
                    <div className="purchase-form-pair">
                      <label>Cantidad *
                        <input type="number" required min="0.000001" step="0.000001"
                          value={line.quantity} placeholder="10"
                          onChange={(event) => updateLine(line.id, { quantity: event.target.value })} />
                      </label>
                      <label>Precio unitario *
                        <input type="number" required min="0" step="0.01"
                          value={line.unit_price} placeholder="0,00"
                          onChange={(event) => updateLine(line.id, { unit_price: event.target.value })} />
                      </label>
                    </div>
                  </div>
                );
              })}
              <button type="button" className="button purchase-soft-button"
                disabled={lines.length >= 40 || choosingSupplier} onClick={() => setLines((current) => [...current, newLine()])}>
                <Plus size={16} /> Agregar ítem
              </button>
              <label>Nota interna
                <textarea maxLength={500} rows={2} value={note}
                  onChange={(event) => setNote(event.target.value)} />
              </label>
              <div className="purchase-total">
                <span>Total estimado</span>
                <strong>{total.toLocaleString('es-AR', {
                  style: 'currency', currency: 'ARS', maximumFractionDigits: 2,
                })}</strong>
              </div>
              <button className="button primary" disabled={busy || choosingSupplier}>
                {busy ? 'Guardando…' : 'Crear orden de compra'}
              </button>
            </form>
          </section>
        )}

        <section className="purchase-card">
          <div className="purchase-card-heading">
            <h2>Órdenes recientes</h2>
            <ShoppingCart size={19} />
          </div>
          {ordersQuery.isPending && <p className="purchase-muted">Cargando órdenes…</p>}
          {ordersQuery.error && <p role="alert" className="error">{friendlyError(ordersQuery.error)}</p>}
          {!ordersQuery.isPending && !(ordersQuery.data ?? []).length && (
            <p className="purchase-muted">Todavía no registraste órdenes de compra.</p>
          )}
          {(ordersQuery.data ?? []).map((order) => (
            <article className="purchase-order" key={order.id}>
              <div className="purchase-card-heading">
                <div>
                  <strong>Orden #{order.number}</strong>
                  <small>{order.supplier_name} · {new Date(order.created_at).toLocaleDateString('es-AR')}</small>
                </div>
                <span className={order.status === 'open' || order.status === 'partial'
                  ? 'purchase-badge' : 'purchase-badge inactive'}>
                  {statusLabels[order.status] ?? order.status}
                </span>
              </div>
              {(order.lines ?? []).map((line) => (
                <p className="purchase-order-line" key={line.line_no}>
                  {line.item_code} · pedido {line.quantity} {line.unit_symbol}
                  <small>Recibido: {line.received_quantity ?? 0}
                    · pendiente: {subtractQuantity(line.quantity,
                      line.received_quantity ?? 0)}</small>
                  <span>{Number(line.unit_price).toLocaleString('es-AR', {
                    style: 'currency', currency: 'ARS',
                  })} c/u</span>
                </p>
              ))}
              {order.note && <p className="purchase-muted">{order.note}</p>}
              {['open', 'partial'].includes(order.status)
                && can('purchases', 'insert') && can('stock', 'insert')
                && can('stock', 'read') && (
                  <button className="purchase-receive-button" type="button"
                    onClick={() => setReceivingOrderId(order.id)}>
                    Recibir mercadería
                  </button>
                )}
              <button className="purchase-download-button" type="button"
                onClick={() => setReceivingOrderId(order.id)}>
                Ver recepciones
              </button>
              {['open', 'partial'].includes(order.status) && can('purchases', 'update') && (
                <button className="purchase-text-button" type="button"
                  onClick={() => setCancelTarget(order)}>
                  Cancelar pendiente
                </button>
              )}
              <button
                className="purchase-download-button"
                type="button"
                onClick={async () => {
                  try {
                    const { downloadPurchaseOrderPdf } = await import('./orderPdf');
                    downloadPurchaseOrderPdf(order, activeCompany?.name);
                    notifySuccess(`PDF de orden #${order.number} descargado`);
                  } catch (error) {
                    notifyError(error);
                  }
                }}
              >
                <Download size={15} /> Descargar PDF
              </button>
            </article>
          ))}
          <p className="purchase-muted">Se muestran las 50 órdenes más recientes.</p>
        </section>
      </div>

      {receivingOrder && (
        <div ref={receiptPanelRef}>
          <ReceiveOrderPanel order={receivingOrder}
            onClose={() => setReceivingOrderId(null)} />
        </div>
      )}

      <ConfirmDeleteDialog
        open={Boolean(cancelTarget)}
        title="¿Seguro que quieres cancelar?"
        description={`La orden #${cancelTarget?.number ?? ''} quedará cancelada.
          Lo que ya ingresó a stock se conserva y no se recibirán pendientes.`}
        confirmLabel="Cancelar orden"
        busy={busy}
        onCancel={() => setCancelTarget(null)}
        onConfirm={cancel}
      />
    </div>
  );
}

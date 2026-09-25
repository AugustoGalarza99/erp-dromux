import { useEffect, useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Download, Plus, ShoppingCart, X } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog';
import { notifyError, notifySuccess } from '../../lib/notifications';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import ReceiveOrderPanel from './ReceiveOrderPanel';
import { subtractQuantity } from '../inventory/stockNumber';
import {
  cancelPurchaseOrder,
  createPurchaseOrder,
  findPurchaseItems,
  listPurchaseOrders,
  listSuppliers,
} from '../../services/purchases';
import './purchases.css';

function newLine() {
  return { id: crypto.randomUUID(), item_id: '', item: null, quantity: '', unit_price: '' };
}

export default function PurchaseOrdersPage() {
  const { activeCompanyId, activeCompany, user, can } = useAuth();
  const queryClient = useQueryClient();
  const [supplierId, setSupplierId] = useState('');
  const [selectedSupplier, setSelectedSupplier] = useState(null);
  const [supplierSearch, setSupplierSearch] = useState('');
  const [note, setNote] = useState('');
  const [search, setSearch] = useState('');
  const [lines, setLines] = useState([newLine()]);
  const [busy, setBusy] = useState(false);
  const [cancelTarget, setCancelTarget] = useState(null);
  const [receivingOrderId, setReceivingOrderId] = useState(null);
  const receiptPanelRef = useRef(null);
  const term = useDebouncedValue(search);
  const supplierTerm = useDebouncedValue(supplierSearch);

  useEffect(() => {
    setSupplierId('');
    setSelectedSupplier(null);
    setSupplierSearch('');
    setLines([newLine()]);
    setNote('');
    setSearch('');
    setCancelTarget(null);
    setReceivingOrderId(null);
  }, [activeCompanyId]);

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
  const itemsQuery = useQuery({
    queryKey: ['purchase-items', user?.id, activeCompanyId, term, supplierId],
    queryFn: () => findPurchaseItems(activeCompanyId, term, supplierId || null),
    enabled: Boolean(activeCompanyId && can('purchases', 'read')),
  });

  const updateLine = (id, values) => {
    setLines((current) => current.map((line) => (
      line.id === id ? { ...line, ...values } : line
    )));
  };

  const refresh = () => queryClient.invalidateQueries({
    queryKey: ['purchase-orders', user?.id, activeCompanyId],
  });

  const submit = async (event) => {
    event.preventDefault();
    if (new Set(lines.map((line) => line.item_id)).size !== lines.length) {
      notifyError(new Error('Cada ítem puede aparecer una sola vez en la orden.'));
      return;
    }
    setBusy(true);
    try {
      await createPurchaseOrder(activeCompanyId, supplierId, note, lines);
      await refresh();
      setSupplierId('');
      setSelectedSupplier(null);
      setSupplierSearch('');
      setLines([newLine()]);
      setNote('');
      notifySuccess('Orden de compra creada');
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
  const supplierOptions = selectedSupplier && !(suppliersQuery.data ?? []).some(
    (entry) => entry.id === selectedSupplier.id,
  ) ? [selectedSupplier, ...(suppliersQuery.data ?? [])] : (suppliersQuery.data ?? []);
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
                <select required value={supplierId} onChange={(event) => {
                  setSupplierId(event.target.value);
                  setLines([newLine()]);
                  setSelectedSupplier(supplierOptions.find(
                    (entry) => entry.id === event.target.value,
                  ) ?? null);
                }}>
                  <option value="">Seleccionar proveedor</option>
                  {supplierOptions.filter((entry) => entry.active).map((entry) => (
                    <option value={entry.id} key={entry.id}>{entry.name}</option>
                  ))}
                </select>
              </label>
              {suppliersQuery.error && <small className="error">{suppliersQuery.error.message}</small>}
              <label>Buscar ítem
                <input value={search} onChange={(event) => setSearch(event.target.value)}
                  placeholder="Nombre, código o código de barras" />
              </label>
              {itemsQuery.error && <small className="error">{itemsQuery.error.message}</small>}
              {lines.map((line, index) => {
                const choices = line.item && !(itemsQuery.data ?? []).some(
                  (entry) => entry.id === line.item.id,
                ) ? [line.item, ...(itemsQuery.data ?? [])] : (itemsQuery.data ?? []);
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
                    <label>Ítem *
                      <select required value={line.item_id} onChange={(event) => {
                        const item = choices.find((entry) => entry.id === event.target.value);
                        updateLine(line.id, {
                          item_id: event.target.value,
                          item: item ?? null,
                          unit_price: item?.supplier_unit_price
                            ?? item?.reference_unit_cost ?? '',
                        });
                      }}>
                        <option value="">Seleccionar ítem</option>
                        {choices.map((item) => (
                          <option key={item.id} value={item.id}>
                            {item.code} · {item.name} ({item.unit_symbol})
                          </option>
                        ))}
                      </select>
                    </label>
                    {line.item?.item_type === 'raw_material' && (
                      <small className={line.item.supplier_unit_price == null
                        ? 'purchase-price-hint' : 'purchase-price-hint matched'}>
                        {line.item.supplier_unit_price == null
                          ? 'Sin precio de este proveedor: se usa el costo de referencia si existe.'
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
                disabled={lines.length >= 40} onClick={() => setLines((current) => [...current, newLine()])}>
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
              <button className="button primary" disabled={busy || itemsQuery.isPending}>
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
          {ordersQuery.error && <p role="alert" className="error">{ordersQuery.error.message}</p>}
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

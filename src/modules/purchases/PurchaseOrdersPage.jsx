import { useEffect, useMemo, useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useSearchParams } from 'react-router-dom';
import { ClipboardList, Download, PackageCheck, Plus, Sparkles, X } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog';
import ActionDialog from '../../components/ActionDialog';
import ListPager, { usePagedList } from '../../components/ListPager';
import { SupplierPagination } from './SupplierCatalog';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import { dateEs } from '../../lib/display';
import { LINE_LIMITS } from '../../lib/limits';
import ReceiveOrderPanel from './ReceiveOrderPanel';
import PurchaseLinesEditor from './PurchaseLinesEditor';
import PurchasesShell from './PurchasesShell';
import { receivedLines } from './PurchasesOverview';
import { subtractQuantity } from '../inventory/stockNumber';
import { getReplenishmentForecast } from '../../services/replenishment';
import { convertPurchaseRequest, getPurchaseRequest } from '../../services/purchaseRequests';
import {
  cancelPurchaseOrder,
  createPurchaseOrder,
  getPurchaseSuggestion,
  getSupplier,
  listPurchaseOrdersPage,
  listSuppliers,
  listSupplierQuotes,
  listPurchaseSuppliersForItems,
} from '../../services/purchases';
import './suppliers.css';
import './purchases.css';

const money = (value) => Number(value || 0).toLocaleString('es-AR', {
  style: 'currency', currency: 'ARS', maximumFractionDigits: 2,
});
const statusLabels = { open: 'Abierta', partial: 'Parcial', received: 'Recibida', cancelled: 'Cancelada' };
const statusSegments = [['', 'Todas'], ['open', 'Abiertas'], ['partial', 'Parciales'],
  ['received', 'Recibidas'], ['cancelled', 'Canceladas']];

/* Ítems de una orden ya creada: plegados y paginados para órdenes grandes. */
function OrderLines({ order }) {
  const sorted = useMemo(
    () => [...(order.lines ?? [])].sort((a, b) => a.line_no - b.line_no),
    [order.lines],
  );
  const pager = usePagedList(sorted, { pageSize: 10 });
  return (
    <details className="po-order-details">
      <summary>Ver ítems y cantidades pendientes ({sorted.length})</summary>
      <div className="mod-table-wrap">
        <table className="mod-table">
          <thead>
            <tr>
              <th scope="col">Ítem</th>
              <th scope="col" className="is-num">Pedido</th>
              <th scope="col" className="is-num">Recibido</th>
              <th scope="col" className="is-num">Pendiente</th>
              <th scope="col" className="is-num">Precio</th>
            </tr>
          </thead>
          <tbody>
            {pager.visible.map((line) => {
              const pending = subtractQuantity(line.quantity, line.received_quantity ?? 0);
              return (
                <tr key={line.line_no} className={pending !== '0' ? 'is-attention' : ''}>
                  <td className="is-name" data-label="Ítem">
                    <strong>{line.item_name || line.item_code}</strong>
                    <small>{line.item_code}</small>
                  </td>
                  <td className="is-num" data-label="Pedido">{line.quantity} {line.unit_symbol}</td>
                  <td className="is-num" data-label="Recibido">{line.received_quantity ?? 0}</td>
                  <td className="is-num" data-label="Pendiente">
                    {pending === '0' ? <span className="mod-chip is-ok">Completo</span> : `${pending} ${line.unit_symbol}`}
                  </td>
                  <td className="is-num" data-label="Precio">{money(line.unit_price)} c/u</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <ListPager pager={pager} noun="ítems" sizes={[10, 25, 50]} />
      {order.note && <p className="mod-muted">Nota: {order.note}</p>}
    </details>
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
  const mayBuy = can('purchases_orders', 'insert');
  // El pronóstico lo exige el servidor con el módulo completo de Compras (pasa a Producción en 047).
  const canForecast = can('production_replenishment', 'read') && can('stock', 'read');
  const [createOpen, setCreateOpen] = useState(false);
  const [orderSearch, setOrderSearch] = useState(params.get('order') ?? '');
  const [orderStatus, setOrderStatus] = useState(params.get('status') ?? '');
  const [orderPage, setOrderPage] = useState(0);
  const orderTerm = useDebouncedValue(orderSearch);
  const [supplierId, setSupplierId] = useState('');
  const [selectedSupplier, setSelectedSupplier] = useState(null);
  const [supplierSearch, setSupplierSearch] = useState('');
  const [note, setNote] = useState('');
  const [choosingSupplier, setChoosingSupplier] = useState(false);
  const [loadingSuggested, setLoadingSuggested] = useState(false);
  const [lines, setLines] = useState([]);
  const [requestInfo, setRequestInfo] = useState(null);
  const [busy, setBusy] = useState(false);
  const [confirmCreate, setConfirmCreate] = useState(false);
  const [cancelTarget, setCancelTarget] = useState(null);
  const [receivingOrderId, setReceivingOrderId] = useState(null);
  const [receiptBusy, setReceiptBusy] = useState(false);
  const purchaseRequestRef = useRef({ fingerprint: null, id: crypto.randomUUID() });
  const linesRef = useRef(lines);
  linesRef.current = lines;
  const supplierTerm = useDebouncedValue(supplierSearch);

  useEffect(() => {
    purchaseRequestRef.current = { fingerprint: null, id: crypto.randomUUID() };
    setCreateOpen(false);
    setOrderSearch(''); setOrderStatus(''); setOrderPage(0);
    setSupplierId('');
    setSelectedSupplier(null);
    setSupplierSearch('');
    setLines([]);
    setNote('');
    setCancelTarget(null);
    setConfirmCreate(false);
    setRequestInfo(null);
    setReceivingOrderId(null);
  }, [activeCompanyId]);

  // Los parámetros de la dirección solo preparan la pantalla una vez y después se limpian.
  useEffect(() => {
    if (!activeCompanyId || !mayBuy) return undefined;
    const wantsNew = params.get('new') === '1';
    const wantsSuggested = params.get('suggested') === '1';
    const fromRequest = params.get('request');
    if (!suggestedItem && !wantsNew && !fromRequest) return undefined;
    const key = `${activeCompanyId}:${suggestedItem}:${suggestedSupplier ?? ''}:${suggestedQuantity ?? ''}:${wantsNew}:${wantsSuggested}:${fromRequest ?? ''}`;
    if (loadedSuggestion.current === key) return undefined;
    loadedSuggestion.current = key;
    let mounted = true;
    (async () => {
      try {
        if (fromRequest) {
          // Pedido interno: se cargan las líneas del catálogo; las escritas a mano se avisan aparte.
          const request = await getPurchaseRequest(activeCompanyId, fromRequest);
          if (!mounted) return;
          if (request.status !== 'pending') throw new Error('Ese pedido ya fue resuelto.');
          const catalog = (request.lines ?? []).filter((line) => line.item_id);
          const skipped = (request.lines ?? []).filter((line) => !line.item_id).map((line) => line.item_name);
          setLines(catalog.map((line) => ({
            id: crypto.randomUUID(), item_id: line.item_id,
            item: { id: line.item_id, code: line.item_code, name: line.item_name, unit_symbol: line.unit_symbol },
            quantity: String(line.quantity), unit_price: '',
          })));
          setNote(`Pedido interno Nº ${request.number} (${request.requester_label})`);
          setRequestInfo({ id: request.id, number: request.number, requester: request.requester_label, skipped });
          if (skipped.length) {
            notifySuccess(
              skipped.length === 1
                ? '1 línea del pedido no se incluyó'
                : `${skipped.length} líneas del pedido no se incluyeron`,
              skipped.length === 1
                ? 'Estaba escrita a mano y no está en el catálogo. Cargala como ítem para poder comprarla.'
                : 'Estaban escritas a mano y no están en el catálogo. Cargalas como ítems para poder comprarlas.',
            );
          }
        } else if (suggestedItem) {
          const { item, supplier, price } = await getPurchaseSuggestion(
            activeCompanyId, suggestedItem, suggestedSupplier);
          if (!mounted) return;
          setLines([{ id: crypto.randomUUID(), item_id: item.id,
            item: { ...item, supplier_unit_price: price },
            quantity: Number(suggestedQuantity) > 0 ? suggestedQuantity : '',
            unit_price: price == null ? '' : String(price) }]);
          setSupplierId(supplier?.active ? supplier.id : '');
          setSelectedSupplier(supplier?.active ? supplier : null);
          setNote('Reposición sugerida por pronóstico');
        } else if (suggestedSupplier) {
          const supplier = await getSupplier(activeCompanyId, suggestedSupplier);
          if (!mounted) return;
          if (supplier?.active) {
            setSupplierId(supplier.id);
            setSelectedSupplier(supplier);
            if (wantsSuggested) await addSuggested(supplier.id, true);
          }
        }
        if (mounted) setCreateOpen(true);
      } catch (error) {
        if (mounted) notifyError(error);
      } finally {
        if (mounted) setParams((current) => {
          const next = new URLSearchParams(current);
          ['new', 'supplier', 'suggested', 'item', 'quantity', 'request'].forEach((name) => next.delete(name));
          return next;
        }, { replace: true });
      }
    })();
    return () => { mounted = false; };
  }, [activeCompanyId, suggestedItem, suggestedSupplier, suggestedQuantity, mayBuy, params.get('request')]);

  const ordersQuery = useQuery({
    queryKey: ['purchase-orders', user?.id, activeCompanyId, orderPage, orderTerm, orderStatus],
    queryFn: () => listPurchaseOrdersPage(activeCompanyId, orderPage, orderTerm, orderStatus),
    enabled: Boolean(activeCompanyId),
  });
  const suppliersQuery = useQuery({
    queryKey: ['purchase-suppliers', user?.id, activeCompanyId, supplierTerm],
    queryFn: () => listSuppliers(activeCompanyId, supplierTerm),
    enabled: Boolean(activeCompanyId && createOpen),
  });
  const selectedItemIds = [...new Set(lines.map((line) => line.item_id).filter(Boolean))];
  const supplierQuotesQuery = useQuery({
    queryKey: ['purchase-providers-for-items', user?.id, activeCompanyId,
      [...selectedItemIds].sort().join(',')],
    queryFn: () => listPurchaseSuppliersForItems(activeCompanyId, selectedItemIds),
    enabled: Boolean(activeCompanyId && !supplierId && selectedItemIds.length),
  });

  // Con proveedor elegido, todos los precios salen de sus cotizaciones en una sola consulta.
  async function chooseSupplier(nextId, options) {
    if (!nextId) {
      setSupplierId('');
      setSelectedSupplier(null);
      setLines((current) => current.map((line) => ({ ...line, unit_price: '' })));
      return;
    }
    setChoosingSupplier(true);
    try {
      let prices = new Map();
      if (selectedItemIds.length) {
        const quotes = (await listSupplierQuotes(activeCompanyId, nextId, null))
          .filter((row) => row.supplier_active && row.unit_cost_ars != null);
        prices = new Map(quotes.map((row) => [row.item_id, String(row.unit_cost_ars)]));
        const missing = selectedItemIds.filter((id) => !prices.has(id));
        if (missing.length) {
          throw new Error(`Falta una cotización vigente de este proveedor para ${missing.length === 1 ? 'un ítem' : `${missing.length} ítems`} de la orden.`);
        }
      }
      setLines((current) => current.map((line) => ({
        ...line,
        unit_price: prices.get(line.item_id) ?? line.unit_price,
        item: line.item && prices.has(line.item_id)
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

  // Agrega los materiales a reponer de este proveedor con la cantidad sugerida y su precio vigente.
  async function addSuggested(forSupplier = supplierId, silent = false) {
    if (!forSupplier || loadingSuggested) return;
    setLoadingSuggested(true);
    try {
      const [forecast, quotes] = await Promise.all([
        getReplenishmentForecast(activeCompanyId),
        listSupplierQuotes(activeCompanyId, forSupplier, null),
      ]);
      const quoteOf = new Map(quotes.filter((row) => row.supplier_active && row.unit_cost_ars != null)
        .map((row) => [row.item_id, row]));
      const current = linesRef.current;
      const used = new Set(current.map((line) => line.item_id));
      const incoming = [];
      let withoutPrice = 0;
      forecast
        .filter((row) => row.supplier_id === forSupplier && row.alert_level !== 'ok'
          && Number(row.suggested_quantity) > 0 && !used.has(row.item_id))
        .sort((a, b) => (a.alert_level === 'critical' ? 0 : 1) - (b.alert_level === 'critical' ? 0 : 1))
        .forEach((row) => {
          const quote = quoteOf.get(row.item_id);
          if (!quote) { withoutPrice += 1; return; }
          incoming.push({
            id: crypto.randomUUID(),
            item_id: row.item_id,
            item: { id: row.item_id, code: row.item_code, name: row.item_name,
              unit_symbol: row.unit_symbol, supplier_unit_price: quote.unit_cost_ars },
            quantity: String(row.suggested_quantity),
            unit_price: String(quote.unit_cost_ars),
          });
        });
      const room = Math.max(0, LINE_LIMITS.purchaseOrder - current.length);
      const accepted = incoming.slice(0, room);
      const added = accepted.length;
      setLines([...accepted, ...current]);
      if (!silent || added) {
        notifySuccess(
          added ? `${added} material${added === 1 ? '' : 'es'} agregado${added === 1 ? '' : 's'} desde la reposición` : 'No hay materiales para agregar',
          withoutPrice
            ? `${withoutPrice} no se agregaron porque este proveedor no tiene su cotización.`
            : added ? 'Revisá las cantidades antes de crear la orden.' : 'Este proveedor no tiene reposición sugerida pendiente.',
        );
      }
    } catch (error) {
      notifyError(error);
    } finally {
      setLoadingSuggested(false);
    }
  }

  const refresh = () => Promise.all([
    queryClient.invalidateQueries({ queryKey: ['purchase-orders', user?.id, activeCompanyId] }),
    queryClient.invalidateQueries({ queryKey: ['replenishment-forecast', user?.id, activeCompanyId] }),
    queryClient.invalidateQueries({ queryKey: ['operational-report'] }),
  ]);

  const total = lines.reduce((sum, line) => (
    sum + Number(line.quantity || 0) * Number(line.unit_price || 0)
  ), 0);

  // "Revisar y crear" valida y abre el resumen; la creación real ocurre al confirmar.
  const review = (event) => {
    event.preventDefault();
    if (busy) return;
    if (!supplierId || choosingSupplier) {
      notifyError(new Error('Elegí el proveedor de la orden.'));
      return;
    }
    if (!lines.length) {
      notifyError(new Error('Agregá al menos un ítem a la orden.'));
      return;
    }
    if (lines.some((line) => !(Number(line.quantity) > 0) || line.unit_price === '' || Number(line.unit_price) < 0)) {
      notifyError(new Error('Revisá que todos los ítems tengan cantidad y precio.'));
      return;
    }
    setConfirmCreate(true);
  };

  const submit = async () => {
    if (busy) return;
    setBusy(true);
    try {
      const fingerprint = JSON.stringify({ supplierId, note: note.trim(),
        lines: lines.map((line) => [line.item_id, line.quantity, line.unit_price]) });
      if (purchaseRequestRef.current.fingerprint !== fingerprint) {
        purchaseRequestRef.current = { fingerprint, id: crypto.randomUUID() };
      }
      // Con un pedido interno de origen, la orden y el marcado ocurren juntos en el servidor.
      if (requestInfo) {
        await convertPurchaseRequest(activeCompanyId, requestInfo.id, supplierId, note, lines,
          purchaseRequestRef.current.id);
        await queryClient.invalidateQueries({ queryKey: ['purchase-requests'] });
      } else {
        await createPurchaseOrder(activeCompanyId, supplierId, note, lines,
          purchaseRequestRef.current.id);
      }
      purchaseRequestRef.current = { fingerprint: null, id: crypto.randomUUID() };
      await refresh();
      notifySuccess(
        'Orden de compra creada',
        `${selectedSupplier?.name ?? 'Proveedor'} · ${lines.length} ítem${lines.length === 1 ? '' : 's'} · ${money(total)}${requestInfo ? ` · pedido interno Nº ${requestInfo.number} marcado como ordenado` : ''}`,
      );
      setRequestInfo(null);
      setConfirmCreate(false);
      setSupplierId('');
      setSelectedSupplier(null);
      setSupplierSearch('');
      setLines([]);
      setNote('');
      setCreateOpen(false);
    } catch (error) {
      setConfirmCreate(false);
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
      notifySuccess(`Orden Nº ${cancelTarget.number} cancelada`, 'Lo ya recibido se conserva en el stock.');
      setCancelTarget(null);
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  };

  const availableSuppliers = selectedItemIds.length
    ? (supplierQuotesQuery.data ?? []).filter((entry) =>
      entry.name.toLowerCase().includes(supplierSearch.toLowerCase()))
      .map((entry) => ({ ...entry, active: true }))
    : (suppliersQuery.data ?? []);
  const supplierOptions = selectedSupplier && !availableSuppliers.some(
    (entry) => entry.id === selectedSupplier.id,
  ) ? [selectedSupplier, ...availableSuppliers] : availableSuppliers;
  const receivingOrder = (ordersQuery.data?.rows ?? []).find((entry) => (
    entry.id === receivingOrderId
  ));
  const hasFilters = Boolean(orderSearch || orderStatus);
  const rows = ordersQuery.data?.rows ?? [];

  return (
    <PurchasesShell
      title="Órdenes de compra"
      description="Pedí materiales a tus proveedores, seguí qué llegó y qué falta, y descargá la orden en PDF para enviarla."
      actions={(
        <>
          <Link to="/purchases/suppliers" className="button outline">Proveedores</Link>
          {mayBuy && (
            <button type="button" className="button primary" onClick={() => setCreateOpen(true)}>
              <Plus size={17} aria-hidden="true" /> Nueva orden de compra
            </button>
          )}
        </>
      )}
    >
    <div className="purchase-page">
      <div className="mod-segments" role="group" aria-label="Filtrar por estado">
        {statusSegments.map(([value, label]) => (
          <button key={value || 'all'} type="button" className="mod-segment"
            aria-pressed={orderStatus === value}
            onClick={() => { setOrderStatus(value); setOrderPage(0); }}>
            {label}
          </button>
        ))}
      </div>
      <div className="mod-filters">
        <label className="mod-filter-grow">
          Buscar orden
          <input type="search" value={orderSearch} maxLength={100}
            placeholder="Número de orden o nombre del proveedor"
            onChange={(event) => { setOrderSearch(event.target.value); setOrderPage(0); }} />
        </label>
        {hasFilters && (
          <button type="button" className="button outline"
            onClick={() => { setOrderSearch(''); setOrderStatus(''); setOrderPage(0); }}>
            <X size={15} aria-hidden="true" /> Limpiar filtros
          </button>
        )}
      </div>

      {ordersQuery.isPending && <p className="mod-muted">Cargando órdenes…</p>}
      {ordersQuery.error && <p role="alert" className="error">{friendlyError(ordersQuery.error)}</p>}
      {!ordersQuery.isPending && !ordersQuery.error && !rows.length && (
        <div className="replenishment-empty">
          <strong>{hasFilters ? 'No hay órdenes con esos filtros.' : 'Todavía no creaste órdenes de compra.'}</strong>
          <p className="mod-muted">
            {hasFilters ? 'Probá con otro estado o limpiá los filtros.'
              : 'Creá la primera para registrar lo que le pedís a un proveedor.'}
          </p>
          {!hasFilters && mayBuy && (
            <button type="button" className="button primary" onClick={() => setCreateOpen(true)}>
              <Plus size={16} aria-hidden="true" /> Nueva orden de compra
            </button>
          )}
        </div>
      )}

      <div className="po-list">
        {rows.map((order) => {
          const { done, total: lineCount } = receivedLines(order);
          const orderTotal = (order.lines ?? []).reduce(
            (sum, line) => sum + Number(line.quantity) * Number(line.unit_price), 0);
          const percent = lineCount ? Math.round((done / lineCount) * 100) : 0;
          const active = ['open', 'partial'].includes(order.status);
          return (
            <article className={`po-order is-${order.status}`} key={order.id}>
              <header className="po-order-head">
                <div>
                  <strong>Orden Nº {order.number} · {order.supplier_name}</strong>
                  <small>{dateEs(order.created_at)} · {lineCount} ítem{lineCount === 1 ? '' : 's'} · {money(orderTotal)}</small>
                </div>
                <span className={`mod-chip po-status-${order.status}`}>{statusLabels[order.status] ?? order.status}</span>
              </header>
              {order.status !== 'cancelled' && (
                <div className="po-progress">
                  <div className="job-progress-bar" role="progressbar" aria-valuemin={0} aria-valuemax={100}
                    aria-valuenow={percent} aria-label="Líneas recibidas">
                    <span style={{ width: `${percent}%` }} />
                  </div>
                  <small>{done} de {lineCount} líneas recibidas completas</small>
                </div>
              )}
              <OrderLines order={order} />
              <div className="po-order-actions">
                {active && mayBuy && can('stock', 'insert') && can('stock', 'read') && (
                  <button className="button primary" type="button" onClick={() => setReceivingOrderId(order.id)}>
                    <PackageCheck size={16} aria-hidden="true" /> Recibir mercadería
                  </button>
                )}
                <button className="button outline" type="button" onClick={() => setReceivingOrderId(order.id)}>
                  <ClipboardList size={16} aria-hidden="true" /> Recepciones
                </button>
                <button
                  className="button outline"
                  type="button"
                  onClick={async () => {
                    try {
                      const { downloadPurchaseOrderPdf } = await import('./orderPdf');
                      downloadPurchaseOrderPdf(order, activeCompany?.name);
                      notifySuccess(`PDF de la orden Nº ${order.number} descargado`);
                    } catch (error) {
                      notifyError(error);
                    }
                  }}
                >
                  <Download size={15} aria-hidden="true" /> PDF
                </button>
                {active && can('purchases_orders', 'update') && (
                  <button className="button outline po-cancel" type="button" onClick={() => setCancelTarget(order)}>
                    Cancelar pendiente
                  </button>
                )}
              </div>
            </article>
          );
        })}
      </div>
      <SupplierPagination page={orderPage} count={ordersQuery.data?.count ?? 0} onChange={setOrderPage} />

      {createOpen && mayBuy && (
        <ActionDialog open title="Preparar orden de compra" busy={busy || choosingSupplier}
          description="Elegí el proveedor, agregá los ítems con su cantidad y revisá antes de crear."
          onClose={() => setCreateOpen(false)}>
          <form className="po-compose" onSubmit={review}>
            {requestInfo && (
              <p className="pr-banner" role="status">
                <strong>Viene del pedido interno Nº {requestInfo.number}</strong> ({requestInfo.requester}).
                Al crear la orden, el pedido se marca como ordenado.
                {requestInfo.skipped.length > 0 && (
                  <> No se incluyeron por no estar en el catálogo: {requestInfo.skipped.join(', ')}.</>
                )}
                {' '}
                <button type="button" className="button outline" onClick={() => { setRequestInfo(null); setLines([]); setNote(''); }}>
                  Descartar y empezar de cero
                </button>
              </p>
            )}
            <section className="po-step">
              <h3>1. Proveedor</h3>
              <div className="po-supplier">
                <label>
                  Buscar proveedor
                  <input type="search" value={supplierSearch} disabled={Boolean(supplierId)}
                    onChange={(event) => setSupplierSearch(event.target.value)}
                    placeholder="Nombre del proveedor" />
                </label>
                <label>
                  Proveedor *
                  <select required value={supplierId} disabled={busy || choosingSupplier}
                    onChange={(event) => chooseSupplier(event.target.value, supplierOptions)}>
                    <option value="">{choosingSupplier ? 'Verificando cotizaciones…' : 'Seleccionar proveedor'}</option>
                    {supplierOptions.filter((entry) => entry.active).map((entry) => (
                      <option value={entry.id} key={entry.id}>{entry.name}</option>
                    ))}
                  </select>
                </label>
                {supplierId && (
                  <button type="button" className="button outline" disabled={busy || choosingSupplier}
                    onClick={() => chooseSupplier('', supplierOptions)}>
                    Cambiar proveedor
                  </button>
                )}
              </div>
              {!supplierId && selectedItemIds.length > 0 && (
                <small className="purchase-price-hint">Se muestran los proveedores que cotizan todos los ítems elegidos.</small>
              )}
              {!supplierId && selectedItemIds.length > 0 && !supplierQuotesQuery.isPending
                && !supplierQuotesQuery.error && !supplierOptions.length && (
                <p className="supplier-info">
                  Ningún proveedor cotiza todos estos ítems. Revisá las cotizaciones en Proveedores o separá la compra en varias órdenes.
                </p>
              )}
              {(supplierQuotesQuery.error || suppliersQuery.error) && (
                <small className="error">{friendlyError(supplierQuotesQuery.error || suppliersQuery.error)}</small>
              )}
              {supplierId && canForecast && (
                <button type="button" className="button outline" disabled={loadingSuggested || busy}
                  onClick={() => addSuggested()}>
                  <Sparkles size={16} aria-hidden="true" />{' '}
                  {loadingSuggested ? 'Buscando…' : 'Agregar lo que conviene reponer de este proveedor'}
                </button>
              )}
            </section>

            <section className="po-step">
              <h3>2. Ítems</h3>
              <PurchaseLinesEditor
                companyId={activeCompanyId}
                userId={user?.id}
                supplierId={supplierId}
                lines={lines}
                limit={LINE_LIMITS.purchaseOrder}
                disabled={busy || choosingSupplier}
                onChange={setLines}
              />
            </section>

            <section className="po-step">
              <h3>3. Nota interna (opcional)</h3>
              <label>
                <span className="sr-only">Nota interna</span>
                <textarea maxLength={500} rows={2} value={note} placeholder="Ej.: entrega en depósito central antes del viernes"
                  onChange={(event) => setNote(event.target.value)} />
              </label>
            </section>

            <div className="po-savebar">
              <div className="po-total">
                <span>Total estimado</span>
                <strong>{money(total)}</strong>
              </div>
              <button type="button" className="button outline" disabled={busy || choosingSupplier}
                onClick={() => setCreateOpen(false)}>Cerrar y conservar borrador</button>
              <button className="button primary" disabled={busy || choosingSupplier || !lines.length}>
                Revisar y crear
              </button>
            </div>
          </form>
        </ActionDialog>
      )}

      {receivingOrder && (
        <ActionDialog open title={`Recepciones · Orden Nº ${receivingOrder.number}`}
          description={receivingOrder.supplier_name} busy={receiptBusy}
          onClose={() => setReceivingOrderId(null)}>
          <ReceiveOrderPanel order={receivingOrder} onBusyChange={setReceiptBusy}
            onClose={() => setReceivingOrderId(null)} />
        </ActionDialog>
      )}

      <ConfirmDeleteDialog
        open={confirmCreate}
        intent="primary"
        busy={busy}
        title="¿Crear la orden de compra?"
        description={`${selectedSupplier?.name ?? 'Proveedor'} · ${lines.length} ítem${lines.length === 1 ? '' : 's'} · total estimado ${money(total)}. Crear la orden no suma stock: la mercadería se ingresa al recibirla.`}
        confirmLabel="Crear orden"
        onCancel={() => setConfirmCreate(false)}
        onConfirm={submit}
      />
      <ConfirmDeleteDialog
        open={Boolean(cancelTarget)}
        title="¿Cancelar lo que falta recibir?"
        description={`La orden Nº ${cancelTarget?.number ?? ''} quedará cancelada. Lo que ya ingresó a stock se conserva y no se recibirán los pendientes.`}
        confirmLabel="Cancelar orden"
        busy={busy}
        onCancel={() => setCancelTarget(null)}
        onConfirm={cancel}
      />
    </div>
    </PurchasesShell>
  );
}

import { useEffect, useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { ArrowDownToLine, X } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import { findStockWarehouses, listStockLots } from '../../services/stock';
import { subtractQuantity } from '../inventory/stockNumber';
import {
  getReceivableLines,
  listPurchaseReceipts,
  receivePurchaseOrder,
} from '../../services/purchases';

function LotFields({ companyId, userId, line, value, update, disabled }) {
  const query = useQuery({
    queryKey: ['stock-lots', userId, companyId, line.item_id, null],
    queryFn: () => listStockLots(companyId, line.item_id),
    enabled: Boolean(companyId && value.checked && line.track_lots),
    staleTime: 15_000,
  });
  const knownLot = (query.data ?? []).find((lot) => (
    lot.code.toLocaleLowerCase() === (value.lot_code ?? '').trim().toLocaleLowerCase()
  ));

  return (
    <div className="purchase-lot-fields">
      <label>
        Lote *
        <input
          required
          maxLength={80}
          disabled={disabled}
          value={value.lot_code ?? ''}
          list={`receipt-lots-${line.line_no}`}
          placeholder="Ej.: L-001"
          onChange={(event) => update(line.line_no, {
            lot_code: event.target.value,
            expires_on: '',
          })}
        />
        <datalist id={`receipt-lots-${line.line_no}`}>
          {(query.data ?? []).map((lot) => (
            <option key={lot.id} value={lot.code} />
          ))}
        </datalist>
      </label>
      <label>
        Vencimiento (opcional)
        <input
          type="date"
          disabled={disabled || Boolean(knownLot)}
          value={knownLot ? knownLot.expires_on ?? '' : value.expires_on ?? ''}
          onChange={(event) => update(line.line_no, {
            expires_on: event.target.value,
          })}
        />
      </label>
      {knownLot && <small>Se conserva el vencimiento registrado para este lote.</small>}
      {query.error && <small className="error">{friendlyError(query.error)}</small>}
    </div>
  );
}

export default function ReceiveOrderPanel({ order, onClose, onBusyChange }) {
  const { activeCompanyId, user, can } = useAuth();
  const queryClient = useQueryClient();
  const requestId = useRef(crypto.randomUUID());
  const [values, setValues] = useState({});
  const [warehouseId, setWarehouseId] = useState('');
  const [selectedWarehouse, setSelectedWarehouse] = useState(null);
  const [warehouseSearch, setWarehouseSearch] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  useEffect(() => { onBusyChange?.(busy); }, [busy, onBusyChange]);
  useEffect(() => () => onBusyChange?.(false), [onBusyChange]);
  const [reviewRequired, setReviewRequired] = useState(false);

  const linesQuery = useQuery({
    queryKey: ['purchase-receivable', user?.id, activeCompanyId, order.id],
    queryFn: () => getReceivableLines(activeCompanyId, order.id),
    enabled: Boolean(activeCompanyId),
  });

  const historyQuery = useQuery({
    queryKey: ['purchase-receipts', user?.id, activeCompanyId, order.id],
    queryFn: () => listPurchaseReceipts(activeCompanyId, order.id),
    enabled: Boolean(activeCompanyId),
  });

  const warehousesQuery = useQuery({
    queryKey: ['stock-options', user?.id, activeCompanyId, 'warehouses', warehouseSearch],
    queryFn: () => findStockWarehouses(activeCompanyId, warehouseSearch),
    enabled: Boolean(activeCompanyId && can('stock', 'read')),
  });

  useEffect(() => {
    setValues({});
    setWarehouseId('');
    setSelectedWarehouse(null);
    setNote('');
    setReviewRequired(false);
    requestId.current = crypto.randomUUID();
  }, [order.id, activeCompanyId]);

  const update = (lineNo, patch) => {
    setValues((current) => ({
      ...current,
      [lineNo]: { ...current[lineNo], ...patch },
    }));
  };

  const lines = linesQuery.data ?? [];
  const pending = lines.filter((line) => (
    subtractQuantity(line.quantity, line.received_quantity) !== '0'
  ));
  const chosen = pending.filter((line) => values[line.line_no]?.checked);
  const warehouses = selectedWarehouse && !(warehousesQuery.data ?? []).some(
    (entry) => entry.id === selectedWarehouse.id,
  ) ? [selectedWarehouse, ...(warehousesQuery.data ?? [])]
    : (warehousesQuery.data ?? []);

  const submit = async (event) => {
    event.preventDefault();
    if (!chosen.length) {
      notifyError(new Error('Marcá al menos un ítem para recibir.'));
      return;
    }

    const payload = chosen.map((line) => {
      const entry = values[line.line_no];
      const knownLot = (queryClient.getQueryData([
        'stock-lots', user?.id, activeCompanyId, line.item_id, null,
      ]) ?? []).find((lot) => (
        lot.code.toLocaleLowerCase() === (entry.lot_code ?? '').trim().toLocaleLowerCase()
      ));

      return {
        line_no: line.line_no,
        quantity: entry.quantity,
        warehouse_id: warehouseId,
        lot_code: line.track_lots ? entry.lot_code?.trim() : null,
        expires_on: line.track_lots
          ? knownLot?.expires_on ?? entry.expires_on ?? null : null,
      };
    });

    setBusy(true);
    try {
      const receiptId = await receivePurchaseOrder(activeCompanyId, order.id,
        requestId.current, note, payload);
      requestId.current = crypto.randomUUID();
      await Promise.allSettled([
        queryClient.invalidateQueries({ queryKey: ['purchase-orders', user?.id, activeCompanyId] }),
        queryClient.invalidateQueries({ queryKey: ['purchase-receivable', user?.id, activeCompanyId, order.id] }),
        queryClient.invalidateQueries({ queryKey: ['purchase-receipts', user?.id, activeCompanyId, order.id] }),
        queryClient.invalidateQueries({ queryKey: ['stock-summary', user?.id, activeCompanyId] }),
        queryClient.invalidateQueries({ queryKey: ['stock-balances', user?.id, activeCompanyId] }),
        queryClient.invalidateQueries({ queryKey: ['stock-lot-breakdown', user?.id, activeCompanyId] }),
        queryClient.invalidateQueries({ queryKey: ['stock-lots', user?.id, activeCompanyId] }),
        queryClient.invalidateQueries({ queryKey: ['stock-movements', user?.id, activeCompanyId] }),
      ]);
      setValues({});
      setNote('');
      setReviewRequired(false);
      notifySuccess('Recepción registrada', `N.º ${receiptId.slice(0, 8)} · Stock actualizado.`);
    } catch (error) {
      notifyError(error);
      if (!error?.code || /fetch|network|timeout/i.test(error.message)) {
        setReviewRequired(true);
        await Promise.allSettled([
          queryClient.invalidateQueries({ queryKey: ['purchase-orders', user?.id, activeCompanyId] }),
          queryClient.invalidateQueries({ queryKey: ['purchase-receivable', user?.id, activeCompanyId, order.id] }),
          queryClient.invalidateQueries({ queryKey: ['purchase-receipts', user?.id, activeCompanyId, order.id] }),
        ]);
      } else {
        requestId.current = crypto.randomUUID();
      }
    } finally {
      setBusy(false);
    }
  };

  const canReceive = can('purchases', 'insert') && can('stock', 'insert')
    && can('stock', 'read') && ['open', 'partial'].includes(order.status);

  return (
    <section className="purchase-card purchase-receive-panel">
      <div className="purchase-card-heading">
        <div>
          <span className="eyebrow">RECEPCIÓN · ORDEN #{order.number}</span>
          <h2>{order.supplier_name}</h2>
        </div>
        <button className="purchase-text-button" type="button" disabled={busy} onClick={onClose}
          aria-label="Cerrar recepción"><X size={18} /></button>
      </div>
      <p className="purchase-muted">
        Lo recibido se registra una sola vez. Elegí los ítems, el depósito y,
        si corresponde, su lote. El precio queda tomado de la orden.
      </p>

      {linesQuery.error && <p role="alert" className="error">{friendlyError(linesQuery.error)}</p>}
      {linesQuery.isPending && <p className="purchase-muted">Cargando pendientes…</p>}

      {canReceive && (
        <form className="purchase-form" onSubmit={submit}>
          <label>Buscar depósito
            <input value={warehouseSearch} disabled={reviewRequired}
              onChange={(event) => setWarehouseSearch(event.target.value)}
              placeholder="Nombre o código" />
          </label>
          <label>Depósito de recepción *
            <select required value={warehouseId}
              disabled={reviewRequired}
              onChange={(event) => {
                setWarehouseId(event.target.value);
                setSelectedWarehouse(warehouses.find((entry) => (
                  entry.id === event.target.value
                )) ?? null);
              }}>
              <option value="">Seleccionar depósito</option>
              {warehouses.map((entry) => (
                <option key={entry.id} value={entry.id}>{entry.name}</option>
              ))}
            </select>
          </label>
          {warehousesQuery.error && <p className="error">{friendlyError(warehousesQuery.error)}</p>}
          {pending.map((line) => {
            const remaining = subtractQuantity(line.quantity, line.received_quantity);
            const value = values[line.line_no] ?? {};
            return (
              <div className="purchase-receive-line" key={line.line_no}>
                <label className="purchase-receive-check">
                  <input type="checkbox" checked={Boolean(value.checked)}
                    disabled={reviewRequired}
                    onChange={(event) => update(line.line_no, {
                      checked: event.target.checked,
                      quantity: event.target.checked ? String(remaining) : '',
                    })} />
                  <span><strong>{line.item_code} · {line.item_name}</strong>
                    <small>Pedido: {line.quantity} · recibido: {line.received_quantity}
                      · pendiente: {remaining} {line.unit_symbol}</small></span>
                </label>
                {value.checked && (
                  <>
                    <label>Cantidad que llegó *
                      <input required type="number" min="0.000001"
                        max={remaining} step="0.000001" disabled={reviewRequired}
                        value={value.quantity ?? ''}
                        onChange={(event) => update(line.line_no, {
                          quantity: event.target.value,
                        })} />
                    </label>
                    {line.track_lots && (
                      <LotFields companyId={activeCompanyId} userId={user?.id}
                        line={line} value={value} update={update}
                        disabled={reviewRequired} />
                    )}
                  </>
                )}
              </div>
            );
          })}
          {!pending.length && (
            <p className="purchase-muted">No quedan cantidades pendientes.</p>
          )}
          <label>Motivo / remito *
            <textarea required minLength={3} maxLength={430} rows={2}
              disabled={reviewRequired}
              value={note} onChange={(event) => setNote(event.target.value)}
              placeholder="Ej.: Entrega parcial, remito 2841" />
          </label>
          {reviewRequired && (
            <div className="purchase-review-warning" role="alert">
              Hubo un corte al confirmar. Revisá el historial inferior.
              Reintentá sin cambiar los datos, o iniciá una nueva solicitud
              después de comprobar si se registró.
              <button type="button" onClick={() => {
                requestId.current = crypto.randomUUID();
                setReviewRequired(false);
              }}>Ya revisé: iniciar nueva solicitud</button>
            </div>
          )}
          <button className="button primary" disabled={busy || !pending.length
            || warehousesQuery.isPending || Boolean(warehousesQuery.error)}>
            <ArrowDownToLine size={16} /> {busy ? 'Registrando…' : 'Confirmar recepción'}
          </button>
        </form>
      )}

      <div className="purchase-receipt-history">
        <h3>Historial de recepciones</h3>
        {historyQuery.error && <p role="alert" className="error">{friendlyError(historyQuery.error)}</p>}
        {!historyQuery.isPending && !historyQuery.data?.length && (
          <p className="purchase-muted">Todavía no hay entregas registradas.</p>
        )}
        {(historyQuery.data ?? []).map((receipt) => (
          <div className="purchase-receipt-entry" key={receipt.id}>
            <strong>{new Date(receipt.created_at).toLocaleString('es-AR')}</strong>
            <span>{receipt.note}</span>
            {(receipt.lines ?? []).map((line) => (
              <small key={line.line_no}>
                {lines.find((entry) => entry.line_no === line.line_no)?.item_code
                  ?? `Línea ${line.line_no}`} · {line.quantity}
                · depósito {line.warehouse_code}
                {line.lot_code ? ` · lote ${line.lot_code}` : ''}
              </small>
            ))}
          </div>
        ))}
      </div>
    </section>
  );
}

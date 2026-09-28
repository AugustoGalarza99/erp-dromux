import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog';
import { useAuth } from '../../contexts/AuthContext';
import { friendlyError, notifyError, notifySuccess } from '../../lib/notifications';
import { adjustSale, getSaleCredit, refundSaleCredit } from '../../services/sales';
import { formatQuantity } from '../inventory/stockNumber';

const money = (value) => Number(value).toLocaleString('es-AR', {
  style: 'currency', currency: 'ARS',
});

function remainingFor(sale, line) {
  const returned = (sale.sale_adjustments ?? []).reduce((sum, adjustment) => (
    sum + (adjustment.sale_adjustment_lines ?? [])
      .filter((entry) => entry.sale_line_no === line.line_no)
      .reduce((quantity, entry) => quantity + Number(entry.quantity), 0)
  ), 0);
  return Math.max(0, Number(line.quantity) - returned);
}

export default function SaleAdjustmentPanel({ sale, accounts, onUpdated }) {
  const { activeCompanyId, user, can } = useAuth();
  const client = useQueryClient();
  const [kind, setKind] = useState('');
  const [lines, setLines] = useState({});
  const [reason, setReason] = useState('');
  const [confirming, setConfirming] = useState(false);
  const [confirmRefund, setConfirmRefund] = useState(false);
  const [busy, setBusy] = useState(false);
  const [requestId, setRequestId] = useState(() => crypto.randomUUID());
  const [refundAmount, setRefundAmount] = useState('');
  const [refundAccount, setRefundAccount] = useState('');
  const [refundReason, setRefundReason] = useState('');
  const [refundRequestId, setRefundRequestId] = useState(() => crypto.randomUUID());
  const canceled = (sale.sale_adjustments ?? []).some((entry) => entry.kind === 'cancel');
  const availableLines = sale.sale_lines.filter((line) => remainingFor(sale, line) > 0);
  const creditQuery = useQuery({
    queryKey: ['sale-credit', user?.id, activeCompanyId, sale.id],
    queryFn: () => getSaleCredit(activeCompanyId, sale.id),
    enabled: Boolean(activeCompanyId && can('finance', 'read')),
  });
  const credit = Number(creditQuery.data?.credit_due ?? 0);

  function selectKind(next) {
    setKind(next);
    setReason('');
    setRequestId(crypto.randomUUID());
    setLines(Object.fromEntries(availableLines.map((line) => [line.line_no, {
      quantity: next === 'cancel' ? String(remainingFor(sale, line)) : '',
      restock: false,
    }])));
  }

  const chosen = availableLines.map((line) => ({
    line_no: line.line_no,
    quantity: lines[line.line_no]?.quantity ?? '',
    restock: Boolean(lines[line.line_no]?.restock),
  })).filter((line) => Number(line.quantity) > 0);
  const valid = reason.trim().length >= 5 && chosen.length > 0 && chosen.every((entry) => {
    const original = availableLines.find((line) => line.line_no === entry.line_no);
    return /^\d+(?:\.\d{1,6})?$/.test(entry.quantity)
      && Number(entry.quantity) <= remainingFor(sale, original);
  }) && (kind !== 'cancel' || chosen.length === availableLines.length);

  async function submitAdjustment() {
    if (!valid || busy) return;
    setBusy(true);
    try {
      await adjustSale(activeCompanyId, sale.id, kind, reason, chosen, requestId);
      setConfirming(false);
      setKind('');
      setRequestId(crypto.randomUUID());
      await onUpdated();
      await client.invalidateQueries({ queryKey: ['sale-credit', user?.id, activeCompanyId, sale.id] });
      notifySuccess(kind === 'cancel' ? 'Venta anulada' : 'Devolución registrada',
        'El stock y el saldo se actualizaron según los productos recibidos.');
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  async function submitRefund() {
    if (busy || !/^\d+(?:\.\d{1,2})?$/.test(refundAmount)
      || Number(refundAmount) <= 0 || Number(refundAmount) > credit) {
      notifyError(new Error('El reintegro debe ser mayor a cero y no superar el crédito.'));
      return;
    }
    setBusy(true);
    try {
      await refundSaleCredit(activeCompanyId, sale.id, refundAccount,
        refundAmount, refundReason, refundRequestId);
      setConfirmRefund(false);
      setRefundRequestId(crypto.randomUUID());
      setRefundAmount('');
      setRefundReason('');
      await onUpdated();
      await client.invalidateQueries({ queryKey: ['sale-credit', user?.id, activeCompanyId, sale.id] });
      notifySuccess('Reintegro registrado', 'Se descontó el dinero de la cuenta seleccionada.');
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="sales-adjustment">
      {(sale.sale_adjustments ?? []).length > 0 && (
        <div className="sales-adjustment-history">
          {(sale.sale_adjustments ?? []).map((entry) => (
            <small key={entry.id}>
              {entry.kind === 'cancel' ? 'Anulación' : 'Devolución'} ·
              {money(entry.credit_total)} · {entry.reason}
            </small>
          ))}
        </div>
      )}
      {creditQuery.error && <p role="alert" className="sales-error">{friendlyError(creditQuery.error)}</p>}
      {creditQuery.data && (
        <p className="sales-muted">
          Importe vigente: {money(creditQuery.data.net_total)} · Cobrado:
          {' '}{money(creditQuery.data.paid)}
          {credit > 0 && <strong> · Crédito a reintegrar: {money(credit)}</strong>}
        </p>
      )}
      {can('sales', 'update') && can('stock', 'insert') && !canceled
        && availableLines.length > 0 && (
        <div className="sales-adjustment-actions">
          <button type="button" className="sales-link" onClick={() => selectKind('return')}>
            Registrar devolución
          </button>
          <button type="button" className="sales-link" onClick={() => selectKind('cancel')}>
            Anular venta
          </button>
        </div>
      )}
      {kind && (
        <div className="sales-adjustment-form">
          <h3>{kind === 'cancel' ? 'Anular venta' : 'Productos devueltos'}</h3>
          <p>Reingresá stock únicamente si la mercadería volvió en condiciones de venderse.
            El resto quedará descontado y registrado como devolución sin ingreso.</p>
          {availableLines.map((line) => (
            <div className="sales-return-line" key={line.line_no}>
              <strong>{line.item_name} · hasta {formatQuantity(remainingFor(sale, line))}
                {' '}{line.unit_symbol}</strong>
              <label>Cantidad
                <input
                  type="number"
                  min="0"
                  max={remainingFor(sale, line)}
                  step="0.000001"
                  value={lines[line.line_no]?.quantity ?? ''}
                  disabled={kind === 'cancel'}
                  onChange={(event) => setLines((current) => ({
                    ...current,
                    [line.line_no]: { ...current[line.line_no], quantity: event.target.value },
                  }))}
                />
              </label>
              <label className="sales-check">
                <input
                  type="checkbox"
                  checked={Boolean(lines[line.line_no]?.restock)}
                  onChange={(event) => setLines((current) => ({
                    ...current,
                    [line.line_no]: { ...current[line.line_no], restock: event.target.checked },
                  }))}
                />
                Recibido y apto: reingresar al depósito original
              </label>
            </div>
          ))}
          <label>Motivo
            <textarea
              minLength={5}
              maxLength={300}
              value={reason}
              onChange={(event) => setReason(event.target.value)}
              placeholder="Describí el motivo para conservarlo en el historial"
            />
          </label>
          <div className="sales-adjustment-actions">
            <button type="button" className="button outline" onClick={() => setKind('')}>
              Volver
            </button>
            <button type="button" className="button primary" disabled={!valid || busy}
              onClick={() => setConfirming(true)}>
              Revisar {kind === 'cancel' ? 'anulación' : 'devolución'}
            </button>
          </div>
        </div>
      )}
      {credit > 0 && can('finance', 'insert') && can('sales', 'update') && (
        <form className="sales-adjustment-form" onSubmit={(event) => {
          event.preventDefault();
          if (/^\d+(?:\.\d{1,2})?$/.test(refundAmount)
            && Number(refundAmount) > 0 && Number(refundAmount) <= credit) {
            setConfirmRefund(true);
          } else {
            notifyError(new Error('Revisá el importe a reintegrar.'));
          }
        }}>
          <h3>Reintegrar dinero al cliente</h3>
          <p>Crédito disponible: {money(credit)}. El reintegro se registra como salida
            de la cuenta seleccionada.</p>
          <label>Cuenta de salida
            <select required value={refundAccount}
              onChange={(event) => setRefundAccount(event.target.value)}>
              <option value="">Seleccionar cuenta…</option>
              {accounts.map((account) => (
                <option key={account.account_id} value={account.account_id}>
                  {account.name} · {account.kind === 'cash' ? 'Efectivo' : 'Cuenta'}
                </option>
              ))}
            </select>
          </label>
          <label>Importe a reintegrar
            <input type="number" min="0.01" max={credit} step="0.01"
              required value={refundAmount}
              onChange={(event) => setRefundAmount(event.target.value)} />
          </label>
          <label>Motivo del reintegro
            <input required minLength={5} maxLength={240} value={refundReason}
              onChange={(event) => setRefundReason(event.target.value)} />
          </label>
          <button className="button outline" disabled={busy || !accounts.length}>
            {busy ? 'Registrando…' : 'Registrar reintegro'}
          </button>
        </form>
      )}
      <ConfirmDeleteDialog
        open={confirmRefund}
        busy={busy}
        title="¿Confirmás el reintegro al cliente?"
        description={`Se descontarán ${money(refundAmount || 0)} de la cuenta seleccionada. La operación quedará registrada en tesorería.`}
        confirmLabel="Confirmar reintegro"
        onCancel={() => setConfirmRefund(false)}
        onConfirm={submitRefund}
      />
      <ConfirmDeleteDialog
        open={confirming}
        busy={busy}
        title={kind === 'cancel' ? '¿Seguro que querés anular esta venta?' : '¿Confirmás la devolución?'}
        description={`Se registrará un crédito por ${chosen.length} producto(s). Solo se reingresará al stock la mercadería que marcaste como recibida y apta. El historial quedará disponible.`}
        confirmLabel={kind === 'cancel' ? 'Anular venta' : 'Registrar devolución'}
        onCancel={() => setConfirming(false)}
        onConfirm={submitAdjustment}
      />
    </div>
  );
}

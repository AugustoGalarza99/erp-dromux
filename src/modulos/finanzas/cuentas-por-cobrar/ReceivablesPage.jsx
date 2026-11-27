import { useEffect, useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Banknote, CreditCard, Receipt, Search } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import {
  listReceivables, listSalePayments, postSalePayment, reverseSalePayment,
} from '../../services/receivables';
import { getTreasuryBalances } from '../../services/treasury';
import './receivables.css';

const money = (value) => Number(value).toLocaleString('es-AR', {
  minimumFractionDigits: 2, maximumFractionDigits: 2,
});
const methods = {
  cash: 'Efectivo', transfer: 'Transferencia', card: 'Tarjeta',
  check: 'Cheque', other: 'Otro',
};
const localToday = () => new Intl.DateTimeFormat('sv-SE', {
  timeZone: 'America/Argentina/Buenos_Aires',
}).format(new Date());

function toCents(value) {
  const raw = String(value ?? '');
  if (!/^\d+(\.\d{1,2})?$/.test(raw)) return null;
  const [whole, fraction = ''] = raw.split('.');
  return BigInt(whole) * 100n + BigInt(fraction.padEnd(2, '0'));
}

function ReversalDialog({ payment, busy, onClose, onSubmit }) {
  const dialog = useRef(null);
  const [reason, setReason] = useState('');
  useEffect(() => {
    if (payment && !dialog.current?.open) dialog.current?.showModal();
    if (!payment && dialog.current?.open) dialog.current?.close();
    if (!payment) setReason('');
  }, [payment]);
  return <dialog ref={dialog} className="erp-confirm-dialog" onCancel={(event) => {
    event.preventDefault();
    if (!busy) onClose();
  }}>
    <h2>¿Seguro que quieres anular este cobro?</h2>
    <p>El importe dejará de contar como pagado. El registro y el motivo de anulación quedarán en el historial.</p>
    <form onSubmit={(event) => { event.preventDefault(); onSubmit(reason); }}>
      <label className="finance-reversal-reason">Motivo de anulación
        <textarea required minLength={5} maxLength={300} value={reason}
          onChange={(event) => setReason(event.target.value)}
          placeholder="Ej.: Se cargó con un monto incorrecto" />
      </label>
      <div className="erp-confirm-actions">
        <button type="button" className="button outline" disabled={busy} onClick={onClose}>Volver</button>
        <button className="button erp-confirm-danger" disabled={busy}>
          {busy ? 'Anulando…' : 'Anular cobro'}
        </button>
      </div>
    </form>
  </dialog>;
}

export default function ReceivablesPage() {
  const { activeCompanyId, user, can } = useAuth();
  const client = useQueryClient();
  const [page, setPage] = useState(0);
  const [search, setSearch] = useState('');
  const [saleId, setSaleId] = useState('');
  const [amount, setAmount] = useState('');
  const [accountId, setAccountId] = useState('');
  const [method, setMethod] = useState('transfer');
  const [paidOn, setPaidOn] = useState(localToday);
  const [reference, setReference] = useState('');
  const [note, setNote] = useState('Cobro de venta');
  const [busy, setBusy] = useState(false);
  const [reversing, setReversing] = useState(null);
  const [requestId, setRequestId] = useState(() => crypto.randomUUID());
  const term = useDebouncedValue(search);
  const receivablesQuery = useQuery({
    queryKey: ['receivables', user?.id, activeCompanyId, page, term],
    queryFn: () => listReceivables(activeCompanyId, page, term),
    enabled: !!activeCompanyId,
  });
  const accountsQuery = useQuery({
    queryKey: ['treasury-balances', user?.id, activeCompanyId],
    queryFn: () => getTreasuryBalances(activeCompanyId),
    enabled: !!activeCompanyId,
  });
  const accounts = (accountsQuery.data ?? []).filter((row) => row.active);
  const paymentsQuery = useQuery({
    queryKey: ['sale-payments', user?.id, activeCompanyId, saleId],
    queryFn: () => listSalePayments(activeCompanyId, saleId),
    enabled: !!(activeCompanyId && saleId),
  });
  const rows = receivablesQuery.data?.rows ?? [];
  const selected = rows.find((row) => row.sale_id === saleId);
  const balanceCents = toCents(selected?.outstanding);
  const amountCents = toCents(amount);
  const validAmount = amountCents != null && balanceCents != null &&
    amountCents > 0n && amountCents <= balanceCents;

  useEffect(() => {
    setSaleId('');
    setAccountId('');
    setSearch('');
    setPage(0);
    setReversing(null);
    setRequestId(crypto.randomUUID());
  }, [activeCompanyId]);
  useEffect(() => { setPage(0); setSaleId(''); }, [term]);

  const refresh = () => Promise.all([
    client.invalidateQueries({ queryKey: ['receivables', user?.id, activeCompanyId] }),
    client.invalidateQueries({ queryKey: ['sale-payments', user?.id, activeCompanyId] }),
    client.invalidateQueries({ queryKey: ['treasury-balances', user?.id, activeCompanyId] }),
  ]);

  function selectSale(row) {
    setSaleId(row.sale_id);
    setAmount(Number(row.outstanding) > 0 ? String(row.outstanding) : '');
    setReference('');
    setNote('Cobro de venta');
    setRequestId(crypto.randomUUID());
  }

  async function submit(event) {
    event.preventDefault();
    if (!accountId) {
      notifyError(new Error('Elegí una cuenta de tesorería para este cobro.'));
      return;
    }
    if (!selected || !validAmount) {
      notifyError(new Error('El monto debe ser mayor a cero y no superar el saldo pendiente.'));
      return;
    }
    setBusy(true);
    try {
      await postSalePayment(activeCompanyId, {
        saleId, amount, method, paidOn, reference, note, accountId,
      }, requestId);
      setRequestId(crypto.randomUUID());
      setAmount('');
      setReference('');
      await refresh();
      notifySuccess('Cobro registrado', `Venta Nº ${selected.sale_number} · $ ${money(amount)}`);
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  async function reverse(reason) {
    if (!reversing) return;
    setBusy(true);
    try {
      await reverseSalePayment(activeCompanyId, reversing.id, reason);
      await refresh();
      setReversing(null);
      setAmount('');
      setRequestId(crypto.randomUUID());
      notifySuccess('Cobro anulado', 'El saldo pendiente se actualizó.');
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return <section className="finance-page">
    <div className="finance-heading">
      <div><span className="eyebrow">FINANZAS / CUENTAS POR COBRAR</span>
        <h1>Cobros de clientes</h1>
        <p>Consultá el saldo de cada venta y registrá pagos parciales o completos.</p>
      </div>
      <Link className="button" to="/sales/orders">Ir a ventas</Link>
    </div>
    <div className="finance-grid">
      <div className="finance-card">
        <h2><Receipt size={19} /> Ventas y saldos</h2>
        <div className="finance-search"><Search size={17} />
          <input aria-label="Buscar venta o cliente" value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Cliente o número de venta…" />
        </div>
        {receivablesQuery.isError && <p className="finance-error">{friendlyError(receivablesQuery.error)}</p>}
        {!rows.length && !receivablesQuery.isPending && <p className="finance-muted">
          No hay ventas para esta búsqueda.
        </p>}
        {rows.map((row) => <button type="button" key={row.sale_id}
          className={`finance-sale ${saleId === row.sale_id ? 'selected' : ''}`}
          onClick={() => selectSale(row)}>
          <span><strong>Venta Nº {row.sale_number} · {row.customer_name}</strong>
            <small>{new Date(row.created_at).toLocaleDateString('es-AR')}</small></span>
          <span className="finance-sale-totals">
            <strong>$ {money(row.outstanding)}</strong>
            <small>pendiente de $ {money(row.total)}</small>
            {Number(row.total) === 0 && (
              <span className="finance-paid">Anulada o devuelta por completo</span>
            )}
            {Number(row.total) > 0 && Number(row.outstanding) === 0 && (
              <span className="finance-paid">Sin saldo pendiente</span>
            )}
            {Number(row.paid) > Number(row.total) && (
              <small>Hay cobros anteriores a la devolución. Revisá el reintegro en Ventas.</small>
            )}
          </span>
        </button>)}
        <div className="finance-pagination">
          <span>{receivablesQuery.data?.count ?? 0} ventas · Página {page + 1}</span>
          <div>
            <button type="button" disabled={page === 0}
              onClick={() => { setPage((current) => current - 1); setSaleId(''); }}>Anterior</button>
            <button type="button" disabled={(page + 1) * 25 >= (receivablesQuery.data?.count ?? 0)}
              onClick={() => { setPage((current) => current + 1); setSaleId(''); }}>Siguiente</button>
          </div>
        </div>
      </div>
      <div className="finance-card">
        <h2><Banknote size={19} /> {selected ? `Cobrar venta Nº ${selected.sale_number}` : 'Seleccioná una venta'}</h2>
        {!selected && <p className="finance-muted">Elegí una venta para ver los pagos y registrar un cobro.</p>}
        {selected && <>
          <div className="finance-summary">
            <span>Total $ {money(selected.total)}</span>
            <span>Cobrado $ {money(selected.paid)}</span>
            <strong>Saldo $ {money(selected.outstanding)}</strong>
          </div>
          {Number(selected.outstanding) > 0 ? <form onSubmit={submit}>
            <div className="finance-fields">
              <label>Monto a cobrar
                <input required type="number" min="0.01" step="0.01" value={amount}
                  onChange={(event) => { setAmount(event.target.value);
                    setRequestId(crypto.randomUUID()); }} />
              </label>
              <label>Fecha del cobro
                <input required type="date" value={paidOn}
                  onChange={(event) => { setPaidOn(event.target.value);
                    setRequestId(crypto.randomUUID()); }} />
              </label>
            </div>
            <label>Cuenta que recibe el cobro
              <select required value={accountId} onChange={(event) => {
                setAccountId(event.target.value);
                setRequestId(crypto.randomUUID());
              }}>
                <option value="">Elegí una cuenta</option>
                {accounts.map((account) => <option key={account.account_id}
                  value={account.account_id}>{account.name}</option>)}
              </select>
            </label>
            {!accounts.length && <p className="finance-muted">Creá primero una cuenta en Tesorería.</p>}
            <label>Medio de pago
              <select value={method} onChange={(event) => {
                setMethod(event.target.value);
                setRequestId(crypto.randomUUID());
              }}>
                {Object.entries(methods).map(([key, label]) => <option key={key} value={key}>
                  {label}
                </option>)}
              </select>
            </label>
            <label>Referencia (opcional)
              <input maxLength={100} value={reference} placeholder="Número de transferencia, cheque…"
                onChange={(event) => { setReference(event.target.value);
                  setRequestId(crypto.randomUUID()); }} />
            </label>
            <label>Observaciones
              <textarea maxLength={500} value={note}
                onChange={(event) => { setNote(event.target.value);
                  setRequestId(crypto.randomUUID()); }} />
            </label>
            <button className="button primary" disabled={busy || !validAmount || !accountId || !can('finance', 'insert')}>
              <CreditCard size={17} /> {busy ? 'Registrando…' : 'Registrar cobro'}
            </button>
          </form> : <p className="finance-paid-message">La venta está totalmente cobrada.</p>}
          <div className="finance-history">
            <h3>Historial de cobros</h3>
            {paymentsQuery.isError && <p className="finance-error">{friendlyError(paymentsQuery.error)}</p>}
            {!paymentsQuery.data?.length && <p className="finance-muted">No se registraron cobros todavía.</p>}
            {paymentsQuery.data?.map((payment) => <div key={payment.id}
              className={`finance-payment ${payment.reversal ? 'reversed' : ''}`}>
              <div><strong>$ {money(payment.amount)} · {methods[payment.method]}</strong>
                <small>{new Date(`${payment.paid_on}T12:00:00`).toLocaleDateString('es-AR')}
                  {payment.reference ? ` · ${payment.reference}` : ''}</small>
                {payment.reversal && <small>Anulado: {payment.reversal.reason}</small>}
              </div>
              {!payment.reversal && can('finance', 'update') && <button type="button"
                disabled={busy} onClick={() => setReversing(payment)}>Anular</button>}
            </div>)}
          </div>
        </>}
      </div>
    </div>
    <ReversalDialog payment={reversing} busy={busy}
      onClose={() => setReversing(null)} onSubmit={reverse} />
  </section>;
}

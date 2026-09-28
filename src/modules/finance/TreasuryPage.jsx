import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '../../contexts/AuthContext';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog';
import { notifyError, notifySuccess } from '../../lib/notifications';
import { listPurchaseOrders } from '../../services/purchases';
import {
  assignSalePayment, createTreasuryAccount, getTreasuryBalances,
  listTreasuryEntries, listUnassignedPayments, postTreasuryEntry,
} from '../../services/treasury';
import './financeExtra.css';

const ars = (value) => Number(value).toLocaleString('es-AR', {
  style: 'currency', currency: 'ARS',
});
const kinds = {
  income: 'Otro ingreso', expense: 'Gasto', supplier_payment: 'Pago a proveedor',
  customer_payment: 'Cobro de cliente', annulled_payment: 'Cobro anulado',
  transfer_out: 'Transferencia entre cuentas', transfer_in: 'Transferencia recibida',
};
const today = () => new Intl.DateTimeFormat('sv-SE', {
  timeZone: 'America/Argentina/Buenos_Aires',
}).format(new Date());

export default function TreasuryPage() {
  const { activeCompanyId, user, can } = useAuth();
  const client = useQueryClient();
  const [busy, setBusy] = useState(false);
  const [confirmEntry, setConfirmEntry] = useState(false);
  const [newAccount, setNewAccount] = useState({ name: '', kind: 'bank', opening: '0' });
  const [entry, setEntry] = useState({ kind: 'expense', accountId: '', targetId: '',
    orderId: '', amount: '', note: '', date: today() });
  const [requestId, setRequestId] = useState(() => crypto.randomUUID());
  const [allocation, setAllocation] = useState({});
  const balances = useQuery({
    queryKey: ['treasury-balances', user?.id, activeCompanyId],
    queryFn: () => getTreasuryBalances(activeCompanyId), enabled: !!activeCompanyId,
  });
  const movements = useQuery({
    queryKey: ['treasury-entries', user?.id, activeCompanyId],
    queryFn: () => listTreasuryEntries(activeCompanyId), enabled: !!activeCompanyId,
  });
  const unassigned = useQuery({
    queryKey: ['treasury-unassigned', user?.id, activeCompanyId],
    queryFn: () => listUnassignedPayments(activeCompanyId), enabled: !!activeCompanyId,
  });
  const orders = useQuery({
    queryKey: ['treasury-orders', user?.id, activeCompanyId],
    queryFn: () => listPurchaseOrders(activeCompanyId),
    enabled: !!activeCompanyId && can('purchases', 'read'),
  });
  useEffect(() => {
    setEntry({ kind: 'expense', accountId: '', targetId: '', orderId: '',
      amount: '', note: '', date: today() });
    setRequestId(crypto.randomUUID());
  }, [activeCompanyId]);
  const accounts = (balances.data ?? []).filter((row) => row.active);
  const refresh = () => Promise.all([
    client.invalidateQueries({ queryKey: ['treasury-balances', user?.id, activeCompanyId] }),
    client.invalidateQueries({ queryKey: ['treasury-entries', user?.id, activeCompanyId] }),
    client.invalidateQueries({ queryKey: ['treasury-unassigned', user?.id, activeCompanyId] }),
  ]);

  async function saveAccount(event) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    try {
      await createTreasuryAccount(activeCompanyId, newAccount);
      await refresh();
      setNewAccount({ name: '', kind: 'bank', opening: '0' });
      notifySuccess('Cuenta creada');
    } catch (error) { notifyError(error); } finally { setBusy(false); }
  }

  async function saveEntry(event) {
    event.preventDefault();
    if (busy) return;
    if (entry.kind === 'supplier_payment' && !entry.orderId) {
      notifyError(new Error('Elegí una orden de compra abierta.'));
      return;
    }
    if (entry.kind === 'transfer_out' && !entry.targetId) {
      notifyError(new Error('Elegí la cuenta de destino.'));
      return;
    }
    setConfirmEntry(true);
  }

  async function confirmSaveEntry() {
    if (busy) return;
    setBusy(true);
    try {
      await postTreasuryEntry(activeCompanyId, entry, requestId);
      setConfirmEntry(false);
      setRequestId(crypto.randomUUID());
      setEntry((current) => ({ ...current, amount: '', note: '', orderId: '' }));
      await refresh();
      notifySuccess('Movimiento registrado');
    } catch (error) { notifyError(error); } finally { setBusy(false); }
  }

  async function assign(paymentId) {
    const accountId = allocation[paymentId];
    if (!accountId || busy) return;
    setBusy(true);
    try {
      await assignSalePayment(activeCompanyId, paymentId, accountId);
      await refresh();
      notifySuccess('Cobro asignado a la cuenta');
    } catch (error) { notifyError(error); } finally { setBusy(false); }
  }

  return <section className="finance-extra">
    <div className="page-head"><div><span className="eyebrow">FINANZAS / TESORERÍA</span>
      <h1>Tesorería</h1>
      <p>Cuentas, cobros, pagos y movimientos en pesos de tu empresa.</p>
    </div></div>
    {balances.error && <p role="alert" className="error">No pudimos consultar los saldos. Reintentá más tarde.</p>}
    <div className="finance-extra-accounts">{(balances.data ?? []).map((row) =>
      <article className="finance-extra-account" key={row.account_id}>
        <small>{row.kind === 'cash' ? 'EFECTIVO' : row.kind === 'bank' ? 'BANCO' : 'OTRA CUENTA'}</small>
        <h2>{row.name}</h2>
        <strong>{ars(row.balance)}</strong>
        <span>Ingresos {ars(row.income)} · Egresos {ars(row.expense)}</span>
      </article>)}</div>
    {!balances.isPending && !balances.data?.length && <p>Creá una cuenta para empezar a registrar movimientos.</p>}
    <div className="finance-extra-columns">
      {can('finance', 'insert') && <section className="finance-extra-card">
        <h2>Nueva cuenta</h2>
        <form className="finance-extra-form" onSubmit={saveAccount}>
          <label>Nombre<input required minLength={2} maxLength={100} value={newAccount.name}
            onChange={(event) => setNewAccount({ ...newAccount, name: event.target.value })} /></label>
          <label>Tipo<select value={newAccount.kind}
            onChange={(event) => setNewAccount({ ...newAccount, kind: event.target.value })}>
            <option value="bank">Banco</option><option value="cash">Efectivo</option>
            <option value="other">Otra cuenta</option>
          </select></label>
          <label>Saldo inicial en pesos<input required type="number" step="0.01"
            value={newAccount.opening}
            onChange={(event) => setNewAccount({ ...newAccount, opening: event.target.value })} /></label>
          <button className="button primary" disabled={busy}>Crear cuenta</button>
        </form>
      </section>}
      {can('finance', 'insert') && <section className="finance-extra-card">
        <h2>Registrar movimiento</h2>
        <form className="finance-extra-form" onSubmit={saveEntry}>
          <label>Movimiento<select value={entry.kind} onChange={(event) => {
            setEntry({ ...entry, kind: event.target.value, orderId: '', targetId: '' });
            setRequestId(crypto.randomUUID());
          }}>
            {['expense', 'supplier_payment', 'income', 'transfer_out'].map((key) =>
              <option key={key} value={key}>{kinds[key]}</option>)}
          </select></label>
          <label>Cuenta de origen<select required value={entry.accountId}
            onChange={(event) => { setEntry({ ...entry, accountId: event.target.value });
              setRequestId(crypto.randomUUID()); }}>
            <option value="">Elegí una cuenta</option>
            {accounts.map((row) => <option key={row.account_id} value={row.account_id}>{row.name}</option>)}
          </select></label>
          {entry.kind === 'transfer_out' && <label>Cuenta de destino<select required
            value={entry.targetId} onChange={(event) => { setEntry({ ...entry, targetId: event.target.value });
              setRequestId(crypto.randomUUID()); }}>
            <option value="">Elegí una cuenta</option>
            {accounts.filter((row) => row.account_id !== entry.accountId).map((row) =>
              <option key={row.account_id} value={row.account_id}>{row.name}</option>)}
          </select></label>}
          {entry.kind === 'supplier_payment' && <label>Orden de compra<select required
            value={entry.orderId} onChange={(event) => { setEntry({ ...entry, orderId: event.target.value });
              setRequestId(crypto.randomUUID()); }}>
            <option value="">Elegí una orden abierta</option>
            {(orders.data ?? []).filter((row) => row.status === 'open').map((row) =>
              <option key={row.id} value={row.id}>Nº {row.number} · {row.supplier_name}</option>)}
          </select></label>}
          <label>Importe en pesos<input required type="number" min="0.01" step="0.01"
            value={entry.amount} onChange={(event) => { setEntry({ ...entry, amount: event.target.value });
              setRequestId(crypto.randomUUID()); }} /></label>
          <label>Fecha<input required type="date" max={today()} value={entry.date}
            onChange={(event) => { setEntry({ ...entry, date: event.target.value });
              setRequestId(crypto.randomUUID()); }} /></label>
          <label>Detalle<textarea required minLength={3} maxLength={240} value={entry.note}
            onChange={(event) => { setEntry({ ...entry, note: event.target.value });
              setRequestId(crypto.randomUUID()); }} /></label>
          <button className="button primary" disabled={busy || !accounts.length}>Registrar</button>
        </form>
      </section>}
    </div>
    {!!unassigned.data?.length && <section className="finance-extra-card">
      <h2>Cobros anteriores sin cuenta</h2>
      <p>Asigná una sola vez cada cobro anterior para incluirlo en el saldo de tesorería.</p>
      {unassigned.data.map((payment) => <div className="finance-extra-movement" key={payment.id}>
        <span>Venta Nº {payment.sale?.number} · {payment.sale?.customer_name}
          <small>{payment.paid_on} · {ars(payment.amount)}</small></span>
        {can('finance', 'update') && <><select aria-label="Cuenta para cobro"
          value={allocation[payment.id] ?? ''}
          onChange={(event) => setAllocation({ ...allocation, [payment.id]: event.target.value })}>
          <option value="">Elegí una cuenta</option>
          {accounts.map((row) => <option key={row.account_id} value={row.account_id}>{row.name}</option>)}
        </select><button type="button" disabled={busy || !allocation[payment.id]}
          onClick={() => assign(payment.id)}>Asignar</button></>}
      </div>)}
    </section>}
    <section className="finance-extra-card"><h2>Movimientos recientes</h2>
      {movements.error && <p role="alert" className="error">No pudimos cargar los movimientos.</p>}
      {!movements.isPending && !movements.data?.length && <p>Sin movimientos todavía.</p>}
      {(movements.data ?? []).map((row) => <div className="finance-extra-movement" key={row.id}>
        <span><strong>{kinds[row.kind]} · {balances.data?.find((account) =>
          account.account_id === row.account_id)?.name ?? 'Cuenta'}</strong>
          <small>{row.note} · {row.occurred_on}</small></span>
        <strong className={['expense', 'supplier_payment', 'transfer_out'].includes(row.kind)
          ? 'finance-negative' : ''}>{ars(row.amount)}</strong>
      </div>)}
    </section>
    <ConfirmDeleteDialog open={confirmEntry} title="¿Confirmás el movimiento?"
      description="El importe y la cuenta quedarán registrados en el historial."
      confirmLabel="Registrar movimiento" busy={busy}
      onCancel={() => setConfirmEntry(false)} onConfirm={confirmSaveEntry} />
    <p className="finance-extra-note">Saldo declarado según los movimientos registrados.
      Un cobro anulado deja de sumar automáticamente. Consultá las cuentas por cobrar
      para registrar nuevos cobros de clientes.</p>
  </section>;
}

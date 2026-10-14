import { useEffect, useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '../../contexts/AuthContext';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import ActionDialog from '../../components/ActionDialog';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import { getTreasuryBalances } from '../../services/treasury';
import {
  purchaseStatistics,
  supplierAccount,
  payableOrders,
  paymentOrders,
  createPaymentOrder,
  confirmPaymentOrder,
  cancelPaymentOrder,
  findFinanceSuppliers,
} from '../../services/supplierFinance';
import { money, argentinaToday } from './supplierUi';
import './supplierAccounts.css';

function Pager({ page, count, onChange }) {
  return (
    <div className="supplier-finance-pagination">
      <button
        type="button"
        className="button outline"
        disabled={!page}
        onClick={() => onChange(page - 1)}
      >
        Anterior
      </button>
      <span>
        Página {page + 1} de {Math.max(1, Math.ceil(count / 25))}
      </span>
      <button
        type="button"
        className="button outline"
        disabled={(page + 1) * 25 >= count}
        onClick={() => onChange(page + 1)}
      >
        Siguiente
      </button>
    </div>
  );
}

export default function SupplierAccountsPage() {
  const { activeCompanyId: company, user, can, activeCompany } = useAuth();
  const client = useQueryClient();
  const [tab, setTab] = useState('stats');
  const [ranking, setRanking] = useState('products');
  const [from, setFrom] = useState(() => `${argentinaToday().slice(0, 7)}-01`);
  const [to, setTo] = useState(argentinaToday);
  const [search, setSearch] = useState('');
  const term = useDebouncedValue(search);
  const [supplier, setSupplier] = useState(null);
  const [page, setPage] = useState(0);
  const [ordersPage, setOrdersPage] = useState(0);
  const [payablePage, setPayablePage] = useState(0);
  const [createOpen, setCreateOpen] = useState(false);
  const [form, setForm] = useState({
    account: '',
    date: argentinaToday(),
    note: 'Pago a proveedor',
    reference: '',
  });
  const [picked, setPicked] = useState({});
  const [action, setAction] = useState(null);
  const [busy, setBusy] = useState(false);
  const request = useRef(null);
  const validDates = Boolean(from && to && from <= to);
  const finance = can('finance', 'read');
  const key = (name, ...parts) => [name, user?.id, company, ...parts];
  const suppliers = useQuery({
    queryKey: key('finance-suppliers', term),
    queryFn: () => findFinanceSuppliers(company, term),
    enabled: Boolean(company),
  });
  const stats = useQuery({
    queryKey: key('supplier-statistics', from, to),
    queryFn: () => purchaseStatistics(company, from, to),
    enabled: Boolean(company && validDates && tab === 'stats'),
  });
  const ledger = useQuery({
    queryKey: key('supplier-account', supplier?.id, from, to, page),
    queryFn: () => supplierAccount(company, supplier.id, from, to, page),
    enabled: Boolean(company && finance && supplier && validDates && tab === 'account'),
  });
  const payments = useQuery({
    queryKey: key('supplier-payments', ordersPage),
    queryFn: () => paymentOrders(company, ordersPage),
    enabled: Boolean(company && finance && tab === 'payments'),
  });
  const accounts = useQuery({
    queryKey: key('treasury-balances'),
    queryFn: () => getTreasuryBalances(company),
    enabled: Boolean(company && finance && createOpen),
  });
  const pending = useQuery({
    queryKey: key('supplier-payables', supplier?.id, payablePage),
    queryFn: () => payableOrders(company, supplier.id, payablePage),
    enabled: Boolean(company && finance && supplier && createOpen),
  });
  const chosen = [supplier, ...(suppliers.data ?? [])].filter(
    (entry, index, all) => entry && all.findIndex((other) => other?.id === entry.id) === index,
  );
  const total = Object.values(picked).reduce((sum, amount) => sum + Number(amount || 0), 0);

  useEffect(() => {
    setSupplier(null);
    setPicked({});
    setPage(0);
    setOrdersPage(0);
    setCreateOpen(false);
    setAction(null);
    request.current = null;
  }, [company]);
  useEffect(() => {
    setPage(0);
  }, [from, to, supplier?.id]);

  async function refresh() {
    await client.invalidateQueries({
      predicate: (query) =>
        [
          'supplier-account',
          'supplier-payments',
          'supplier-payables',
          'treasury-balances',
          'treasury-entries',
          'treasury-activity',
          'erp-dashboard',
        ].includes(query.queryKey[0]),
    });
  }

  async function save(event) {
    event.preventDefault();
    if (busy || !supplier || total <= 0) return;
    const values = {
      ...form,
      supplier: supplier.id,
      lines: Object.entries(picked)
        .filter(([, amount]) => Number(amount) > 0)
        .map(([order_id, amount]) => ({ order_id, amount })),
    };
    const fingerprint = JSON.stringify(values);
    if (request.current?.fingerprint !== fingerprint)
      request.current = { fingerprint, id: crypto.randomUUID() };
    setBusy(true);
    try {
      await createPaymentOrder(company, values, request.current.id);
      request.current = null;
      setPicked({});
      setCreateOpen(false);
      setTab('payments');
      await refresh();
      notifySuccess(
        'Orden de pago creada',
        'Quedó como borrador. Confirmala cuando registres el pago.',
      );
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  async function apply() {
    if (busy || !action) return;
    setBusy(true);
    try {
      if (action.kind === 'pay') await confirmPaymentOrder(company, action.row.id);
      else await cancelPaymentOrder(company, action.row.id);
      setAction(null);
      await refresh();
      notifySuccess(action.kind === 'pay' ? 'Pago registrado en Tesorería' : 'Borrador anulado');
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  async function print(row) {
    try {
      const { downloadPaymentOrder } = await import('./supplierPaymentPdf');
      downloadPaymentOrder(row, activeCompany?.name);
    } catch (error) {
      notifyError(error);
    }
  }

  return (
    <section className="supplier-finance-page">
      <header className="page-head">
        <div>
          <span className="eyebrow">COMPRAS</span>
          <h1>Compras y cuentas de proveedores</h1>
          <p>Recepciones, saldos y órdenes de pago conectadas a Tesorería.</p>
        </div>
      </header>
      <nav className="supplier-finance-tabs" aria-label="Compras de proveedores">
        {[
          ['stats', 'Estadísticas'],
          ['account', 'Cuenta corriente'],
          ['payments', 'Órdenes de pago'],
        ]
          .filter(([id]) => id === 'stats' || finance)
          .map(([id, title]) => (
            <button
              type="button"
              key={id}
              className={`button ${tab === id ? 'primary' : 'outline'}`}
              onClick={() => setTab(id)}
            >
              {title}
            </button>
          ))}
      </nav>
      {tab !== 'payments' && (
        <div className="supplier-finance-filters">
          <label>
            Desde
            <input type="date" value={from} onChange={(event) => setFrom(event.target.value)} />
          </label>
          <label>
            Hasta
            <input type="date" value={to} onChange={(event) => setTo(event.target.value)} />
          </label>
          {!validDates && (
            <p role="alert" className="error">
              Revisá el rango de fechas.
            </p>
          )}
        </div>
      )}
      {tab === 'account' && (
        <div className="supplier-finance-filters">
          <label>
            Buscar proveedor
            <input
              type="search"
              value={search}
              placeholder="Filtrar por nombre"
              onChange={(event) => setSearch(event.target.value)}
            />
          </label>
          <label>
            Proveedor
            <select
              value={supplier?.id ?? ''}
              onChange={(event) => {
                setSupplier(chosen.find((entry) => entry.id === event.target.value) ?? null);
                setPicked({});
                setPayablePage(0);
              }}
            >
              <option value="">Seleccionar proveedor</option>
              {chosen.map((entry) => (
                <option key={entry.id} value={entry.id}>
                  {entry.name}
                  {!entry.active && ' (inactivo)'}
                </option>
              ))}
            </select>
          </label>
          {suppliers.error && (
            <p role="alert" className="error">
              {friendlyError(suppliers.error)}
            </p>
          )}
        </div>
      )}
      {tab === 'stats' && (
        <>
          {stats.isFetching && <p>Consultando recepciones…</p>}
          {stats.error && (
            <p className="error" role="alert">
              {friendlyError(stats.error)}
            </p>
          )}
          <div className="supplier-finance-metrics">
            <article>
              <span>Compras recibidas</span>
              <strong>{money(stats.data?.total ?? 0)}</strong>
            </article>
            <article>
              <span>Recepciones del período</span>
              <strong>{stats.data?.receipts ?? 0}</strong>
            </article>
          </div>
          <div className="supplier-finance-columns">
            <article className="supplier-finance-card">
              <h2>Top 10 proveedores por importe</h2>
              {!(stats.data?.suppliers ?? []).length && (
                <p>Sin compras recibidas en este período.</p>
              )}
              {(stats.data?.suppliers ?? []).map((entry, index) => (
                <div className="supplier-finance-rank" key={entry.supplier_id}>
                  <strong>
                    {index + 1}. {entry.name}
                  </strong>
                  <span>{money(entry.amount)}</span>
                  <small>{entry.receipts} recepciones</small>
                </div>
              ))}
            </article>
            <article className="supplier-finance-card">
              <h2>Top 10 productos</h2>
              <label>
                Ordenar por
                <select value={ranking} onChange={(event) => setRanking(event.target.value)}>
                  <option value="products">Importe comprado</option>
                  <option value="products_frequency">Frecuencia de recepción</option>
                </select>
              </label>
              <p>Se muestra la cantidad de cada producto en su propia unidad.</p>
              {(stats.data?.[ranking] ?? []).map((entry, index) => (
                <div
                  className="supplier-finance-rank"
                  key={`${entry.item_id}:${entry.unit_symbol}`}
                >
                  <strong>
                    {index + 1}. {entry.name}
                  </strong>
                  <span>{money(entry.amount)}</span>
                  <small>
                    {entry.frequency != null && `${entry.frequency} recepciones · `}
                    {Number(entry.quantity).toLocaleString('es-AR', {
                      maximumFractionDigits: 6,
                    })}{' '}
                    {entry.unit_symbol}
                  </small>
                </div>
              ))}
            </article>
          </div>
        </>
      )}
      {tab === 'account' && supplier && (
        <>
          {ledger.isFetching && <p>Cargando movimientos…</p>}
          {ledger.error && (
            <p className="error" role="alert">
              {friendlyError(ledger.error)}
            </p>
          )}
          <div className="supplier-finance-metrics">
            {[
              ['Saldo anterior', 'opening'],
              ['Compras del período', 'debit'],
              ['Pagos del período', 'credit'],
              ['Saldo al cierre', 'balance'],
            ].map(([label, field]) => (
              <article key={field}>
                <span>{label}</span>
                <strong>{money(ledger.data?.[field] ?? 0)}</strong>
              </article>
            ))}
          </div>
          <p>
            Saldo positivo: deuda por mercadería recibida. Saldo negativo: anticipo a favor. Las
            órdenes pendientes de recepción no se suman como deuda.
          </p>
          <div className="supplier-finance-table">
            <table>
              <thead>
                <tr>
                  <th>Fecha</th>
                  <th>Movimiento</th>
                  <th>Compras</th>
                  <th>Pagos</th>
                  <th>Saldo</th>
                </tr>
              </thead>
              <tbody>
                {(ledger.data?.rows ?? []).map((row) => (
                  <tr key={row.id}>
                    <td>{row.ledger_date}</td>
                    <td>{row.title}</td>
                    <td>{money(row.debit)}</td>
                    <td>{money(row.credit)}</td>
                    <td>{money(row.balance)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pager page={page} count={ledger.data?.total_count ?? 0} onChange={setPage} />
        </>
      )}
      {finance && can('finance', 'insert') && (
        <button type="button" className="button primary" onClick={() => setCreateOpen(true)}>
          Nueva orden de pago
        </button>
      )}
      {tab === 'payments' && (
        <>
          {payments.error && (
            <p className="error" role="alert">
              {friendlyError(payments.error)}
            </p>
          )}
          {(payments.data?.rows ?? []).map((row) => (
            <article className="supplier-finance-card" key={row.id}>
              <h2>
                OP {row.number} · {row.supplier?.name}
              </h2>
              <p>
                {money(row.amount)} · {row.account?.name} · {row.paid_on} ·{' '}
                {{ draft: 'Borrador', paid: 'Pagada', cancelled: 'Anulada' }[row.status]}
              </p>
              <p>
                {row.note}
                {row.reference && ` · ${row.reference}`}
              </p>
              <div className="supplier-finance-tabs">
                <button className="button outline" onClick={() => print(row)}>
                  Descargar PDF
                </button>
                {row.status === 'draft' && (
                  <>
                    {can('finance', 'insert') && (
                      <button
                        className="button primary"
                        onClick={() => setAction({ kind: 'pay', row })}
                      >
                        Registrar pago
                      </button>
                    )}
                    {can('finance', 'update') && (
                      <button
                        className="button outline"
                        onClick={() => setAction({ kind: 'cancel', row })}
                      >
                        Anular borrador
                      </button>
                    )}
                  </>
                )}
              </div>
            </article>
          ))}
          <Pager page={ordersPage} count={payments.data?.count ?? 0} onChange={setOrdersPage} />
        </>
      )}
      <ActionDialog
        open={createOpen}
        title="Nueva orden de pago"
        description={supplier?.name ?? 'Prepará un pago parcial o total.'}
        busy={busy}
        onClose={() => setCreateOpen(false)}
      >
        <div className="supplier-finance-form">
          <label>
            Buscar proveedor
            <input
              type="search"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
          </label>
          <label>
            Proveedor
            <select
              value={supplier?.id ?? ''}
              onChange={(event) => {
                setSupplier(chosen.find((entry) => entry.id === event.target.value) ?? null);
                setPicked({});
                setPayablePage(0);
              }}
            >
              <option value="">Seleccionar proveedor</option>
              {chosen.map((entry) => (
                <option key={entry.id} value={entry.id}>
                  {entry.name}
                  {!entry.active && ' (inactivo)'}
                </option>
              ))}
            </select>
          </label>
        </div>
        {!supplier ? (
          <p>Seleccioná un proveedor para ver las órdenes pendientes de pago.</p>
        ) : (
          <form className="supplier-finance-form" onSubmit={save}>
            <p>
              Asigná importes a sus órdenes de compra. Se permiten pagos parciales y anticipos hasta
              el total de cada orden.
            </p>
            <label>
              Cuenta de pago
              <select
                required
                value={form.account}
                onChange={(event) => setForm({ ...form, account: event.target.value })}
              >
                <option value="">Seleccionar cuenta</option>
                {(accounts.data ?? [])
                  .filter((entry) => entry.active)
                  .map((entry) => (
                    <option key={entry.account_id} value={entry.account_id}>
                      {entry.name}
                    </option>
                  ))}
              </select>
            </label>
            <label>
              Fecha del pago
              <input
                required
                type="date"
                max={argentinaToday()}
                value={form.date}
                onChange={(event) => setForm({ ...form, date: event.target.value })}
              />
            </label>
            {(accounts.error || pending.error) && (
              <p className="error" role="alert">
                {friendlyError(accounts.error || pending.error)}
              </p>
            )}
            {(pending.data?.rows ?? []).map((row) => (
              <label key={row.id}>
                OC {row.number} · Pendiente de pago {money(row.remaining)}
                <input
                  type="number"
                  min="0"
                  step="0.01"
                  max={row.remaining}
                  value={picked[row.id] ?? ''}
                  placeholder="Importe a pagar"
                  onChange={(event) => setPicked({ ...picked, [row.id]: event.target.value })}
                />
              </label>
            ))}
            <Pager page={payablePage} count={pending.data?.count ?? 0} onChange={setPayablePage} />
            <label>
              Referencia
              <input
                maxLength={120}
                value={form.reference}
                placeholder="Transferencia, comprobante o cheque"
                onChange={(event) => setForm({ ...form, reference: event.target.value })}
              />
            </label>
            <label>
              Detalle
              <input
                required
                minLength={3}
                maxLength={240}
                value={form.note}
                onChange={(event) => setForm({ ...form, note: event.target.value })}
              />
            </label>
            <strong>Total {money(total)}</strong>
            <button className="button primary" disabled={busy || total <= 0 || !supplier.active}>
              Guardar borrador
            </button>
          </form>
        )}
      </ActionDialog>
      <ActionDialog
        open={Boolean(action)}
        title={
          action?.kind === 'pay'
            ? '¿Registrar este pago?'
            : '¿Seguro que querés anular el borrador?'
        }
        description=""
        busy={busy}
        onClose={() => setAction(null)}
      >
        <p>
          {action?.kind === 'pay'
            ? `Se registra ${money(action?.row.amount)} en Tesorería y en la cuenta del proveedor. Esto no ejecuta una transferencia bancaria.`
            : 'El borrador se anula sin modificar Tesorería.'}
        </p>
        <div className="supplier-finance-tabs">
          <button className="button outline" disabled={busy} onClick={() => setAction(null)}>
            Volver
          </button>
          <button className="button primary" disabled={busy} onClick={apply}>
            Confirmar
          </button>
        </div>
      </ActionDialog>
    </section>
  );
}

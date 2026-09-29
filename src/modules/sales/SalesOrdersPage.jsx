import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Plus, ReceiptText, ShoppingBag, Trash2 } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import { formatQuantity } from '../inventory/stockNumber';
import { listStockLots } from '../../services/stock';
import { listProductionBalances, listProductionWarehouses } from '../../services/production';
import { listCustomers, listSaleProducts, listSales, postSale } from '../../services/sales';
import { getTreasuryBalances } from '../../services/treasury';
import SaleAdjustmentPanel from './SaleAdjustmentPanel';
import './sales.css';

const money = (value) => Number(value).toLocaleString('es-AR', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});
const methods = { cash: 'Efectivo', transfer: 'Transferencia', card: 'Tarjeta',
  check: 'Cheque', other: 'Otro' };
const newLine = () => ({ key: crypto.randomUUID(), itemId: '', warehouseId: '', lotCode: '', quantity: '1' });

function SaleLine({ line, item, warehouses, companyId, balance, onChange, onRemove, disabledRemove }) {
  const lotsQuery = useQuery({
    queryKey: ['sale-lots', companyId, line.itemId, line.warehouseId],
    queryFn: () => listStockLots(companyId, line.itemId, line.warehouseId),
    enabled: !!(companyId && item?.track_lots && line.warehouseId),
  });
  const lots = (lotsQuery.data ?? []).filter((lot) => Number(lot.available) > 0);
  const available = item?.infinite_stock ? Infinity : item?.track_lots
    ? Number(lots.find((lot) => lot.code === line.lotCode)?.available ?? 0)
    : Number(balance ?? 0);
  const required = Number(line.quantity);
  const enough = line.warehouseId && available >= required && required > 0;
  return <div className="sales-line">
    <div className="sales-line-heading"><strong>{item?.name || 'Producto por seleccionar'}</strong>
      <button type="button" className="sales-icon" disabled={disabledRemove}
        aria-label="Quitar producto" onClick={onRemove}><Trash2 size={16} /></button>
    </div>
    <div className="sales-line-fields">
      <label>Cantidad ({item?.units?.symbol ?? 'unidad'})
        <input required type="number" min="0.000001" step="0.000001"
          max="999999999999" value={line.quantity}
          onChange={(event) => onChange({ quantity: event.target.value })} />
      </label>
      <label>Depósito de salida
        <select required value={line.warehouseId}
          onChange={(event) => onChange({ warehouseId: event.target.value, lotCode: '', lotAvailable: 0 })}>
          <option value="">Seleccionar…</option>
          {warehouses.map((warehouse) => <option key={warehouse.id} value={warehouse.id}>
            {warehouse.name}
          </option>)}
        </select>
      </label>
      {item?.track_lots && <label>Lote a entregar
        <select required value={line.lotCode}
          onChange={(event) => {
            const chosen = lots.find((lot) => lot.code === event.target.value);
            onChange({ lotCode: event.target.value, lotAvailable: Number(chosen?.available ?? 0) });
          }}>
          <option value="">Seleccionar lote…</option>
          {lots.map((lot) => <option key={lot.id} value={lot.code}>
            {lot.code} · {formatQuantity(lot.available)} disponibles
          </option>)}
        </select>
      </label>}
    </div>
    <div className="sales-line-footer">
      <small className={line.warehouseId ? enough ? 'sales-ok' : 'sales-error' : 'sales-muted'}>
        {line.warehouseId ? item?.infinite_stock ? 'Stock infinito ✓' : `${formatQuantity(available.toFixed(6))} disponibles ${enough ? '✓' : '· Stock insuficiente'}` : 'Elegí un depósito'}
      </small>
      {item?.sale_unit_price != null && <strong>
        $ {money(Number(line.quantity) * Number(item.sale_unit_price))}
      </strong>}
    </div>
  </div>;
}

export default function SalesOrdersPage() {
  const { activeCompanyId, user, can } = useAuth();
  const client = useQueryClient();
  const [customerId, setCustomerId] = useState('');
  const [note, setNote] = useState('Entrega de producto terminado');
  const [lines, setLines] = useState([newLine()]);
  const [busy, setBusy] = useState(false);
  const [openSaleIds, setOpenSaleIds] = useState(() => new Set());
  const [paymentMode, setPaymentMode] = useState('pending');
  const [paymentAmount, setPaymentAmount] = useState('');
  const [paymentMethod, setPaymentMethod] = useState('cash');
  const [accountId, setAccountId] = useState('');
  const [paymentRequestId, setPaymentRequestId] = useState(() => crypto.randomUUID());
  const [requestId, setRequestId] = useState(() => crypto.randomUUID());
  const customersQuery = useQuery({
    queryKey: ['sales-customers', user?.id, activeCompanyId],
    queryFn: () => listCustomers(activeCompanyId), enabled: !!activeCompanyId,
  });
  const productsQuery = useQuery({
    queryKey: ['sales-products', user?.id, activeCompanyId],
    queryFn: () => listSaleProducts(activeCompanyId), enabled: !!activeCompanyId,
  });
  const warehousesQuery = useQuery({
    queryKey: ['sale-warehouses', user?.id, activeCompanyId],
    queryFn: () => listProductionWarehouses(activeCompanyId), enabled: !!activeCompanyId,
  });
  const salesQuery = useQuery({
    queryKey: ['sales-history', user?.id, activeCompanyId],
    queryFn: () => listSales(activeCompanyId), enabled: !!activeCompanyId,
  });
  const accountsQuery = useQuery({
    queryKey: ['treasury-balances', user?.id, activeCompanyId],
    queryFn: () => getTreasuryBalances(activeCompanyId),
    enabled: Boolean(activeCompanyId && can('finance', 'read') && can('finance', 'insert')),
  });
  const accounts = (accountsQuery.data ?? []).filter((account) => account.active);
  const paymentAccounts = accounts.filter((account) =>
    paymentMethod !== 'cash' || account.kind === 'cash');
  const itemIds = lines.map((line) => line.itemId).filter(Boolean);
  const balancesQuery = useQuery({
    queryKey: ['sale-balances', activeCompanyId, [...itemIds].sort().join(',')],
    queryFn: () => listProductionBalances(activeCompanyId, itemIds),
    enabled: !!(activeCompanyId && itemIds.length),
  });
  const balances = balancesQuery.data ?? [];
  const products = (productsQuery.data ?? []).filter((item) => item.active);
  const byId = Object.fromEntries(products.map((item) => [item.id, item]));
  const total = lines.reduce((sum, line) => {
    const price = byId[line.itemId]?.sale_unit_price;
    return sum + (price == null ? 0 : Math.round(Number(line.quantity) * Number(price) * 100) / 100);
  }, 0);
  const totalCents = Math.round(total * 100);
  const enteredCents = /^\d+(?:\.\d{1,2})?$/.test(paymentAmount)
    ? Math.round(Number(paymentAmount) * 100) : 0;
  const paymentReady = paymentMode === 'pending' || (
    can('finance', 'insert') && can('finance', 'read') && !!accountId &&
    !!paymentAccounts.find((entry) => entry.account_id === accountId) &&
    totalCents > 0 && (paymentMode === 'paid' ||
      (enteredCents > 0 && enteredCents < totalCents))
  );
  const ready = paymentReady && !!customerId && !!note.trim() && lines.length > 0 &&
    new Set(lines.map((line) => line.itemId)).size === lines.length &&
    lines.every((line) => {
      const item = byId[line.itemId];
      const available = Number(balances.find((entry) =>
        entry.item_id === line.itemId && entry.warehouse_id === line.warehouseId)?.quantity ?? 0);
      return item?.sale_unit_price != null && line.warehouseId &&
        /^\d{1,12}(\.\d{1,6})?$/.test(line.quantity) && Number(line.quantity) > 0 &&
        (item.infinite_stock || available >= Number(line.quantity)) &&
        (!item.track_lots || (!!line.lotCode && Number(line.lotAvailable) >= Number(line.quantity)));
    });

  useEffect(() => {
    setOpenSaleIds(new Set());
    setCustomerId('');
    setNote('Entrega de producto terminado');
    setLines([newLine()]);
    setRequestId(crypto.randomUUID());
    setPaymentRequestId(crypto.randomUUID());
    setPaymentMode('pending');
    setPaymentAmount('');
    setAccountId('');
  }, [activeCompanyId]);

  function changeLine(key, changes) {
    setLines((current) => current.map((line) => line.key === key ? { ...line, ...changes } : line));
    setRequestId(crypto.randomUUID());
  }

  async function submit(event) {
    event.preventDefault();
    if (!ready) {
      notifyError(new Error('Revisá cliente, precios, cantidades, depósitos y lotes.'));
      return;
    }
    if (new Set(lines.map((line) => line.itemId)).size !== lines.length) {
      notifyError(new Error('Cada producto puede figurar una sola vez por venta.'));
      return;
    }
    if (lines.some((line) => byId[line.itemId]?.sale_unit_price == null)) {
      notifyError(new Error('Todos los productos necesitan un precio de venta.'));
      return;
    }
    setBusy(true);
    try {
      await postSale(activeCompanyId, {
        customerId, note, paymentMode, paymentMethod, accountId,
        paymentAmount: paymentMode === 'paid' ? (totalCents / 100).toFixed(2) : paymentAmount,
        paymentRequestId,
        lines: lines.map((line) => ({
          ...line,
          price: byId[line.itemId].sale_unit_price,
        })),
      }, requestId);
      setRequestId(crypto.randomUUID());
      setPaymentRequestId(crypto.randomUUID());
      setPaymentMode('pending');
      setPaymentAmount('');
      setAccountId('');
      setLines([newLine()]);
      setNote('Entrega de producto terminado');
      await Promise.all([
        client.invalidateQueries({ queryKey: ['sales-history', user?.id, activeCompanyId] }),
        client.invalidateQueries({ queryKey: ['sale-balances', activeCompanyId] }),
        client.invalidateQueries({ queryKey: ['sale-lots', activeCompanyId] }),
        client.invalidateQueries({ queryKey: ['stock'] }),
        client.invalidateQueries({ queryKey: ['receivables'] }),
        client.invalidateQueries({ queryKey: ['treasury-balances'] }),
        client.invalidateQueries({ queryKey: ['treasury-entries'] }),
        client.invalidateQueries({ queryKey: ['erp-dashboard'] }),
        client.invalidateQueries({ queryKey: ['operational-alerts'] }),
        client.invalidateQueries({ queryKey: ['production-reservations'] }),
        client.invalidateQueries({ queryKey: ['planning-availability'] }),
        client.invalidateQueries({ queryKey: ['sales-profit'] }),
        client.invalidateQueries({ queryKey: ['sales-profit-detail'] }),
        client.invalidateQueries({ queryKey: ['operational-report'] }),
      ]);
      notifySuccess('Venta registrada', paymentMode === 'pending'
        ? 'El stock se descontó y la venta quedó pendiente de cobro.'
        : 'La venta, el stock y el cobro quedaron registrados juntos.');
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return <section className="sales-page">
    <div className="sales-heading"><div>
      <span className="eyebrow">VENTAS / OPERACIÓN</span><h1>Registrar venta</h1>
      <p>Vendé productos terminados y descontá su stock al confirmar.</p>
    </div><Link className="button" to="/sales/lista-precios">Consultar precios</Link></div>
    <div className="sales-grid">
      <form className="sales-card" onSubmit={submit}>
        <h2><ShoppingBag size={19} /> Nueva venta</h2>
        <label>Cliente
          <select required value={customerId} onChange={(event) => {
            setCustomerId(event.target.value);
            setRequestId(crypto.randomUUID());
          }}>
            <option value="">Seleccionar cliente…</option>
            {customersQuery.data?.filter((customer) => customer.active).map((customer) =>
              <option key={customer.id} value={customer.id}>{customer.name}
                {customer.tax_id ? ` · ${customer.tax_id}` : ''}
              </option>)}
          </select>
        </label>
        <Link className="sales-link" to="/sales/customers">Administrar clientes</Link>
        <div className="sales-divider">Productos a entregar</div>
        {lines.map((line, index) => <div key={line.key}>
          <label>Producto {index + 1}
            <select required value={line.itemId} onChange={(event) => changeLine(line.key, {
              itemId: event.target.value, warehouseId: '', lotCode: '', lotAvailable: 0,
            })}>
              <option value="">Seleccionar producto…</option>
              {products.map((item) => <option key={item.id} value={item.id}>
                {item.code} · {item.name}{item.sale_unit_price == null ? ' · Sin precio' : ` · $ ${money(item.sale_unit_price)}`}
              </option>)}
            </select>
          </label>
          {line.itemId && <SaleLine line={line} item={byId[line.itemId]}
            warehouses={warehousesQuery.data ?? []} companyId={activeCompanyId}
            balance={balances.find((balance) => balance.item_id === line.itemId &&
              balance.warehouse_id === line.warehouseId)?.quantity ?? 0}
            onChange={(changes) => changeLine(line.key, changes)}
            disabledRemove={lines.length === 1}
            onRemove={() => { setLines((current) => current.filter((entry) => entry.key !== line.key));
              setRequestId(crypto.randomUUID()); }} />}
        </div>)}
        <button type="button" className="sales-link sales-add" disabled={lines.length >= 40}
          onClick={() => { setLines((current) => [...current, newLine()]);
            setRequestId(crypto.randomUUID()); }}><Plus size={16} /> Agregar otro producto</button>
        <label>Observaciones
          <input required minLength={3} maxLength={500} value={note}
            onChange={(event) => { setNote(event.target.value); setRequestId(crypto.randomUUID()); }} />
        </label>
        <div className="sales-total"><span>Total estimado</span><strong>$ {money(total)}</strong></div>
        <div className="sales-payment-panel">
          <h3>¿Cómo se cobra esta venta?</h3>
          <label>Estado del cobro
            <select value={paymentMode} onChange={(event) => {
              setPaymentMode(event.target.value);
              setPaymentRequestId(crypto.randomUUID());
            }}>
              <option value="pending">Pendiente de cobro</option>
              {can('finance', 'insert') && can('finance', 'read') && (
                <option value="partial">Cobro parcial ahora</option>
              )}
              {can('finance', 'insert') && can('finance', 'read') && (
                <option value="paid">Pagada por completo ahora</option>
              )}
            </select>
          </label>
          {paymentMode !== 'pending' && (
            <>
              {paymentMode === 'partial' && (
                <label>Importe recibido
                  <input type="number" required min="0.01" step="0.01"
                    max={(totalCents / 100).toFixed(2)} value={paymentAmount}
                    onChange={(event) => setPaymentAmount(event.target.value)} />
                </label>
              )}
              <label>Medio de pago
                <select value={paymentMethod} onChange={(event) => {
                  setPaymentMethod(event.target.value);
                  setAccountId('');
                }}>
                  {Object.entries(methods).map(([key, label]) => (
                    <option key={key} value={key}>{label}</option>
                  ))}
                </select>
              </label>
              <label>{paymentMethod === 'cash' ? 'Caja que recibe el efectivo' : 'Cuenta que recibe el cobro'}
                <select required value={accountId}
                  onChange={(event) => setAccountId(event.target.value)}>
                  <option value="">Seleccionar cuenta…</option>
                  {paymentAccounts.map((account) => (
                    <option key={account.account_id} value={account.account_id}>
                      {account.name}
                    </option>
                  ))}
                </select>
              </label>
              {!paymentAccounts.length && <p className="sales-muted">
                Creá una {paymentMethod === 'cash' ? 'caja' : 'cuenta'} en Tesorería
                para registrar el cobro en este paso.
              </p>}
              <p className="sales-muted">El cobro quedará registrado en la cuenta seleccionada;
                no habrá que cargarlo otra vez.</p>
            </>
          )}
        </div>
        <p className="sales-muted">Los precios se verifican al confirmar. Si alguien cambia un precio mientras cargás la venta, el servidor pedirá revisar antes de registrar.</p>
        <div className="sales-actions"><span>Venta, stock y cobro inicial se registran juntos.</span>
          <button className="button primary" disabled={busy || !ready || !can('sales', 'insert') || !can('stock', 'insert')}>
            <ReceiptText size={17} /> {busy ? 'Registrando…' : 'Confirmar venta'}
          </button>
        </div>
      </form>
        <aside className="sales-card">
          <h2>Últimas ventas</h2>
          {can('finance', 'read') && <Link className="sales-link" to="/finance/receivables">
            Ver saldos y registrar cobros
          </Link>}
        {salesQuery.isError && <p className="sales-error">{friendlyError(salesQuery.error)}</p>}
        {!salesQuery.data?.length && <p className="sales-muted">Aún no hay ventas registradas.</p>}
        {salesQuery.data?.map((sale) => <div className="sales-history" key={sale.id}>
          <strong>Venta Nº {sale.number} · {sale.customer_name}</strong>
          <small>{new Date(sale.created_at).toLocaleString('es-AR')} · $ {money(sale.total)}</small>
          {(sale.sale_adjustments ?? []).some((entry) => entry.kind === 'cancel') && (
            <span className="sales-badge canceled">Anulada</span>
          )}
          {can('stock', 'insert') && can('stock', 'read') &&
            !(sale.sale_adjustments ?? []).some((entry) => entry.kind === 'cancel') && (
              <Link className="sales-link" to={`/inventory/delivery-notes?sale=${sale.id}`}>
                Emitir remito de entrega
              </Link>
            )}
          <details onToggle={(event) => {
            const isOpen = event.currentTarget.open;
            setOpenSaleIds((current) => {
              const next = new Set(current);
              if (isOpen) next.add(sale.id);
              else next.delete(sale.id);
              return next;
            });
          }}>
            <summary>Productos y gestión de devoluciones</summary>
            {sale.sale_lines.map((line) => <p key={line.line_no}>
              {line.item_name} · {formatQuantity(line.quantity)} {line.unit_symbol} · $ {money(line.line_total)}
              {line.lot_code ? ` · Lote ${line.lot_code}` : ''}
            </p>)}
            {openSaleIds.has(sale.id) && <SaleAdjustmentPanel
              sale={sale}
              accounts={accounts}
              onUpdated={() => Promise.all([
                client.invalidateQueries({ queryKey: ['sales-history', user?.id, activeCompanyId] }),
                client.invalidateQueries({ queryKey: ['receivables'] }),
                client.invalidateQueries({ queryKey: ['sale-balances'] }),
                client.invalidateQueries({ queryKey: ['sale-lots'] }),
                client.invalidateQueries({ queryKey: ['stock'] }),
                client.invalidateQueries({ queryKey: ['treasury-balances'] }),
                client.invalidateQueries({ queryKey: ['treasury-entries'] }),
                client.invalidateQueries({ queryKey: ['erp-dashboard'] }),
                client.invalidateQueries({ queryKey: ['operational-alerts'] }),
                client.invalidateQueries({ queryKey: ['production-reservations'] }),
                client.invalidateQueries({ queryKey: ['planning-availability'] }),
                client.invalidateQueries({ queryKey: ['sales-profit'] }),
        client.invalidateQueries({ queryKey: ['sales-profit-detail'] }),
        client.invalidateQueries({ queryKey: ['operational-report'] }),
              ])}
            />}
          </details>
        </div>)}
      </aside>
    </div>
  </section>;
}

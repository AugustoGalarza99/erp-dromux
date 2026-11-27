import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Plus, ReceiptText, ShoppingBag, Trash2 } from 'lucide-react';
import { useAuth } from '../../../compartido/contextos/AuthContext';
import { notifyError, notifySuccess, friendlyError } from '../../../compartido/utilidades/notifications';
import { formatQuantity } from '../../stock/compartido/stockNumber';
import { lotLabel, dateTimeEs } from '../../../compartido/utilidades/display';
import { listStockLots } from '../../stock/compartido/stock';
import { listProductionBalances, listProductionWarehouses } from '../../produccion/compartido/production';
import {
  getDiscountPolicy, getSalePrices, listCustomers, listSaleProducts, listSales, postSale,
} from '../compartido/sales';
import { isMissingFunction } from '../compartido/pricing';
import { getTreasuryBalances } from '../../finanzas/tesoreria/treasury';
import SaleAdjustmentPanel from './SaleAdjustmentPanel';
import SalesShell from '../compartido/SalesShell';
import { MEDIO_PAGO_ETIQUETA } from '../../../compartido/valores';
import '../compartido/sales.css';

const money = (value) => Number(value).toLocaleString('es-AR', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});
const methods = MEDIO_PAGO_ETIQUETA;
const newLine = () => ({
  key: crypto.randomUUID(), itemId: '', warehouseId: '', lotCode: '', quantity: '1',
  discount: '', discountReason: '',
});
// Aritmética en enteros (centavos y millonésimas) para coincidir exacto con el redondeo del servidor
// (round half up sobre decimales exactos). Con coma flotante, 10,05 con 50 % daría 5,02 y el servidor 5,03.
const toCents = (value) => BigInt(Math.round(Number(value) * 100));
const fromCents = (cents) => Number(cents) / 100;
const discountOf = (line) => {
  const value = Number(line.discount);
  return Number.isFinite(value) && value > 0 ? value : 0;
};
/* Precio final de una unidad: el de la lista menos el descuento, redondeado a 2 decimales (igual que el servidor). */
const finalPrice = (base, line) => {
  if (base == null) return null;
  const permille = BigInt(10000 - Math.round(discountOf(line) * 100)); // descuento con hasta 2 decimales
  return fromCents((toCents(base) * permille + 5000n) / 10000n);
};
/* Total de una línea: round(cantidad × precio unitario, 2), cantidad con hasta 6 decimales. */
const lineTotal = (quantity, unit) => {
  if (unit == null) return 0;
  const micro = BigInt(Math.round(Number(quantity) * 1e6));
  return fromCents((micro * toCents(unit) + 500000n) / 1000000n);
};

function SaleLine({ line, item, base, listName, tax, policy, warehouses, companyId, balance, onChange, onRemove, disabledRemove }) {
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
  const discount = discountOf(line);
  const overCap = discount > Number(policy.max_discount_percent ?? 0);
  const canDiscount = Number(policy.max_discount_percent ?? 0) > 0 || policy.can_exceed;
  const unit = finalPrice(base, line);
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
            {lotLabel(lot.code)} · {formatQuantity(lot.available)} disponibles
          </option>)}
        </select>
      </label>}
      {item && base != null && canDiscount && <label>Descuento (%)
        <input type="number" min="0" max="99.99" step="0.01" inputMode="decimal" value={line.discount}
          aria-label="Descuento de la línea" placeholder="0"
          onChange={(event) => onChange({ discount: event.target.value })} />
        <small className={overCap && !policy.can_exceed ? 'sales-error' : 'sales-muted'}>
          {policy.can_exceed ? `Hasta ${policy.max_discount_percent} % sin motivo` : `Máximo ${policy.max_discount_percent} %`}
        </small>
      </label>}
      {item && overCap && policy.can_exceed && <label>Motivo del descuento
        <input required minLength={3} maxLength={200} value={line.discountReason}
          onChange={(event) => onChange({ discountReason: event.target.value })} />
      </label>}
    </div>
    {item && base != null && <small className="sales-muted">
      {listName ? `Lista ${listName}` : 'Precio del producto'} · $ {money(base)} por {item.units?.symbol ?? 'unidad'}
      {discount > 0 ? ` − ${discount} % = $ ${money(unit)}` : ''}
      {tax != null ? ` · IVA ${tax} % (informativo, no se suma al total)` : ''}
    </small>}
    <div className="sales-line-footer">
      <small className={line.warehouseId ? enough ? 'sales-ok' : 'sales-error' : 'sales-muted'}>
        {line.warehouseId ? item?.infinite_stock ? 'Stock infinito ✓' : `${formatQuantity(available.toFixed(6))} disponibles ${enough ? '✓' : '· Stock insuficiente'}` : 'Elegí un depósito'}
      </small>
      {unit != null && <strong>
        $ {money(lineTotal(line.quantity, unit))}
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
  const [paymentMode, setPaymentMode] = useState('pendiente');
  const [paymentAmount, setPaymentAmount] = useState('');
  const [paymentMethod, setPaymentMethod] = useState('efectivo');
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
    enabled: Boolean(activeCompanyId && can('finanzas', 'ver') && can('finanzas', 'crear')),
  });
  const accounts = (accountsQuery.data ?? []).filter((account) => account.active);
  const paymentAccounts = accounts.filter((account) =>
    paymentMethod !== 'efectivo' || account.kind === 'caja');
  const itemIds = lines.map((line) => line.itemId).filter(Boolean);
  const balancesQuery = useQuery({
    queryKey: ['sale-balances', activeCompanyId, [...itemIds].sort().join(',')],
    queryFn: () => listProductionBalances(activeCompanyId, itemIds),
    enabled: !!(activeCompanyId && itemIds.length),
  });
  const balances = balancesQuery.data ?? [];
  const products = (productsQuery.data ?? []).filter((item) => item.active);
  const byId = Object.fromEntries(products.map((item) => [item.id, item]));
  // Precio por cliente (lista del cliente → predeterminada → precio del producto). Si la base todavía no tiene
  // las listas (migración 040), se usa el precio único del producto como antes.
  const pricesQuery = useQuery({
    queryKey: ['sale-prices', user?.id, activeCompanyId, customerId, [...itemIds].sort().join(',')],
    queryFn: () => getSalePrices(activeCompanyId, customerId, itemIds),
    enabled: !!(activeCompanyId && customerId && itemIds.length),
    retry: false,
  });
  const policyQuery = useQuery({
    queryKey: ['sale-discount-policy', user?.id, activeCompanyId],
    queryFn: () => getDiscountPolicy(activeCompanyId),
    enabled: !!activeCompanyId, retry: false, staleTime: 60_000,
  });
  const policy = policyQuery.data ?? { max_discount_percent: 0, can_exceed: false };
  const legacyPrices = isMissingFunction(pricesQuery.error);
  const pricesById = Object.fromEntries((pricesQuery.data ?? []).map((row) => [row.item_id, row]));
  const pricesReady = legacyPrices || (pricesQuery.isSuccess && !pricesQuery.isFetching);
  const baseOf = (itemId) => {
    if (legacyPrices) return byId[itemId]?.sale_unit_price ?? null;
    return pricesReady ? pricesById[itemId]?.net_price ?? null : null;
  };
  const discountOk = (line) => discountOf(line) <= Number(policy.max_discount_percent ?? 0)
    || (policy.can_exceed && line.discountReason.trim().length >= 3);
  const total = lines.reduce((sum, line) => {
    const unit = finalPrice(baseOf(line.itemId), line);
    return sum + Number(toCents(lineTotal(line.quantity, unit)));
  }, 0) / 100;
  const totalCents = Math.round(total * 100);
  const enteredCents = /^\d+(?:\.\d{1,2})?$/.test(paymentAmount)
    ? Math.round(Number(paymentAmount) * 100) : 0;
  const paymentReady = paymentMode === 'pendiente' || (
    can('finanzas', 'crear') && can('finanzas', 'ver') && !!accountId &&
    !!paymentAccounts.find((entry) => entry.account_id === accountId) &&
    totalCents > 0 && (paymentMode === 'pagado' ||
      (enteredCents > 0 && enteredCents < totalCents))
  );
  const ready = paymentReady && !!customerId && !!note.trim() && lines.length > 0 &&
    new Set(lines.map((line) => line.itemId)).size === lines.length &&
    lines.every((line) => {
      const item = byId[line.itemId];
      const available = Number(balances.find((entry) =>
        entry.item_id === line.itemId && entry.warehouse_id === line.warehouseId)?.quantity ?? 0);
      return baseOf(line.itemId) != null && discountOk(line) && line.warehouseId &&
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
    setPaymentMode('pendiente');
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
    if (lines.some((line) => baseOf(line.itemId) == null)) {
      notifyError(new Error('Todos los productos necesitan un precio de venta.'));
      return;
    }
    setBusy(true);
    try {
      await postSale(activeCompanyId, {
        customerId, note, paymentMode, paymentMethod, accountId,
        paymentAmount: paymentMode === 'pagado' ? (totalCents / 100).toFixed(2) : paymentAmount,
        paymentRequestId,
        lines: lines.map((line) => ({
          ...line,
          price: finalPrice(baseOf(line.itemId), line),
        })),
      }, requestId);
      setRequestId(crypto.randomUUID());
      setPaymentRequestId(crypto.randomUUID());
      setPaymentMode('pendiente');
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
      notifySuccess('Venta registrada', paymentMode === 'pendiente'
        ? 'El stock se descontó y la venta quedó pendiente de cobro.'
        : 'La venta, el stock y el cobro quedaron registrados juntos.');
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return <SalesShell title="Registrar venta" description="Vendé productos terminados y descontá su stock al confirmar."
    actions={<Link className="button outline" to="/sales/lista-precios">Consultar precios</Link>}>
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
                {item.code} · {item.name}
              </option>)}
            </select>
          </label>
          {line.itemId && <SaleLine line={line} item={byId[line.itemId]} policy={policy}
            base={baseOf(line.itemId)} listName={pricesById[line.itemId]?.list_name}
            tax={pricesById[line.itemId]?.tax_percent}
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
              <option value="pendiente">Pendiente de cobro</option>
              {can('finanzas', 'crear') && can('finanzas', 'ver') && (
                <option value="parcial">Cobro parcial ahora</option>
              )}
              {can('finanzas', 'crear') && can('finanzas', 'ver') && (
                <option value="pagado">Pagada por completo ahora</option>
              )}
            </select>
          </label>
          {paymentMode !== 'pendiente' && (
            <>
              {paymentMode === 'parcial' && (
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
              <label>{paymentMethod === 'efectivo' ? 'Caja que recibe el efectivo' : 'Cuenta que recibe el cobro'}
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
                Creá una {paymentMethod === 'efectivo' ? 'caja' : 'cuenta'} en Tesorería
                para registrar el cobro en este paso.
              </p>}
              <p className="sales-muted">El cobro quedará registrado en la cuenta seleccionada;
                no habrá que cargarlo otra vez.</p>
            </>
          )}
        </div>
        <p className="sales-muted">Los precios se verifican al confirmar. Si alguien cambia un precio mientras cargás la venta, el servidor pedirá revisar antes de registrar.</p>
        <div className="sales-actions"><span>Venta, stock y cobro inicial se registran juntos.</span>
          <button className="button primary" disabled={busy || !ready || !can('ventas', 'crear') || !can('stock', 'crear')}>
            <ReceiptText size={17} /> {busy ? 'Registrando…' : 'Confirmar venta'}
          </button>
        </div>
      </form>
        <aside className="sales-card">
          <h2>Últimas ventas</h2>
          {can('finanzas', 'ver') && <Link className="sales-link" to="/finance/receivables">
            Ver saldos y registrar cobros
          </Link>}
        {salesQuery.isError && <p className="sales-error">{friendlyError(salesQuery.error)}</p>}
        {!salesQuery.data?.length && <p className="sales-muted">Aún no hay ventas registradas.</p>}
        {salesQuery.data?.map((sale) => <div className="sales-history" key={sale.id}>
          <strong>Venta Nº {sale.number} · {sale.customer_name}</strong>
          <small>{dateTimeEs(sale.created_at)} · $ {money(sale.total)}</small>
          {(sale.sale_adjustments ?? []).some((entry) => entry.kind === 'anulacion') && (
            <span className="sales-badge canceled">Anulada</span>
          )}
          {can('stock', 'crear') && can('stock', 'ver') &&
            !(sale.sale_adjustments ?? []).some((entry) => entry.kind === 'anulacion') && (
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
              {line.lot_code ? ` · Lote ${lotLabel(line.lot_code)}` : ''}
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
  </SalesShell>;
}

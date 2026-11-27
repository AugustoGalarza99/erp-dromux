import { useEffect, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Plus, Trash2 } from 'lucide-react';
import { useAuth } from '../../../compartido/contextos/AuthContext';
import { notifyError, notifySuccess, friendlyError } from '../../../compartido/utilidades/notifications';
import { listStockLots } from '../compartido/stock';
import { listProductionBalances } from '../../produccion/compartido/production';
import { issueDeliveryNote, issueSaleDeliveryNote } from './deliveryNotes';
import { formatQuantity } from '../compartido/stockNumber';
import { itemTypeLabels } from '../items/itemTypes';
import { lotLabel } from '../../../compartido/utilidades/display';
import { LINE_LIMITS } from '../../../compartido/utilidades/limits';
import './deliveryNotes.css';

const newLine = (itemId = '', quantity = '', warehouseId = '', lotCode = '') => ({
  key: crypto.randomUUID(),
  itemId,
  warehouseId,
  lotCode,
  quantity,
  search: '',
});
const kindOptions = [
  { value: 'materiales', title: 'Materiales', hint: 'Materias primas, insumos o semielaborados que salen del depósito.' },
  { value: 'productos', title: 'Productos o semielaborados', hint: 'Mercadería terminada que se entrega.' },
  { value: 'produccion', title: 'Para fabricación', hint: 'Insumos para una orden activa; queda como consumo real.' },
  { value: 'venta', title: 'De una venta', hint: 'Documenta lo entregado de una venta; no vuelve a descontar stock.' },
];
const validAmount = (value) =>
  /^\d+(?:\.\d{1,6})?$/.test(String(value)) && Number(value) > 0 && Number(value) < 1000000000000;

function LineEditor({ companyId, line, index, items, warehouses, onUpdate, onRemove }) {
  const item = items.find((entry) => entry.id === line.itemId);
  const balanceQuery = useQuery({
    queryKey: ['delivery-balance', companyId, line.itemId],
    queryFn: () => listProductionBalances(companyId, [line.itemId]),
    enabled: Boolean(companyId && line.itemId),
  });
  const lotsQuery = useQuery({
    queryKey: ['delivery-lots', companyId, line.itemId, line.warehouseId],
    queryFn: () => listStockLots(companyId, line.itemId, line.warehouseId),
    enabled: Boolean(companyId && item?.track_lots && line.warehouseId),
  });
  const available = item?.infinite_stock
    ? Infinity
    : item?.track_lots
      ? Number((lotsQuery.data ?? []).find((lot) => lot.code === line.lotCode)?.available ?? 0)
      : Number(
          (balanceQuery.data ?? []).find((row) => row.warehouse_id === line.warehouseId)
            ?.quantity ?? 0,
        );
  const choices = items.filter((entry) =>
    `${entry.code} ${entry.name}`.toLowerCase().includes(line.search.toLowerCase()),
  );
  if (item && !choices.some((entry) => entry.id === item.id)) choices.unshift(item);

  return (
    <fieldset className="delivery-line" data-type={item?.item_type}>
      <legend>
        Ítem {index + 1}
        {item && <span className="item-type-tag">{itemTypeLabels[item.item_type]}</span>}
      </legend>
      <button
        className="delivery-line-remove"
        type="button"
        aria-label={`Quitar ítem ${index + 1}`}
        onClick={onRemove}
      >
        <Trash2 size={16} /> Quitar
      </button>
      <label>
        Buscar ítem
        <input
          type="search"
          value={line.search}
          placeholder="Filtrar por nombre o código"
          onChange={(event) => onUpdate({ search: event.target.value })}
        />
      </label>
      <label>
        Material o producto
        <select
          required
          value={line.itemId}
          onChange={(event) =>
            onUpdate({
              itemId: event.target.value,
              warehouseId: '',
              lotCode: '',
              quantity: '',
            })
          }
        >
          <option value="">Seleccionar…</option>
          {choices.map((entry) => (
            <option value={entry.id} key={entry.id}>
              {entry.code} · {entry.name}
            </option>
          ))}
        </select>
      </label>
      <div className="delivery-line-fields">
        <label>
          Depósito de origen
          <select
            required
            value={line.warehouseId}
            onChange={(event) => onUpdate({ warehouseId: event.target.value, lotCode: '' })}
          >
            <option value="">Seleccionar…</option>
            {warehouses.map((entry) => (
              <option key={entry.id} value={entry.id}>
                {entry.name}
              </option>
            ))}
          </select>
        </label>
        <label>
          Cantidad ({item?.units?.symbol || 'unidad'})
          <input
            required
            type="number"
            min="0.000001"
            step="0.000001"
            value={line.quantity}
            onChange={(event) => onUpdate({ quantity: event.target.value })}
          />
        </label>
      </div>
      {item?.track_lots && (
        <label>
          Lote de salida
          <select
            required
            value={line.lotCode}
            onChange={(event) => onUpdate({ lotCode: event.target.value })}
          >
            <option value="">Seleccionar lote…</option>
            {(lotsQuery.data ?? [])
              .filter((lot) => Number(lot.available) > 0)
              .map((lot) => (
                <option key={lot.id} value={lot.code}>
                  {lotLabel(lot.code)} · {formatQuantity(lot.available)} disponibles
                </option>
              ))}
          </select>
        </label>
      )}
      {line.warehouseId && item && (
        <small
          className={
            Number(line.quantity) > available ? 'delivery-insufficient' : 'delivery-available'
          }
        >
          {item.infinite_stock
            ? 'Stock infinito'
            : (balanceQuery.isPending || lotsQuery.isFetching)
              ? 'Calculando disponible…'
            : Number(line.quantity) > available
              ? `Stock insuficiente: pedís ${formatQuantity(String(line.quantity))} y hay ${formatQuantity(available.toFixed(6))} ${item.units?.symbol ?? ''}`
              : `Disponible: ${formatQuantity(available.toFixed(6))} ${item.units?.symbol ?? ''}`}
        </small>
      )}
      {(balanceQuery.error || lotsQuery.error) && (
        <p className="delivery-insufficient" role="alert">
          {friendlyError(balanceQuery.error || lotsQuery.error)}
        </p>
      )}
    </fieldset>
  );
}

export default function DeliveryNoteComposer({
  items,
  warehouses,
  jobs,
  allocations = [],
  sales = [],
  notes = [],
  initialKind = 'materiales',
  initialJobId = '',
  initialSaleId = '',
  onIssued,
  onCancel,
  onBusyChange,
}) {
  const { activeCompanyId, can } = useAuth();
  const [kind, setKind] = useState(initialKind);
  const [jobId, setJobId] = useState(initialJobId);
  const [saleId, setSaleId] = useState(initialSaleId);
  const [saleQuantities, setSaleQuantities] = useState({});
  const [recipient, setRecipient] = useState(
    initialKind === 'produccion' ? 'Sector de producción' : '',
  );
  const [note, setNote] = useState(
    initialKind === 'produccion' ? 'Entrega para fabricación' : 'Entrega de mercadería',
  );
  const [lines, setLines] = useState([newLine()]);
  const [busy, setBusy] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const [requestId, setRequestId] = useState(() => crypto.randomUUID());
  useEffect(() => {
    onBusyChange?.(busy);
  }, [busy, onBusyChange]);

  function changeKind(value) {
    setKind(value);
    setJobId('');
    setSaleId('');
    setSaleQuantities({});
    setLines([newLine()]);
    setRecipient(value === 'produccion' ? 'Sector de producción' : '');
    setNote(value === 'produccion' ? 'Entrega para fabricación' : 'Entrega de mercadería');
  }
  const initializedJob = useRef(null);
  const initializedSale = useRef(null);
  const activeJobs = jobs.filter((job) => ['pendiente', 'en_proceso'].includes(job.status));
  const selectedJob = activeJobs.find((job) => job.id === jobId);
  const selectedSale = sales.find((sale) => sale.id === saleId);
  const allowedItems = items.filter((item) =>
    kind === 'productos'
      ? ['semielaborado', 'producto_terminado'].includes(item.item_type)
      : kind === 'materiales'
        ? ['materia_prima', 'semielaborado', 'insumo'].includes(item.item_type)
        : ['materia_prima', 'semielaborado', 'insumo'].includes(item.item_type),
  );

  useEffect(() => {
    setRequestId(crypto.randomUUID());
    setLines([newLine()]);
  }, [activeCompanyId]);

  useEffect(() => {
    if (
      initialJobId &&
      initializedJob.current !== initialJobId &&
      activeJobs.some((job) => job.id === initialJobId)
    ) {
      initializedJob.current = initialJobId;
      selectJob(initialJobId);
    }
  }, [initialJobId, jobs, allocations]);

  useEffect(() => {
    if (
      initialSaleId &&
      initializedSale.current !== initialSaleId &&
      sales.some((sale) => sale.id === initialSaleId)
    ) {
      initializedSale.current = initialSaleId;
      selectSale(initialSaleId);
    }
  }, [initialSaleId, sales]);

  function saleRemaining(sale, line) {
    const returned = (sale.sale_adjustments ?? [])
      .flatMap((adjustment) => adjustment.sale_adjustment_lines ?? [])
      .filter((entry) => entry.sale_line_no === line.line_no)
      .reduce((sum, entry) => sum + Number(entry.quantity), 0);
    const delivered = notes
      .filter((entry) => entry.sale_id === sale.id && entry.status === 'emitido')
      .flatMap((entry) => entry.delivery_note_lines ?? [])
      .filter((entry) => entry.sale_line_no === line.line_no)
      .reduce((sum, entry) => sum + Number(entry.quantity), 0);
    return Math.max(0, Number(line.quantity) - returned - delivered);
  }

  function selectSale(id) {
    setSaleId(id);
    const sale = sales.find((entry) => entry.id === id);
    if (!sale) {
      setSaleQuantities({});
      return;
    }
    setRecipient(sale.customer_name);
    setSaleQuantities(
      Object.fromEntries(
        sale.sale_lines.map((line) => [
          line.line_no,
          String(Number(saleRemaining(sale, line).toFixed(6))),
        ]),
      ),
    );
  }

  function selectJob(id) {
    setJobId(id);
    const job = activeJobs.find((entry) => entry.id === id);
    if (!job) {
      setLines([newLine()]);
      return;
    }
    const consumed = new Map();
    for (const entry of job.production_job_events ?? []) {
      consumed.set(
        entry.component_id,
        (consumed.get(entry.component_id) ?? 0) +
          Number(entry.quantity) * (entry.kind === 'entrega' ? 1 : -1),
      );
    }
    const pending = (job.formula_snapshot ?? [])
      .map((entry) => ({
        itemId: entry.component_id,
        quantity: Math.max(0, Number(entry.quantity) - (consumed.get(entry.component_id) ?? 0)),
      }))
      .filter((entry) => entry.quantity > 0.000001);
    const suggestions = pending.flatMap((entry) => {
      let left = entry.quantity;
      const proposed = [];
      for (const slot of allocations.filter(
        (row) => row.job_id === id && row.component_id === entry.itemId,
      )) {
        const amount = Math.min(left, Number(slot.quantity));
        if (amount > 0.000001)
          proposed.push(
            newLine(
              entry.itemId,
              String(Number(amount.toFixed(6))),
              slot.warehouse_id,
              slot.lot_code ?? '',
            ),
          );
        left -= amount;
      }
      if (!proposed.length)
        proposed.push(newLine(entry.itemId, String(Number(entry.quantity.toFixed(6)))));
      return proposed;
    });
    setLines(suggestions.length ? suggestions : [newLine()]);
  }

  const reviewRows = reviewing
    ? kind === 'venta'
      ? (selectedSale?.sale_lines ?? [])
          .filter((line) => Number(saleQuantities[line.line_no]) > 0)
          .map((line) => ({
            key: line.line_no,
            name: line.item_name,
            warehouse: '',
            lot: line.lot_code,
            quantity: `${formatQuantity(saleQuantities[line.line_no])} ${line.unit_symbol ?? ''}`,
          }))
      : lines.map((line) => {
          const found = items.find((entry) => entry.id === line.itemId);
          return {
            key: line.key,
            name: found ? `${found.code} · ${found.name}` : 'Ítem',
            warehouse: warehouses.find((entry) => entry.id === line.warehouseId)?.name ?? '',
            lot: line.lotCode,
            quantity: `${formatQuantity(line.quantity)} ${found?.units?.symbol ?? ''}`,
          };
        })
    : [];

  async function submit(event) {
    event.preventDefault();
    const saleLines =
      selectedSale?.sale_lines
        .filter((line) => Number(saleQuantities[line.line_no]) > 0)
        .map((line) => ({
          line_no: line.line_no,
          quantity: saleQuantities[line.line_no],
        })) ?? [];
    if (
      busy ||
      (kind === 'venta' &&
        (!selectedSale ||
          !saleLines.length ||
          saleLines.some(
            (line) =>
              !validAmount(line.quantity) ||
              Number(line.quantity) >
                saleRemaining(
                  selectedSale,
                  selectedSale.sale_lines.find((entry) => entry.line_no === line.line_no),
                ),
          ))) ||
      (kind === 'produccion' && !selectedJob) ||
      (kind !== 'venta' &&
        (!lines.length ||
          lines.some(
            (line) =>
              !allowedItems.some((item) => item.id === line.itemId) ||
              !line.warehouseId ||
              !validAmount(line.quantity) ||
              (items.find((item) => item.id === line.itemId)?.track_lots && !line.lotCode),
          )))
    ) {
      notifyError(new Error('Revisá el destino, ítems, depósitos, lotes y cantidades.'));
      return;
    }
    // Primer envío: se muestra el resumen. Recién el segundo emite el remito.
    if (!reviewing) {
      setReviewing(true);
      return;
    }
    setBusy(true);
    try {
      const id =
        kind === 'venta'
          ? await issueSaleDeliveryNote(
              activeCompanyId,
              {
                saleId,
                recipient,
                note,
                lines: saleLines,
              },
              requestId,
            )
          : await issueDeliveryNote(
              activeCompanyId,
              {
                kind,
                jobId: kind === 'produccion' ? jobId : null,
                recipient,
                note,
                lines,
              },
              requestId,
            );
      setRequestId(crypto.randomUUID());
      notifySuccess(
        'Remito emitido',
        kind === 'venta'
          ? 'Se documentó la entrega; la venta ya había descontado el stock.'
          : 'Se registró la entrega y se descontó el stock una sola vez.',
      );
      await onIssued(id);
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="delivery-composer" onSubmit={submit}>
      <fieldset className="delivery-kinds" disabled={!!(initialJobId || initialSaleId) || reviewing}>
        <legend>¿Qué vas a entregar?</legend>
        <div>
          {kindOptions
            .filter((option) => option.value !== 'venta' || sales.length > 0)
            .map(({ value, title, hint }) => (
              <label key={value} className={`delivery-kind ${kind === value ? 'is-selected' : ''}`}>
                <input
                  type="radio"
                  name="delivery-kind"
                  value={value}
                  checked={kind === value}
                  onChange={() => changeKind(value)}
                />
                <strong>{title}</strong>
                <small>{hint}</small>
              </label>
            ))}
        </div>
      </fieldset>
      <div className="delivery-edit" hidden={reviewing}>
      {kind === 'produccion' && (
        <label>
          Orden de fabricación
          <select
            required
            value={jobId}
            disabled={!!initialJobId}
            onChange={(event) => selectJob(event.target.value)}
          >
            <option value="">Seleccionar orden activa…</option>
            {activeJobs.map((job) => (
              <option key={job.id} value={job.id}>
                {items.find((item) => item.id === job.product_id)?.name ?? 'Producto'}
                {' · '}
                {new Date(job.created_at).toLocaleDateString('es-AR')}
              </option>
            ))}
          </select>
        </label>
      )}
      {kind === 'venta' && (
        <label>
          Venta registrada
          <select
            required
            value={saleId}
            disabled={!!initialSaleId}
            onChange={(event) => selectSale(event.target.value)}
          >
            <option value="">Seleccionar venta…</option>
            {sales.map((sale) => (
              <option key={sale.id} value={sale.id}>
                Nº {sale.number} · {sale.customer_name}
              </option>
            ))}
          </select>
        </label>
      )}
      <div className="delivery-line-fields">
        <label>
          Destinatario / sector
          <input
            required
            minLength={3}
            maxLength={120}
            value={recipient}
            placeholder="Nombre de quien recibe o sector"
            onChange={(event) => setRecipient(event.target.value)}
          />
        </label>
        <label>
          Motivo / observaciones
          <input
            required
            minLength={3}
            maxLength={300}
            value={note}
            onChange={(event) => setNote(event.target.value)}
          />
        </label>
      </div>
      {kind === 'produccion' && selectedJob && (
        <p className="delivery-composer-tip">
          Se sugieren depósitos y lotes con stock asignado a esta orden. Podés entregar solo una
          parte, cambiar cantidades o agregar otros insumos. Si hay faltantes sin asignación, esperá
          un ingreso de stock o elegí stock libre. Cada renglón quedará registrado como consumo de
          esta orden.
        </p>
      )}
      {kind === 'productos' && (
        <p className="delivery-composer-tip">
          La entrega descuenta el stock del semielaborado o producto elegido. Sus componentes ya se
          consumieron al fabricarlo.
        </p>
      )}
      {kind === 'venta' && selectedSale && (
        <>
          <p className="delivery-composer-tip">
            La venta ya descontó el stock. Este remito documenta cuánto entregás sin registrar otra
            salida. Podés completar la venta con entregas parciales.
          </p>
          {selectedSale.sale_lines.map((line) => {
            const remaining = saleRemaining(selectedSale, line);
            if (remaining <= 0.000001) return null;
            return (
              <div className="delivery-sale-line" key={line.line_no}>
                <strong>{line.item_name}</strong>
                <small>
                  Disponible para remitir: {formatQuantity(remaining.toFixed(6))} {line.unit_symbol}
                  {line.lot_code && ` · Lote ${lotLabel(line.lot_code)}`}
                </small>
                <label>
                  Cantidad a entregar ahora
                  <input
                    type="number"
                    min="0"
                    step="0.000001"
                    max={remaining}
                    value={saleQuantities[line.line_no] ?? ''}
                    onChange={(event) =>
                      setSaleQuantities((current) => ({
                        ...current,
                        [line.line_no]: event.target.value,
                      }))
                    }
                  />
                </label>
              </div>
            );
          })}
        </>
      )}
      {kind !== 'venta' &&
        lines.map((line, index) => (
          <LineEditor
            key={line.key}
            companyId={activeCompanyId}
            line={line}
            index={index}
            items={allowedItems}
            warehouses={warehouses}
            onUpdate={(values) =>
              setLines((current) =>
                current.map((entry) => (entry.key === line.key ? { ...entry, ...values } : entry)),
              )
            }
            onRemove={() =>
              setLines((current) =>
                current.length > 1 ? current.filter((entry) => entry.key !== line.key) : current,
              )
            }
          />
        ))}
      {kind !== 'venta' && (
        <button
          type="button"
          className="button outline"
          disabled={lines.length >= LINE_LIMITS.deliveryNote}
          onClick={() => setLines((current) => [...current, newLine()])}
        >
          <Plus size={16} /> Agregar ítem
        </button>
      )}
      </div>

      {reviewing && (
        <section className="delivery-review" aria-label="Resumen de la entrega">
          <h3>Revisá antes de emitir</h3>
          <p>
            Para <strong>{recipient}</strong> · {note}
            {kind === 'produccion' && selectedJob && ' · Orden de fabricación vinculada'}
            {kind === 'venta' && selectedSale && ` · Venta Nº ${selectedSale.number}`}
          </p>
          <ul>
            {reviewRows.map((row) => (
              <li key={row.key}>
                <span>
                  <strong>{row.name}</strong>
                  <small>{[row.warehouse, row.lot && `Lote ${lotLabel(row.lot)}`].filter(Boolean).join(' · ')}</small>
                </span>
                <strong>{row.quantity}</strong>
              </li>
            ))}
          </ul>
          <p className="delivery-review-effect">
            {kind === 'venta'
              ? 'No se descuenta stock: la venta ya lo hizo. Solo queda documentada la entrega.'
              : 'Al confirmar se descuenta el stock una sola vez. Si hay un error, el remito se anula y el stock vuelve.'}
          </p>
        </section>
      )}

      <div className="erp-action-dialog-actions">
        <button
          type="button"
          className="button outline"
          disabled={busy}
          onClick={reviewing ? () => setReviewing(false) : onCancel}
        >
          {reviewing ? 'Volver a editar' : 'Cancelar'}
        </button>
        <button
          className="button primary"
          disabled={
            busy ||
            !can('stock', 'crear') ||
            (kind === 'produccion' && !can('produccion_ordenes', 'crear')) ||
            (kind === 'venta' && !can('ventas', 'ver'))
          }
        >
          {busy
            ? 'Emitiendo…'
            : !reviewing
              ? 'Revisar entrega'
              : kind === 'venta'
                ? 'Emitir remito (sin descontar de nuevo)'
                : 'Confirmar y descontar stock'}
        </button>
      </div>
    </form>
  );
}

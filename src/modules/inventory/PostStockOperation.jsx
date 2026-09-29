import { useEffect, useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { ArrowDownToLine, ArrowRightLeft, ArrowUpFromLine } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import {
  findStockItems,
  findStockWarehouses,
  listStockLots,
  postStockOperation,
} from '../../services/stock';

const kinds = [
  { value: 'receipt', label: 'Entrada', icon: ArrowDownToLine },
  { value: 'issue', label: 'Salida', icon: ArrowUpFromLine },
  { value: 'transfer', label: 'Transferencia', icon: ArrowRightLeft },
];

function newRequestId() {
  return crypto.randomUUID();
}

export default function PostStockOperation({ initialItem = null }) {
  const { activeCompanyId, user, can } = useAuth();
  const queryClient = useQueryClient();
  const requestId = useRef(newRequestId());
  const [kind, setKind] = useState('receipt');
  const [itemId, setItemId] = useState(initialItem?.item_id ?? '');
  const [selectedItem, setSelectedItem] = useState(null);
  const [itemSearch, setItemSearch] = useState('');
  const [warehouseId, setWarehouseId] = useState('');
  const [targetId, setTargetId] = useState('');
  const [selectedSource, setSelectedSource] = useState(null);
  const [selectedTarget, setSelectedTarget] = useState(null);
  const [warehouseSearch, setWarehouseSearch] = useState('');
  const itemTerm = useDebouncedValue(itemSearch);
  const warehouseTerm = useDebouncedValue(warehouseSearch);
  const [quantity, setQuantity] = useState('');
  const [note, setNote] = useState('');
  const [lotCode, setLotCode] = useState('');
  const [expiresOn, setExpiresOn] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    if (initialItem) {
      setItemId(initialItem.item_id);
      setSelectedItem(null);
      setLotCode('');
      setExpiresOn('');
    }
  }, [initialItem?.item_id]);

  useEffect(() => {
    setItemId(initialItem?.item_id ?? '');
    setSelectedItem(null);
    setWarehouseId('');
    setSelectedSource(null);
    setSelectedTarget(null);
    setTargetId('');
    setError('');
    setMessage('');
    setLotCode('');
    setExpiresOn('');
    requestId.current = newRequestId();
  }, [activeCompanyId]);

  const itemsQuery = useQuery({
    queryKey: ['stock-options', user?.id, activeCompanyId, 'items', itemTerm],
    queryFn: () => findStockItems(activeCompanyId, itemTerm),
    enabled: Boolean(activeCompanyId && can('stock', 'insert')),
    staleTime: 60_000,
  });

  const warehousesQuery = useQuery({
    queryKey: ['stock-options', user?.id, activeCompanyId, 'warehouses', warehouseTerm],
    queryFn: () => findStockWarehouses(activeCompanyId, warehouseTerm),
    enabled: Boolean(activeCompanyId && can('stock', 'insert')),
    staleTime: 60_000,
  });

  const trackedItem = selectedItem ?? itemsQuery.data?.find(
    (item) => item.id === itemId,
  ) ?? (initialItem?.item_id === itemId ? initialItem : null);
  const requiresLots = Boolean(trackedItem?.track_lots);
  const lotsQuery = useQuery({
    queryKey: ['stock-lots', user?.id, activeCompanyId, itemId,
      kind === 'receipt' ? null : warehouseId],
    queryFn: () => listStockLots(activeCompanyId, itemId,
      kind === 'receipt' ? null : warehouseId),
    enabled: Boolean(activeCompanyId && itemId && requiresLots
      && (kind === 'receipt' || warehouseId)),
    staleTime: 0,
  });

  if (!can('stock', 'insert')) return null;

  const items = itemsQuery.data ?? [];
  const warehouses = warehousesQuery.data ?? [];
  const currentItem = trackedItem ?? (initialItem?.item_id === itemId
    ? { id: initialItem.item_id, code: initialItem.item_code,
      name: initialItem.item_name, unit_symbol: initialItem.unit_symbol,
      track_lots: initialItem.track_lots }
    : null);
  const visibleItems = currentItem && !items.some((item) => item.id === currentItem.id)
    ? [currentItem, ...items] : items;
  const visibleWarehouses = [selectedSource, selectedTarget, ...warehouses]
    .filter((warehouse, index, all) => warehouse
      && all.findIndex((entry) => entry?.id === warehouse.id) === index);
  const availableLots = (lotsQuery.data ?? []).filter(
    (lot) => Number(lot.available) > 0,
  );
  const chosenLot = (lotsQuery.data ?? []).find(
    (lot) => lot.code.toLocaleLowerCase() === lotCode.trim().toLocaleLowerCase(),
  );

  const handleSubmit = async (event) => {
    event.preventDefault();
    if (requiresLots && (lotsQuery.isPending || lotsQuery.isFetching || lotsQuery.error)) {
      setError(notifyError(new Error('Esperá a que se carguen los lotes del ítem.')));
      return;
    }
    setBusy(true);
    setError('');
    setMessage('');

    try {
      const operationId = await postStockOperation(activeCompanyId, {
        kind,
        itemId,
        warehouseId,
        targetId,
        quantity,
        note,
        lotCode: requiresLots ? lotCode.trim() : '',
        expiresOn: requiresLots && kind === 'receipt'
          ? (chosenLot ? chosenLot.expires_on ?? '' : expiresOn) : '',
      }, requestId.current);

      requestId.current = newRequestId();
      setQuantity('');
      setNote('');
      if (kind === 'receipt') {
        setLotCode('');
        setExpiresOn('');
      }
      setMessage(`Operación ${operationId.slice(0, 8)} registrada correctamente.`);
      notifySuccess(
        kind === 'receipt' ? 'Entrada registrada'
          : kind === 'issue' ? 'Salida registrada' : 'Transferencia registrada',
        `Operación ${operationId.slice(0, 8)}`,
      );
      await Promise.allSettled([
        queryClient.invalidateQueries({ queryKey: ['stock-summary', user.id, activeCompanyId] }),
        queryClient.invalidateQueries({ queryKey: ['stock-balances', user.id, activeCompanyId] }),
        queryClient.invalidateQueries({ queryKey: ['stock-movements', user.id, activeCompanyId] }),
        queryClient.invalidateQueries({ queryKey: ['stock-lots', user.id, activeCompanyId] }),
        queryClient.invalidateQueries({ queryKey: ['stock-lot-breakdown', user.id, activeCompanyId] }),
        queryClient.invalidateQueries({ queryKey: ['production-reservations'] }),
        queryClient.invalidateQueries({ queryKey: ['planning-availability'] }),
        queryClient.invalidateQueries({ queryKey: ['operational-alerts'] }),
      ]);
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="stock-form-card">
      <span className="eyebrow">REGISTRAR OPERACIÓN</span>
      <h2>Mové el inventario con trazabilidad</h2>
      <p>Cada cambio de stock requiere un motivo y queda asociado a tu usuario.</p>

      <div className="stock-kind-tabs">
        {kinds.map(({ value, label, icon: Icon }) => (
          <button
            key={value}
            type="button"
            className={kind === value ? 'selected' : ''}
            onClick={() => {
              setKind(value);
              setError('');
              setMessage('');
              setLotCode('');
              setExpiresOn('');
            }}
          >
            <Icon size={16} /> {label}
          </button>
        ))}
      </div>

      <form className="stock-operation-fields" onSubmit={handleSubmit}>
        <label>
          Buscar ítem por nombre, código o código de barras
          <input
            value={itemSearch}
            onChange={(event) => setItemSearch(event.target.value)}
            placeholder="Escribí para filtrar (máximo 30 resultados)"
          />
        </label>
        <label>
          Ítem *
          <select
            required
            value={itemId}
            onChange={(event) => {
              setItemId(event.target.value);
              setSelectedItem(items.find((item) => item.id === event.target.value) ?? null);
              setLotCode('');
              setExpiresOn('');
            }}
          >
            <option value="">Seleccionar ítem</option>
            {visibleItems.map((item) => (
              <option key={item.id} value={item.id}>
                {item.code} · {item.name} ({item.unit_symbol})
              </option>
            ))}
          </select>
          {itemsQuery.error && <small className="error">{friendlyError(itemsQuery.error)}</small>}
        </label>

        <label>
          Buscar depósito
          <input
            value={warehouseSearch}
            onChange={(event) => setWarehouseSearch(event.target.value)}
            placeholder="Nombre o código del depósito"
          />
        </label>
        <div className="stock-form-pair">
          <label>
            {kind === 'transfer' ? 'Depósito origen *' : 'Depósito *'}
            <select
              required
              value={warehouseId}
              onChange={(event) => {
                setWarehouseId(event.target.value);
                setSelectedSource(warehouses.find((entry) => entry.id === event.target.value) ?? null);
                setLotCode('');
                setExpiresOn('');
              }}
            >
              <option value="">Seleccionar</option>
              {visibleWarehouses.map((warehouse) => (
                <option key={warehouse.id} value={warehouse.id}>
                  {warehouse.name} ({warehouse.code})
                </option>
              ))}
            </select>
          </label>
          {kind === 'transfer' && (
            <label>
              Depósito destino *
              <select
                required
                value={targetId}
                onChange={(event) => {
                  setTargetId(event.target.value);
                  setSelectedTarget(warehouses.find((entry) => entry.id === event.target.value) ?? null);
                }}
              >
                <option value="">Seleccionar</option>
                {visibleWarehouses.filter((warehouse) => warehouse.id !== warehouseId)
                  .map((warehouse) => (
                    <option key={warehouse.id} value={warehouse.id}>
                      {warehouse.name} ({warehouse.code})
                    </option>
                  ))}
              </select>
            </label>
          )}
        </div>
        {warehousesQuery.error && (
          <small className="error">{friendlyError(warehousesQuery.error)}</small>
        )}
        {requiresLots && (
          <div className="stock-lot-fields">
            {kind === 'receipt' ? (
              <>
                <label>
                  Código del lote *
                  <input
                    required
                    maxLength={80}
                    value={lotCode}
                    onChange={(event) => {
                      setLotCode(event.target.value);
                      setExpiresOn('');
                    }}
                    placeholder="Ej.: LOTE-2026-01"
                    list="stock-known-lots"
                  />
                  <datalist id="stock-known-lots">
                    {(lotsQuery.data ?? []).map((lot) => (
                      <option value={lot.code} key={lot.id} />
                    ))}
                  </datalist>
                </label>
                <label>
                  Vencimiento del lote (opcional)
                  <input
                    type="date"
                    value={chosenLot ? chosenLot.expires_on ?? '' : expiresOn}
                    disabled={Boolean(chosenLot)}
                    onChange={(event) => setExpiresOn(event.target.value)}
                  />
                </label>
                {chosenLot && (
                  <small>
                    Lote existente: se conservará su vencimiento
                    {chosenLot.expires_on ? ` (${chosenLot.expires_on})` : ' (sin vencimiento)'}.
                  </small>
                )}
              </>
            ) : (
              <label>
                Lote de origen *
                <select
                  required
                  value={lotCode}
                  onChange={(event) => setLotCode(event.target.value)}
                >
                  <option value="">Seleccionar lote</option>
                  {availableLots.map((lot) => (
                    <option key={lot.id} value={lot.code}>
                      {lot.code} · {lot.available} disponibles
                      {lot.expires_on ? ` · vence ${lot.expires_on}` : ''}
                    </option>
                  ))}
                </select>
              </label>
            )}
            {lotsQuery.error && <small className="error">{friendlyError(lotsQuery.error)}</small>}
            {kind !== 'receipt' && warehouseId && !lotsQuery.isPending
              && availableLots.length === 0 && (
                <small>Este depósito no tiene existencias por lote para el ítem.</small>
              )}
          </div>
        )}
        <div className="stock-form-pair">
          <label>
            Cantidad *
            <input
              type="number"
              required
              min="0.000001"
              step="0.000001"
              max="999999999999.999999"
              value={quantity}
              onChange={(event) => setQuantity(event.target.value)}
              placeholder="Ej.: 10"
            />
          </label>
        </div>
        <label>
          Motivo *
          <textarea
            required
            minLength={3}
            maxLength={500}
            rows={3}
            value={note}
            onChange={(event) => setNote(event.target.value)}
            placeholder={kind === 'receipt'
              ? 'Ej.: Stock inicial según conteo físico'
              : kind === 'issue'
                ? 'Ej.: Consumo en orden de prueba'
                : 'Ej.: Reubicación entre depósitos'}
          />
        </label>

        {error && (
          <p role="alert" className="error stock-form-feedback">
            {error}. Si hubo un corte de red, revisá el historial antes de cambiar
            los datos; reintentar tal cual usa la misma solicitud.
          </p>
        )}
        {message && <p role="status" className="success stock-form-feedback">{message}</p>}
        {error && (
          <button
            type="button"
            className="stock-reset-request"
            onClick={() => {
              requestId.current = newRequestId();
              setError('');
            }}
          >
            Ya revisé el historial: iniciar una solicitud nueva
          </button>
        )}

        <button
          className="button primary stock-submit"
          disabled={busy || (requiresLots && (lotsQuery.isPending
            || lotsQuery.isFetching || Boolean(lotsQuery.error)))}
          data-busy={busy}
        >
          {busy ? 'Registrando…' : kind === 'transfer'
            ? 'Confirmar transferencia' : 'Confirmar movimiento'}
        </button>
      </form>
    </section>
  );
}

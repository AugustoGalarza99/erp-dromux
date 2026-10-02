import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Tag } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import { searchActiveSuppliers } from '../../services/items';
import { listExchangeOverview } from '../../services/costing';
import { friendlyError } from '../../lib/notifications';
import { money } from '../purchases/supplierUi';

export const emptyPurchaseCost = {
  currency: 'ARS',
  usd: '',
  exchangeType: '',
  supplier: null,
};

export default function ItemCostFields({ form, cost, onCostChange, onPesosChange, context, unitSymbol }) {
  const { activeCompanyId, user, can } = useAuth();
  const [supplierSearch, setSupplierSearch] = useState('');
  const [exchangeSearch, setExchangeSearch] = useState('');
  const term = useDebouncedValue(supplierSearch);
  const canReadPurchases = can('purchases', 'read');
  const canAssociate = canReadPurchases && can('purchases', 'update');
  const suppliers = useQuery({
    queryKey: ['item-supplier-options', user?.id, activeCompanyId, term],
    queryFn: () => searchActiveSuppliers(activeCompanyId, term),
    enabled: Boolean(activeCompanyId && canAssociate),
  });
  const exchange = useQuery({
    queryKey: ['exchange-overview', user?.id, activeCompanyId],
    queryFn: () => listExchangeOverview(activeCompanyId),
    enabled: Boolean(activeCompanyId && canReadPurchases),
  });
  const set = (key, value) => onCostChange({ ...cost, [key]: value });
  const supplierOptions = [cost.supplier, ...(suppliers.data ?? [])]
    .filter((entry, index, all) => entry && all.findIndex((other) => other?.id === entry.id) === index);
  const types = (exchange.data ?? []).filter((entry) => entry.active
    && (entry.id === cost.exchangeType || entry.name.toLowerCase().includes(exchangeSearch.toLowerCase().trim())));
  const rate = exchange.data?.find((entry) => entry.id === cost.exchangeType)?.current_rate;
  const primary = context.data;
  const locked = Boolean(primary && !cost.supplier);
  const preview = locked ? form.reference_unit_cost
    : cost.currency === 'USD'
      ? cost.usd !== '' && rate != null ? Number(cost.usd) * Number(rate) : null
      : form.reference_unit_cost !== '' ? form.reference_unit_cost : null;

  return (
    <section className="item-supplier-section" aria-labelledby="item-cost-title">
      <div className="form-section-heading">
        <span className="item-form-icon"><Tag size={19} /></span>
        <div>
          <h2 id="item-cost-title">Costos y proveedor</h2>
          <p>Precio por {unitSymbol || 'unidad seleccionada'}. No incluye impuestos ni flete.</p>
        </div>
      </div>

      {primary && (
        <div className="item-cost-notice">
          <strong>Proveedor principal: {primary.supplier_name}</strong>
          <p>El costo actual se actualiza desde su precio en Compras.
            Si agregás otro proveedor aquí, conserva el principal actual.</p>
          <Link to="/purchases/suppliers">Ver y editar precios de proveedores</Link>
        </div>
      )}

      {canAssociate && (
        <div className="item-form-pair">
          <label>
            Buscar proveedor
            <input
              maxLength={100}
              value={supplierSearch}
              placeholder="Filtrar por nombre"
              onChange={(event) => setSupplierSearch(event.target.value)}
            />
          </label>
          <label>
            {primary ? 'Agregar otro proveedor (opcional)' : 'Proveedor (opcional)'}
            <select
              value={cost.supplier?.id ?? ''}
              onChange={(event) => set('supplier', supplierOptions.find(
                (entry) => entry.id === event.target.value,
              ) ?? null)}
            >
              <option value="">{suppliers.isFetching ? 'Buscando proveedores…' : 'Sin asociar proveedor'}</option>
              {supplierOptions.filter((entry) => entry.id !== primary?.supplier_id).map((entry) => (
                <option key={entry.id} value={entry.id}>{entry.name}</option>
              ))}
            </select>
            <small>Se muestran hasta 30 coincidencias. Usá el buscador para encontrar otro.</small>
          </label>
        </div>
      )}

      {suppliers.error && <p className="error" role="alert">{friendlyError(suppliers.error)}</p>}
      {context.error && <p className="error" role="alert">{friendlyError(context.error)}</p>}
      {!canAssociate && <p>Podés guardar el costo del ítem. Para asociar un proveedor necesitás acceso de edición a Compras.</p>}

      <div className="item-form-pair">
        <label>
          Moneda del costo
          <select
            value={cost.currency}
            disabled={locked}
            onChange={(event) => set('currency', event.target.value)}
          >
            <option value="ARS">Pesos argentinos</option>
            <option value="USD" disabled={!canReadPurchases && cost.currency !== 'USD'}>Dólares estadounidenses</option>
          </select>
        </label>
        {cost.currency === 'ARS' ? (
          <label>
            Costo por unidad en pesos {form.item_type === 'raw_material' || cost.supplier ? '*' : '(opcional)'}
            <input
              type="number"
              min="0"
              max="999999999999.99"
              step="0.01"
              required={form.item_type === 'raw_material' || Boolean(cost.supplier)}
              disabled={locked}
              value={form.reference_unit_cost}
              placeholder="Ej.: 1250.00"
              onChange={(event) => onPesosChange(event.target.value)}
            />
          </label>
        ) : (
          <label>
            Costo por unidad en dólares *
            <input
              type="number"
              min="0"
              max="999999999999.99"
              step="0.01"
              required
              disabled={locked}
              value={cost.usd}
              placeholder="Ej.: 2.50"
              onChange={(event) => set('usd', event.target.value)}
            />
          </label>
        )}
      </div>

      {cost.currency === 'USD' && !locked && (
        <div className="item-form-pair">
          <label>
            Buscar tipo de dólar
            <input value={exchangeSearch} onChange={(event) => setExchangeSearch(event.target.value)}
              placeholder="Ej.: Oficial, MEP o Blue" maxLength={100} />
          </label>
          <label>
            Tipo de dólar *
            <select required value={cost.exchangeType} onChange={(event) => set('exchangeType', event.target.value)}>
              <option value="">Seleccionar tipo de dólar</option>
              {types.map((entry) => (
                <option key={entry.id} value={entry.id}>
                  {entry.name} · {entry.current_rate == null ? 'Sin cotización' : money(entry.current_rate)}
                </option>
              ))}
            </select>
          </label>
        </div>
      )}
      {exchange.error && cost.currency === 'USD' && <p className="error" role="alert">{friendlyError(exchange.error)}</p>}
      {cost.currency === 'USD' && !locked && cost.exchangeType && rate == null && (
        <p className="error" role="alert">Cargá una cotización vigente para este tipo de dólar antes de guardar.</p>
      )}

      <div className="item-supplier-price" aria-live="polite">
        <span>{cost.supplier ? 'Costo del proveedor en pesos' : 'Costo de referencia en pesos'}</span>
        <strong>{preview == null || preview === '' ? 'Sin costo definido' : money(preview)}</strong>
        <small>
          {cost.currency === 'USD' && !locked
            ? 'Se calcula con la cotización vigente y se actualiza cuando cambia el dólar.'
            : 'Este costo se utiliza como referencia para fabricación.'}
        </small>
      </div>
      {cost.supplier && !primary && <p>Al guardar, este proveedor queda como principal y el precio aparece en su catálogo.</p>}
      {!cost.supplier && canReadPurchases && <small>Podés dejar el proveedor vacío y asociarlo más adelante en Compras.</small>}
    </section>
  );
}

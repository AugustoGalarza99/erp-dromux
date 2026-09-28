import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useLocation } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import { friendlyError, notifyError, notifySuccess } from '../../lib/notifications';
import { getSalesProfitSummary, listProductCosts } from '../../services/costing';
import { saveSalePrice } from '../../services/sales';
import SalesProfitTable from './SalesProfitTable';
import './financeExtra.css';

const ars = (value) => value == null ? 'Pendiente' : Number(value).toLocaleString('es-AR', {
  style: 'currency', currency: 'ARS',
});

function PriceEditor({ row, companyId, onSaved }) {
  const [price, setPrice] = useState(row.price == null ? '' : String(row.price));
  const [saving, setSaving] = useState(false);

  async function save(event) {
    event.preventDefault();
    const amount = Number(price);
    if (!/^\d+(?:\.\d{1,2})?$/.test(price.trim()) ||
        !Number.isFinite(amount) || amount >= 10000000000000000) {
      notifyError(new Error('Ingresá un precio válido con hasta dos decimales.'));
      return;
    }
    setSaving(true);
    try {
      await saveSalePrice(companyId, row.item_id, amount);
      await onSaved();
      notifySuccess('Precio actualizado', 'Ya aparece en la lista de ventas.');
    } catch (error) {
      notifyError(error);
    } finally {
      setSaving(false);
    }
  }

  return (
    <form className="cost-price-editor" onSubmit={save}>
      <label>
        <span className="sr-only">Precio de {row.name}</span>
        <input
          aria-label={`Precio de ${row.name} en pesos`}
          type="number"
          min="0"
          step="0.01"
          value={price}
          onChange={(event) => setPrice(event.target.value)}
        />
      </label>
      <button className="button outline" type="submit" disabled={saving}>
        {saving ? 'Guardando…' : 'Guardar'}
      </button>
    </form>
  );
}

export default function CostsPage() {
  const { activeCompanyId, user, can, role } = useAuth();
  const client = useQueryClient();
  const { hash } = useLocation();
  useEffect(() => {
    if (hash === '#ventas') {
      requestAnimationFrame(() => document.getElementById('ventas')?.scrollIntoView());
    }
  }, [hash]);
  const [search, setSearch] = useState('');
  const term = useDebouncedValue(search);
  const allowed = Boolean(activeCompanyId && role === 'admin' && can('finance', 'read'));
  const query = useQuery({
    queryKey: ['product-costs', user?.id, activeCompanyId, term],
    queryFn: () => listProductCosts(activeCompanyId, term),
    enabled: allowed && can('items', 'read'),
  });
  const profitQuery = useQuery({
    queryKey: ['sales-profit', user?.id, activeCompanyId],
    queryFn: () => getSalesProfitSummary(activeCompanyId),
    enabled: allowed && can('sales', 'read'),
  });

  async function refreshPrices() {
    await Promise.all([
      client.invalidateQueries({ queryKey: ['product-costs'] }),
      client.invalidateQueries({ queryKey: ['public-price-list'] }),
      client.invalidateQueries({ queryKey: ['sales-products'] }),
    ]);
  }

  if (!allowed) return <p role="alert">Necesitás el rol administrador para ver costos.</p>;

  return (
    <section className="finance-extra">
      <div className="page-head">
        <div>
          <span className="eyebrow">FINANZAS / RENTABILIDAD</span>
          <h1>Rentabilidad y precios</h1>
          <p>Compará precio, costo y margen de productos y ventas.</p>
        </div>
      </div>
      {profitQuery.error && <p role="alert" className="error">{friendlyError(profitQuery.error)}</p>}
      {profitQuery.data && (
        <>
          <h2 className="finance-aggregate-label">Acumulado histórico de ventas</h2>
          <div className="finance-extra-accounts">
          <article className="finance-extra-account">
            <small>VENTAS REGISTRADAS</small>
            <strong>{ars(profitQuery.data.sales_total)}</strong><span>Ingreso total</span>
          </article>
          <article className="finance-extra-account">
            <small>VENTAS CON COSTO COMPLETO</small>
            <strong>{ars(profitQuery.data.covered_revenue)}</strong>
            <span>Costo {ars(profitQuery.data.covered_cost)}</span>
          </article>
          <article className="finance-extra-account">
            <small>GANANCIA BRUTA IDENTIFICADA</small>
            <strong>{ars(profitQuery.data.estimated_profit)}</strong>
            <span>{profitQuery.data.missing_lines} productos sin costo excluidos</span>
          </article>
          </div>
        </>
      )}
      <div className="finance-extra-card">
        <div className="finance-extra-toolbar">
          <input
            aria-label="Buscar producto"
            placeholder="Buscar por nombre o código…"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
          />
          {can('production', 'read') && <Link to="/production/formulas">Ver fórmulas</Link>}
        </div>
        {query.isPending && <p>Calculando costos…</p>}
        {query.error && <p role="alert" className="error">{friendlyError(query.error)}</p>}
        {!query.isPending && !query.error && !query.data?.length && (
          <p>Aún no hay productos para esta búsqueda.</p>
        )}
        <div className="finance-extra-table-wrap">
          <table className="finance-extra-table">
            <thead>
              <tr>
                <th>Producto</th><th>Costo unitario</th><th>Precio final</th>
                <th>Margen bruto</th><th>Margen %</th><th>Estado</th>
              </tr>
            </thead>
            <tbody>
              {(query.data ?? []).map((row) => (
                <tr key={row.item_id}>
                  <td><strong>{row.name}</strong><small>{row.code} · {row.unit_symbol}</small></td>
                  <td>{ars(row.cost)}</td>
                  <td>{row.item_type === 'finished_product' && can('sales', 'update') ? (
                    <PriceEditor
                      key={`${row.item_id}:${row.price}`}
                      row={row}
                      companyId={activeCompanyId}
                      onSaved={refreshPrices}
                    />
                  ) : ars(row.price)}</td>
                  <td className={Number(row.margin) < 0 ? 'finance-negative' : ''}>
                    {ars(row.margin)}
                  </td>
                  <td>{row.margin_percent == null ? '—' : `${row.margin_percent} %`}</td>
                  <td><span className="finance-status">{row.status}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
      {can('sales', 'read') && <SalesProfitTable />}
      <p className="finance-extra-note">
        Margen bruto = precio de venta menos costo estimado por unidad.
        No incluye impuestos, comisiones, flete ni gastos indirectos.
      </p>
    </section>
  );
}

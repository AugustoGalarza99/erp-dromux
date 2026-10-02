import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Plus } from 'lucide-react';
import ActionDialog from '../../components/ActionDialog';
import { useAuth } from '../../contexts/AuthContext';
import { addExchangeRate, addExchangeType, listExchangeRates } from '../../services/costing';
import { notifySuccess, notifyError, friendlyError } from '../../lib/notifications';
import { argentinaToday, money, refreshSupplierData } from './supplierUi';

export default function SupplierExchangePanel({ types }) {
  const { activeCompanyId, user, can } = useAuth();
  const client = useQueryClient();
  const [target, setTarget] = useState(null);
  const [newType, setNewType] = useState(false);
  const [name, setName] = useState('');
  const [rate, setRate] = useState('');
  const [date, setDate] = useState(argentinaToday);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const history = useQuery({
    queryKey: ['exchange-rates', user?.id, activeCompanyId],
    queryFn: () => listExchangeRates(activeCompanyId),
    enabled: Boolean(activeCompanyId),
  });
  async function save(event) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError('');
    try {
      if (newType) await addExchangeType(activeCompanyId, name);
      else await addExchangeRate(activeCompanyId, target.id, rate, date);
      notifySuccess(newType ? 'Tipo de dólar creado' : 'Cotización guardada',
        newType ? name : 'Los costos asociados se recalcularon. Las órdenes anteriores conservan sus precios.');
      await refreshSupplierData(client);
      setTarget(null);
      setNewType(false);
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="purchase-card">
      <div className="supplier-catalog-head">
        <div><h2>Cotizaciones del dólar</h2>
          <p className="purchase-muted">Cada ítem en dólares usa el tipo que le asignaste. Podés corregir el valor las veces que necesites.</p>
        </div>
        {can('purchases', 'update') && <button type="button" className="button outline" onClick={() => {
          setName(''); setError(''); setNewType(true);
        }}><Plus size={16} /> Nuevo tipo de dólar</button>}
      </div>
      {!types.length && <p className="supplier-empty">Creá un tipo de dólar para cotizar ítems en esa moneda.</p>}
      <div className="supplier-exchange-grid">
        {types.map((type) => <article key={type.id}>
          <span>Dólar {type.name}{!type.active ? ' · Inactivo' : ''}</span>
          <strong>{type.current_rate == null ? 'Sin cotización' : money(type.current_rate)}</strong>
          <small>{type.effective_on ? `Vigente desde ${type.effective_on.split('-').reverse().join('/')}` : 'Cargá el valor de un dólar en pesos'}</small>
          {type.active && can('purchases', 'update') && <button type="button" className="button outline" onClick={() => {
            setTarget(type); setRate(type.current_rate == null ? '' : String(type.current_rate));
            setDate(argentinaToday()); setError('');
          }}>Actualizar cotización</button>}
        </article>)}
      </div>
      <details className="supplier-advanced">
        <summary>Ver historial de cotizaciones</summary>
        {history.isPending && <p>Cargando historial…</p>}
        {history.error && <p className="error" role="alert">{friendlyError(history.error)}</p>}
        {(history.data ?? []).map((entry) => <div className="supplier-rate-history" key={entry.id}>
          <span>{types.find((type) => type.id === entry.type_id)?.name ?? 'Tipo de dólar'}</span>
          <strong>{money(entry.ars_per_usd)}</strong>
          <small>Vigencia: {entry.effective_on.split('-').reverse().join('/')} · Guardado: {new Date(entry.created_at).toLocaleString('es-AR')}</small>
        </div>)}
        <p className="purchase-muted">Se muestran los últimos 100 registros. Repetir el valor vigente no agrega otro registro; volver a un valor anterior después de cambiarlo sí queda en el historial.</p>
      </details>
      {(target || newType) && <ActionDialog open title={newType ? 'Nuevo tipo de dólar' : `Actualizar dólar ${target.name}`}
        busy={busy} onClose={() => { setTarget(null); setNewType(false); }}>
        <form className="purchase-form" onSubmit={save}>
          {newType ? <label>Nombre del tipo de dólar
            <input autoFocus required minLength={2} maxLength={60} value={name}
              placeholder="Ej.: Oficial, MEP o proveedor"
              onChange={(event) => setName(event.target.value)} />
          </label> : <>
            <label>Pesos por dólar
              <input autoFocus required type="number" min="0.000001" max="999999999999" step="0.000001"
                value={rate} onChange={(event) => setRate(event.target.value)} />
            </label>
            <label>Fecha de vigencia
              <input required type="date" max={argentinaToday()} value={date}
                onChange={(event) => setDate(event.target.value)} />
            </label>
            <p className="supplier-info">Se conserva el historial y se aplica la última cotización de la fecha más reciente. Una corrección de una fecha anterior no reemplaza las cotizaciones de fechas posteriores.</p>
          </>}
          {error && <p className="error" role="alert">{error}</p>}
          <div className="erp-action-dialog-actions">
            <button type="button" className="button outline" disabled={busy} onClick={() => { setTarget(null); setNewType(false); }}>Cancelar</button>
            <button className="button primary" disabled={busy}>{busy ? 'Guardando…' : 'Guardar'}</button>
          </div>
        </form>
      </ActionDialog>}
    </section>
  );
}

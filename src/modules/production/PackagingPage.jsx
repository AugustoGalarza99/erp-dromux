import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '../../contexts/AuthContext';
import { packagingTypes, savePackaging } from '../../services/productionDocuments';
import { searchItemOptions } from '../../services/items';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import ActionDialog from '../../components/ActionDialog';
import '../purchases/supplierAccounts.css';

const empty = { id: '', name: '', capacity: '', unit_id: '', active: true };

export default function PackagingPage() {
  const { activeCompanyId: company, user, can } = useAuth();
  const client = useQueryClient();
  const [page, setPage] = useState(0);
  const [search, setSearch] = useState('');
  const [unitSearch, setUnitSearch] = useState('');
  const [form, setForm] = useState(null);
  const [busy, setBusy] = useState(false);
  const query = useQuery({
    queryKey: ['packaging-types', user?.id, company, page, search],
    queryFn: () => packagingTypes(company, page, search),
    enabled: Boolean(company),
  });
  const units = useQuery({
    queryKey: ['item-options', user?.id, company, 'unit', unitSearch],
    queryFn: () => searchItemOptions(company, 'unit', unitSearch),
    enabled: Boolean(company && form),
  });
  const options = [form?.unit, ...(units.data ?? [])].filter(
    (entry, index, all) => entry && all.findIndex((other) => other?.id === entry.id) === index,
  );
  useEffect(() => {
    setPage(0);
    setForm(null);
  }, [company]);
  async function save(event) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    try {
      await savePackaging(company, form);
      await client.invalidateQueries({ queryKey: ['packaging-types'] });
      setForm(null);
      notifySuccess('Envasado guardado');
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="supplier-finance-page">
      <div className="page-head">
        <div>
          <span className="eyebrow">PRODUCCIÓN</span>
          <h1>Tipos de envasado</h1>
          <p>Presentaciones para distribuir el producto fabricado.</p>
        </div>
        {can('production', 'update') && (
          <button className="button primary" onClick={() => setForm(empty)}>
            Nuevo envasado
          </button>
        )}
      </div>
      <label>
        Buscar envasado
        <input
          type="search"
          value={search}
          onChange={(event) => {
            setSearch(event.target.value);
            setPage(0);
          }}
        />
      </label>
      {query.error && (
        <p className="error" role="alert">
          {friendlyError(query.error)}
        </p>
      )}
      {(query.data?.rows ?? []).map((row) => (
        <article className="supplier-finance-card" key={row.id}>
          <h2>{row.name}</h2>
          <p>
            {Number(row.capacity).toLocaleString('es-AR')} {row.unit?.symbol} por envase ·{' '}
            {row.active ? 'Activo' : 'Inactivo'}
          </p>
          {can('production', 'update') && (
            <button
              className="button outline"
              onClick={() => setForm({ ...row, capacity: String(row.capacity) })}
            >
              Editar
            </button>
          )}
        </article>
      ))}
      <div className="supplier-finance-pagination">
        <button className="button outline" disabled={!page} onClick={() => setPage(page - 1)}>
          Anterior
        </button>
        <span>Página {page + 1}</span>
        <button
          className="button outline"
          disabled={(page + 1) * 25 >= (query.data?.count ?? 0)}
          onClick={() => setPage(page + 1)}
        >
          Siguiente
        </button>
      </div>
      <ActionDialog
        open={Boolean(form)}
        title="Tipo de envasado"
        description="Capacidad por envase y unidad de medida."
        busy={busy}
        onClose={() => setForm(null)}
      >
        {form && (
          <form className="supplier-finance-form" onSubmit={save}>
            <label>
              Nombre
              <input
                required
                minLength={2}
                maxLength={100}
                value={form.name}
                onChange={(event) => setForm({ ...form, name: event.target.value })}
                placeholder="Ej.: Bidón de 20 litros"
              />
            </label>
            <label>
              Capacidad por envase
              <input
                required
                type="number"
                min="0.000001"
                step="0.000001"
                value={form.capacity}
                onChange={(event) => setForm({ ...form, capacity: event.target.value })}
              />
            </label>
            <label>
              Buscar unidad
              <input value={unitSearch} onChange={(event) => setUnitSearch(event.target.value)} />
            </label>
            <label>
              Unidad
              <select
                required
                value={form.unit_id}
                onChange={(event) => setForm({ ...form, unit_id: event.target.value })}
              >
                <option value="">Seleccionar unidad</option>
                {options.map((unit) => (
                  <option key={unit.id} value={unit.id}>
                    {unit.name} ({unit.symbol})
                  </option>
                ))}
              </select>
            </label>
            {units.error && (
              <p className="error" role="alert">
                {friendlyError(units.error)}
              </p>
            )}
            <label>
              Estado
              <select
                value={form.active ? 'true' : 'false'}
                onChange={(event) => setForm({ ...form, active: event.target.value === 'true' })}
              >
                <option value="true">Activo</option>
                <option value="false">Inactivo</option>
              </select>
            </label>
            <button className="button primary" disabled={busy}>
              Guardar envasado
            </button>
          </form>
        )}
      </ActionDialog>
    </section>
  );
}

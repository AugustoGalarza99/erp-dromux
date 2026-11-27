import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { ChevronLeft, ChevronRight, PackageOpen, Pencil, Plus, X } from 'lucide-react';
import { useAuth } from '../../../compartido/contextos/AuthContext';
import { useDebouncedValue } from '../../../compartido/hooks/useDebouncedValue';
import { packagingTypes, savePackaging } from '../compartido/productionDocuments';
import { searchItemOptions } from '../../stock/items/items';
import { notifyError, notifySuccess, friendlyError } from '../../../compartido/utilidades/notifications';
import ActionDialog from '../../../compartido/componentes/ActionDialog';
import ProductionShell from '../compartido/ProductionShell';
import './packaging.css';

const empty = { id: '', name: '', capacity: '', unit_id: '', active: true };
const PAGE_SIZE = 25;

export default function PackagingPage() {
  const { activeCompanyId: company, user, can } = useAuth();
  const client = useQueryClient();
  const [page, setPage] = useState(0);
  const [inputSearch, setInputSearch] = useState('');
  const search = useDebouncedValue(inputSearch);
  const [unitSearch, setUnitSearch] = useState('');
  const [form, setForm] = useState(null);
  const [busy, setBusy] = useState(false);
  const canEdit = can('produccion_envasado', 'editar');

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
  const rows = query.data?.rows ?? [];
  const count = query.data?.count ?? 0;
  const pages = Math.max(1, Math.ceil(count / PAGE_SIZE));
  const isNew = form && !form.id;

  useEffect(() => {
    setPage(0);
    setForm(null);
  }, [company]);
  useEffect(() => setPage(0), [search]);

  async function save(event) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    try {
      await savePackaging(company, form);
      await client.invalidateQueries({ queryKey: ['packaging-types'] });
      notifySuccess(
        isNew ? 'Presentación creada' : 'Presentación actualizada',
        `${form.name.trim()} · ${Number(form.capacity).toLocaleString('es-AR')} por envase`,
      );
      setForm(null);
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <ProductionShell
      title="Envases y presentaciones"
      description="Las formas en que entregás lo fabricado (por ejemplo: bolsa, caja, bidón, pack, rollo). Cada empresa define las suyas con su capacidad y unidad."
      actions={canEdit && (
        <button type="button" className="button primary" onClick={() => setForm(empty)}>
          <Plus size={17} aria-hidden="true" /> Nueva presentación
        </button>
      )}
    >
    <section className="packaging-page">
      <p className="packaging-hint">
        <PackageOpen size={17} aria-hidden="true" />
        La presentación describe cómo se reparte lo fabricado en las órdenes. Los envases físicos
        se descuentan como insumos de la fórmula.
      </p>

      <div className="mod-filters">
        <label className="mod-filter-grow">
          Buscar presentación
          <input
            type="search"
            value={inputSearch}
            placeholder="Nombre de la presentación"
            onChange={(event) => setInputSearch(event.target.value)}
          />
        </label>
        {inputSearch && (
          <button type="button" className="button outline" onClick={() => setInputSearch('')}>
            <X size={15} aria-hidden="true" /> Limpiar
          </button>
        )}
      </div>

      {query.error && <p className="error" role="alert">{friendlyError(query.error)}</p>}
      {query.isPending && <p className="mod-muted">Cargando presentaciones…</p>}
      {!query.isPending && !query.error && !rows.length && (
        <div className="replenishment-empty">
          <strong>{search ? 'No hay presentaciones con ese nombre.' : 'Todavía no definiste presentaciones.'}</strong>
          <p className="mod-muted">
            {search
              ? 'Probá con otra palabra o limpiá la búsqueda.'
              : 'Creá la primera para poder indicar el envasado previsto en las órdenes de fabricación.'}
          </p>
          {!search && canEdit && (
            <button type="button" className="button primary" onClick={() => setForm(empty)}>
              <Plus size={16} aria-hidden="true" /> Nueva presentación
            </button>
          )}
        </div>
      )}

      {rows.length > 0 && (
        <div className="mod-table-wrap">
          <table className="mod-table">
            <thead>
              <tr>
                <th scope="col">Presentación</th>
                <th scope="col" className="is-num">Capacidad por envase</th>
                <th scope="col">Estado</th>
                <th scope="col"><span className="sr-only">Acciones</span></th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.id} className={row.active ? '' : 'is-inactive'}>
                  <td className="is-name" data-label="Presentación"><strong>{row.name}</strong></td>
                  <td className="is-num" data-label="Capacidad">
                    {Number(row.capacity).toLocaleString('es-AR')} {row.unit?.symbol}
                  </td>
                  <td data-label="Estado">
                    <span className={`mod-chip ${row.active ? 'is-ok' : ''}`}>
                      {row.active ? 'Activa' : 'Inactiva'}
                    </span>
                  </td>
                  <td data-label="">
                    {canEdit && (
                      <button
                        type="button"
                        className="button outline"
                        aria-label={`Editar ${row.name}`}
                        onClick={() => setForm({ ...row, capacity: String(row.capacity) })}
                      >
                        <Pencil size={15} aria-hidden="true" /> Editar
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {count > PAGE_SIZE && (
        <nav className="mod-pager" aria-label="Paginación de presentaciones">
          <span className="mod-pager-count">{count} presentaciones</span>
          <div className="mod-pager-buttons">
            <button type="button" aria-label="Página anterior" disabled={!page}
              onClick={() => setPage(page - 1)}><ChevronLeft size={18} /></button>
            <span aria-live="polite">Página {page + 1} de {pages}</span>
            <button type="button" aria-label="Página siguiente" disabled={page + 1 >= pages}
              onClick={() => setPage(page + 1)}><ChevronRight size={18} /></button>
          </div>
        </nav>
      )}

      <ActionDialog
        open={Boolean(form)}
        title={isNew ? 'Nueva presentación' : 'Editar presentación'}
        description="Indicá cómo se llama, cuánto contiene cada envase y en qué unidad."
        busy={busy}
        onClose={() => setForm(null)}
      >
        {form && (
          <form className="packaging-form" onSubmit={save}>
            <label className="is-wide">
              Nombre de la presentación *
              <input
                required
                minLength={2}
                maxLength={100}
                value={form.name}
                onChange={(event) => setForm({ ...form, name: event.target.value })}
                placeholder="Ej.: Caja de 12 unidades, Bolsa de 25 kg, Rollo de 50 m"
              />
            </label>
            <label>
              Capacidad por envase *
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
              Unidad *
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
            <label className="is-wide">
              Filtrar unidades
              <input
                type="search"
                value={unitSearch}
                placeholder="Escribí para acotar la lista de unidades"
                onChange={(event) => setUnitSearch(event.target.value)}
              />
            </label>
            {units.error && (
              <p className="error is-wide" role="alert">{friendlyError(units.error)}</p>
            )}
            <label className="packaging-switch is-wide">
              <input
                type="checkbox"
                checked={form.active}
                onChange={(event) => setForm({ ...form, active: event.target.checked })}
              />
              <span>
                <strong>Disponible para nuevas órdenes</strong>
                <small>Si la desactivás deja de ofrecerse, pero las órdenes anteriores la conservan.</small>
              </span>
            </label>
            <div className="erp-action-dialog-actions is-wide">
              <button type="button" className="button outline" disabled={busy} onClick={() => setForm(null)}>
                Cancelar
              </button>
              <button className="button primary" disabled={busy}>
                {busy ? 'Guardando…' : isNew ? 'Crear presentación' : 'Guardar cambios'}
              </button>
            </div>
          </form>
        )}
      </ActionDialog>
    </section>
    </ProductionShell>
  );
}

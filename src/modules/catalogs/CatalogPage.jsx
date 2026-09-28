import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Boxes, ChevronLeft, ChevronRight, Plus, Search } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import {
  listCatalog,
  saveCatalog,
  setCatalogActive,
} from '../../services/catalogs';
import './catalogs.css';

const configurations = {
  units: {
    title: 'Unidades de medida',
    description: 'Definí cómo se mide y registra cada material o producto.',
    singular: 'unidad',
    fields: [
      { key: 'code', label: 'Código', placeholder: 'ej: kg', required: true },
      { key: 'name', label: 'Nombre', placeholder: 'ej: Kilogramo', required: true },
      { key: 'symbol', label: 'Símbolo', placeholder: 'ej: kg', required: true },
      {
        key: 'dimension', label: 'Magnitud', required: true,
        options: [
          ['count', 'Cantidad'],
          ['mass', 'Masa'],
          ['volume', 'Volumen'],
          ['length', 'Longitud'],
          ['area', 'Superficie'],
          ['time', 'Tiempo'],
        ],
      },
    ],
    detail: (item) => `${item.symbol} · ${item.dimension}`,
  },
  categories: {
    title: 'Categorías',
    description: 'Organizá tus futuros ítems por tipo o familia.',
    singular: 'categoría',
    fields: [
      { key: 'code', label: 'Código', placeholder: 'ej: materia_prima', required: true },
      { key: 'name', label: 'Nombre', placeholder: 'ej: Materias primas', required: true },
      { key: 'description', label: 'Descripción', placeholder: 'Opcional' },
    ],
    detail: (item) => item.description || item.code,
  },
  warehouses: {
    title: 'Depósitos',
    description: 'Prepará las ubicaciones que usarán tus movimientos de stock.',
    singular: 'depósito',
    fields: [
      { key: 'code', label: 'Código', placeholder: 'ej: central', required: true },
      { key: 'name', label: 'Nombre', placeholder: 'ej: Depósito central', required: true },
      { key: 'location', label: 'Ubicación', placeholder: 'Dirección o sector, opcional' },
    ],
    detail: (item) => item.location || item.code,
  },
};

function cleanForm(config) {
  return Object.fromEntries(config.fields.map((field) => [field.key, '']));
}

export default function CatalogPage({ resource }) {
  const config = configurations[resource];
  const { activeCompanyId, can, user } = useAuth();
  const queryClient = useQueryClient();
  const [page, setPage] = useState(0);
  const [search, setSearch] = useState('');
  const [inputSearch, setInputSearch] = useState('');
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(() => cleanForm(config));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');

  useEffect(() => {
    setPage(0);
    setSearch('');
    setInputSearch('');
    setEditing(null);
    setForm(cleanForm(config));
    setError('');
    setMessage('');
  }, [resource, activeCompanyId]);

  const query = useQuery({
    queryKey: ['catalog', user?.id, activeCompanyId, resource, page, search],
    queryFn: () => listCatalog(resource, activeCompanyId, page, search),
    enabled: Boolean(activeCompanyId),
  });

  const rows = query.data?.rows ?? [];
  const count = query.data?.count ?? 0;
  const totalPages = Math.max(1, Math.ceil(count / 25));
  const canEdit = can(resource, 'update');

  const refresh = () => queryClient.invalidateQueries({
    queryKey: ['catalog', user?.id, activeCompanyId, resource],
  });

  const startNew = () => {
    setEditing(null);
    setForm(cleanForm(config));
    setError('');
    setMessage('');
  };

  const startEditing = (item) => {
    setEditing(item);
    setForm(Object.fromEntries(
      config.fields.map((field) => [field.key, item[field.key] ?? '']),
    ));
    setError('');
    setMessage('');
  };

  const handleSave = async (event) => {
    event.preventDefault();
    setError('');
    setMessage('');
    setBusy(true);

    try {
      const wasEditing = Boolean(editing);
      await saveCatalog(resource, activeCompanyId, editing?.id, form);
      await refresh();
      startNew();
      setMessage('Cambios guardados correctamente.');
      notifySuccess(
        wasEditing ? 'Registro actualizado' : 'Registro creado',
        `${config.singular}: ${form.name.trim()}`,
      );
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
    }
  };

  const toggleActive = async (item) => {
    setError('');
    setMessage('');
    setBusy(true);

    try {
      await setCatalogActive(resource, activeCompanyId, item.id, !item.active);
      await refresh();
      setMessage(item.active ? 'Registro desactivado.' : 'Registro activado.');
      notifySuccess(item.active ? 'Registro desactivado' : 'Registro activado', item.name);
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="catalog-page">
      <div className="page-head">
        <div>
          <span className="eyebrow">CONFIGURACIÓN / INVENTARIO</span>
          <h1>{config.title}</h1>
          <p>{config.description}</p>
        </div>
        {can(resource, 'insert') && (
          <button className="button primary" onClick={startNew}>
            <Plus size={17} /> Nueva {config.singular}
          </button>
        )}
      </div>

      {error && <p role="alert" className="error catalog-feedback">{error}</p>}
      {message && <p role="status" className="success catalog-feedback">{message}</p>}
      {query.error && <p role="alert" className="error">{friendlyError(query.error)}</p>}

      <div className="catalog-grid">
        <section className="catalog-card catalog-list">
          <div className="catalog-toolbar">
            <div className="catalog-search">
              <Search size={17} />
              <input
                value={inputSearch}
                onChange={(event) => setInputSearch(event.target.value)}
                placeholder="Buscar por nombre"
                aria-label="Buscar por nombre"
                onKeyDown={(event) => {
                  if (event.key === 'Enter') {
                    setPage(0);
                    setSearch(inputSearch);
                  }
                }}
              />
            </div>
            <button className="button catalog-filter" onClick={() => {
              setPage(0);
              setSearch(inputSearch);
            }}>
              Buscar
            </button>
          </div>

          {query.isPending && <p className="catalog-muted">Cargando registros…</p>}
          {!query.isPending && rows.length === 0 && (
            <div className="catalog-empty">
              <Boxes size={28} />
              <h2>No hay registros</h2>
              <p>Agregá el primero para empezar a configurar el inventario.</p>
            </div>
          )}
          {rows.map((item) => (
            <div className="catalog-row" key={item.id}>
              <span className="catalog-row-icon"><Boxes size={18} /></span>
              <div className="catalog-row-copy">
                <strong>{item.name}</strong>
                <small>{item.code} · {config.detail(item)}</small>
              </div>
              <span className={`catalog-status ${item.active ? '' : 'inactive'}`}>
                {item.active ? 'Activo' : 'Inactivo'}
              </span>
              {canEdit && (
                <button className="catalog-text-button" onClick={() => startEditing(item)}>
                  Editar
                </button>
              )}
            </div>
          ))}

          <div className="catalog-pagination">
            <span>{count} registros · página {page + 1} de {totalPages}</span>
            <div>
              <button
                aria-label="Página anterior"
                disabled={page === 0}
                onClick={() => setPage((value) => value - 1)}
              >
                <ChevronLeft size={17} />
              </button>
              <button
                aria-label="Página siguiente"
                disabled={page + 1 >= totalPages}
                onClick={() => setPage((value) => value + 1)}
              >
                <ChevronRight size={17} />
              </button>
            </div>
          </div>
        </section>

        {(can(resource, 'insert') || canEdit) && (
          <section className="catalog-card catalog-editor">
            <span className="eyebrow">
              {editing ? `EDITAR ${config.singular.toUpperCase()}` : 'NUEVO REGISTRO'}
            </span>
            <h2>{editing ? editing.name : `Agregar ${config.singular}`}</h2>
            <p>Los campos con * son obligatorios.</p>
            <form onSubmit={handleSave}>
              {config.fields.map((field) => (
                <label key={field.key}>
                  {field.label}{field.required ? ' *' : ''}
                  {field.options ? (
                    <select
                      required={field.required}
                      value={form[field.key]}
                      onChange={(event) => setForm((current) => ({
                        ...current, [field.key]: event.target.value,
                      }))}
                    >
                      <option value="">Seleccionar magnitud</option>
                      {field.options.map(([value, label]) => (
                        <option value={value} key={value}>{label}</option>
                      ))}
                    </select>
                  ) : (
                    <input
                      required={field.required}
                      maxLength={field.key === 'description' ? 500
                        : field.key === 'location' ? 250
                          : field.key === 'symbol' ? 12 : 100}
                      pattern={field.key === 'code' ? '[a-z][a-z0-9_]*' : undefined}
                      value={form[field.key]}
                      onChange={(event) => setForm((current) => ({
                        ...current,
                        [field.key]: event.target.value,
                      }))}
                      placeholder={field.placeholder}
                    />
                  )}
                </label>
              ))}
              <button className="button primary" disabled={busy}>
                {busy ? 'Guardando…' : editing ? 'Guardar cambios' : 'Crear registro'}
              </button>
            </form>
            {editing && canEdit && (
              <button
                className="catalog-toggle"
                disabled={busy}
                onClick={() => toggleActive(editing)}
              >
                {editing.active ? 'Desactivar registro' : 'Volver a activar registro'}
              </button>
            )}
          </section>
        )}
      </div>
    </div>
  );
}

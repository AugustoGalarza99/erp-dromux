import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useAuth } from '../../contexts/AuthContext';
import { documentSettings, packagingTypes } from '../../services/productionDocuments';
import { friendlyError } from '../../lib/notifications';

export default function WorkOrderOptions({ value, onChange }) {
  const { activeCompanyId: company, user } = useAuth();
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(0);
  const settings = useQuery({
    queryKey: ['production-document-settings', user?.id, company],
    queryFn: () => documentSettings(company),
    enabled: Boolean(company),
  });
  const packaging = useQuery({
    queryKey: ['packaging-types', user?.id, company, page, search],
    queryFn: () => packagingTypes(company, page, search),
    enabled: Boolean(company),
  });
  return (
    <section className="production-work-options">
      <h3>Envasado previsto (opcional)</h3>
      <label>
        Buscar presentación
        <input
          value={search}
          placeholder="Ej.: Bidón"
          onChange={(event) => {
            setSearch(event.target.value);
            setPage(0);
          }}
        />
      </label>
      {(packaging.data?.rows ?? [])
        .filter((entry) => entry.active)
        .map((entry) => (
          <label key={entry.id}>
            {entry.name} · {Number(entry.capacity).toLocaleString('es-AR')} {entry.unit?.symbol} por
            envase
            <input
              type="number"
              min="0"
              max="999999999"
              step="1"
              placeholder="Cantidad de envases"
              value={value.packaging.find((row) => row.id === entry.id)?.count ?? ''}
              onChange={(event) => {
                const rows = value.packaging.filter((row) => row.id !== entry.id);
                if (Number(event.target.value) > 0)
                  rows.push({ id: entry.id, count: event.target.value });
                onChange({ ...value, packaging: rows });
              }}
            />
          </label>
        ))}
      <p>
        {value.packaging.length} presentaciones seleccionadas. El envasado describe la distribución;
        los envases físicos se consumen como insumos de la fórmula.
      </p>
      <div className="production-two-columns">
        <button
          type="button"
          className="button outline"
          disabled={!page}
          onClick={() => setPage(page - 1)}
        >
          Anterior
        </button>
        <button
          type="button"
          className="button outline"
          disabled={(page + 1) * 25 >= (packaging.data?.count ?? 0)}
          onClick={() => setPage(page + 1)}
        >
          Siguiente
        </button>
      </div>
      {(settings.error || packaging.error) && (
        <p className="error" role="alert">
          {friendlyError(settings.error || packaging.error)}
        </p>
      )}
      {(settings.data?.observation_labels ?? []).length > 0 && <h3>Controles y observaciones</h3>}
      {(settings.data?.observation_labels ?? []).map((label) => (
        <label key={label}>
          {label}
          <textarea
            maxLength={500}
            rows={2}
            value={value.observations[label] ?? ''}
            onChange={(event) =>
              onChange({
                ...value,
                observations: { ...value.observations, [label]: event.target.value },
              })
            }
          />
        </label>
      ))}
    </section>
  );
}

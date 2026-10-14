import { useState } from 'react';
import ActionDialog from '../../components/ActionDialog';
import { useAuth } from '../../contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { notifyError, notifySuccess } from '../../lib/notifications';

export default function WorkDetailsDialog({ job, onClose, onUpdated }) {
  const { activeCompanyId } = useAuth();
  const [counts, setCounts] = useState(() =>
    Object.fromEntries(
      (job.work_options?.packaging ?? []).map((entry) => [
        entry.id,
        entry.actual_count == null ? '' : String(entry.actual_count),
      ]),
    ),
  );
  const [observations, setObservations] = useState(job.work_options?.observations ?? {});
  const [busy, setBusy] = useState(false);
  async function save(event) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    try {
      const { error } = await supabase.rpc('save_production_work_details', {
        p_company: activeCompanyId,
        p_job: job.id,
        p_counts: counts,
        p_observations: observations,
        p_expected: job.details_updated_at,
      });
      if (error) throw error;
      await onUpdated();
      onClose();
      notifySuccess('Envasado y controles actualizados');
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }
  return (
    <ActionDialog
      open
      title={`Envasado y controles · OF ${job.number}`}
      description="Registrá las cantidades reales y los resultados del proceso."
      busy={busy}
      onClose={onClose}
    >
      <form className="supplier-finance-form" onSubmit={save}>
        {(job.work_options?.packaging ?? []).map((entry) => (
          <label key={entry.id}>
            {entry.name} · Previsto {entry.count}
            <input
              type="number"
              min="0"
              max="999999999"
              step="1"
              placeholder="Envases reales (opcional)"
              value={counts[entry.id]}
              onChange={(event) => setCounts({ ...counts, [entry.id]: event.target.value })}
            />
          </label>
        ))}
        {(job.document_snapshot?.labels ?? []).map((label) => (
          <label key={label}>
            {label}
            <textarea
              rows={3}
              maxLength={500}
              value={observations[label] ?? ''}
              onChange={(event) =>
                setObservations({ ...observations, [label]: event.target.value })
              }
            />
          </label>
        ))}
        <p>
          Estos datos se reflejan en el PDF. El stock y los consumos se registran con las acciones
          de fabricación, no con este formulario.
        </p>
        <button className="button primary" disabled={busy}>
          Guardar controles
        </button>
      </form>
    </ActionDialog>
  );
}

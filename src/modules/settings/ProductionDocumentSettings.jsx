import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '../../contexts/AuthContext';
import { documentSettings, saveDocumentSettings } from '../../services/productionDocuments';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import '../purchases/supplierAccounts.css';

const empty = { logo_data: '', document_code: 'OP', revision: '01', labels: '' };

async function readLogo(file) {
  if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type) || file.size > 2_000_000) {
    throw new Error('Seleccioná un logo PNG, JPG o WebP de hasta 2 MB.');
  }
  const bitmap = await createImageBitmap(file);
  const canvas = document.createElement('canvas');
  const ratio = Math.min(1, 360 / bitmap.width, 160 / bitmap.height);
  canvas.width = Math.max(1, Math.round(bitmap.width * ratio));
  canvas.height = Math.max(1, Math.round(bitmap.height * ratio));
  canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  const data = canvas.toDataURL('image/png');
  if (data.length > 120000)
    throw new Error('El logo es demasiado complejo. Usá una imagen más simple.');
  return data;
}

export default function ProductionDocumentSettings() {
  const { activeCompanyId: company, user, role } = useAuth();
  const client = useQueryClient();
  const [form, setForm] = useState(empty);
  const [busy, setBusy] = useState(false);
  const query = useQuery({
    queryKey: ['production-document-settings', user?.id, company],
    queryFn: () => documentSettings(company),
    enabled: Boolean(company),
  });
  useEffect(() => {
    setForm(
      query.data
        ? { ...query.data, labels: (query.data.observation_labels ?? []).join('\n') }
        : empty,
    );
  }, [query.data, company]);
  async function upload(event) {
    const file = event.target.files?.[0];
    if (!file) return;
    setBusy(true);
    try {
      const logo = await readLogo(file);
      setForm((current) => ({ ...current, logo_data: logo }));
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
      event.target.value = '';
    }
  }
  async function save(event) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    try {
      await saveDocumentSettings(company, form);
      await client.invalidateQueries({ queryKey: ['production-document-settings'] });
      notifySuccess('Formato de producción actualizado');
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
          <span className="eyebrow">CONFIGURACIÓN</span>
          <h1>Documentos de producción</h1>
          <p>Logo y campos de control propios de tu empresa.</p>
        </div>
      </div>
      {query.error && (
        <p className="error" role="alert">
          {friendlyError(query.error)}
        </p>
      )}
      <form className="supplier-finance-card supplier-finance-form" onSubmit={save}>
        <label>
          Logo de la empresa
          <input
            type="file"
            accept="image/png,image/jpeg,image/webp"
            disabled={busy || role !== 'admin'}
            onChange={upload}
          />
        </label>
        {form.logo_data && (
          <>
            <img
              src={form.logo_data}
              alt="Logo de la empresa"
              style={{ maxWidth: 240, maxHeight: 100, objectFit: 'contain' }}
            />
            <button
              type="button"
              className="button outline"
              disabled={busy || role !== 'admin'}
              onClick={() => setForm({ ...form, logo_data: '' })}
            >
              Quitar logo del formato
            </button>
          </>
        )}
        <div className="supplier-finance-filters">
          <label>
            Código del documento
            <input
              required
              maxLength={40}
              value={form.document_code}
              onChange={(event) => setForm({ ...form, document_code: event.target.value })}
            />
          </label>
          <label>
            Revisión
            <input
              required
              maxLength={20}
              value={form.revision}
              onChange={(event) => setForm({ ...form, revision: event.target.value })}
            />
          </label>
        </div>
        <label>
          Campos de observación y control
          <textarea
            rows={8}
            value={form.labels}
            onChange={(event) => setForm({ ...form, labels: event.target.value })}
            placeholder={
              'Un título por línea. Ejemplo:\nControl de calidad\nEquipo utilizado\nResponsable de liberación'
            }
          />
        </label>
        <p>
          Hasta 12 campos. Las órdenes nuevas conservan los títulos vigentes al crearse. El logo del
          PDF utiliza el formato actual.
        </p>
        <button className="button primary" disabled={busy || role !== 'admin'}>
          {busy ? 'Guardando…' : 'Guardar formato'}
        </button>
      </form>
    </section>
  );
}

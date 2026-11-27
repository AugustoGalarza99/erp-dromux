import { useEffect, useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { ImagePlus, Save, Trash2 } from 'lucide-react';
import { useAuth } from '../../../compartido/contextos/AuthContext';
import { documentSettings, saveDocumentSettings } from '../../produccion/compartido/productionDocuments';
import { notifyError, notifySuccess, friendlyError } from '../../../compartido/utilidades/notifications';
import '../compartido/settings.css';

const empty = { logo_data: '', document_code: 'OP', revision: '01', labels: '' };
const MAX_LABELS = 12;

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
  if (data.length > 120000) throw new Error('El logo es demasiado complejo. Usá una imagen más simple.');
  return data;
}

const labelList = (text) => text.split('\n').map((line) => line.trim()).filter(Boolean);

export default function ProductionDocumentSettings() {
  const { activeCompanyId: company, user, role } = useAuth();
  const client = useQueryClient();
  const fileRef = useRef(null);
  const [form, setForm] = useState(empty);
  const [saved, setSaved] = useState(JSON.stringify(empty));
  const [busy, setBusy] = useState(false);
  const canEdit = role === 'admin';

  const query = useQuery({
    queryKey: ['production-document-settings', user?.id, company],
    queryFn: () => documentSettings(company),
    enabled: Boolean(company),
  });
  useEffect(() => {
    const next = query.data
      ? { ...query.data, labels: (query.data.observation_labels ?? []).join('\n') }
      : empty;
    setForm(next);
    setSaved(JSON.stringify(next));
  }, [query.data, company]);

  const labels = labelList(form.labels);
  const tooMany = labels.length > MAX_LABELS;
  const dirty = JSON.stringify(form) !== saved;

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
    if (busy || tooMany) return;
    setBusy(true);
    try {
      await saveDocumentSettings(company, form);
      await client.invalidateQueries({ queryKey: ['production-document-settings'] });
      setSaved(JSON.stringify(form));
      notifySuccess('Formato de producción actualizado');
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="settings-page">
      <div className="page-head">
        <div>
          <span className="eyebrow">AJUSTES / PRODUCCIÓN</span>
          <h1>Documentos de producción</h1>
          <p>Cómo se ve la hoja de fabricación (PDF): logo, código de documento y campos de control propios de tu empresa.</p>
        </div>
      </div>
      {query.error && <p className="error" role="alert">{friendlyError(query.error)}</p>}
      {!canEdit && <p className="callout">Solo el administrador puede cambiar el formato. Acá lo ves tal como está.</p>}

      <form className="docs-layout" onSubmit={save}>
        <div className="docs-fields">
          <section className="settings-card">
            <h2 className="card-title">Logo</h2>
            <p className="muted">Aparece en el encabezado del PDF. PNG, JPG o WebP de hasta 2 MB; se ajusta solo.</p>
            <div className="logo-box">
              {form.logo_data
                ? <img src={form.logo_data} alt="Logo de la empresa" />
                : <span className="logo-empty"><ImagePlus size={26} aria-hidden="true" /> Sin logo</span>}
            </div>
            <div className="inline-actions">
              <input ref={fileRef} type="file" accept="image/png,image/jpeg,image/webp" hidden
                disabled={busy || !canEdit} onChange={upload} aria-label="Elegir archivo de logo" />
              <button type="button" className="button outline" disabled={busy || !canEdit} onClick={() => fileRef.current?.click()}>
                <ImagePlus size={16} aria-hidden="true" /> {form.logo_data ? 'Cambiar logo' : 'Elegir logo'}
              </button>
              {form.logo_data && (
                <button type="button" className="button outline" disabled={busy || !canEdit}
                  onClick={() => setForm({ ...form, logo_data: '' })}>
                  <Trash2 size={16} aria-hidden="true" /> Quitar logo
                </button>
              )}
            </div>
          </section>

          <section className="settings-card">
            <h2 className="card-title">Identificación del documento</h2>
            <div className="form-row two">
              <label>
                Código del documento
                <input required maxLength={40} disabled={!canEdit} value={form.document_code}
                  onChange={(event) => setForm({ ...form, document_code: event.target.value })} />
              </label>
              <label>
                Revisión
                <input required maxLength={20} disabled={!canEdit} value={form.revision}
                  onChange={(event) => setForm({ ...form, revision: event.target.value })} />
              </label>
            </div>
          </section>

          <section className="settings-card">
            <h2 className="card-title">Campos de observación y control</h2>
            <p className="muted">Un título por línea. Quien fabrica los completa en cada orden. Las órdenes ya creadas conservan los títulos que tenían.</p>
            <label>
              <span className="sr-only">Campos de observación</span>
              <textarea rows={7} disabled={!canEdit} value={form.labels}
                onChange={(event) => setForm({ ...form, labels: event.target.value })}
                placeholder={'Ej.:\nControl de calidad\nEquipo utilizado\nResponsable de liberación'} />
            </label>
            <p className={`counter ${tooMany ? 'is-over' : ''}`}>
              {labels.length} de {MAX_LABELS} campos{tooMany ? ' — quitá algunos para poder guardar' : ''}
            </p>
          </section>

          {canEdit && (
            <div className={`roles-savebar ${dirty ? 'is-dirty' : ''}`}>
              <span>{dirty ? 'Tenés cambios sin guardar.' : 'Sin cambios pendientes.'}</span>
              <button className="button primary" disabled={busy || !dirty || tooMany}>
                <Save size={16} aria-hidden="true" /> {busy ? 'Guardando…' : 'Guardar formato'}
              </button>
            </div>
          )}
        </div>

        <aside className="settings-card docs-preview" aria-label="Vista previa del encabezado">
          <span className="eyebrow">VISTA PREVIA</span>
          <div className="sheet">
            <div className="sheet-head">
              <div className="sheet-logo">{form.logo_data ? <img src={form.logo_data} alt="" /> : <span>Logo</span>}</div>
              <div className="sheet-title">
                <strong>Orden de fabricación</strong>
                <small>Código {form.document_code || '—'} · Rev. {form.revision || '—'}</small>
              </div>
            </div>
            <div className="sheet-lines" aria-hidden="true"><i /><i /><i /></div>
            {labels.length > 0 && (
              <ul className="sheet-fields">
                {labels.slice(0, MAX_LABELS).map((label, index) => (
                  <li key={`${label}-${index}`}><span>{label}</span><i /></li>
                ))}
              </ul>
            )}
          </div>
        </aside>
      </form>
    </div>
  );
}

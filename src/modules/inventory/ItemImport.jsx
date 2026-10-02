import { useEffect, useRef, useState } from 'react';
import { Download, FileSpreadsheet, Upload, X } from 'lucide-react';
import { useQueryClient } from '@tanstack/react-query';
import { useAuth } from '../../contexts/AuthContext';
import { friendlyError, notifyError, notifySuccess } from '../../lib/notifications';
import { supabase } from '../../lib/supabase';
import { mapWorkbookRows, normalizeRows, typeLabels, validateLocalRows } from './itemImportSchema';
import { refreshSupplierData, money } from '../purchases/supplierUi';
import './itemImport.css';

async function loadZip() {
  if (window.JSZip) return window.JSZip;
  await new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = '/vendor/jszip.min.js';
    script.onload = resolve;
    script.onerror = () => reject(new Error('No se pudo abrir el lector de Excel. Recargá la página.'));
    document.head.appendChild(script);
  });
  return window.JSZip;
}

async function readWorkbook(file) {
  if (!file.name.toLowerCase().endsWith('.xlsx') || file.size > 2_000_000) {
    throw new Error('Seleccioná un archivo .xlsx de hasta 2 MB.');
  }
  const JSZip = await loadZip();
  const zip = await JSZip.loadAsync(file);
  const xml = await zip.file('xl/worksheets/sheet1.xml')?.async('string');
  if (!xml) throw new Error('No se encontró la primera hoja del archivo Excel.');
  const parse = (value) => {
    const document = new DOMParser().parseFromString(value, 'application/xml');
    if (document.querySelector('parsererror')) throw new Error('El archivo Excel no se puede leer.');
    return document;
  };
  const sharedXml = await zip.file('xl/sharedStrings.xml')?.async('string');
  const strings = sharedXml
    ? [...parse(sharedXml).getElementsByTagNameNS('*', 'si')]
      .map((node) => [...node.getElementsByTagNameNS('*', 't')]
        .map((text) => text.textContent).join(''))
    : [];
  const document = parse(xml);
  const rows = [...document.getElementsByTagNameNS('*', 'sheetData')[0]?.getElementsByTagNameNS('*', 'row') ?? []];
  const matrix = rows.map((row) => {
    const values = {};
    for (const cell of row.getElementsByTagNameNS('*', 'c')) {
      const col = cell.getAttribute('r')?.match(/^[A-Z]+/)?.[0];
      if (!col) continue;
      const type = cell.getAttribute('t');
      const raw = cell.getElementsByTagNameNS('*', 'v')[0]?.textContent ?? '';
      values[col] = type === 's' ? strings[Number(raw)] ?? ''
        : type === 'inlineStr' ? cell.getElementsByTagNameNS('*', 'is')[0]?.textContent ?? ''
          : raw;
    }
    return { number: Number(row.getAttribute('r')), values };
  });
  return mapWorkbookRows(matrix);
}

export default function ItemImport({ onClose }) {
  const { activeCompanyId } = useAuth();
  const queryClient = useQueryClient();
  const input = useRef(null);
  const [rows, setRows] = useState([]);
  const [preview, setPreview] = useState([]);
  const [issues, setIssues] = useState([]);
  const [filename, setFilename] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const currentCompany = useRef(activeCompanyId);
  currentCompany.current = activeCompanyId;

  useEffect(() => {
    setRows([]);
    setPreview([]);
    setIssues([]);
    setError('');
    setFilename('');
  }, [activeCompanyId]);

  const pickFile = async (file) => {
    if (!file || busy) return;
    const companyId = activeCompanyId;
    setBusy(true);
    setError('');
    setIssues([]);
    setRows([]);
    setPreview([]);
    setFilename(file.name);
    try {
      const parsed = await readWorkbook(file);
      if (currentCompany.current !== companyId) return;
      if (!parsed.length || parsed.length > 200) {
        throw new Error('El archivo debe tener entre 1 y 200 filas con productos.');
      }
      const localIssues = validateLocalRows(parsed);
      setIssues(localIssues);
      setRows(parsed);
      if (!localIssues.length) {
        const { data, error: validationError } = await supabase.rpc('preview_item_import', {
          p_company: companyId,
          p_rows: normalizeRows(parsed),
        });
        if (currentCompany.current !== companyId) return;
        if (validationError) {
          const message = validationError.message?.replace(/Fila (\d+):/g, (match, number) => {
            const excelRow = parsed[Number(number) - 2]?.number;
            return excelRow ? `Fila ${excelRow}:` : match;
          });
          throw { ...validationError, message };
        }
        setPreview(data ?? []);
      }
    } catch (err) {
      if (currentCompany.current === companyId) setError(friendlyError(err));
    } finally {
      setBusy(false);
      if (input.current) input.current.value = '';
    }
  };

  const confirm = async () => {
    if (busy || !rows.length || issues.length || error) return;
    setBusy(true);
    setError('');
    try {
      const normalized = normalizeRows(rows);
      const { data, error: importError } = await supabase.rpc('import_items', {
        p_company: activeCompanyId,
        p_rows: normalized,
      });
      if (importError) throw importError;
      await refreshSupplierData(queryClient);
      notifySuccess('Importación completada', `${data} ítems creados.`);
      onClose();
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="item-import-backdrop" role="presentation" onMouseDown={(event) => {
      if (event.target === event.currentTarget && !busy) onClose();
    }}>
      <section className="item-import-modal" role="dialog" aria-modal="true" aria-labelledby="import-title">
        <div className="item-import-heading">
          <div><span className="eyebrow">INVENTARIO</span><h2 id="import-title">Importar productos</h2></div>
          <button type="button" aria-label="Cerrar" onClick={onClose} disabled={busy}><X size={19} /></button>
        </div>
        <p>Creá materias primas, semielaborados, productos terminados e insumos en un solo paso.</p>
        <div className="item-import-steps">
          <a className="button" href="/plantillas/importacion-items.xlsx" download>
            <Download size={17} /> Descargar plantilla Excel
          </a>
          <label className="button item-import-picker">
            <Upload size={17} /> {busy ? 'Procesando…' : 'Seleccionar archivo .xlsx'}
            <input ref={input} type="file" accept=".xlsx" disabled={busy}
              onChange={(event) => pickFile(event.target.files?.[0])} />
          </label>
        </div>
        <p className="item-import-tip">Reemplazá las filas de ejemplo. Usá códigos de unidad y categoría existentes. Proveedor y tipo de dólar se identifican por su nombre exacto. Las tres columnas nuevas pueden quedar vacías; un costo en dólares requiere tipo de dólar con cotización vigente. Si completás ambos costos, se usa el costo en dólares para calcular los pesos. Máximo 200 filas. La importación crea fichas; el stock inicial se carga mediante ingresos.</p>
        {error && <p role="alert" className="error">{error}</p>}
        {rows.length > 0 && <div className="item-import-preview">
          <h3><FileSpreadsheet size={17} /> {filename} · {rows.length} ítems</h3>
          {issues.length ? (
            <div role="alert" className="item-import-errors">
              <strong>Corregí {issues.length} fila(s) en Excel y volvé a seleccionar el archivo:</strong>
              <ul>{issues.slice(0, 30).map(({ number, message }) => (
                <li key={number}>Fila {number}: {message}</li>
              ))}</ul>
              {issues.length > 30 && <p>Se muestran los primeros 30 errores.</p>}
            </div>
          ) : error ? (
            <p>Corregí el problema indicado y volvé a seleccionar el archivo para validarlo.</p>
          ) : <>
            <p role="status">Validación lista. Al confirmar se crean los {rows.length} ítems y sus asociaciones juntos. Las filas con proveedor lo dejan como principal.</p>
            <div className="item-import-table">
              <table>
                <thead>
                  <tr>
                    <th>Fila</th>
                    <th>Código</th>
                    <th>Nombre</th>
                    <th>Tipo</th>
                    <th>Proveedor</th>
                    <th>Costo USD</th>
                    <th>Tipo de dólar</th>
                    <th>Costo en pesos</th>
                    <th>Stock</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.slice(0, 20).map(({ number, data }, index) => (
                    <tr key={number}>
                      <td>{number}</td>
                      <td>{data.codigo}</td>
                      <td>{data.nombre}</td>
                      <td>{typeLabels[data.tipo]}</td>
                      <td>{data.proveedor || 'Sin proveedor'}</td>
                      <td>{data.costo_usd === '' ? '—' : money(data.costo_usd, 'USD')}</td>
                      <td>{data.tipo_dolar || '—'}</td>
                      <td>{preview[index]?.cost_ars == null ? 'Sin costo' : money(preview[index].cost_ars)}</td>
                      <td>{data.stock_infinito.toUpperCase() === 'SI' ? 'Infinito' : 'Controlado'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {rows.length > 20 && <small>Mostrando las primeras 20 filas.</small>}
          </>}
        </div>}
        <div className="item-import-footer">
          <button type="button" className="button" onClick={onClose} disabled={busy}>Cancelar</button>
          <button type="button" className="button primary" onClick={confirm}
            disabled={busy || !rows.length || Boolean(issues.length) || Boolean(error) || preview.length !== rows.length}>
            {busy ? 'Importando…' : `Confirmar importación (${rows.length})`}
          </button>
        </div>
      </section>
    </div>
  );
}

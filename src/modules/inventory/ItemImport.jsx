import { useRef, useState } from 'react';
import { Download, FileSpreadsheet, Upload, X } from 'lucide-react';
import { useQueryClient } from '@tanstack/react-query';
import { useAuth } from '../../contexts/AuthContext';
import { friendlyError, notifyError, notifySuccess } from '../../lib/notifications';
import { supabase } from '../../lib/supabase';
import './itemImport.css';

const headers = [
  'codigo', 'nombre', 'tipo', 'unidad_codigo', 'categoria_codigo',
  'codigo_barras', 'descripcion', 'stock_minimo', 'seguir_lotes',
  'stock_infinito', 'costo_referencia_ars', 'precio_venta_ars', 'activo',
];
const types = ['raw_material', 'semi_finished', 'finished_product', 'consumable'];

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
  const columns = Array.from({ length: 13 }, (_, i) => String.fromCharCode(65 + i));
  if (headers.some((header, index) => String(matrix[0]?.values[columns[index]] ?? '').trim() !== header)) {
    throw new Error('Los encabezados no coinciden con la plantilla. Descargá una copia nueva.');
  }
  return matrix.slice(1).filter(({ values }) => Object.values(values).some((v) => String(v).trim()))
    .map(({ number, values }) => ({
      number,
      data: Object.fromEntries(headers.map((key, index) => [key,
        String(values[columns[index]] ?? '').trim()])),
    }));
}

function validate(rows, units, categories) {
  const codes = new Set();
  const barcodes = new Set();
  const errors = [];
  rows.forEach(({ number, data: d }) => {
    const issues = [];
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$/.test(d.codigo)) issues.push('código inválido');
    if (d.nombre.length < 2 || d.nombre.length > 160) issues.push('nombre de 2 a 160 caracteres');
    if (!types.includes(d.tipo)) issues.push('tipo inválido');
    if (!units.has(d.unidad_codigo.toLowerCase())) issues.push('unidad inexistente o inactiva');
    if (d.categoria_codigo && !categories.has(d.categoria_codigo.toLowerCase())) {
      issues.push('categoría inexistente o inactiva');
    }
    if (d.codigo_barras && (d.codigo_barras.length < 4 || d.codigo_barras.length > 80)) {
      issues.push('código de barras de 4 a 80 caracteres');
    }
    if (d.descripcion.length > 1500) issues.push('descripción demasiado larga');
    if (!/^\d+(\.\d{1,6})?$/.test(d.stock_minimo) || Number(d.stock_minimo) >= 1e12) {
      issues.push('stock mínimo inválido');
    }
    for (const field of ['costo_referencia_ars', 'precio_venta_ars']) {
      if (d[field] && (!/^\d+(\.\d{1,2})?$/.test(d[field]) || Number(d[field]) >= 1e12)) {
        issues.push(`${field}: importe inválido`);
      }
    }
    for (const field of ['seguir_lotes', 'stock_infinito', 'activo']) {
      if (!['SI', 'NO'].includes(d[field].toUpperCase())) issues.push(`${field}: usá SI o NO`);
    }
    if (d.tipo === 'raw_material' && d.costo_referencia_ars === '') {
      issues.push('falta costo de materia prima');
    }
    if (d.stock_infinito.toUpperCase() === 'SI' &&
      (d.seguir_lotes.toUpperCase() !== 'NO' || Number(d.stock_minimo) !== 0)) {
      issues.push('stock infinito requiere sin lotes y mínimo 0');
    }
    if (codes.has(d.codigo.toLowerCase())) issues.push('código repetido en el archivo');
    if (d.codigo_barras && barcodes.has(d.codigo_barras)) issues.push('código de barras repetido');
    codes.add(d.codigo.toLowerCase());
    if (d.codigo_barras) barcodes.add(d.codigo_barras);
    if (issues.length) errors.push({ number, message: issues.join(' · ') });
  });
  return errors;
}

export default function ItemImport({ onClose }) {
  const { activeCompanyId, user } = useAuth();
  const queryClient = useQueryClient();
  const input = useRef(null);
  const [rows, setRows] = useState([]);
  const [issues, setIssues] = useState([]);
  const [filename, setFilename] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const pickFile = async (file) => {
    if (!file) return;
    setBusy(true);
    setError('');
    setIssues([]);
    setRows([]);
    setFilename(file.name);
    try {
      const parsed = await readWorkbook(file);
      if (!parsed.length || parsed.length > 200) {
        throw new Error('El archivo debe tener entre 1 y 200 filas con productos.');
      }
      const [units, categories] = await Promise.all([
        supabase.from('units').select('code').eq('company_id', activeCompanyId).eq('active', true).limit(1000),
        supabase.from('item_categories').select('code').eq('company_id', activeCompanyId).eq('active', true).limit(1000),
      ]);
      if (units.error) throw units.error;
      if (categories.error) throw categories.error;
      setIssues(validate(parsed,
        new Set(units.data.map((v) => v.code.toLowerCase())),
        new Set(categories.data.map((v) => v.code.toLowerCase()))));
      setRows(parsed);
    } catch (err) {
      setError(friendlyError(err));
    } finally {
      setBusy(false);
      if (input.current) input.current.value = '';
    }
  };

  const confirm = async () => {
    setBusy(true);
    setError('');
    try {
      const normalized = rows.map(({ data }) => ({
        ...data,
        seguir_lotes: data.seguir_lotes.toUpperCase() === 'SI',
        stock_infinito: data.stock_infinito.toUpperCase() === 'SI',
        activo: data.activo.toUpperCase() === 'SI',
      }));
      const { data, error: importError } = await supabase.rpc('import_items', {
        p_company: activeCompanyId,
        p_rows: normalized,
      });
      if (importError) throw importError;
      await queryClient.invalidateQueries({ queryKey: ['items', user?.id, activeCompanyId] });
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
        <p className="item-import-tip">Reemplazá las filas de ejemplo. Usá códigos de unidad y categoría que ya existan en tu empresa. Máximo 200 filas. La importación crea fichas; el stock inicial se carga mediante ingresos.</p>
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
          ) : <>
            <p role="status">Validación lista. Al confirmar se crean los {rows.length} ítems juntos.</p>
            <div className="item-import-table"><table>
              <thead><tr><th>Fila</th><th>Código</th><th>Nombre</th><th>Tipo</th><th>Stock</th></tr></thead>
              <tbody>{rows.slice(0, 20).map(({ number, data }) => (
                <tr key={number}><td>{number}</td><td>{data.codigo}</td><td>{data.nombre}</td>
                  <td>{data.tipo}</td><td>{data.stock_infinito.toUpperCase() === 'SI' ? 'Infinito' : 'Controlado'}</td></tr>
              ))}</tbody>
            </table></div>
            {rows.length > 20 && <small>Mostrando las primeras 20 filas.</small>}
          </>}
        </div>}
        <div className="item-import-footer">
          <button type="button" className="button" onClick={onClose} disabled={busy}>Cancelar</button>
          <button type="button" className="button primary" onClick={confirm}
            disabled={busy || !rows.length || Boolean(issues.length)}>
            {busy ? 'Importando…' : `Confirmar importación (${rows.length})`}
          </button>
        </div>
      </section>
    </div>
  );
}

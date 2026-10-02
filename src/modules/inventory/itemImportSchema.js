export const baseHeaders = [
  'codigo',
  'nombre',
  'tipo',
  'unidad_codigo',
  'categoria_codigo',
  'codigo_barras',
  'descripcion',
  'stock_minimo',
  'seguir_lotes',
  'stock_infinito',
  'costo_referencia_ars',
  'precio_venta_ars',
  'activo',
];

export const optionalHeaders = ['costo_usd', 'proveedor', 'tipo_dolar'];
export const headers = [...baseHeaders, ...optionalHeaders];

export const typeLabels = {
  raw_material: 'Materia prima',
  semi_finished: 'Semielaborado',
  finished_product: 'Producto terminado',
  consumable: 'Insumo',
};

export function columnName(index) {
  let result = '';
  for (let number = index + 1; number > 0; number = Math.floor((number - 1) / 26)) {
    result = String.fromCharCode(65 + ((number - 1) % 26)) + result;
  }
  return result;
}

export function mapWorkbookRows(matrix) {
  const columns = {};
  for (const [column, value] of Object.entries(matrix[0]?.values ?? {})) {
    const header = String(value).trim();
    if (headers.includes(header)) {
      if (columns[header]) throw new Error(`La columna ${header} está repetida.`);
      columns[header] = column;
    }
  }
  if (baseHeaders.some((header) => !columns[header])) {
    throw new Error('Faltan columnas de la plantilla. Descargá una copia nueva.');
  }
  return matrix.slice(1)
    .filter(({ values }) => headers.some((header) => String(values[columns[header]] ?? '').trim()))
    .map(({ number, values }) => ({
      number,
      data: Object.fromEntries(headers.map((header) => [
        header,
        String(values[columns[header]] ?? '').trim(),
      ])),
    }));
}

export function normalizeRows(rows) {
  return rows.map(({ data }) => ({
    ...data,
    seguir_lotes: data.seguir_lotes.toUpperCase() === 'SI',
    stock_infinito: data.stock_infinito.toUpperCase() === 'SI',
    activo: data.activo.toUpperCase() === 'SI',
  }));
}

export function validateLocalRows(rows) {
  const codes = new Set();
  const barcodes = new Set();
  const errors = [];
  for (const { number, data: row } of rows) {
    const issues = [];
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$/.test(row.codigo)) issues.push('código inválido');
    if (row.nombre.length < 2 || row.nombre.length > 160) issues.push('nombre de 2 a 160 caracteres');
    if (!typeLabels[row.tipo]) issues.push('tipo inválido');
    if (!row.unidad_codigo) issues.push('falta unidad');
    if (!/^\d+(\.\d{1,6})?$/.test(row.stock_minimo) || Number(row.stock_minimo) >= 1e12) {
      issues.push('stock mínimo inválido, hasta seis decimales');
    }
    for (const field of ['costo_referencia_ars', 'precio_venta_ars', 'costo_usd']) {
      if (row[field] && (!/^\d+(\.\d{1,2})?$/.test(row[field]) || Number(row[field]) >= 1e12)) {
        issues.push(`${field}: importe inválido, hasta dos decimales`);
      }
    }
    for (const field of ['seguir_lotes', 'stock_infinito', 'activo']) {
      if (!['SI', 'NO'].includes(row[field].toUpperCase())) issues.push(`${field}: usá SI o NO`);
    }
    if (row.costo_usd !== '' && !row.tipo_dolar) issues.push('falta tipo de dólar');
    if (row.tipo_dolar && row.costo_usd === '') issues.push('tipo de dólar sin costo en dólares');
    if (row.tipo === 'raw_material' && row.costo_referencia_ars === '' && row.costo_usd === '') {
      issues.push('falta costo de materia prima');
    }
    if (row.proveedor && row.costo_referencia_ars === '' && row.costo_usd === '') {
      issues.push('el proveedor necesita un costo en pesos o dólares');
    }
    if (row.stock_infinito.toUpperCase() === 'SI'
      && (row.seguir_lotes.toUpperCase() !== 'NO' || Number(row.stock_minimo) !== 0)) {
      issues.push('stock infinito requiere sin lotes y mínimo 0');
    }
    if (codes.has(row.codigo.toLowerCase())) issues.push('código repetido en el archivo');
    if (row.codigo_barras && barcodes.has(row.codigo_barras)) issues.push('código de barras repetido');
    codes.add(row.codigo.toLowerCase());
    if (row.codigo_barras) barcodes.add(row.codigo_barras);
    if (issues.length) errors.push({ number, message: issues.join(' · ') });
  }
  return errors;
}

// Las celdas numéricas de Excel ya vienen en formato decimal estándar.
// Las celdas de texto admiten el formato argentino de miles y centavos.
export function normalizeImportNumber(value, numericCell = false) {
  const text = String(value ?? '').trim();
  if (!text) return '';
  if (numericCell) {
    if (!/^[+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$/.test(text)) {
      throw new Error('Número de Excel inválido.');
    }
    const number = Number(text);
    if (!Number.isFinite(number)) throw new Error('Número fuera de rango.');
    return number.toLocaleString('en-US', { useGrouping: false, maximumFractionDigits: 20 });
  }
  const clean = text.replace(/^(?:ARS|USD|US\$|\$)\s*/i, '').replace(/[\s\u00a0]/g, '');
  if (clean.includes(',')) {
    if (!/^[+-]?(?:\d+|\d{1,3}(?:\.\d{3})+),\d+$/.test(clean)) {
      throw new Error('Usá el formato 16.500,50 o 16500.50.');
    }
    return clean.replace(/\./g, '').replace(',', '.');
  }
  if (/^[+-]?[1-9]\d{0,2}(?:\.\d{3})+$/.test(clean)) return clean.replace(/\./g, '');
  if (!/^[+-]?\d+(?:\.\d+)?$/.test(clean)) throw new Error('Importe o cantidad inválido.');
  return clean;
}

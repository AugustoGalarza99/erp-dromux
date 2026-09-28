const uuid = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const saleNote = new RegExp(`^Venta (${uuid})$`, 'i');
const productionNote = new RegExp(`^(?:Orden producción|Fabricación orden) (${uuid})$`, 'i');

export function saleIdFromNote(note) {
  return String(note ?? '').match(saleNote)?.[1] ?? null;
}

export function readableMovementNote(note, sales = {}) {
  const text = String(note ?? '');
  const saleId = saleIdFromNote(text);
  if (saleId) {
    const sale = sales[saleId];
    return sale ? `Venta Nº ${sale.number} · ${sale.customer_name}` : 'Venta registrada';
  }
  if (productionNote.test(text)) return 'Consumo o ingreso de fabricación';
  return text;
}

export const money = (value, currency = 'ARS') => Number(value).toLocaleString('es-AR', {
  style: 'currency', currency, maximumFractionDigits: 2,
});

export const typeNames = {
  raw_material: 'Materia prima', semi_finished: 'Semielaborado',
  finished_product: 'Producto terminado', consumable: 'Insumo',
};

export const argentinaToday = () => new Intl.DateTimeFormat('sv-SE', {
  timeZone: 'America/Argentina/Buenos_Aires',
}).format(new Date());

export async function refreshSupplierData(client) {
  const prefixes = new Set([
    'purchase-suppliers', 'supplier-directory', 'supplier-catalog', 'supplier-quotes',
    'purchase-items', 'purchase-item-choices', 'purchase-providers-for-items',
    'items', 'item-detail', 'product-costs', 'production-items', 'formula-cost',
    'item-cost-context', 'item-supplier-options', 'stock-options',
    'production-formula-cost', 'production-cost', 'exchange-overview', 'exchange-rates', 'exchange-types',
    'replenishment-forecast', 'operational-alerts', 'erp-dashboard',
  ]);
  await client.invalidateQueries({ predicate: (query) => prefixes.has(query.queryKey[0]) });
}

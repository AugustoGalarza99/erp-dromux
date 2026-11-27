/*
 * Plantillas de rol: solo precargan casillas que el administrador revisa y puede cambiar.
 * Lenguaje neutro (sirve a cualquier rubro). Los recursos que no existan en el catálogo se ignoran.
 */
const all = ['read', 'insert', 'update'];

export const ROLE_TEMPLATES = [
  {
    id: 'consulta',
    label: 'Solo consulta',
    help: 'Puede ver las pantallas principales. No crea ni modifica nada ni ve costos.',
    build: (catalog) => catalog
      .filter((entry) => !entry.is_group && !entry.admin_only && entry.module !== 'sensitive')
      .map((entry) => ({ resource: entry.resource, actions: ['read'] })),
  },
  {
    id: 'operario',
    label: 'Operario de planta',
    help: 'Ve y avanza órdenes de fabricación, consulta stock y pide materiales. Sin costos.',
    build: () => [
      { resource: 'dashboard', actions: ['read'] },
      { resource: 'production_overview', actions: ['read'] },
      { resource: 'production_orders', actions: ['read', 'update'] },
      { resource: 'production_availability', actions: ['read'] },
      { resource: 'items', actions: ['read'] },
      { resource: 'stock_levels', actions: ['read'] },
      { resource: 'purchase_requests', actions: ['read', 'insert'] },
    ],
  },
  {
    id: 'compras',
    label: 'Encargado de compras',
    help: 'Gestiona pedidos internos, órdenes, proveedores y cuentas. Ve costos de materiales.',
    build: () => [
      { resource: 'dashboard', actions: ['read'] },
      { resource: 'purchases_overview', actions: ['read'] },
      { resource: 'purchase_requests', actions: ['read', 'insert', 'update', 'manage'] },
      { resource: 'purchases_orders', actions: all },
      { resource: 'purchases_suppliers', actions: all },
      { resource: 'purchases_accounts', actions: ['read'] },
      { resource: 'items', actions: ['read'] },
      { resource: 'stock_levels', actions: ['read', 'insert'] },
      { resource: 'costs_materials', actions: ['read'] },
    ],
  },
  {
    id: 'ventas',
    label: 'Vendedor',
    help: 'Presupuestos, clientes y ventas. Ve precios de lista, no costos.',
    build: () => [
      { resource: 'dashboard', actions: ['read'] },
      { resource: 'sales', actions: all },
      { resource: 'items', actions: ['read'] },
      { resource: 'stock_levels', actions: ['read'] },
    ],
  },
  {
    id: 'supervisor',
    label: 'Supervisor de producción',
    help: 'Todas las pantallas de Producción y Stock; sin costos ni compras.',
    build: (catalog) => catalog
      .filter((entry) => ['production', 'stock'].includes(entry.module) && !entry.is_group)
      .map((entry) => ({ resource: entry.resource, actions: entry.actions.filter((a) => a !== 'delete' && a !== 'manage') }))
      .concat([{ resource: 'dashboard', actions: ['read'] }]),
  },
];

/* Convierte una plantilla en la lista plana {resource, action} válida para el catálogo. */
export function applyTemplate(template, catalog) {
  const byResource = new Map(catalog.map((entry) => [entry.resource, entry]));
  return template.build(catalog).flatMap(({ resource, actions }) => {
    const entry = byResource.get(resource);
    if (!entry || entry.is_group || entry.admin_only) return [];
    return actions.filter((action) => entry.actions.includes(action)).map((action) => ({ resource, action }));
  });
}

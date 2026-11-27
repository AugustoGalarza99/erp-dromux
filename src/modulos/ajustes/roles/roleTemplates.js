/*
 * Plantillas de rol: solo precargan casillas que el administrador revisa y puede cambiar.
 * Lenguaje neutro (sirve a cualquier rubro). Los recursos que no existan en el catálogo se ignoran.
 */
const all = ['ver', 'crear', 'editar'];

export const ROLE_TEMPLATES = [
  {
    id: 'consulta',
    label: 'Solo consulta',
    help: 'Puede ver las pantallas principales. No crea ni modifica nada ni ve costos.',
    build: (catalog) => catalog
      .filter((entry) => !entry.is_group && !entry.admin_only && entry.module !== 'sensible')
      .map((entry) => ({ resource: entry.resource, actions: ['ver'] })),
  },
  {
    id: 'operario',
    label: 'Operario de planta',
    help: 'Ve y avanza órdenes de fabricación, consulta stock y pide materiales. Sin costos.',
    build: () => [
      { resource: 'inicio', actions: ['ver'] },
      { resource: 'produccion_resumen', actions: ['ver'] },
      { resource: 'produccion_ordenes', actions: ['ver', 'editar'] },
      { resource: 'produccion_disponibilidad', actions: ['ver'] },
      { resource: 'items', actions: ['ver'] },
      { resource: 'stock_saldos', actions: ['ver'] },
      { resource: 'compras_pedidos', actions: ['ver', 'crear'] },
    ],
  },
  {
    id: 'compras',
    label: 'Encargado de compras',
    help: 'Gestiona pedidos internos, órdenes, proveedores y cuentas. Ve costos de materiales.',
    build: () => [
      { resource: 'inicio', actions: ['ver'] },
      { resource: 'compras_resumen', actions: ['ver'] },
      { resource: 'compras_pedidos', actions: ['ver', 'crear', 'editar', 'gestionar'] },
      { resource: 'compras_ordenes', actions: all },
      { resource: 'compras_proveedores', actions: all },
      { resource: 'compras_cuentas', actions: ['ver'] },
      { resource: 'items', actions: ['ver'] },
      { resource: 'stock_saldos', actions: ['ver', 'crear'] },
      { resource: 'costos_materiales', actions: ['ver'] },
    ],
  },
  {
    id: 'ventas',
    label: 'Vendedor',
    help: 'Presupuestos, clientes y ventas. Ve precios de lista, no costos.',
    build: () => [
      { resource: 'inicio', actions: ['ver'] },
      { resource: 'ventas', actions: all },
      { resource: 'items', actions: ['ver'] },
      { resource: 'stock_saldos', actions: ['ver'] },
    ],
  },
  {
    id: 'supervisor',
    label: 'Supervisor de producción',
    help: 'Todas las pantallas de Producción y Stock; sin costos ni compras.',
    build: (catalog) => catalog
      .filter((entry) => ['produccion', 'stock'].includes(entry.module) && !entry.is_group)
      .map((entry) => ({ resource: entry.resource, actions: entry.actions.filter((a) => a !== 'eliminar' && a !== 'gestionar') }))
      .concat([{ resource: 'inicio', actions: ['ver'] }]),
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

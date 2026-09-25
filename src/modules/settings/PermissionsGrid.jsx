const resources = [
  ['dashboard', 'Panel'],
  ['inventory', 'Inventario'],
  ['production', 'Producción'],
  ['purchases', 'Compras'],
  ['finance', 'Finanzas'],
  ['reports', 'Reportes'],
  ['settings', 'Configuración'],
  ['users', 'Usuarios'],
  ['roles', 'Roles y permisos'],
  ['units', 'Unidades'],
  ['categories', 'Categorías'],
  ['warehouses', 'Depósitos'],
  ['items', 'Ítems'],
  ['stock', 'Stock y movimientos'],
];

const actions = [
  ['read', 'Ver'],
  ['insert', 'Crear'],
  ['update', 'Editar'],
  ['delete', 'Eliminar'],
  ['manage', 'Gestionar'],
];

export default function PermissionsGrid({ permissions, onChange, disabled = false }) {
  const hasPermission = (resource, action) => permissions.some(
    (item) => item.resource === resource && item.action === action,
  );

  const toggle = (resource, action) => {
    const next = hasPermission(resource, action)
      ? permissions.filter((item) => !(item.resource === resource && item.action === action))
      : [...permissions, { resource, action }];

    onChange(next);
  };

  return (
    <div className="permissions-scroll">
      <table className="permissions-table">
        <thead>
          <tr>
            <th>Módulo</th>
            {actions.map(([key, label]) => <th key={key}>{label}</th>)}
          </tr>
        </thead>
        <tbody>
          {resources.map(([resource, label]) => (
            <tr key={resource}>
              <td>{label}</td>
              {actions.map(([action]) => (
                <td key={action}>
                  <input
                    type="checkbox"
                    aria-label={`${label}: ${action}`}
                    checked={hasPermission(resource, action)}
                    disabled={disabled}
                    onChange={() => toggle(resource, action)}
                  />
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

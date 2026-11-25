import { useMemo, useState } from 'react';
import { Lock, ShieldAlert } from 'lucide-react';

/*
 * Permisos de un rol, módulo por módulo (diseño 045):
 *  1) ¿Puede entrar al módulo? Sí / No.
 *  2) Si puede: a qué pantallas accede y qué puede hacer en cada una (ver, crear, editar, eliminar).
 *  3) Datos sensibles (costos): decisión explícita del administrador.
 * La lista viene del catálogo del servidor. Sin catálogo (antes de la migración 045) se usa la grilla anterior.
 */
const MODULE_LABELS = {
  home: 'Inicio',
  stock: 'Stock',
  production: 'Producción',
  sales: 'Ventas',
  purchases: 'Compras',
  finance: 'Finanzas',
  reports: 'Reportes',
  settings: 'Ajustes',
  sensitive: 'Datos sensibles',
};

const ACTIONS = [
  ['read', 'Ver'],
  ['insert', 'Crear'],
  ['update', 'Editar'],
  ['delete', 'Eliminar'],
];

// "Gestionar" solo existe donde el catálogo lo declara (hoy: Pedidos internos → rechazar y convertir pedidos ajenos).
const SCREEN_ACTIONS = [...ACTIONS, ["manage", "Gestionar"]];

// Pantallas que necesitan ver el stock para mostrar datos correctos (el servidor las exige junto con Stock por depósito).
const DEPENDENCIES = [
  { screen: 'production_availability', needs: 'stock_levels', why: 'para calcular si alcanza el stock' },
  { screen: 'production_replenishment', needs: 'stock_levels', why: 'para proyectar qué reponer' },
  { screen: 'production_orders', needs: 'stock_levels', why: 'para ver existencias y materiales asignados en las órdenes' },
];

const LEGACY_RESOURCES = [
  ['dashboard', 'Panel'], ['inventory', 'Inventario'], ['production', 'Producción'], ['purchases', 'Compras'],
  ['purchase_requests', 'Pedidos de compra internos'], ['sales', 'Ventas'], ['finance', 'Finanzas'],
  ['reports', 'Reportes'], ['settings', 'Configuración'], ['users', 'Usuarios'], ['roles', 'Roles y permisos'],
  ['units', 'Unidades'], ['categories', 'Categorías'], ['warehouses', 'Depósitos'], ['items', 'Ítems'],
  ['stock', 'Stock y movimientos'],
];

function LegacyGrid({ permissions, onChange, disabled }) {
  const has = (resource, action) => permissions.some((p) => p.resource === resource && p.action === action);
  const toggle = (resource, action) => onChange(has(resource, action)
    ? permissions.filter((p) => !(p.resource === resource && p.action === action))
    : [...permissions, { resource, action }]);
  return (
    <div className="permissions-scroll">
      <table className="permissions-table">
        <thead><tr><th>Módulo</th>{ACTIONS.map(([key, label]) => <th key={key}>{label}</th>)}</tr></thead>
        <tbody>
          {LEGACY_RESOURCES.map(([resource, label]) => (
            <tr key={resource}>
              <td>{label}</td>
              {ACTIONS.map(([action]) => (
                <td key={action}>
                  <input type="checkbox" aria-label={`${label}: ${action}`} checked={has(resource, action)}
                    disabled={disabled} onChange={() => toggle(resource, action)} />
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export default function PermissionsGrid({ permissions, onChange, disabled = false, catalog = [] }) {
  const screens = useMemo(
    () => catalog.filter((entry) => !entry.is_group && !entry.admin_only).sort((a, b) => a.sort - b.sort),
    [catalog],
  );
  const modules = useMemo(() => {
    const map = new Map();
    for (const screen of screens) {
      if (!map.has(screen.module)) map.set(screen.module, []);
      map.get(screen.module).push(screen);
    }
    return [...map.entries()];
  }, [screens]);

  const has = (resource, action) => permissions.some((p) => p.resource === resource && p.action === action);
  const [openState, setOpenState] = useState({});
  const isOpen = (module, rows) => openState[module]
    ?? rows.some((screen) => permissions.some((p) => p.resource === screen.resource));

  if (!catalog.length) return <LegacyGrid permissions={permissions} onChange={onChange} disabled={disabled} />;

  const userActions = (screen) => SCREEN_ACTIONS.map(([a]) => a).filter((a) => screen.actions.includes(a));
  const without = (resources) => permissions.filter((p) => !resources.includes(p.resource));
  const setScreen = (screen, actions) => onChange([
    ...without([screen.resource]),
    ...actions.map((action) => ({ resource: screen.resource, action })),
  ]);
  const toggleAction = (screen, action) => {
    // Stock: ver se da pantalla por pantalla; registrar (crear/editar/eliminar) es todo o nada para todo el módulo (el servidor lo exige así).
    if (screen.module === 'stock' && action !== 'read') {
      const stockRows = screen.module && modules.find(([name]) => name === 'stock')?.[1];
      if (stockRows) {
        if (has(screen.resource, action)) {
          const stockResources = stockRows.map((row) => row.resource);
          onChange(permissions.filter((p) => !(stockResources.includes(p.resource) && p.action !== 'read')));
        } else {
          setModule(stockRows, 'all');
        }
        return;
      }
    }
    const current = userActions(screen).filter((a) => has(screen.resource, a));
    if (action === 'read') {
      setScreen(screen, current.includes('read') ? [] : [...current, 'read']);
    } else {
      setScreen(screen, current.includes(action) ? current.filter((a) => a !== action) : [...new Set([...current, 'read', action])]);
    }
  };
  const columnsOf = (rows) => SCREEN_ACTIONS.slice(1)
    .filter(([action]) => action !== "manage" || rows.some((screen) => screen.actions.includes("manage")));
  const setModule = (rows, mode) => onChange([
    ...without(rows.map((screen) => screen.resource)),
    ...(mode === 'none' ? [] : rows.flatMap((screen) => (mode === 'all' ? userActions(screen) : ['read'])
      .filter((a) => screen.actions.includes(a)).map((action) => ({ resource: screen.resource, action })))),
  ]);

  const labelOf = (resource) => catalog.find((entry) => entry.resource === resource)?.label ?? resource;
  const missing = DEPENDENCIES.filter((dep) => has(dep.screen, 'read') && !has(dep.needs, 'read')
    && catalog.some((entry) => entry.resource === dep.needs));
  const addMissing = () => onChange([
    ...permissions,
    ...[...new Set(missing.map((dep) => dep.needs))].map((resource) => ({ resource, action: 'read' })),
  ]);

  return (
    <>
    {missing.length > 0 && (
      <div className="perm-dependency" role="alert">
        <ShieldAlert size={16} aria-hidden="true" />
        <div>
          <strong>Falta un acceso que va de la mano</strong>
          <ul>
            {missing.map((dep) => (
              <li key={dep.screen}>
                «{labelOf(dep.screen)}» necesita poder ver «{labelOf(dep.needs)}» {dep.why}.
              </li>
            ))}
          </ul>
          <button type="button" className="button outline" disabled={disabled} onClick={addMissing}>
            Agregar «Ver» en las pantallas que faltan
          </button>
        </div>
      </div>
    )}
    <div className="perm-modules">
      {modules.map(([module, rows]) => {
        const open = isOpen(module, rows);
        const withAccess = rows.filter((screen) => has(screen.resource, 'read'));
        const sensitive = module === 'sensitive';
        return (
          <section className={`perm-module ${open ? 'is-open' : ''}`} key={module} aria-label={MODULE_LABELS[module] ?? module}>
            <header>
              <div>
                <h3>{MODULE_LABELS[module] ?? module}</h3>
                <small>
                  {open
                    ? `${withAccess.length} de ${rows.length} ${sensitive ? 'permisos' : 'pantallas'} con acceso`
                    : sensitive ? 'Sin acceso a datos sensibles' : 'No puede entrar a este módulo'}
                </small>
              </div>
              <label className="perm-switch">
                <input type="checkbox" role="switch" checked={open} disabled={disabled}
                  aria-label={sensitive ? 'Permitir ver datos sensibles' : `¿Puede entrar al módulo ${MODULE_LABELS[module] ?? module}?`}
                  onChange={(event) => {
                    if (event.target.checked) setOpenState({ ...openState, [module]: true });
                    else { setOpenState({ ...openState, [module]: false }); setModule(rows, 'none'); }
                  }} />
                <span>{open ? 'Sí puede entrar' : 'No puede entrar'}</span>
              </label>
            </header>
            {sensitive && open && (
              <p className="perm-warning"><ShieldAlert size={15} aria-hidden="true" /> Estos datos son sensibles: tildá solo lo que este rol realmente necesita.</p>
            )}
            {open && rows.some((screen) => !screen.enforced && (screen.parent || sensitive)) && (
              <p className={`perm-note-line ${!sensitive && withAccess.length > 0 && withAccess.length < rows.length ? "is-warn" : ""}`}>
                {sensitive
                  ? "El servidor exigirá estos permisos desde la próxima actualización; hasta entonces se mantiene el comportamiento actual."
                  : withAccess.length > 0 && withAccess.length < rows.length
                    ? "Atención: hasta que se active el control por pantalla, el servidor solo habilita este módulo si el rol tiene TODAS sus pantallas. Un acceso parcial hoy NO le abre estas pantallas en el servidor."
                    : "Por ahora el servidor aplica el acceso a todo el módulo; el control pantalla por pantalla se activa en la próxima actualización."}
              </p>
            )}
            {open && module === 'stock' && (
              <p className="perm-note-line">
                Cómo funciona Stock: <strong>Ver</strong> se da pantalla por pantalla. Si marcás <strong>Crear, Editar o Eliminar</strong> en
                cualquiera, la persona recibe acceso completo a todo Stock (movimientos, remitos e ingresos), porque todos esos movimientos
                comparten el mismo control. Cada movimiento queda registrado con quién lo hizo.
              </p>
            )}
            {open && (
              <>
                {rows.length > 1 && !sensitive && (
                  <div className="perm-bulk">
                    <button type="button" className="button outline" disabled={disabled} onClick={() => setModule(rows, 'all')}>Acceso total al módulo</button>
                    <button type="button" className="button outline" disabled={disabled} onClick={() => setModule(rows, 'read')}>Solo ver todo</button>
                    <button type="button" className="button outline" disabled={disabled} onClick={() => setModule(rows, 'none')}>Quitar todo</button>
                  </div>
                )}
                <div className="permissions-scroll">
                  <table className="permissions-table perm-screens">
                    <thead>
                      <tr>
                        <th>{sensitive ? 'Dato' : 'Pantalla'}</th>
                        <th>Acceso</th>
                        {!sensitive && columnsOf(rows).map(([key, label]) => <th key={key}>{label}</th>)}
                      </tr>
                    </thead>
                    <tbody>
                      {rows.map((screen) => {
                        const access = has(screen.resource, 'read');
                        return (
                          <tr key={screen.resource} className={access ? '' : 'is-denied'}>
                            <td>
                              <strong>{screen.label}</strong>
                              <small>{screen.help}</small>
                            </td>
                            <td>
                              <label className="perm-access">
                                <input type="checkbox" role="switch" checked={access} disabled={disabled}
                                  aria-label={`${screen.label}: acceso`} onChange={() => toggleAction(screen, 'read')} />
                                <span>{access ? 'Acceso' : <><Lock size={12} aria-hidden="true" /> Sin acceso</>}</span>
                              </label>
                            </td>
                            {!sensitive && columnsOf(rows).map(([action, label]) => (
                              <td key={action}>
                                <input type="checkbox" aria-label={`${screen.label}: ${label}`}
                                  checked={has(screen.resource, action)} disabled={disabled || !access || !screen.actions.includes(action)}
                                  onChange={() => toggleAction(screen, action)} />
                              </td>
                            ))}
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              </>
            )}
          </section>
        );
      })}

      <section className="perm-summary" aria-label="Resumen de accesos">
        <h3>Resumen: qué puede y qué no puede este rol</h3>
        {modules.map(([module, rows]) => {
          const yes = rows.filter((screen) => has(screen.resource, 'read'));
          const no = rows.filter((screen) => !has(screen.resource, 'read'));
          return (
            <p key={module}>
              <strong>{MODULE_LABELS[module] ?? module}:</strong>{' '}
              {yes.length === 0 ? 'sin acceso.' : (
                <>
                  <span className="perm-yes">Puede: {yes.map((s) => s.label).join(', ')}.</span>
                  {no.length > 0 && <span className="perm-no"> No puede: {no.map((s) => s.label).join(', ')}.</span>}
                </>
              )}
            </p>
          );
        })}
        <small>Usuarios y roles solo los gestiona el administrador.</small>
      </section>
    </div>
    </>
  );
}

import { useState } from 'react';
import { NavLink, Outlet, useLocation } from 'react-router-dom';
import {
  BarChart3,
  Boxes,
  Building2,
  ChevronDown,
  CircleHelp,
  Factory,
  LayoutDashboard,
  LogOut,
  Menu,
  Settings2,
  ShoppingCart,
  ShoppingBag,
  Wallet,
  UserRound,
  X,
  Sparkles,
} from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';
import { notifyError, notifySuccess } from '../lib/notifications';
import ModuleHelp from '../modules/help/ModuleHelp';
import NotificationCenter from '../modules/operations/NotificationCenter';
import ActionDialog from './ActionDialog';

const groups = [
  {
    title: 'OPERACIÓN',
    items: [
      { label: 'Inicio', icon: LayoutDashboard, to: '/', permission: 'dashboard' },
    ],
  },
  {
    title: 'MÓDULOS',
    items: [
      {
        label: 'Inventario', icon: Boxes, permission: 'inventory',
        children: [
          { label: 'Todos los ítems', to: '/inventory/items', permission: 'items' },
          { label: 'Materias primas', to: '/inventory/items?type=raw_material', permission: 'items' },
          { label: 'Productos', to: '/inventory/items?type=finished_product', permission: 'items' },
          { label: 'Stock por depósito', to: '/inventory/stock', permission: 'stock' },
          { label: 'Movimientos', to: '/inventory/movements', permission: 'stock' },
          { label: 'Remitos de entrega', to: '/inventory/delivery-notes', permission: 'stock' },
        ],
      },
      {
        label: 'Producción', icon: Factory, permission: 'production',
        children: [
          { label: 'Órdenes de fabricación', to: '/production/orders', permission: 'production' },
          { label: 'Fórmulas', to: '/production/formulas', permission: 'production' },
          { label: 'Planificación', to: '/production/planning', permission: 'production' },
          { label: '¿Tengo stock para fabricar?', to: '/production/availability', permission: 'production' },
          { label: 'Pronóstico y reposición', to: '/production/replenishment', permission: 'production' },
        ],
      },
      {
        label: 'Compras', icon: ShoppingCart, permission: 'purchases',
        children: [
          { label: 'Proveedores', to: '/purchases/suppliers', permission: 'purchases' },
          { label: 'Órdenes de compra', to: '/purchases/orders', permission: 'purchases' },
        ],
      },
      {
        label: 'Ventas', icon: ShoppingBag, permission: 'sales',
        children: [
          { label: 'Clientes', to: '/sales/customers', permission: 'sales' },
          { label: 'Lista de precios', to: '/sales/lista-precios', permission: 'sales' },
          { label: 'Registrar venta', to: '/sales/orders', permission: 'sales' },
        ],
      },
      {
        label: 'Finanzas', icon: Wallet, permission: 'finance',
        children: [
          { label: 'Cuentas por cobrar', to: '/finance/receivables', permission: 'finance' },
          { label: 'Tesorería', to: '/finance/treasury', permission: 'finance' },
          { label: 'Rentabilidad y precios', to: '/finance/costs', permission: 'finance', adminOnly: true },
        ],
      },
      {
        label: 'Reportes', icon: BarChart3, permission: 'reports',
        children: [
          { label: 'Resumen por período', to: '/reports', permission: 'reports' },
        ],
      },
    ],
  },
  {
    title: 'SISTEMA',
    items: [
      {
        label: 'Configuración', icon: Settings2, permission: 'settings',
        children: [
          { label: 'Usuarios', to: '/settings/users', permission: 'users' },
          { label: 'Roles y permisos', to: '/settings/roles', permission: 'roles' },
          { label: 'Unidades', to: '/settings/units', permission: 'units' },
          { label: 'Categorías', to: '/settings/categories', permission: 'categories' },
          { label: 'Depósitos', to: '/settings/warehouses', permission: 'warehouses' },
        ],
      },
    ],
  },
];

export default function AdminLayout() {
  const {
    activeCompany,
    memberships,
    setActiveCompanyId,
    can,
    role,
    user,
    signOut,
    openSupportCompany,
  } = useAuth();
  const location = useLocation();
  const routeName = {
    '/': 'Inicio', '/inventory/items': 'Ítems', '/inventory/stock': 'Stock por depósito',
    '/inventory/movements': 'Movimientos', '/inventory/delivery-notes': 'Remitos',
    '/purchases/suppliers': 'Proveedores',
    '/purchases/orders': 'Órdenes de compra', '/production/formulas': 'Fórmulas',
    '/production/orders': 'Órdenes de fabricación', '/production/planning': 'Planificación',
    '/production/availability': 'Disponibilidad para fabricar',
    '/production/replenishment': 'Pronóstico y reposición',
    '/sales/customers': 'Clientes', '/sales/lista-precios': 'Lista de precios', '/sales/orders': 'Ventas',
    '/finance/receivables': 'Cuentas por cobrar', '/finance/treasury': 'Tesorería',
    '/finance/costs': 'Rentabilidad y precios', '/reports': 'Reportes',
    '/ayuda': 'Guía de uso', '/mi-perfil': 'Mi perfil', '/settings/users': 'Usuarios',
    '/settings/roles': 'Roles y permisos', '/settings/units': 'Unidades',
    '/settings/categories': 'Categorías', '/settings/warehouses': 'Depósitos',
    '/actualizaciones': 'Actualizaciones',
  };
  const sectionName = routeName[location.pathname]
    ?? (location.pathname.startsWith('/inventory/items/') ? 'Ficha de ítem' : 'Espacio de trabajo');
  const [open, setOpen] = useState({});
  const [menuOpen, setMenuOpen] = useState(false);
  const [supportTarget, setSupportTarget] = useState(null);
  const [supportReason, setSupportReason] = useState('');
  const [supportBusy, setSupportBusy] = useState(false);

  async function switchSupportCompany(event) {
    event.preventDefault();
    if (!supportTarget || supportReason.trim().length < 8 || supportBusy) return;
    setSupportBusy(true);
    try {
      await openSupportCompany(supportTarget.company_id, supportReason);
      notifySuccess('Empresa seleccionada', supportTarget.companies.name);
      setSupportTarget(null);
      setSupportReason('');
      setMenuOpen(false);
    } catch (error) {
      notifyError(error);
    } finally {
      setSupportBusy(false);
    }
  }

  return (
    <div className="app-shell">
      <aside className={`sidebar ${menuOpen ? 'mobile-open' : ''}`}>
        <div className="sidebar-top">
          <div className="brand">
            <span className="brand-mark">D</span>
            <span>DROMUX <small>ERP</small></span>
          </div>
          <button
            className="mobile-close icon-button"
            onClick={() => setMenuOpen(false)}
            aria-label="Cerrar menú"
          >
            <X size={21} />
          </button>
        </div>

        <div className="workspace">
          <span className="workspace-logo"><Building2 size={20} /></span>
          <div>
            <small>ESPACIO ACTUAL</small>
            <select
              aria-label="Empresa activa"
              value={activeCompany?.id ?? ''}
              onChange={(event) => {
                const target = memberships.find((item) =>
                  item.company_id === event.target.value);
                if (target?.roles?.code === 'support') {
                  setSupportTarget(target);
                } else {
                  setActiveCompanyId(event.target.value);
                }
              }}
            >
              {memberships.map((membership) => (
                <option key={membership.company_id} value={membership.company_id}>
                  {membership.companies.name}
                </option>
              ))}
            </select>
          </div>
          <ChevronDown size={16} />
        </div>

        <nav aria-label="Menú principal">
          {groups.map((group) => {
            const visible = group.items.filter((item) => (
              can(item.permission, 'read') || item.children?.some((child) => (
                typeof child === 'object' && (!child.adminOnly || role === 'admin') && can(child.permission, 'read')
              ))
            ));
            if (!visible.length) return null;

            return (
              <section className="nav-group" key={group.title}>
                <span className="nav-title">{group.title}</span>
                {visible.map((item) => {
                  const Icon = item.icon;

                  return (
                    <div key={item.label}>
                      {item.children ? (
                        <>
                          <button
                            className={`nav-item ${item.children.some((child) =>
                              child.to?.split('?')[0] === location.pathname) ? 'active' : ''}`}
                            onClick={() => setOpen((previous) => ({
                              ...previous,
                              [item.label]: !(previous[item.label] ?? item.children.some((child) =>
                                child.to?.split('?')[0] === location.pathname)),
                            }))}
                            aria-expanded={Boolean(open[item.label] ?? item.children.some((child) =>
                              child.to?.split('?')[0] === location.pathname))}
                          >
                            <Icon size={19} />
                            <span>{item.label}</span>
                            <ChevronDown
                              className={(open[item.label] ?? item.children.some((child) =>
                                child.to?.split('?')[0] === location.pathname)) ? 'rotated' : ''}
                              size={16}
                            />
                          </button>

                          {(open[item.label] ?? item.children.some((child) =>
                            child.to?.split('?')[0] === location.pathname)) && (
                            <div className="subnav">
                              {item.children
                                .filter((child) => (
                                  typeof child !== 'object' || ((!child.adminOnly || role === 'admin') && can(child.permission, 'read'))
                                ))
                                .map((child) => (
                                  typeof child === 'object' && child.to ? (
                                    <NavLink
                                      key={child.label}
                                      to={child.to}
                                      className={({ isActive }) => (
                                        `subnav-item ${isActive && location.search === (child.to.split('?')[1] ? `?${child.to.split('?')[1]}` : '') ? 'selected' : ''}`
                                      )}
                                      onClick={() => setMenuOpen(false)}
                                    >
                                      {child.label}
                                    </NavLink>
                                  ) : (
                                    <span
                                      key={typeof child === 'object' ? child.label : child}
                                      className="subnav-item"
                                      title="Se habilitará en una fase posterior"
                                    >
                                      {typeof child === 'object' ? child.label : child}
                                      <span className="subnav-lock">·</span>
                                    </span>
                                  )
                                ))}
                            </div>
                          )}
                        </>
                      ) : (
                        <NavLink
                          to={item.to}
                          end
                          className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}
                          onClick={() => setMenuOpen(false)}
                        >
                          <Icon size={19} />
                          <span>{item.label}</span>
                        </NavLink>
                      )}
                    </div>
                  );
                })}
              </section>
            );
          })}
        </nav>

        <div className="sidebar-footer">
          <NavLink className="nav-item" to="/actualizaciones"
            onClick={() => setMenuOpen(false)}>
            <Sparkles size={18} /> <span>Actualizaciones</span>
          </NavLink>
          <NavLink className="nav-item" to="/mi-perfil" onClick={() => setMenuOpen(false)}>
            <UserRound size={18} /> <span>Mi perfil</span>
          </NavLink>
          <NavLink className="help-box" to="/ayuda" onClick={() => setMenuOpen(false)}>
            <CircleHelp size={19} />
            <div><strong>Guía de uso</strong><span>Pasos para cada tarea</span></div>
          </NavLink>
          <button
            className="nav-item signout"
            onClick={async () => {
              try {
                await signOut();
                notifySuccess('Sesión cerrada');
              } catch (err) {
                notifyError(err);
              }
            }}
          >
            <LogOut size={18} />
            <span>Cerrar sesión</span>
          </button>
        </div>
      </aside>
      <ActionDialog open={!!supportTarget} busy={supportBusy}
        title="Consultar otra empresa"
        description={`El acceso a ${supportTarget?.companies.name ?? 'esta empresa'} será de solo lectura y quedará registrado.`}
        onClose={() => setSupportTarget(null)}>
        <form onSubmit={switchSupportCompany}>
          <label>Motivo de la consulta
            <textarea required minLength={8} maxLength={300}
              value={supportReason} onChange={(event) => setSupportReason(event.target.value)}
              placeholder="Ej.: revisión solicitada por el responsable de la empresa" />
          </label>
          <div className="erp-action-dialog-actions">
            <button type="button" className="button outline" disabled={supportBusy}
              onClick={() => setSupportTarget(null)}>Cancelar</button>
            <button className="button primary" disabled={supportBusy || supportReason.trim().length < 8}>
              {supportBusy ? 'Ingresando…' : 'Ingresar en modo lectura'}
            </button>
          </div>
        </form>
      </ActionDialog>

      {menuOpen && (
        <button
          type="button"
          className="overlay"
          aria-label="Cerrar navegación"
          onClick={() => setMenuOpen(false)}
        />
      )}

      <div className="main-area">
        <header className="topbar">
          <div className="crumb">
            <button
              className="mobile-menu icon-button"
              type="button"
              aria-expanded={menuOpen}
              onClick={() => setMenuOpen(true)}
              aria-label="Abrir menú"
            >
              <Menu size={22} />
            </button>
            <span>Espacio de trabajo</span>
            <span className="crumb-divider">/</span>
            <strong>{sectionName}</strong>
          </div>
          <div className="topbar-right">
            {role === 'support' && <span className="support-readonly">Soporte · solo lectura</span>}
            <span className="online"><i /> Sistema activo</span>
            <NotificationCenter />
            <NavLink className="avatar" to="/mi-perfil"
              aria-label="Abrir mi perfil" title={user.email}>
              {(user.user_metadata?.full_name || user.email)?.[0]?.toUpperCase()}
            </NavLink>
          </div>
        </header>

        <ModuleHelp />
        <main className="content"><Outlet /></main>
        <footer className="footer">
          ERP Dromux <span>·</span> Gestión de tu empresa
        </footer>
      </div>
    </div>
  );
}

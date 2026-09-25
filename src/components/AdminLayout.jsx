import { useState } from 'react';
import { NavLink, Outlet } from 'react-router-dom';
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
  Wallet,
  X,
} from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';
import { notifyError, notifySuccess } from '../lib/notifications';

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
        ],
      },
      {
        label: 'Producción', icon: Factory, permission: 'production',
        children: [
          { label: 'Órdenes de fabricación', to: '/production/orders', permission: 'production' },
          { label: 'Fórmulas', to: '/production/formulas', permission: 'production' },
          { label: 'Planificación', to: '/production/planning', permission: 'production' },
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
        label: 'Finanzas', icon: Wallet, permission: 'finance',
        children: ['Tesorería', 'Costos'],
      },
      {
        label: 'Reportes', icon: BarChart3, permission: 'reports',
        children: ['Resumen', 'Indicadores'],
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
          { label: 'Empresa', to: null, permission: 'settings' },
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
    user,
    signOut,
  } = useAuth();
  const [open, setOpen] = useState({});
  const [menuOpen, setMenuOpen] = useState(false);

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
              onChange={(event) => setActiveCompanyId(event.target.value)}
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
                typeof child === 'object' && can(child.permission, 'read')
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
                            className="nav-item"
                            onClick={() => setOpen((previous) => ({
                              ...previous,
                              [item.label]: !previous[item.label],
                            }))}
                            aria-expanded={Boolean(open[item.label])}
                          >
                            <Icon size={19} />
                            <span>{item.label}</span>
                            <ChevronDown
                              className={open[item.label] ? 'rotated' : ''}
                              size={16}
                            />
                          </button>

                          {open[item.label] && (
                            <div className="subnav">
                              {item.children
                                .filter((child) => (
                                  typeof child !== 'object' || can(child.permission, 'read')
                                ))
                                .map((child) => (
                                  typeof child === 'object' && child.to ? (
                                    <NavLink
                                      key={child.label}
                                      to={child.to}
                                      className={({ isActive }) => (
                                        `subnav-item ${isActive ? 'selected' : ''}`
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
          <div className="help-box">
            <CircleHelp size={19} />
            <div>
              <strong>Construyendo el futuro</strong>
              <span>Versión inicial del ERP</span>
            </div>
          </div>
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

      {menuOpen && <div className="overlay" onClick={() => setMenuOpen(false)} />}

      <div className="main-area">
        <header className="topbar">
          <div className="crumb">
            <button
              className="mobile-menu icon-button"
              onClick={() => setMenuOpen(true)}
              aria-label="Abrir menú"
            >
              <Menu size={22} />
            </button>
            <span>Espacio de trabajo</span>
            <span className="crumb-divider">/</span>
            <strong>Inicio</strong>
          </div>
          <div className="topbar-right">
            <span className="online"><i /> Sistema activo</span>
            <span className="avatar" title={user.email}>
              {user.email?.[0]?.toUpperCase()}
            </span>
          </div>
        </header>

        <main className="content"><Outlet /></main>
        <footer className="footer">
          ERP Dromux <span>·</span> Una nueva forma de trabajar <span>© 2026</span>
        </footer>
      </div>
    </div>
  );
}

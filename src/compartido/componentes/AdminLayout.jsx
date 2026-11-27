import { useEffect, useState } from "react";
import { Link, NavLink, Outlet, useLocation } from "react-router-dom";
import {
  Building2,
  Lock,
  ChevronDown,
  CircleHelp,
  LogOut,
  Menu,
  Search,
  UserRound,
  X,
  Sparkles,
} from "lucide-react";
import { useAuth } from "../contextos/AuthContext";
import { notifyError, notifySuccess } from "../utilidades/notifications";
import ModuleHelp from "../../modulos/ayuda/ModuleHelp";
import NotificationCenter from "../../modulos/inicio/avisos/NotificationCenter";
import ActionDialog from "./ActionDialog";
import CommandPalette from "./CommandPalette";
import ViewAsBar from "./ViewAsBar";
import { canSeeChild, locate, navGroups, pathOf } from "./navConfig";

export default function AdminLayout() {
  const {
    activeCompany,
    memberships,
    setActiveCompanyId,
    can,
    role,
    viewingAs,
    user,
    signOut,
    openSupportCompany,
  } = useAuth();
  const location = useLocation();
  const where = locate(location.pathname);
  const activeModuleId = where?.module.id ?? "home";
  const [open, setOpen] = useState({});
  const [menuOpen, setMenuOpen] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const [supportTarget, setSupportTarget] = useState(null);
  const [supportReason, setSupportReason] = useState("");
  const [supportBusy, setSupportBusy] = useState(false);

  // Al navegar en pantallas chicas el menú se cierra solo.
  useEffect(() => setMenuOpen(false), [location.pathname]);

  // Escape cierra el menú lateral en pantallas chicas.
  useEffect(() => {
    if (!menuOpen) return undefined;
    const onKey = (event) => event.key === "Escape" && setMenuOpen(false);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [menuOpen]);

  async function switchSupportCompany(event) {
    event.preventDefault();
    if (!supportTarget || supportReason.trim().length < 8 || supportBusy)
      return;
    setSupportBusy(true);
    try {
      await openSupportCompany(supportTarget.company_id, supportReason);
      notifySuccess("Empresa seleccionada", supportTarget.companies.name);
      setSupportTarget(null);
      setSupportReason("");
      setMenuOpen(false);
    } catch (error) {
      notifyError(error);
    } finally {
      setSupportBusy(false);
    }
  }

  const allowedChildren = (module) =>
    (module.children ?? []).filter((child) => canSeeChild(child, { can, role }));

  const crumbModule = where?.module;
  const crumbLast = where?.page?.crumb ?? where?.page?.label;
  const pageTitle = crumbLast ?? crumbModule?.label ?? "Espacio de trabajo";

  return (
    <div className={`app-shell mod-${activeModuleId} ${viewingAs ? "has-view-as" : ""}`}>
      <aside className={`sidebar ${menuOpen ? "mobile-open" : ""}`}>
        <div className="sidebar-top">
          <div className="brand">
            <span className="brand-mark">D</span>
            <span>
              DROMUX <small>ERP</small>
            </span>
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
          <span className="workspace-logo">
            <Building2 size={20} />
          </span>
          <div>
            <small>ESPACIO ACTUAL</small>
            <select
              aria-label="Empresa activa"
              value={activeCompany?.id ?? ""}
              onChange={(event) => {
                const target = memberships.find(
                  (item) => item.company_id === event.target.value,
                );
                if (target?.roles?.code === "support") {
                  setSupportTarget(target);
                } else {
                  setActiveCompanyId(event.target.value);
                }
              }}
            >
              {memberships.map((membership) => (
                <option
                  key={membership.company_id}
                  value={membership.company_id}
                >
                  {membership.companies.name}
                </option>
              ))}
            </select>
          </div>
          <ChevronDown size={16} />
        </div>

        <button
          type="button"
          className="nav-search"
          onClick={() => setSearchOpen(true)}
          aria-label="Buscar en el sistema (Ctrl+K)"
          aria-keyshortcuts="Control+K Meta+K"
        >
          <Search size={16} aria-hidden="true" />
          <span>Buscar…</span>
          <kbd>Ctrl K</kbd>
        </button>

        <nav aria-label="Menú principal">
          {navGroups.map((group) => {
            // Los módulos y pantallas sin permiso se muestran bloqueados (candado), no ocultos: el servidor igual los rechaza.
            const visible = group.modules;
            if (!visible.length) return null;

            return (
              <section className="nav-group" key={group.title} aria-label={group.title}>
                <span className="nav-title">{group.title}</span>
                {visible.map((module) => {
                  const Icon = module.icon;
                  const isActive = activeModuleId === module.id;

                  const moduleLocked = module.to
                    ? !can(module.permission, "read")
                    : allowedChildren(module).length === 0 &&
                      !can(module.permission, "read");

                  if (module.to) {
                    return (
                      <div key={module.id} className={`nav-module mod-${module.id}`}>
                        <NavLink
                          to={module.to}
                          end
                          className={({ isActive: current }) =>
                            `nav-item ${current ? "active" : ""} ${moduleLocked ? "is-locked" : ""}`
                          }
                          aria-label={moduleLocked ? `${module.label} (acceso restringido)` : module.label}
                          title={moduleLocked ? "Acceso restringido" : undefined}
                        >
                          <Icon size={19} aria-hidden="true" />
                          <span>{module.label}</span>
                          {moduleLocked && <Lock className="nav-lock" size={14} aria-hidden="true" />}
                        </NavLink>
                      </div>
                    );
                  }

                  const expanded = open[module.id] ?? isActive;
                  const panelId = `subnav-${module.id}`;

                  return (
                    <div key={module.id} className={`nav-module mod-${module.id}`}>
                      <button
                        type="button"
                        className={`nav-item ${isActive ? "active" : ""} ${moduleLocked ? "is-locked" : ""}`}
                        title={moduleLocked ? "Acceso restringido" : undefined}
                        aria-expanded={expanded}
                        aria-controls={panelId}
                        onClick={() =>
                          setOpen((previous) => ({
                            ...previous,
                            [module.id]: !(previous[module.id] ?? isActive),
                          }))
                        }
                      >
                        <Icon size={19} aria-hidden="true" />
                        <span>{module.label}</span>
                        {moduleLocked && <Lock className="nav-lock" size={14} aria-hidden="true" />}
                        <ChevronDown
                          className={expanded ? "rotated" : ""}
                          size={16}
                          aria-hidden="true"
                        />
                      </button>

                      {expanded && (
                        <div className="subnav" id={panelId}>
                          {(module.children ?? []).map((child) => {
                            const locked = !canSeeChild(child, { can, role });
                            const query = child.to.split("?")[1];
                            // Sin filtro propio, la entrada está activa aunque la URL tenga otros parámetros (búsquedas, fechas).
                            const sameSearch = query
                              ? location.search === `?${query}`
                              : !/[?&]type=/.test(location.search);
                            return (
                              <NavLink
                                key={child.to}
                                to={child.to}
                                end
                                title={locked ? "Acceso restringido" : undefined}
                                className={({ isActive: current }) =>
                                  `subnav-item ${
                                    current && sameSearch ? "selected" : ""
                                  } ${locked ? "is-locked" : ""}`
                                }
                                aria-current={
                                  pathOf(child.to) === location.pathname &&
                                  sameSearch
                                    ? "page"
                                    : undefined
                                }
                              >
                                <span>{child.label}</span>
                                {locked && (
                                  <>
                                    <Lock className="nav-lock" size={12} aria-hidden="true" />
                                    <span className="sr-only">(acceso restringido)</span>
                                  </>
                                )}
                              </NavLink>
                            );
                          })}
                        </div>
                      )}
                    </div>
                  );
                })}
              </section>
            );
          })}
        </nav>

        <div className="sidebar-footer">
          <NavLink className="nav-item" to="/actualizaciones">
            <Sparkles size={18} /> <span>Actualizaciones</span>
          </NavLink>
          <NavLink className="nav-item" to="/mi-perfil">
            <UserRound size={18} /> <span>Mi perfil</span>
          </NavLink>
          <NavLink className="help-box" to="/ayuda">
            <CircleHelp size={19} />
            <div>
              <strong>Guía de uso</strong>
              <span>Pasos para cada tarea</span>
            </div>
          </NavLink>
          <button
            className="nav-item signout"
            onClick={async () => {
              try {
                await signOut();
                notifySuccess("Sesión cerrada");
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
      <ActionDialog
        open={!!supportTarget}
        busy={supportBusy}
        title="Consultar otra empresa"
        description={`El acceso a ${supportTarget?.companies.name ?? "esta empresa"} será de solo lectura y quedará registrado.`}
        onClose={() => setSupportTarget(null)}
      >
        <form onSubmit={switchSupportCompany}>
          <label>
            Motivo de la consulta
            <textarea
              required
              minLength={8}
              maxLength={300}
              value={supportReason}
              onChange={(event) => setSupportReason(event.target.value)}
              placeholder="Ej.: revisión solicitada por el responsable de la empresa"
            />
          </label>
          <div className="erp-action-dialog-actions">
            <button
              type="button"
              className="button outline"
              disabled={supportBusy}
              onClick={() => setSupportTarget(null)}
            >
              Cancelar
            </button>
            <button
              className="button primary"
              disabled={supportBusy || supportReason.trim().length < 8}
            >
              {supportBusy ? "Ingresando…" : "Ingresar en modo lectura"}
            </button>
          </div>
        </form>
      </ActionDialog>

      <CommandPalette open={searchOpen} onOpenChange={setSearchOpen} />

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
            <nav className="crumbs" aria-label="Ubicación">
              <ol>
                <li className="crumb-area">
                  {where ? where.group.title : "Espacio de trabajo"}
                </li>
                {crumbModule &&
                  crumbModule.to !== location.pathname &&
                  crumbModule.label !== pageTitle && (
                  <li className="crumb-module">
                    {crumbModule.children?.[0] ? (
                      <Link to={allowedChildren(crumbModule)[0]?.to ?? "/"}>
                        {crumbModule.label}
                      </Link>
                    ) : (
                      crumbModule.label
                    )}
                  </li>
                )}
                <li aria-current="page" className="crumb-page">
                  <strong>{pageTitle}</strong>
                </li>
              </ol>
            </nav>
          </div>
          <div className="topbar-right">
            {role === "support" && (
              <span className="support-readonly">Soporte · solo lectura</span>
            )}
            <button
              type="button"
              className="topbar-search"
              onClick={() => setSearchOpen(true)}
              aria-label="Buscar en el sistema (Ctrl+K)"
            >
              <Search size={17} aria-hidden="true" />
              <span>Buscar</span>
            </button>
            <span className="online">
              <i /> Sistema activo
            </span>
            <NotificationCenter />
            <NavLink
              className="avatar"
              to="/mi-perfil"
              aria-label="Abrir mi perfil"
              title={user.email}
            >
              {(user.user_metadata?.full_name ||
                user.email)?.[0]?.toUpperCase()}
            </NavLink>
          </div>
        </header>

        <ModuleHelp />
        <main className="content">
          <Outlet />
        </main>
        <ViewAsBar />
        <footer className="footer">
          ERP Dromux <span>·</span> Gestión de tu empresa
        </footer>
      </div>
    </div>
  );
}

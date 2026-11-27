import { NavLink } from "react-router-dom";
import { useAuth } from "../contextos/AuthContext";
import "./moduleShell.css";

/*
 * Cabecera común de un módulo: etiqueta del módulo, título, descripción, acciones y
 * pestañas hacia sus pantallas. Cada pestaña declara los recursos (`any`) cuyo permiso
 * de lectura la habilita; el servidor es quien realmente autoriza.
 * tabs: [{ to, label, icon, end?, any: [recurso] }]
 */
export default function ModuleShell({
  label,
  labelIcon: LabelIcon,
  tabs,
  title,
  description,
  actions,
  children,
  className = "",
}) {
  const { can } = useAuth();
  const visible = tabs.filter((tab) => tab.any.some((resource) => can(resource, "read")));

  return (
    <div className={`mod-shell ${className}`}>
      <header className="mod-shell-head">
        <div>
          <span className="mod-shell-eyebrow">
            {LabelIcon && <LabelIcon size={14} aria-hidden="true" />} {label}
          </span>
          <h1>{title}</h1>
          {description && <p>{description}</p>}
        </div>
        {actions && <div className="mod-shell-actions">{actions}</div>}
      </header>
      <nav className="mod-tabs" aria-label={`Secciones de ${label}`}>
        {visible.map(({ to, label: tabLabel, icon: Icon, end }) => (
          <NavLink key={to} to={to} end={end} className="mod-tab">
            {Icon && <Icon size={16} aria-hidden="true" />}
            <span>{tabLabel}</span>
          </NavLink>
        ))}
      </nav>
      {children}
    </div>
  );
}

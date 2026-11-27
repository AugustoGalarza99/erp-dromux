import { NavLink } from "react-router-dom";
import {
  ArrowRightLeft,
  Boxes,
  ClipboardList,
  LayoutGrid,
  Truck,
  Warehouse,
} from "lucide-react";
import { useAuth } from "../../../compartido/contextos/AuthContext";
import "./stock.css";

/*
 * Cabecera común del módulo Stock: título, descripción, acciones y pestañas
 * hacia todas las pantallas. Las pestañas respetan los permisos de lectura
 * (el servidor es quien realmente autoriza).
 */
const tabs = [
  { to: "/inventory", label: "Resumen", icon: LayoutGrid, end: true, any: ["stock", "items"] },
  { to: "/inventory/items", label: "Ítems", icon: Boxes, any: ["items"] },
  { to: "/inventory/stock", label: "Stock por depósito", icon: Warehouse, any: ["stock"] },
  { to: "/inventory/movements", label: "Movimientos", icon: ArrowRightLeft, any: ["stock"] },
  { to: "/inventory/delivery-notes", label: "Remitos", icon: Truck, any: ["stock"] },
];

export default function StockShell({ title, description, actions, children }) {
  const { can } = useAuth();
  const visible = tabs.filter((tab) => tab.any.some((resource) => can(resource, "ver")));

  return (
    <div className="stock-shell">
      <header className="stock-shell-head">
        <div>
          <span className="stock-shell-eyebrow">
            <ClipboardList size={14} aria-hidden="true" /> Stock
          </span>
          <h1>{title}</h1>
          {description && <p>{description}</p>}
        </div>
        {actions && <div className="stock-shell-actions">{actions}</div>}
      </header>
      <nav className="stock-tabs" aria-label="Secciones de Stock">
        {visible.map(({ to, label, icon: Icon, end }) => (
          <NavLink key={to} to={to} end={end} className="stock-tab">
            <Icon size={16} aria-hidden="true" />
            <span>{label}</span>
          </NavLink>
        ))}
      </nav>
      {children}
    </div>
  );
}

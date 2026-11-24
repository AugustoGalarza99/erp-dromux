import {
  BarChart3,
  CalendarRange,
  ClipboardList,
  Factory,
  FlaskConical,
  LayoutGrid,
  PackageCheck,
  PackageOpen,
  TrendingUp,
} from "lucide-react";
import ModuleShell from "../../components/ModuleShell";
import "./production.css";

/* Pantallas de Producción. Los nombres son neutros: sirven a cualquier rubro que fabrique. */
const tabs = [
  { to: "/production", label: "Resumen", icon: LayoutGrid, end: true, any: ["production"] },
  { to: "/production/orders", label: "Órdenes", icon: ClipboardList, any: ["production"] },
  { to: "/production/formulas", label: "Fórmulas", icon: FlaskConical, any: ["production"] },
  { to: "/production/planning", label: "Planificación", icon: CalendarRange, any: ["production"] },
  { to: "/production/availability", label: "¿Alcanza el stock?", icon: PackageCheck, any: ["production"] },
  { to: "/production/replenishment", label: "Reposición", icon: TrendingUp, any: ["production"] },
  { to: "/production/packaging", label: "Envases", icon: PackageOpen, any: ["production"] },
  { to: "/production/stats", label: "Estadística", icon: BarChart3, any: ["production"] },
];

export default function ProductionShell({ title, description, actions, children }) {
  return (
    <ModuleShell
      className="production-shell"
      label="Producción"
      labelIcon={Factory}
      tabs={tabs}
      title={title}
      description={description}
      actions={actions}
    >
      {children}
    </ModuleShell>
  );
}

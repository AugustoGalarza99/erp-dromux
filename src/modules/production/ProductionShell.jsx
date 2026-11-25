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
  { to: "/production", label: "Resumen", icon: LayoutGrid, end: true, any: ["production_overview"] },
  { to: "/production/orders", label: "Órdenes", icon: ClipboardList, any: ["production_orders"] },
  { to: "/production/formulas", label: "Fórmulas", icon: FlaskConical, any: ["production_formulas"] },
  { to: "/production/planning", label: "Planificación", icon: CalendarRange, any: ["production_planning"] },
  { to: "/production/availability", label: "¿Alcanza el stock?", icon: PackageCheck, any: ["production_availability"] },
  { to: "/production/replenishment", label: "Reposición", icon: TrendingUp, any: ["production_replenishment"] },
  { to: "/production/packaging", label: "Envases", icon: PackageOpen, any: ["production_packaging"] },
  { to: "/production/stats", label: "Estadística", icon: BarChart3, any: ["production_stats"] },
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

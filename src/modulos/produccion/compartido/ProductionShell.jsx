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
import ModuleShell from "../../../compartido/componentes/ModuleShell";
import "./production.css";

/* Pantallas de Producción. Los nombres son neutros: sirven a cualquier rubro que fabrique. */
const tabs = [
  { to: "/production", label: "Resumen", icon: LayoutGrid, end: true, any: ["produccion_resumen"] },
  { to: "/production/orders", label: "Órdenes", icon: ClipboardList, any: ["produccion_ordenes"] },
  { to: "/production/formulas", label: "Fórmulas", icon: FlaskConical, any: ["produccion_formulas"] },
  { to: "/production/planning", label: "Planificación", icon: CalendarRange, any: ["produccion_planificacion"] },
  { to: "/production/availability", label: "¿Alcanza el stock?", icon: PackageCheck, any: ["produccion_disponibilidad"] },
  { to: "/production/replenishment", label: "Reposición", icon: TrendingUp, any: ["produccion_reposicion"] },
  { to: "/production/packaging", label: "Envases", icon: PackageOpen, any: ["produccion_envasado"] },
  { to: "/production/stats", label: "Estadística", icon: BarChart3, any: ["produccion_estadistica"] },
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

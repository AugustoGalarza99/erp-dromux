import { ContactRound, FileText, LayoutGrid, ShoppingBag, Tags, Wallet } from "lucide-react";
import ModuleShell from "../../../compartido/componentes/ModuleShell";
import "./salesModule.css";

/*
 * Pantallas de Ventas. Vocabulario neutro: sirve a cualquier rubro que venda lo que fabrica.
 * Los presupuestos y las ofertas por cantidad se agregan como pestañas cuando existan (migración 040).
 */
const tabs = [
  { to: "/sales", label: "Resumen", icon: LayoutGrid, end: true, any: ["ventas"] },
  { to: "/sales/orders", label: "Registrar venta", icon: Wallet, any: ["ventas"] },
  { to: "/sales/quotes", label: "Presupuestos", icon: FileText, any: ["ventas"] },
  { to: "/sales/customers", label: "Clientes", icon: ContactRound, any: ["ventas"] },
  { to: "/sales/lista-precios", label: "Listas de precios", icon: Tags, any: ["ventas"] },
];

export default function SalesShell({ title, description, actions, children }) {
  return (
    <ModuleShell
      className="sales-shell"
      label="Ventas"
      labelIcon={ShoppingBag}
      tabs={tabs}
      title={title}
      description={description}
      actions={actions}
    >
      {children}
    </ModuleShell>
  );
}

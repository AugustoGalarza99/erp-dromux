import { ContactRound, FileText, LayoutGrid, ShoppingBag, Tags, Wallet } from "lucide-react";
import ModuleShell from "../../components/ModuleShell";
import "./salesModule.css";

/*
 * Pantallas de Ventas. Vocabulario neutro: sirve a cualquier rubro que venda lo que fabrica.
 * Los presupuestos y las ofertas por cantidad se agregan como pestañas cuando existan (migración 040).
 */
const tabs = [
  { to: "/sales", label: "Resumen", icon: LayoutGrid, end: true, any: ["sales"] },
  { to: "/sales/orders", label: "Registrar venta", icon: Wallet, any: ["sales"] },
  { to: "/sales/quotes", label: "Presupuestos", icon: FileText, any: ["sales"] },
  { to: "/sales/customers", label: "Clientes", icon: ContactRound, any: ["sales"] },
  { to: "/sales/lista-precios", label: "Listas de precios", icon: Tags, any: ["sales"] },
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

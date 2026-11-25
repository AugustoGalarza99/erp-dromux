import { ClipboardList, LayoutGrid, ReceiptText, ShoppingCart, Store, Wallet } from "lucide-react";
import ModuleShell from "../../components/ModuleShell";
import "./purchasesModule.css";

/*
 * Pantallas de Compras. Vocabulario neutro: sirve a cualquier rubro que compre materiales.
 * Cada pantalla se habilita por separado (permisos por pantalla, migración 046).
 */
const tabs = [
  { to: "/purchases", label: "Resumen", icon: LayoutGrid, end: true, any: ["purchases_overview"] },
  { to: "/purchases/requests", label: "Pedidos internos", icon: ClipboardList, any: ["purchase_requests"] },
  { to: "/purchases/orders", label: "Órdenes de compra", icon: ShoppingCart, any: ["purchases_orders"] },
  { to: "/purchases/suppliers", label: "Proveedores", icon: Store, any: ["purchases_suppliers"] },
  { to: "/purchases/accounts", label: "Compras y cuentas", icon: Wallet, any: ["purchases_accounts"] },
];

export default function PurchasesShell({ title, description, actions, children }) {
  return (
    <ModuleShell
      className="purchases-shell"
      label="Compras"
      labelIcon={ReceiptText}
      tabs={tabs}
      title={title}
      description={description}
      actions={actions}
    >
      {children}
    </ModuleShell>
  );
}

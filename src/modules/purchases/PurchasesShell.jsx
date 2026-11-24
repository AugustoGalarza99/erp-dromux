import { ClipboardList, LayoutGrid, ReceiptText, ShoppingCart, Store, Wallet } from "lucide-react";
import ModuleShell from "../../components/ModuleShell";
import "./purchasesModule.css";

/*
 * Pantallas de Compras. Vocabulario neutro: sirve a cualquier rubro que compre materiales.
 * "Pedidos internos" también la ve quien solo puede pedir (sin permiso de Compras).
 */
const tabs = [
  { to: "/purchases", label: "Resumen", icon: LayoutGrid, end: true, any: ["purchases"] },
  { to: "/purchases/requests", label: "Pedidos internos", icon: ClipboardList, any: ["purchases", "purchase_requests"] },
  { to: "/purchases/orders", label: "Órdenes de compra", icon: ShoppingCart, any: ["purchases"] },
  { to: "/purchases/suppliers", label: "Proveedores", icon: Store, any: ["purchases"] },
  { to: "/purchases/accounts", label: "Compras y cuentas", icon: Wallet, any: ["purchases"] },
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

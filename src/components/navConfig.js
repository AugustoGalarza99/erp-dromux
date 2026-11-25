import {
  BarChart3,
  Boxes,
  Factory,
  LayoutDashboard,
  Settings2,
  ShoppingBag,
  ShoppingCart,
  Wallet,
} from "lucide-react";

/*
 * Mapa único de navegación: lo usan el menú lateral, las migas de pan y la
 * búsqueda global. Los permisos son solo de presentación; el servidor decide.
 * `module` coincide con los tokens `--mod-*` de uiFoundation.css.
 */
export const navGroups = [
  {
    title: "Inicio",
    modules: [
      {
        id: "home",
        label: "Inicio",
        icon: LayoutDashboard,
        permission: "dashboard",
        to: "/",
        shortcut: "i",
        keywords: "tablero resumen panel",
      },
    ],
  },
  {
    title: "Operación",
    modules: [
      {
        id: "stock",
        label: "Stock",
        icon: Boxes,
        permission: "inventory",
        shortcut: "s",
        keywords: "inventario depósito existencias",
        children: [
          { label: "Resumen de stock", to: "/inventory", permission: "inventory", crumb: "Resumen", keywords: "panel general" },
          { label: "Todos los ítems", to: "/inventory/items", permission: "items", crumb: "Ítems", keywords: "productos materiales articulos" },
          { label: "Materias primas", to: "/inventory/items?type=raw_material", permission: "items", crumb: "Materias primas", keywords: "insumos" },
          { label: "Productos", to: "/inventory/items?type=finished_product", permission: "items", crumb: "Productos", keywords: "terminados" },
          { label: "Stock por depósito", to: "/inventory/stock", permission: "stock_levels", keywords: "existencias saldo" },
          { label: "Movimientos", to: "/inventory/movements", permission: "stock_movements", keywords: "historial entradas salidas" },
          { label: "Remitos de entrega", to: "/inventory/delivery-notes", permission: "stock_delivery_notes", crumb: "Remitos", keywords: "remito entrega" },
        ],
      },
      {
        id: "production",
        label: "Producción",
        icon: Factory,
        permission: "production",
        shortcut: "p",
        keywords: "fabricación",
        children: [
          { label: "Resumen de producción", to: "/production", permission: "production_overview", crumb: "Resumen", keywords: "panel general" },
          { label: "Órdenes de fabricación", to: "/production/orders", permission: "production_orders", keywords: "orden produccion fabricar" },
          { label: "Fórmulas", to: "/production/formulas", permission: "production_formulas", keywords: "receta" },
          { label: "Planificación", to: "/production/planning", permission: "production_planning", keywords: "plan" },
          { label: "¿Alcanza el stock para fabricar?", to: "/production/availability", permission: "production_availability", crumb: "¿Alcanza el stock?", keywords: "faltantes disponibilidad tengo stock" },
          { label: "Pronóstico y reposición", to: "/production/replenishment", permission: "production_replenishment", crumb: "Reposición", keywords: "reponer comprar" },
          { label: "Envases y presentaciones", to: "/production/packaging", permission: "production_packaging", crumb: "Envases", keywords: "envasado envase presentación embalaje" },
          { label: "Estadística de producción", to: "/production/stats", permission: "production_stats", crumb: "Estadística", keywords: "producido mes semana rango cuánto se produjo informe" },
        ],
      },
    ],
  },
  {
    title: "Comercial",
    modules: [
      {
        id: "sales",
        label: "Ventas",
        icon: ShoppingBag,
        permission: "sales",
        shortcut: "v",
        keywords: "vender clientes",
        children: [
          { label: "Resumen de ventas", to: "/sales", permission: "sales", crumb: "Resumen", keywords: "panel general" },
          { label: "Presupuestos", to: "/sales/quotes", permission: "sales", keywords: "cotizacion cotizar presupuestar pdf cliente" },
          { label: "Clientes", to: "/sales/customers", permission: "sales" },
          { label: "Listas de precios", to: "/sales/lista-precios", permission: "sales", crumb: "Listas de precios", keywords: "precios margen costo mayorista minorista descuento iva importar" },
          { label: "Registrar venta", to: "/sales/orders", permission: "sales", crumb: "Ventas", keywords: "nueva venta cobrar" },
        ],
      },
      {
        id: "purchases",
        label: "Compras",
        icon: ShoppingCart,
        permission: "purchases",
        shortcut: "c",
        keywords: "proveedores comprar",
        children: [
          { label: "Resumen de compras", to: "/purchases", permission: "purchases_overview", crumb: "Resumen", keywords: "panel general" },
          { label: "Pedidos internos", to: "/purchases/requests", permission: "purchase_requests", crumb: "Pedidos internos", keywords: "solicitud pedir necesito falta material operario" },
          { label: "Órdenes de compra", to: "/purchases/orders", permission: "purchases_orders", keywords: "recepción recibir comprar pedido" },
          { label: "Proveedores", to: "/purchases/suppliers", permission: "purchases_suppliers", keywords: "cotización precios" },
          { label: "Compras y cuentas", to: "/purchases/accounts", permission: "purchases_accounts", crumb: "Compras y cuentas", keywords: "deuda pagos proveedor estadísticas" },
        ],
      },
    ],
  },
  {
    title: "Finanzas",
    modules: [
      {
        id: "finance",
        label: "Finanzas",
        icon: Wallet,
        permission: "finance",
        shortcut: "f",
        keywords: "tesorería dinero caja",
        children: [
          { label: "Cuentas por cobrar", to: "/finance/receivables", permission: "finance", keywords: "cobros deudores" },
          { label: "Tesorería", to: "/finance/treasury", permission: "finance", keywords: "caja bancos saldos" },
          { label: "Rentabilidad y precios", to: "/finance/costs", permission: "finance", adminOnly: true, keywords: "margen ganancia costos" },
        ],
      },
    ],
  },
  {
    title: "Análisis",
    modules: [
      {
        id: "reports",
        label: "Reportes",
        icon: BarChart3,
        permission: "reports",
        shortcut: "r",
        keywords: "informes estadísticas",
        children: [
          { label: "Resumen por período", to: "/reports", permission: "reports", crumb: "Reportes" },
        ],
      },
    ],
  },
  {
    title: "Administración",
    modules: [
      {
        id: "settings",
        label: "Ajustes",
        icon: Settings2,
        permission: "settings",
        shortcut: "a",
        keywords: "configuración",
        children: [
          { label: "Documentos de producción", to: "/settings/production-documents", permission: "production_documents", keywords: "pdf hoja" },
          { label: "Archivados", to: "/archivados", permission: "settings" },
          { label: "Usuarios", to: "/settings/users", permission: "users", adminOnly: true },
          { label: "Roles y permisos", to: "/settings/roles", permission: "roles", keywords: "accesos", adminOnly: true },
          { label: "Unidades", to: "/settings/units", permission: "units" },
          { label: "Categorías", to: "/settings/categories", permission: "categories" },
          { label: "Depósitos", to: "/settings/warehouses", permission: "warehouses", keywords: "almacén" },
        ],
      },
    ],
  },
];

/* Páginas sueltas que no son un módulo del menú. */
export const extraPages = [
  { label: "Actualizaciones", to: "/actualizaciones", module: "settings", keywords: "novedades versión" },
  { label: "Mi perfil", to: "/mi-perfil", module: "settings", keywords: "contraseña cuenta" },
  { label: "Guía de uso", to: "/ayuda", module: "home", keywords: "ayuda tutorial pasos" },
];

export const pathOf = (to) => to.split("?")[0];

/* Devuelve { group, module, page } para una ruta, o null si no se reconoce. */
export function locate(pathname) {
  for (const group of navGroups) {
    for (const module of group.modules) {
      if (module.to && pathOf(module.to) === pathname) {
        return { group, module, page: null };
      }
      const page = module.children?.find(
        (child) => pathOf(child.to) === pathname,
      );
      if (page) return { group, module, page };
    }
  }
  if (pathname.startsWith("/inventory/items/")) {
    const group = navGroups[1];
    return {
      group,
      module: group.modules[0],
      page: pathname === "/inventory/items/new"
        ? { label: "Nuevo ítem", crumb: "Nuevo ítem", to: "/inventory/items" }
        : { label: "Ficha de ítem", crumb: "Ficha de ítem", to: "/inventory/items" },
    };
  }
  const extra = extraPages.find((page) => page.to === pathname);
  if (extra) {
    for (const group of navGroups) {
      const module = group.modules.find((entry) => entry.id === extra.module);
      if (module) return { group, module, page: extra };
    }
  }
  return null;
}

/* Una pantalla puede habilitarla uno o varios recursos (`permission` o `any: [...]`). */
export function canSeeChild(child, { can, role }) {
  if (child.adminOnly && role !== "admin") return false;
  const resources = child.any ?? [child.permission];
  return resources.some((resource) => can(resource, "read"));
}

/* Entradas planas para la búsqueda global. Lo que el rol no puede abrir se lista igual, bloqueado (`locked`), y va después. */
export function searchEntries({ can, role }) {
  const entries = [];
  for (const group of navGroups) {
    for (const module of group.modules) {
      const allowedChildren = (module.children ?? []).filter(
        (child) => canSeeChild(child, { can, role }),
      );
      if (module.to) {
        entries.push({
          locked: !can(module.permission, "read"),
          label: module.label,
          to: module.to,
          module: module.id,
          area: group.title,
          icon: module.icon,
          shortcut: module.shortcut,
          keywords: module.keywords ?? "",
        });
      }
      (module.children ?? []).forEach((child) => {
        const index = allowedChildren.indexOf(child);
        entries.push({
          locked: index < 0,
          label: child.label,
          to: child.to,
          module: module.id,
          area: `${group.title} · ${module.label}`,
          icon: module.icon,
          // El atajo "g + letra" abre la primera pantalla permitida del módulo.
          shortcut: index === 0 ? module.shortcut : undefined,
          keywords: `${module.label} ${module.keywords ?? ""} ${child.keywords ?? ""}`,
        });
      });
    }
  }
  for (const page of extraPages) {
    entries.push({
      label: page.label,
      to: page.to,
      module: page.module,
      area: "General",
      keywords: page.keywords ?? "",
    });
  }
  // Lo permitido primero; el orden del menú se conserva dentro de cada grupo.
  return [...entries.filter((entry) => !entry.locked), ...entries.filter((entry) => entry.locked)];
}

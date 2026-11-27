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
        permission: "inicio",
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
        permission: "inventario",
        shortcut: "s",
        keywords: "inventario depósito existencias",
        children: [
          { label: "Resumen de stock", to: "/inventory", permission: "inventario", crumb: "Resumen", keywords: "panel general" },
          { label: "Todos los ítems", to: "/inventory/items", permission: "items", crumb: "Ítems", keywords: "productos materiales articulos" },
          { label: "Materias primas", to: "/inventory/items?type=materia_prima", permission: "items", crumb: "Materias primas", keywords: "insumos" },
          { label: "Productos", to: "/inventory/items?type=producto_terminado", permission: "items", crumb: "Productos", keywords: "terminados" },
          { label: "Stock por depósito", to: "/inventory/stock", permission: "stock_saldos", keywords: "existencias saldo" },
          { label: "Movimientos", to: "/inventory/movements", permission: "stock_movimientos", keywords: "historial entradas salidas" },
          { label: "Remitos de entrega", to: "/inventory/delivery-notes", permission: "stock_remitos", crumb: "Remitos", keywords: "remito entrega" },
        ],
      },
      {
        id: "production",
        label: "Producción",
        icon: Factory,
        permission: "produccion",
        shortcut: "p",
        keywords: "fabricación",
        children: [
          { label: "Resumen de producción", to: "/production", permission: "produccion_resumen", crumb: "Resumen", keywords: "panel general" },
          { label: "Órdenes de fabricación", to: "/production/orders", permission: "produccion_ordenes", keywords: "orden produccion fabricar" },
          { label: "Fórmulas", to: "/production/formulas", permission: "produccion_formulas", keywords: "receta" },
          { label: "Planificación", to: "/production/planning", permission: "produccion_planificacion", keywords: "plan" },
          { label: "¿Alcanza el stock para fabricar?", to: "/production/availability", permission: "produccion_disponibilidad", crumb: "¿Alcanza el stock?", keywords: "faltantes disponibilidad tengo stock" },
          { label: "Pronóstico y reposición", to: "/production/replenishment", permission: "produccion_reposicion", crumb: "Reposición", keywords: "reponer comprar" },
          { label: "Envases y presentaciones", to: "/production/packaging", permission: "produccion_envasado", crumb: "Envases", keywords: "envasado envase presentación embalaje" },
          { label: "Estadística de producción", to: "/production/stats", permission: "produccion_estadistica", crumb: "Estadística", keywords: "producido mes semana rango cuánto se produjo informe" },
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
        permission: "ventas",
        shortcut: "v",
        keywords: "vender clientes",
        children: [
          { label: "Resumen de ventas", to: "/sales", permission: "ventas", crumb: "Resumen", keywords: "panel general" },
          { label: "Presupuestos", to: "/sales/quotes", permission: "ventas", keywords: "cotizacion cotizar presupuestar pdf cliente" },
          { label: "Clientes", to: "/sales/customers", permission: "ventas" },
          { label: "Listas de precios", to: "/sales/lista-precios", permission: "ventas", crumb: "Listas de precios", keywords: "precios margen costo mayorista minorista descuento iva importar" },
          { label: "Registrar venta", to: "/sales/orders", permission: "ventas", crumb: "Ventas", keywords: "nueva venta cobrar" },
        ],
      },
      {
        id: "purchases",
        label: "Compras",
        icon: ShoppingCart,
        permission: "compras",
        shortcut: "c",
        keywords: "proveedores comprar",
        children: [
          { label: "Resumen de compras", to: "/purchases", permission: "compras_resumen", crumb: "Resumen", keywords: "panel general" },
          { label: "Pedidos internos", to: "/purchases/requests", permission: "compras_pedidos", crumb: "Pedidos internos", keywords: "solicitud pedir necesito falta material operario" },
          { label: "Órdenes de compra", to: "/purchases/orders", permission: "compras_ordenes", keywords: "recepción recibir comprar pedido" },
          { label: "Proveedores", to: "/purchases/suppliers", permission: "compras_proveedores", keywords: "cotización precios" },
          { label: "Compras y cuentas", to: "/purchases/accounts", permission: "compras_cuentas", crumb: "Compras y cuentas", keywords: "deuda pagos proveedor estadísticas" },
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
        permission: "finanzas",
        shortcut: "f",
        keywords: "tesorería dinero caja",
        children: [
          { label: "Cuentas por cobrar", to: "/finance/receivables", permission: "finanzas", keywords: "cobros deudores" },
          { label: "Tesorería", to: "/finance/treasury", permission: "finanzas", keywords: "caja bancos saldos" },
          { label: "Rentabilidad y precios", to: "/finance/costs", permission: "finanzas", adminOnly: true, keywords: "margen ganancia costos" },
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
        permission: "reportes",
        shortcut: "r",
        keywords: "informes estadísticas",
        children: [
          { label: "Resumen por período", to: "/reports", permission: "reportes", crumb: "Reportes" },
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
        permission: "ajustes",
        shortcut: "a",
        keywords: "configuración",
        children: [
          { label: "Documentos de producción", to: "/settings/production-documents", permission: "produccion_documentos", keywords: "pdf hoja" },
          { label: "Archivados", to: "/archivados", permission: "ajustes" },
          { label: "Usuarios", to: "/settings/users", permission: "usuarios", adminOnly: true },
          { label: "Roles y permisos", to: "/settings/roles", permission: "roles", keywords: "accesos", adminOnly: true },
          { label: "Unidades", to: "/settings/units", permission: "unidades" },
          { label: "Categorías", to: "/settings/categories", permission: "categorias" },
          { label: "Depósitos", to: "/settings/warehouses", permission: "depositos", keywords: "almacén" },
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
  if (child.adminOnly && role !== "administrador") return false;
  const resources = child.any ?? [child.permission];
  return resources.some((resource) => can(resource, "ver"));
}

/* true si la empresa no contrató ningún módulo que habilite la entrada. */
export function fueraDelPlan(entry, planIncluye) {
  const resources = entry.any ?? [entry.permission];
  return !resources.some((resource) => planIncluye(resource));
}

/* Entradas planas para la búsqueda global. Lo que el rol no puede abrir se lista igual, bloqueado (`locked`), y va después. */
export function searchEntries({ can, role, planIncluye }) {
  const entries = [];
  for (const group of navGroups) {
    for (const module of group.modules) {
      const allowedChildren = (module.children ?? []).filter(
        (child) => canSeeChild(child, { can, role }),
      );
      if (module.to) {
        entries.push({
          locked: !can(module.permission, "ver"),
          planLocked: fueraDelPlan(module, planIncluye),
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
          planLocked: fueraDelPlan(child, planIncluye),
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

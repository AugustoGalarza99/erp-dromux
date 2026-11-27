import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import {
  AlertTriangle,
  ArrowUpRight,
  CheckCircle2,
  Coins,
  Plus,
  ShoppingBag,
  Tags,
  TrendingDown,
  Wallet,
} from "lucide-react";
import { useAuth } from "../../../compartido/contextos/AuthContext";
import { friendlyError } from "../../../compartido/utilidades/notifications";
import { isMissingFunction, money } from "../compartido/pricing";
import { listAdminPriceRows, listPriceLists, listPriceRows } from "../listas-precios/priceLists";
import { getSalesSummary } from "../compartido/sales";
import SalesShell from "../compartido/SalesShell";

const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

/* Resumen de Ventas: qué se vendió, qué falta cobrar y qué precios requieren atención. */
export default function SalesOverview() {
  const { activeCompanyId, user, can, role } = useAuth();
  const scope = [user?.id, activeCompanyId];
  const enabled = Boolean(activeCompanyId) && can("sales", "read");
  const isAdmin = role === "admin" && can("finance", "read");

  const summary = useQuery({
    queryKey: ["erp-dashboard", ...scope],
    queryFn: () => getSalesSummary(activeCompanyId),
    enabled,
    staleTime: 30_000,
  });
  // Si la base todavía no tiene las listas (migración 039), se omite sin error.
  const lists = useQuery({
    queryKey: ["price-lists", ...scope],
    queryFn: () => listPriceLists(activeCompanyId),
    enabled,
    retry: false,
    staleTime: 60_000,
  });
  const active = (lists.data ?? []).filter((list) => !list.archived);
  const defaultList = active.find((list) => list.is_default) ?? null;
  const hasLists = lists.isSuccess;

  const missing = useQuery({
    queryKey: ["price-rows", ...scope, defaultList?.id, "overview-missing"],
    queryFn: () => listPriceRows(activeCompanyId, defaultList.id, { missingOnly: true, pageSize: 1 }),
    enabled: enabled && Boolean(defaultList),
    retry: false,
    staleTime: 60_000,
  });
  const lowMargin = useQuery({
    queryKey: ["price-rows", ...scope, defaultList?.id, "overview-low"],
    queryFn: () => listAdminPriceRows(activeCompanyId, defaultList.id, { filter: "low_margin", pageSize: 1 }),
    enabled: enabled && isAdmin && Boolean(defaultList),
    retry: false,
    staleTime: 60_000,
  });
  const costChanged = useQuery({
    queryKey: ["price-rows", ...scope, defaultList?.id, "overview-cost"],
    queryFn: () => listAdminPriceRows(activeCompanyId, defaultList.id, { filter: "cost_changed", pageSize: 1 }),
    enabled: enabled && isAdmin && Boolean(defaultList),
    retry: false,
    staleTime: 60_000,
  });

  const data = summary.data ?? {};
  const missingCount = Number(missing.data?.[0]?.total_count ?? 0);
  const lowCount = Number(lowMargin.data?.[0]?.total_count ?? 0);
  const costCount = Number(costChanged.data?.[0]?.total_count ?? 0);
  const listsMissingFunction = isMissingFunction(lists.error);
  const error = summary.error || (lists.error && !listsMissingFunction ? lists.error : null);

  const decisions = [];
  if (isAdmin && hasLists && !defaultList) {
    decisions.push({
      key: "default", level: "attention", icon: Tags, to: "/sales/lista-precios",
      title: active.length ? "No hay una lista de precios predeterminada" : "Todavía no creaste una lista de precios",
      ask: "Creá una lista (por ejemplo Mayorista o Minorista) y marcala como predeterminada para cargar los precios.",
    });
  }
  if (missingCount > 0) {
    decisions.push({
      key: "missing", level: "attention", icon: Coins, to: "/sales/lista-precios?filter=missing",
      title: plural(missingCount, "producto sin precio en la lista predeterminada", "productos sin precio en la lista predeterminada"),
      ask: "Sin precio no se pueden vender. Cargalos a mano o importalos desde una planilla.",
    });
  }
  if (lowCount > 0) {
    decisions.push({
      key: "low", level: "urgent", icon: TrendingDown, to: "/sales/lista-precios?filter=low_margin",
      title: plural(lowCount, "producto con margen por debajo del mínimo", "productos con margen por debajo del mínimo"),
      ask: "Revisá el precio o el costo antes de seguir vendiendo a ese valor.",
    });
  }
  if (costCount > 0) {
    decisions.push({
      key: "cost", level: "attention", icon: AlertTriangle, to: "/sales/lista-precios?filter=cost_changed",
      title: plural(costCount, "producto cuyo costo cambió desde que fijaste el precio", "productos cuyo costo cambió desde que fijaste el precio"),
      ask: "Recalculá los precios desde el costo vigente con vista previa antes de aplicar.",
    });
  }
  const rank = { urgent: 0, attention: 1, info: 2 };
  decisions.sort((a, b) => rank[a.level] - rank[b.level]);
  const levelText = { urgent: "Urgente", attention: "Requiere atención", info: "Para organizar" };
  const loading = summary.isPending || lists.isPending;

  const kpis = [
    { key: "sales", label: "Ventas (30 días)", icon: ShoppingBag, value: summary.isSuccess ? Number(data.sales_30d ?? 0) : "…",
      note: "Registradas en el último mes", to: "/sales/orders" },
    { key: "revenue", label: "Facturado (30 días)", icon: Coins, value: summary.isSuccess ? money(data.revenue_30d ?? 0) : "…",
      note: "Total de ventas del período", to: "/sales/orders" },
    ...(data.receivables != null ? [{ key: "receivable", label: "Por cobrar", icon: Wallet, value: money(data.receivables),
      note: "Ventas con saldo pendiente", to: "/finance/receivables" }] : []),
    ...(hasLists ? [{ key: "lists", label: "Listas de precios", icon: Tags, value: active.length,
      note: defaultList ? `Predeterminada: ${defaultList.name}` : "Sin predeterminada", to: "/sales/lista-precios" }] : []),
    ...(defaultList ? [{ key: "nopr", label: "Sin precio", icon: AlertTriangle, warn: missingCount > 0,
      value: missing.isSuccess ? missingCount : "…", note: "Productos sin precio en la predeterminada", to: "/sales/lista-precios?filter=missing" }] : []),
  ];

  return (
    <SalesShell
      title="Resumen de ventas"
      description="Cómo viene la venta, qué falta cobrar y qué precios conviene revisar. Desde acá llegás a cada pantalla del módulo."
      actions={can("sales", "insert") && (
        <Link className="button primary" to="/sales/orders">
          <Plus size={17} aria-hidden="true" /> Registrar venta
        </Link>
      )}
    >
      {error && <p role="alert" className="error">{friendlyError(error)}</p>}
      {listsMissingFunction && (
        <p className="mod-hint" role="note">
          Las listas de precios múltiples todavía no están activas en este entorno. Mientras tanto se usa un único precio por producto.
        </p>
      )}

      <div className="mod-kpis">
        {kpis.map(({ key, label, value, icon: Icon, note, to, warn }) => (
          <Link key={key} to={to} className={`mod-kpi ${warn ? "is-warn" : ""}`}>
            <span className="mod-kpi-top">
              <span className="mod-kpi-icon"><Icon size={18} aria-hidden="true" /></span>
              {label}
            </span>
            <strong>{value}</strong>
            <small>{note}</small>
          </Link>
        ))}
      </div>

      <section className="mod-card" aria-labelledby="sales-decisions">
        <div className="mod-card-head">
          <h2 id="sales-decisions">Para decidir hoy</h2>
          <span className={`mod-chip ${decisions.some((d) => d.level === "urgent") ? "is-urgent" : decisions.length ? "" : "is-ok"}`}>
            {loading ? "Revisando…" : decisions.length ? plural(decisions.length, "tema", "temas") : "Al día"}
          </span>
        </div>
        {!loading && !decisions.length && (
          <p className="mod-allgood">
            <CheckCircle2 size={20} aria-hidden="true" />
            <span><strong>Sin pendientes.</strong> Los precios están cargados y los márgenes dentro de lo esperado.</span>
          </p>
        )}
        <ul className="mod-decisions">
          {decisions.map(({ key, level, icon: Icon, to, title, ask }) => (
            <li key={key}>
              <Link to={to} className={`mod-decision is-${level}`}>
                <span className="mod-decision-icon"><Icon size={19} aria-hidden="true" /></span>
                <span className="mod-decision-text">
                  <small>{levelText[level]}</small>
                  <strong>{title}</strong>
                  <span>{ask}</span>
                </span>
                <ArrowUpRight size={18} aria-hidden="true" />
              </Link>
            </li>
          ))}
        </ul>
      </section>
    </SalesShell>
  );
}

import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import {
  AlertOctagon,
  ArrowUpRight,
  CheckCircle2,
  ClipboardList,
  Clock3,
  HandCoins,
  PackageCheck,
  Plus,
  ShoppingCart,
  Store,
  Wallet,
} from "lucide-react";
import { useAuth } from "../../contexts/AuthContext";
import { friendlyError } from "../../lib/notifications";
import { dateEs } from "../../lib/display";
import { listPurchaseOrdersPage } from "../../services/purchases";
import { listPurchaseRequests } from "../../services/purchaseRequests";
import { getReplenishmentForecast } from "../../services/replenishment";
import { paymentOrders } from "../../services/supplierFinance";
import PurchasesShell from "./PurchasesShell";

const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
const daysSince = (iso) => Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000));

/* Avance de una orden: cuántas líneas ya llegaron completas. */
export function receivedLines(order) {
  const lines = order.lines ?? [];
  const done = lines.filter((line) => Number(line.received_quantity ?? 0) >= Number(line.quantity) - 0.000001).length;
  return { done, total: lines.length };
}

/* Resumen de Compras: qué hay que recibir, qué reponer y qué pagos esperan confirmación. */
export default function PurchasesOverview() {
  const { activeCompanyId, user, can } = useAuth();
  const scope = [user?.id, activeCompanyId];
  const enabled = Boolean(activeCompanyId) && can("purchases_overview", "read");
  // El pronóstico lo exige el servidor con el módulo completo de Compras (pasa a Producción en 047).
  const canForecast = enabled && can("production_replenishment", "read") && can("stock", "read");
  const canFinance = enabled && can("finance", "read") && can("purchases_accounts", "read");

  const open = useQuery({
    queryKey: ["purchase-orders", ...scope, "overview", "open"],
    queryFn: () => listPurchaseOrdersPage(activeCompanyId, 0, "", "open"),
    enabled,
    staleTime: 30_000,
  });
  const partial = useQuery({
    queryKey: ["purchase-orders", ...scope, "overview", "partial"],
    queryFn: () => listPurchaseOrdersPage(activeCompanyId, 0, "", "partial"),
    enabled,
    staleTime: 30_000,
  });
  const forecast = useQuery({
    queryKey: ["replenishment-forecast", ...scope],
    queryFn: () => getReplenishmentForecast(activeCompanyId),
    enabled: canForecast,
    staleTime: 60_000,
  });
  const payments = useQuery({
    queryKey: ["supplier-payments", ...scope, "overview"],
    queryFn: () => paymentOrders(activeCompanyId, 0),
    enabled: canFinance,
    staleTime: 30_000,
  });

  // Pedidos internos pendientes. Si la base todavía no tiene la función (migración 038), se omite sin error.
  const requests = useQuery({
    queryKey: ["purchase-requests", ...scope, "overview"],
    queryFn: () => listPurchaseRequests(activeCompanyId, { page: 0, status: "pending" }),
    enabled: enabled && can("purchase_requests", "read"),
    retry: false,
    staleTime: 30_000,
  });
  const pendingRequests = requests.data?.count ?? 0;
  const urgentRequests = (requests.data?.rows ?? []).filter((row) => row.priority === "urgent").length;

  const toReceive = useMemo(
    () => [...(open.data?.rows ?? []), ...(partial.data?.rows ?? [])]
      .sort((a, b) => new Date(a.created_at) - new Date(b.created_at)),
    [open.data, partial.data],
  );
  const openCount = open.data?.count ?? 0;
  const partialCount = partial.data?.count ?? 0;
  const old = toReceive.filter((order) => daysSince(order.created_at) >= 14);

  const suggestions = useMemo(() => {
    const rows = (forecast.data ?? []).filter(
      (row) => row.alert_level !== "ok" && Number(row.suggested_quantity) > 0,
    );
    const groups = new Map();
    rows.forEach((row) => {
      const key = row.supplier_id ?? "none";
      const group = groups.get(key) ?? {
        id: row.supplier_id, name: row.supplier_name ?? "Sin proveedor asignado", count: 0, urgent: 0,
      };
      group.count += 1;
      if (row.alert_level === "critical") group.urgent += 1;
      groups.set(key, group);
    });
    return [...groups.values()].sort((a, b) => b.urgent - a.urgent || b.count - a.count);
  }, [forecast.data]);
  const urgentTotal = suggestions.reduce((sum, group) => sum + group.urgent, 0);
  const withoutSupplier = suggestions.find((group) => !group.id);
  const drafts = (payments.data?.rows ?? []).filter((row) => row.status === "draft");

  const loading = open.isPending || partial.isPending;
  const error = open.error || partial.error || forecast.error || payments.error;

  const decisions = [];
  if (pendingRequests > 0) {
    decisions.push({
      key: "requests", level: urgentRequests > 0 ? "urgent" : "attention", icon: ClipboardList,
      to: "/purchases/requests",
      title: plural(pendingRequests, "pedido interno esperando respuesta", "pedidos internos esperando respuesta")
        + (urgentRequests ? ` (${urgentRequests} urgente${urgentRequests === 1 ? "" : "s"})` : ""),
      ask: "Convertilos en una orden de compra o rechazalos con un motivo para que el equipo sepa qué pasó.",
    });
  }
  if (urgentTotal > 0) {
    decisions.push({
      key: "urgent", level: "urgent", icon: AlertOctagon, to: "/production/replenishment",
      title: plural(urgentTotal, "material urgente sin compra en curso", "materiales urgentes sin compra en curso"),
      ask: "Elegí el proveedor y preparamos la orden con las cantidades sugeridas.",
    });
  }
  if (old.length > 0) {
    decisions.push({
      key: "old", level: "attention", icon: Clock3, to: "/purchases/orders?status=open",
      title: plural(old.length, "orden con más de 14 días sin recibir completa", "órdenes con más de 14 días sin recibir completas"),
      ask: "Reclamá la entrega al proveedor o cancelá lo que ya no necesitás.",
    });
  }
  if (drafts.length > 0) {
    decisions.push({
      key: "drafts", level: "attention", icon: HandCoins, to: "/purchases/accounts",
      title: plural(drafts.length, "pago a proveedor en borrador", "pagos a proveedores en borrador"),
      ask: "Confirmalos cuando el pago esté hecho para que se descuente de Tesorería.",
    });
  }
  if (withoutSupplier) {
    decisions.push({
      key: "nosupplier", level: "info", icon: Store, to: "/purchases/suppliers",
      title: plural(withoutSupplier.count, "material por reponer sin proveedor", "materiales por reponer sin proveedor"),
      ask: "Asociá un proveedor y su precio para poder comprarlos desde acá.",
    });
  }
  const rank = { urgent: 0, attention: 1, info: 2 };
  decisions.sort((a, b) => rank[a.level] - rank[b.level]);
  const levelText = { urgent: "Urgente", attention: "Requiere atención", info: "Para organizar" };

  const kpis = [
    ...(requests.isSuccess ? [{ key: "requests", label: "Pedidos internos", icon: ClipboardList, warn: urgentRequests > 0,
      value: pendingRequests, note: urgentRequests ? `${urgentRequests} urgentes` : "Esperando respuesta", to: "/purchases/requests" }] : []),
    { key: "open", label: "Órdenes abiertas", icon: ShoppingCart, value: open.data ? openCount : "…", note: "Esperando mercadería", to: "/purchases/orders?status=open" },
    { key: "partial", label: "Recepción parcial", icon: PackageCheck, value: partial.data ? partialCount : "…", note: "Llegó una parte, falta el resto", to: "/purchases/orders?status=partial" },
    ...(canForecast ? [{ key: "reorder", label: "Para reponer", icon: AlertOctagon, warn: urgentTotal > 0, value: forecast.data ? suggestions.reduce((s, g) => s + g.count, 0) : "…", note: urgentTotal ? `${urgentTotal} urgentes` : "Con compra sugerida", to: "/production/replenishment" }] : []),
    ...(canFinance ? [{ key: "drafts", label: "Pagos en borrador", icon: Wallet, value: payments.data ? drafts.length : "…", note: "Por confirmar", to: "/purchases/accounts" }] : []),
  ];

  return (
    <PurchasesShell
      title="Resumen de compras"
      description="Qué esperás recibir, qué conviene reponer y qué pagos esperan confirmación. Desde acá llegás a cada pantalla del módulo."
      actions={can("purchases_orders", "insert") && (
        <Link className="button primary" to="/purchases/orders?new=1">
          <Plus size={17} aria-hidden="true" /> Nueva orden de compra
        </Link>
      )}
    >
      {error && <p role="alert" className="error">{friendlyError(error)}</p>}

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

      <section className="mod-card" aria-labelledby="buy-decisions">
        <div className="mod-card-head">
          <h2 id="buy-decisions">Para decidir hoy</h2>
          <span className={`mod-chip ${decisions.some((d) => d.level === "urgent") ? "is-urgent" : decisions.length ? "" : "is-ok"}`}>
            {loading ? "Revisando…" : decisions.length ? plural(decisions.length, "tema", "temas") : "Al día"}
          </span>
        </div>
        {!loading && !decisions.length && (
          <p className="mod-allgood">
            <CheckCircle2 size={20} aria-hidden="true" />
            <span><strong>Sin pendientes.</strong> No hay compras demoradas ni materiales urgentes sin pedir.</span>
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

      <div className="mod-columns">
        <section className="mod-card" aria-labelledby="buy-receive">
          <div className="mod-card-head">
            <h2 id="buy-receive">Por recibir</h2>
            <Link to="/purchases/orders">Ver órdenes <ArrowUpRight size={14} aria-hidden="true" /></Link>
          </div>
          {loading && <p className="mod-muted">Cargando…</p>}
          {!loading && !toReceive.length && (
            <p className="mod-muted">No hay órdenes esperando mercadería.</p>
          )}
          {toReceive.slice(0, 6).map((order) => {
            const { done, total } = receivedLines(order);
            const age = daysSince(order.created_at);
            return (
              <Link key={order.id} className="mod-line" to={`/purchases/orders?order=${order.number}`}>
                <span className="mod-line-text">
                  <strong>Orden Nº {order.number} · {order.supplier_name}</strong>
                  <small>
                    {dateEs(order.created_at)} · hace {age} {age === 1 ? "día" : "días"} · {done} de {total} líneas completas
                  </small>
                </span>
                <span className={`mod-chip ${age >= 14 ? "is-urgent" : ""}`}>
                  {order.status === "partial" ? "Parcial" : "Abierta"}
                </span>
              </Link>
            );
          })}
        </section>

        {canForecast && (
          <section className="mod-card" aria-labelledby="buy-reorder">
            <div className="mod-card-head">
              <h2 id="buy-reorder">Reposición sugerida por proveedor</h2>
              <Link to="/production/replenishment">Ver todo <ArrowUpRight size={14} aria-hidden="true" /></Link>
            </div>
            {forecast.isPending && <p className="mod-muted">Calculando…</p>}
            {!forecast.isPending && !suggestions.length && (
              <p className="mod-muted">No hay materiales con compra sugerida.</p>
            )}
            {suggestions.slice(0, 6).map((group) => (
              <Link
                key={group.id ?? "none"}
                className="mod-line"
                to={group.id
                  ? `/purchases/orders?new=1&supplier=${group.id}&suggested=1`
                  : "/purchases/suppliers"}
              >
                <span className="mod-line-text">
                  <strong>{group.name}</strong>
                  <small>
                    {plural(group.count, "material", "materiales")}
                    {group.urgent ? ` · ${group.urgent} urgentes` : ""}
                  </small>
                </span>
                <span className="mod-chip">{group.id ? "Preparar orden" : "Asignar proveedor"}</span>
              </Link>
            ))}
          </section>
        )}
      </div>
    </PurchasesShell>
  );
}

import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import {
  AlertOctagon,
  ArrowUpRight,
  CalendarClock,
  CheckCircle2,
  Clock3,
  Factory,
  FlaskConical,
  PackageCheck,
  Play,
  Plus,
} from "lucide-react";
import { useAuth } from "../../contexts/AuthContext";
import { supabase } from "../../lib/supabase";
import { friendlyError } from "../../lib/notifications";
import { dateEs } from "../../lib/display";
import { getReplenishmentForecast } from "../../services/replenishment";
import ProductionShell from "./ProductionShell";

const rpc = async (name, companyId) => {
  const { data, error } = await supabase.rpc(name, { p_company: companyId });
  if (error) throw error;
  return data;
};
const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

/* Resumen de Producción: qué se está fabricando, qué falta y qué hay que decidir hoy. */
export default function ProductionOverview() {
  const { activeCompanyId, user, can } = useAuth();
  const scope = [user?.id, activeCompanyId];
  const enabled = Boolean(activeCompanyId) && can("production_overview", "read");

  const jobs = useQuery({
    queryKey: ["production-dashboard", ...scope],
    queryFn: () => rpc("erp_production_dashboard", activeCompanyId),
    enabled,
    refetchInterval: 60_000,
  });
  const summary = useQuery({
    queryKey: ["erp-dashboard", ...scope],
    queryFn: () => rpc("erp_operational_dashboard", activeCompanyId),
    enabled,
    staleTime: 60_000,
  });
  const forecast = useQuery({
    queryKey: ["replenishment-forecast", ...scope],
    queryFn: () => getReplenishmentForecast(activeCompanyId),
    enabled,
    staleTime: 60_000,
  });

  const inProgress = Number(jobs.data?.in_progress ?? 0);
  const queued = Number(jobs.data?.queued ?? 0);
  const overdue = Number(jobs.data?.overdue ?? 0);
  const plans = Number(summary.data?.planned_runs ?? 0);
  const next = (jobs.data?.next ?? [])
    .slice()
    .sort((a, b) => (a.due_on ?? "9999").localeCompare(b.due_on ?? "9999"))
    .slice(0, 6);
  const shortages = (forecast.data ?? [])
    .filter((row) => row.alert_level === "critical" || row.alert_level === "warning")
    .sort((a, b) => Number(a.days_left ?? 9999) - Number(b.days_left ?? 9999));
  const critical = shortages.filter((row) => row.alert_level === "critical");
  const loading = jobs.isPending || summary.isPending;
  const error = jobs.error || summary.error || forecast.error;

  const decisions = [];
  if (overdue > 0) {
    decisions.push({
      key: "overdue", level: "urgent", icon: CalendarClock, to: "/production/orders",
      title: plural(overdue, "orden fuera de plazo", "órdenes fuera de plazo"),
      ask: "Decidí si la priorizás, reprogramás la entrega o avisás al cliente.",
    });
  }
  if (critical.length > 0) {
    decisions.push({
      key: "short", level: "urgent", icon: AlertOctagon, to: "/production/replenishment",
      title: plural(critical.length, "material se agota pronto", "materiales se agotan pronto"),
      ask: `Revisá qué comprar: ${critical.slice(0, 3).map((row) => row.item_name).join(", ")}${critical.length > 3 ? "…" : ""}.`,
    });
  }
  if (queued > 0 && inProgress === 0) {
    decisions.push({
      key: "idle", level: "attention", icon: Clock3, to: "/production/orders",
      title: plural(queued, "orden en cola sin ninguna en fabricación", "órdenes en cola sin ninguna en fabricación"),
      ask: "Definí cuál se inicia primero y verificá que alcance el stock.",
    });
  }
  if (plans > 0) {
    decisions.push({
      key: "plans", level: "info", icon: Factory, to: "/production/planning",
      title: plural(plans, "plan sin convertir en orden", "planes sin convertir en orden"),
      ask: "Elegí cuáles pasan a fabricación.",
    });
  }
  const levelText = { urgent: "Urgente", attention: "Requiere atención", info: "Para planificar" };
  const rank = { urgent: 0, attention: 1, info: 2 };
  decisions.sort((a, b) => rank[a.level] - rank[b.level]);

  const kpis = [
    { key: "progress", label: "En fabricación", value: jobs.data ? inProgress : "…", icon: Play, note: "Órdenes iniciadas", to: "/production/orders" },
    { key: "queued", label: "En cola", value: jobs.data ? queued : "…", icon: Factory, note: "Esperando iniciar", to: "/production/orders" },
    { key: "overdue", label: "Fuera de plazo", value: jobs.data ? overdue : "…", icon: CalendarClock, warn: overdue > 0, note: overdue > 0 ? "Pasaron su fecha prevista" : "Todo dentro de plazo", to: "/production/orders" },
    { key: "plans", label: "Planes sin lanzar", value: summary.data ? plans : "…", icon: Clock3, note: "Pendientes de orden", to: "/production/planning" },
  ];

  return (
    <ProductionShell
      title="Resumen de producción"
      description="Qué se está fabricando, qué falta y qué necesita tu decisión hoy. Desde acá llegás a cada pantalla del módulo."
      actions={can("production_orders", "insert") && (
        <Link className="button primary" to="/production/orders?new=1">
          <Plus size={17} aria-hidden="true" /> Nueva orden
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

      <section className="mod-card" aria-labelledby="prod-decisions">
        <div className="mod-card-head">
          <h2 id="prod-decisions">Para decidir hoy</h2>
          <span className={`mod-chip ${decisions.some((d) => d.level === "urgent") ? "is-urgent" : decisions.length ? "" : "is-ok"}`}>
            {loading ? "Revisando…" : decisions.length ? plural(decisions.length, "tema", "temas") : "Al día"}
          </span>
        </div>
        {!loading && !decisions.length && (
          <p className="mod-allgood">
            <CheckCircle2 size={20} aria-hidden="true" />
            <span><strong>Sin pendientes urgentes.</strong> No hay órdenes vencidas ni materiales por agotarse.</span>
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
        <section className="mod-card" aria-labelledby="prod-next">
          <div className="mod-card-head">
            <h2 id="prod-next">Próximas entregas</h2>
            <Link to="/production/orders">Ver órdenes <ArrowUpRight size={14} aria-hidden="true" /></Link>
          </div>
          {jobs.isPending && <p className="mod-muted">Cargando…</p>}
          {!jobs.isPending && !next.length && (
            <p className="mod-muted">No hay órdenes activas. Creá una para empezar a fabricar.</p>
          )}
          {next.map((job) => (
            <Link key={job.id} className="mod-line" to={`/production/orders?job=${job.id}`}>
              <span className="mod-line-text">
                <strong>{job.product_name} · {job.planned_quantity}</strong>
                <small>
                  {job.status === "queued" ? "En cola" : "En fabricación"} ·{" "}
                  {job.due_on ? `Entrega ${dateEs(job.due_on)}` : "Sin fecha prevista"}
                </small>
              </span>
              <ArrowUpRight size={16} aria-hidden="true" />
            </Link>
          ))}
        </section>

        <section className="mod-card" aria-labelledby="prod-short">
          <div className="mod-card-head">
            <h2 id="prod-short">Materiales por reponer</h2>
            <Link to="/production/replenishment">Ver reposición <ArrowUpRight size={14} aria-hidden="true" /></Link>
          </div>
          {forecast.isPending && <p className="mod-muted">Calculando…</p>}
          {!forecast.isPending && !shortages.length && (
            <p className="mod-muted">Ningún material está por agotarse con el consumo registrado.</p>
          )}
          {shortages.slice(0, 6).map((row) => (
            <Link key={row.item_id ?? row.item_name} className="mod-line" to="/production/replenishment">
              <span className="mod-line-text">
                <strong>{row.item_name}</strong>
                <small>
                  {row.days_left != null ? `Alcanza para ~${Math.max(0, Math.round(Number(row.days_left)))} días` : "Sin consumo registrado"}
                  {row.supplier_name ? ` · ${row.supplier_name}` : ""}
                </small>
              </span>
              <span className={`mod-chip ${row.alert_level === "critical" ? "is-urgent" : ""}`}>
                {row.alert_level === "critical" ? "Crítico" : "Atención"}
              </span>
            </Link>
          ))}
          <p className="mod-muted" style={{ marginTop: 10 }}>
            El pronóstico usa el consumo registrado; no predice cambios de demanda.
          </p>
        </section>
      </div>

      <section className="mod-card" aria-label="Accesos rápidos">
        <h2>Accesos rápidos</h2>
        <div className="mod-shell-actions" style={{ marginTop: 12 }}>
          <Link className="button outline" to="/production/availability">
            <PackageCheck size={16} aria-hidden="true" /> ¿Alcanza el stock para fabricar?
          </Link>
          <Link className="button outline" to="/production/formulas">
            <FlaskConical size={16} aria-hidden="true" /> Fórmulas
          </Link>
          <Link className="button outline" to="/production/planning">
            <CalendarClock size={16} aria-hidden="true" /> Planificar
          </Link>
        </div>
      </section>
    </ProductionShell>
  );
}

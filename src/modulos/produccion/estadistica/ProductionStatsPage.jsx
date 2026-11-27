import { useEffect, useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { CheckCircle2, ClipboardList, Scale, TrendingDown, TrendingUp, X } from "lucide-react";
import { useAuth } from "../../../compartido/contextos/AuthContext";
import ListPager, { usePagedList } from "../../../compartido/componentes/ListPager";
import { friendlyError } from "../../../compartido/utilidades/notifications";
import { dateEs } from "../../../compartido/utilidades/display";
import {
  getProductionOutputSummary,
  listProductionOutputByProduct,
} from "../compartido/production";
import ProductionShell from "../compartido/ProductionShell";
import "./productionStats.css";

/*
 * Estadística de producción: cuánto se fabricó, en base a las órdenes TERMINADAS (cantidad real obtenida),
 * por día, semana o mes y en cualquier rango de fechas. No muestra costos. Las cantidades se agrupan por
 * unidad: no se suman litros con unidades, etc. (D-006).
 */
const PAGE_SIZE = 25;
const DAY_MS = 86_400_000;

const pad = (value) => String(value).padStart(2, "0");
const ymd = (date) => `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
const parse = (text) => new Date(`${text}T12:00:00`);
const addDays = (date, days) => new Date(date.getTime() + days * DAY_MS);
const daysBetween = (from, to) => Math.round((parse(to) - parse(from)) / DAY_MS) + 1;
const quantity = (value) =>
  Number(value ?? 0).toLocaleString("es-AR", { maximumFractionDigits: 2 });
const MONTHS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];

function presetRange(key) {
  const today = new Date();
  const first = (year, month) => new Date(year, month, 1, 12);
  const y = today.getFullYear();
  const m = today.getMonth();
  switch (key) {
    case "month": return { from: ymd(first(y, m)), to: ymd(today) };
    case "lastMonth": return { from: ymd(first(y, m - 1)), to: ymd(new Date(y, m, 0, 12)) };
    case "weeks4": return { from: ymd(addDays(today, -27)), to: ymd(today) };
    case "months3": return { from: ymd(first(y, m - 2)), to: ymd(today) };
    case "year": return { from: ymd(first(y, 0)), to: ymd(today) };
    default: return null;
  }
}

const PRESETS = [
  ["month", "Este mes"],
  ["lastMonth", "Mes anterior"],
  ["weeks4", "Últimas 4 semanas"],
  ["months3", "Últimos 3 meses"],
  ["year", "Este año"],
  ["custom", "Personalizado"],
];

/* Lunes de la semana de una fecha (igual que date_trunc('week') en la base). */
function weekStart(date) {
  const back = (date.getDay() + 6) % 7;
  return addDays(date, -back);
}

function bucketStarts(from, to, bucket) {
  const out = [];
  const end = parse(to);
  if (bucket === "day") {
    for (let d = parse(from); d <= end; d = addDays(d, 1)) out.push(ymd(d));
  } else if (bucket === "week") {
    for (let d = weekStart(parse(from)); d <= end; d = addDays(d, 7)) out.push(ymd(d));
  } else {
    const start = parse(from);
    for (let d = new Date(start.getFullYear(), start.getMonth(), 1, 12); d <= end;
      d = new Date(d.getFullYear(), d.getMonth() + 1, 1, 12)) out.push(ymd(d));
  }
  return out;
}

function bucketLabel(start, bucket, short = false) {
  const date = parse(start);
  if (bucket === "month") return `${MONTHS[date.getMonth()]} ${short ? String(date.getFullYear()).slice(2) : date.getFullYear()}`;
  if (bucket === "week") return short ? `${pad(date.getDate())}/${pad(date.getMonth() + 1)}` : `Semana del ${dateEs(start).slice(0, 5)}`;
  return short ? `${pad(date.getDate())}/${pad(date.getMonth() + 1)}` : dateEs(start);
}

const missingMigration = (error) =>
  /Could not find the function|PGRST202|42883/i.test(`${error?.code ?? ""} ${error?.message ?? ""}`);

function errorText(error) {
  return missingMigration(error)
    ? "Esta estadística necesita la migración 043 en la base. Pedile al administrador técnico que la aplique."
    : friendlyError(error);
}

function totalsByUnit(rows) {
  const map = new Map();
  for (const row of rows ?? []) {
    const current = map.get(row.unit_symbol) ?? { unit: row.unit_symbol, orders: 0, actual: 0, expected: 0 };
    current.orders += Number(row.orders);
    current.actual += Number(row.actual_quantity);
    current.expected += Number(row.expected_quantity);
    map.set(row.unit_symbol, current);
  }
  return [...map.values()].sort((a, b) => b.actual - a.actual);
}

function Delta({ now, before }) {
  if (!before) return <small>Sin producción en el período anterior</small>;
  const change = ((now - before) / before) * 100;
  const Icon = change >= 0 ? TrendingUp : TrendingDown;
  return (
    <small className={`stats-delta ${change >= 0 ? "is-up" : "is-down"}`}>
      <Icon size={14} aria-hidden="true" /> {change >= 0 ? "+" : ""}{change.toFixed(1)} % vs. período anterior
    </small>
  );
}

export default function ProductionStatsPage() {
  const { activeCompanyId, user, can } = useAuth();
  const enabled = Boolean(activeCompanyId) && can("produccion_estadistica", "ver");
  const scope = [user?.id, activeCompanyId];
  const initial = presetRange("month");

  const [preset, setPreset] = useState("month");
  const [from, setFrom] = useState(initial.from);
  const [to, setTo] = useState(initial.to);
  const [bucketChoice, setBucketChoice] = useState("auto");
  const [unit, setUnit] = useState("");
  const [searchText, setSearchText] = useState("");
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(0);
  const [product, setProduct] = useState(null);

  const days = daysBetween(from, to);
  const rangeOk = days >= 1 && days <= 3660;
  const autoBucket = days <= 31 ? "day" : days <= 120 ? "week" : "month";
  let bucket = bucketChoice === "auto" ? autoBucket : bucketChoice;
  if (bucket === "day" && days > 366) bucket = "week";

  useEffect(() => {
    const timer = setTimeout(() => { setSearch(searchText); setPage(0); }, 300);
    return () => clearTimeout(timer);
  }, [searchText]);
  useEffect(() => setPage(0), [from, to]);

  function choosePreset(key) {
    setPreset(key);
    const range = presetRange(key);
    if (range) { setFrom(range.from); setTo(range.to); }
  }

  const previousTo = ymd(addDays(parse(from), -1));
  const previousFrom = ymd(addDays(parse(from), -days));

  const series = useQuery({
    queryKey: ["production-stats", ...scope, from, to, bucket, product?.id ?? ""],
    queryFn: () => getProductionOutputSummary(activeCompanyId, { from, to, bucket, productId: product?.id }),
    enabled: enabled && rangeOk,
    staleTime: 60_000,
  });
  const previous = useQuery({
    queryKey: ["production-stats-prev", ...scope, previousFrom, previousTo, product?.id ?? ""],
    queryFn: () => getProductionOutputSummary(activeCompanyId, {
      from: previousFrom, to: previousTo, bucket: "month", productId: product?.id,
    }),
    enabled: enabled && rangeOk,
    staleTime: 60_000,
  });
  const products = useQuery({
    queryKey: ["production-stats-products", ...scope, from, to, search, page],
    queryFn: () => listProductionOutputByProduct(activeCompanyId, { from, to, search, page, pageSize: PAGE_SIZE }),
    enabled: enabled && rangeOk,
    staleTime: 60_000,
    placeholderData: (old) => old,
  });

  const totals = useMemo(() => totalsByUnit(series.data), [series.data]);
  const previousTotals = useMemo(() => totalsByUnit(previous.data), [previous.data]);
  const activeUnit = totals.find((entry) => entry.unit === unit)?.unit ?? totals[0]?.unit ?? "";
  const main = totals.find((entry) => entry.unit === activeUnit);
  const before = previousTotals.find((entry) => entry.unit === activeUnit);
  const totalOrders = totals.reduce((sum, entry) => sum + entry.orders, 0);

  const buckets = useMemo(() => {
    if (!rangeOk) return [];
    const starts = bucketStarts(from, to, bucket);
    const byStart = new Map((series.data ?? [])
      .filter((row) => row.unit_symbol === activeUnit)
      .map((row) => [row.bucket_start, row]));
    return starts.map((start) => {
      const row = byStart.get(start);
      return {
        start,
        orders: Number(row?.orders ?? 0),
        expected: Number(row?.expected_quantity ?? 0),
        actual: Number(row?.actual_quantity ?? 0),
      };
    });
  }, [series.data, activeUnit, from, to, bucket, rangeOk]);
  const peak = Math.max(0, ...buckets.map((entry) => entry.actual));
  const average = buckets.length ? (main?.actual ?? 0) / buckets.length : 0;
  const detail = usePagedList([...buckets].reverse(), { pageSize: 12, resetKey: `${from}|${to}|${bucket}|${activeUnit}` });
  const productCount = products.data?.count ?? 0;
  const productPages = Math.max(1, Math.ceil(productCount / PAGE_SIZE));
  const bucketNames = { day: "día", week: "semana", month: "mes" };
  const labelEvery = Math.max(1, Math.ceil(buckets.length / (typeof window !== "undefined" && window.innerWidth < 560 ? 5 : 12)));

  return (
    <ProductionShell
      title="Estadística de producción"
      description="Cuánto se fabricó por mes, por semana o en el rango que elijas. Se calcula con las órdenes terminadas y la cantidad real obtenida; no incluye costos."
    >
      <section className="stats-page">
        <div className="mod-segments" role="group" aria-label="Período">
          {PRESETS.map(([key, label]) => (
            <button key={key} type="button" className="mod-segment" aria-pressed={preset === key}
              onClick={() => choosePreset(key)}>{label}</button>
          ))}
        </div>

        <div className="mod-filters">
          <label>Desde
            <input type="date" value={from} max={to}
              onChange={(event) => { setPreset("custom"); setFrom(event.target.value); }} />
          </label>
          <label>Hasta
            <input type="date" value={to} min={from}
              onChange={(event) => { setPreset("custom"); setTo(event.target.value); }} />
          </label>
          <label>Agrupar por
            <select value={bucketChoice} onChange={(event) => setBucketChoice(event.target.value)}>
              <option value="auto">Automático ({bucketNames[autoBucket]})</option>
              <option value="day" disabled={days > 366}>Día</option>
              <option value="week">Semana (desde el lunes)</option>
              <option value="month">Mes</option>
            </select>
          </label>
          {totals.length > 1 && (
            <label>Unidad
              <select value={activeUnit} onChange={(event) => setUnit(event.target.value)}>
                {totals.map((entry) => <option key={entry.unit} value={entry.unit}>{entry.unit}</option>)}
              </select>
            </label>
          )}
        </div>

        {!rangeOk && <p role="alert" className="error">Elegí un rango válido: la fecha final no puede ser anterior a la inicial ni superar 10 años.</p>}
        {product && (
          <p className="stats-filter" role="status">
            Mostrando solo <strong>{product.name}</strong>
            <button type="button" className="button outline" onClick={() => setProduct(null)}>
              <X size={14} aria-hidden="true" /> Ver todos los productos
            </button>
          </p>
        )}
        {series.isError && <p role="alert" className="error">{errorText(series.error)}</p>}

        <div className="mod-kpis">
          <article className="mod-kpi">
            <span className="mod-kpi-top"><span className="mod-kpi-icon"><ClipboardList size={18} aria-hidden="true" /></span>Órdenes terminadas</span>
            <strong>{series.isPending ? "…" : totalOrders}</strong>
            <small>Del {dateEs(from)} al {dateEs(to)}</small>
          </article>
          <article className="mod-kpi">
            <span className="mod-kpi-top"><span className="mod-kpi-icon"><CheckCircle2 size={18} aria-hidden="true" /></span>Producido{activeUnit ? ` (${activeUnit})` : ""}</span>
            <strong>{series.isPending ? "…" : quantity(main?.actual ?? 0)}</strong>
            {previous.isSuccess && <Delta now={main?.actual ?? 0} before={before?.actual ?? 0} />}
          </article>
          <article className="mod-kpi">
            <span className="mod-kpi-top"><span className="mod-kpi-icon"><Scale size={18} aria-hidden="true" /></span>Promedio por {bucketNames[bucket]}</span>
            <strong>{series.isPending ? "…" : quantity(average)}</strong>
            <small>{main && main.expected > 0
              ? `Real vs. previsto: ${(((main.actual - main.expected) / main.expected) * 100).toFixed(1)} %`
              : "Sin producción en el período"}</small>
          </article>
        </div>

        <section className="mod-card" aria-labelledby="stats-chart">
          <div className="mod-card-head">
            <h2 id="stats-chart">Producción por {bucketNames[bucket]}{activeUnit ? ` (${activeUnit})` : ""}</h2>
          </div>
          {series.isPending && <p className="mod-muted">Calculando…</p>}
          {!series.isPending && !totalOrders && (
            <p className="mod-muted">No hay órdenes terminadas en este período. Probá con otro rango.</p>
          )}
          {totalOrders > 0 && (
            <>
              <ol className="stats-bars" aria-label={`Producción por ${bucketNames[bucket]}`}>
                {buckets.map((entry, index) => (
                  <li key={entry.start}
                    title={`${bucketLabel(entry.start, bucket)}: ${quantity(entry.actual)} ${activeUnit} en ${entry.orders} órdenes`}>
                    <span className="stats-bar" style={{ height: `${peak ? Math.max(entry.actual ? 3 : 0, (entry.actual / peak) * 100) : 0}%` }} />
                    <small>{index % labelEvery === 0 ? bucketLabel(entry.start, bucket, true) : ""}</small>
                  </li>
                ))}
              </ol>
              <div className="mod-table-wrap">
                <table className="mod-table">
                  <thead>
                    <tr>
                      <th scope="col">Período</th>
                      <th scope="col" className="is-num">Órdenes</th>
                      <th scope="col" className="is-num">Previsto</th>
                      <th scope="col" className="is-num">Producido</th>
                      <th scope="col" className="is-num">Diferencia</th>
                    </tr>
                  </thead>
                  <tbody>
                    {detail.visible.map((entry) => {
                      const diff = entry.expected ? ((entry.actual - entry.expected) / entry.expected) * 100 : null;
                      return (
                        <tr key={entry.start}>
                          <td className="is-name" data-label="Período"><strong>{bucketLabel(entry.start, bucket)}</strong></td>
                          <td className="is-num" data-label="Órdenes">{entry.orders}</td>
                          <td className="is-num" data-label="Previsto">{entry.orders ? quantity(entry.expected) : "—"}</td>
                          <td className="is-num" data-label="Producido">{entry.orders ? <strong>{quantity(entry.actual)} {activeUnit}</strong> : "—"}</td>
                          <td className="is-num" data-label="Diferencia">
                            {diff == null ? "—" : <span className={Math.abs(diff) < 0.05 ? "" : diff < 0 ? "stats-neg" : "stats-pos"}>{diff > 0 ? "+" : ""}{diff.toFixed(1)} %</span>}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
              <ListPager pager={detail} noun="períodos" sizes={[12, 24, 48]} />
            </>
          )}
        </section>

        <section className="mod-card" aria-labelledby="stats-products">
          <div className="mod-card-head">
            <h2 id="stats-products">Por producto</h2>
          </div>
          <div className="mod-filters">
            <label className="mod-filter-grow">Buscar producto
              <input type="search" value={searchText} placeholder="Nombre o código"
                onChange={(event) => setSearchText(event.target.value)} />
            </label>
          </div>
          {products.isError && <p role="alert" className="error">{errorText(products.error)}</p>}
          {products.isSuccess && !products.data.rows.length && (
            <p className="mod-muted">{search ? "Ningún producto coincide con la búsqueda." : "No hay producción terminada en este período."}</p>
          )}
          {products.data?.rows.length > 0 && (
            <div className="mod-table-wrap">
              <table className="mod-table">
                <thead>
                  <tr>
                    <th scope="col">Producto</th>
                    <th scope="col" className="is-num">Órdenes</th>
                    <th scope="col" className="is-num">Previsto</th>
                    <th scope="col" className="is-num">Producido</th>
                    <th scope="col"><span className="sr-only">Acción</span></th>
                  </tr>
                </thead>
                <tbody>
                  {products.data.rows.map((row) => (
                    <tr key={row.product_id}>
                      <td className="is-name" data-label="Producto">
                        <strong>{row.product_name}</strong><small>{row.product_code}</small>
                      </td>
                      <td className="is-num" data-label="Órdenes">{Number(row.orders)}</td>
                      <td className="is-num" data-label="Previsto">{quantity(row.expected_quantity)} {row.unit_symbol}</td>
                      <td className="is-num" data-label="Producido"><strong>{quantity(row.actual_quantity)} {row.unit_symbol}</strong></td>
                      <td data-label="">
                        <button type="button" className="button outline"
                          onClick={() => { setProduct({ id: row.product_id, name: row.product_name }); setUnit(row.unit_symbol); }}>
                          Ver evolución
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          {productCount > PAGE_SIZE && (
            <nav className="mod-pager" aria-label="Paginación de productos">
              <span className="mod-pager-count">
                {page * PAGE_SIZE + 1}–{Math.min(productCount, (page + 1) * PAGE_SIZE)} de {productCount} productos
              </span>
              <div className="mod-pager-buttons">
                <button type="button" disabled={page === 0} aria-label="Página anterior" onClick={() => setPage(page - 1)}>‹</button>
                <span aria-live="polite">Página {page + 1} de {productPages}</span>
                <button type="button" disabled={page + 1 >= productPages} aria-label="Página siguiente" onClick={() => setPage(page + 1)}>›</button>
              </div>
            </nav>
          )}
        </section>

        <details className="stats-method">
          <summary>Cómo se calcula</summary>
          <p>Suma la cantidad real de las órdenes terminadas según su fecha de finalización (hora de Argentina).
            "Previsto" es la salida esperada de la fórmula; "Diferencia" compara lo real contra lo previsto.
            Las semanas comienzan el lunes. Las cantidades se muestran por unidad y no se mezclan unidades distintas.
            Las órdenes canceladas o sin terminar no cuentan.</p>
        </details>
      </section>
    </ProductionShell>
  );
}

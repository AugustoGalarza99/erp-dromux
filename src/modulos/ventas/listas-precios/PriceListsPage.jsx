import { useEffect, useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useSearchParams } from "react-router-dom";
import {
  AlertTriangle, ChevronLeft, ChevronRight, FileUp, History, Pencil, Percent, Plus, Search, Settings2, Tags,
} from "lucide-react";
import { useAuth } from "../../../compartido/contextos/AuthContext";
import { useDebouncedValue } from "../../../compartido/hooks/useDebouncedValue";
import { dateEs } from "../../../compartido/utilidades/display";
import { friendlyError } from "../../../compartido/utilidades/notifications";
import { isMissingFunction, money, percent } from "../compartido/pricing";
import {
  getPriceSettings, listAdminPriceRows, listPriceLists, listPriceRows,
} from "./priceLists";
import { BulkDialog, HistoryDialog, ImportDialog } from "./PriceBulkDialogs";
import { ItemPriceDialog, ListFormDialog, SettingsDialog } from "./PriceListDialogs";
import PriceSimulator from "./PriceSimulator";
import LegacyPriceList from "./PriceListPage";
import SalesShell from "../compartido/SalesShell";

const SIZES = [25, 50, 100];
const FILTERS = [
  { key: "all", label: "Todos", admin: false },
  { key: "missing", label: "Sin precio", admin: false },
  { key: "low_margin", label: "Margen bajo", admin: true },
  { key: "cost_changed", label: "Costo cambió", admin: true },
];

function validity(list) {
  if (!list.valid_from && !list.valid_to) return "Sin vencimiento";
  return `${list.valid_from ? `desde ${dateEs(list.valid_from)}` : ""} ${list.valid_to ? `hasta ${dateEs(list.valid_to)}` : ""}`.trim();
}

function Chips({ row, admin }) {
  return (
    <span className="pl-chips">
      {row.net_price == null && <span className="pl-chip is-warn">Sin precio</span>}
      {row.source === "derived" && <span className="pl-chip">Desde lista base</span>}
      {admin && row.low_margin && <span className="pl-chip is-bad">Margen bajo</span>}
      {admin && row.cost_changed && <span className="pl-chip is-warn">Costo cambió</span>}
    </span>
  );
}

/* Listas de precios: tabla compacta con servidor paginado, edición, cambio masivo e importación. */
export default function PriceListsPage() {
  const { activeCompanyId, user, can, role } = useAuth();
  const client = useQueryClient();
  const [params, setParams] = useSearchParams();
  const scope = [user?.id, activeCompanyId];
  const isAdmin = role === "administrador" && can("finanzas", "ver") && can("ventas", "editar");

  const [selectedId, setSelectedId] = useState("");
  const [search, setSearch] = useState("");
  const term = useDebouncedValue(search);
  const [page, setPage] = useState(0);
  const [size, setSize] = useState(50);
  const [dialog, setDialog] = useState(null);
  const [editRow, setEditRow] = useState(null);
  const filterParam = params.get("filter") ?? "all";
  const filter = FILTERS.some((f) => f.key === filterParam && (isAdmin || !f.admin)) ? filterParam : "all";

  const lists = useQuery({
    queryKey: ["price-lists", ...scope],
    queryFn: () => listPriceLists(activeCompanyId),
    enabled: Boolean(activeCompanyId),
    retry: false,
  });
  const allLists = useMemo(() => lists.data ?? [], [lists.data]);
  // La lista activa se calcula (no se guarda con efectos): la elegida si existe en esta empresa;
  // si no, la predeterminada, la primera vigente o la primera. Así no depende de un re-render extra.
  const current = useMemo(() => {
    if (!allLists.length) return null;
    const visible = allLists.filter((entry) => !entry.archived);
    return allLists.find((entry) => entry.id === selectedId)
      ?? visible.find((entry) => entry.is_default) ?? visible[0] ?? allLists[0];
  }, [allLists, selectedId]);
  const listId = current?.id ?? "";
  useEffect(() => { setSelectedId(""); setPage(0); setSearch(""); }, [activeCompanyId]);
  useEffect(() => { setPage(0); }, [listId, term, filter, size]);

  const settings = useQuery({
    queryKey: ["price-settings", ...scope],
    queryFn: () => getPriceSettings(activeCompanyId),
    enabled: Boolean(activeCompanyId) && isAdmin && Boolean(current),
    retry: false,
    staleTime: 60_000,
  });

  const rowsKey = ["price-rows", ...scope, listId, isAdmin, term, filter, page, size];
  const rows = useQuery({
    queryKey: rowsKey,
    queryFn: () => (isAdmin
      ? listAdminPriceRows(activeCompanyId, listId, { search: term, filter, page, pageSize: size })
      : listPriceRows(activeCompanyId, listId, { search: term, missingOnly: filter === "missing", page, pageSize: size })),
    enabled: Boolean(activeCompanyId && listId),
    // Conserva las filas anteriores solo al paginar/buscar en la MISMA lista (no al cambiar de lista).
    placeholderData: (previous, previousQuery) => (previousQuery?.queryKey?.[3] === listId ? previous : undefined),
    staleTime: 20_000,
  });
  const data = rows.data ?? [];
  const total = Number(data[0]?.total_count ?? 0);
  const pages = Math.max(1, Math.ceil(total / size));
  const currency = current?.currency ?? "ARS";

  const refresh = () => client.invalidateQueries({ queryKey: ["price-rows", ...scope] });
  const refreshAll = async () => {
    await client.invalidateQueries({ queryKey: ["price-lists", ...scope] });
    await refresh();
  };
  const setFilter = (key) => {
    const next = new URLSearchParams(params);
    if (key === "all") next.delete("filter"); else next.set("filter", key);
    setParams(next, { replace: true });
  };

  // Aún no existe la migración 039: se muestra la consulta del precio único.
  if (isMissingFunction(lists.error)) {
    return (
      <SalesShell title="Listas de precios" description="Precios de venta por producto.">
        <p className="mod-hint" role="note">
          <AlertTriangle size={16} aria-hidden="true" />
          <span>Las listas de precios múltiples (por tipo de cliente, con vigencia, margen e historial) todavía no están activas en este entorno. Mientras tanto se consulta el precio único de cada producto.</span>
        </p>
        <LegacyPriceList />
      </SalesShell>
    );
  }

  const actions = isAdmin && (
    <>
      <button type="button" className="button outline" onClick={() => setDialog("settings")}>
        <Settings2 size={16} aria-hidden="true" /> Parámetros
      </button>
      <button type="button" className="button primary" onClick={() => setDialog("new")}>
        <Plus size={16} aria-hidden="true" /> Nueva lista
      </button>
    </>
  );

  return (
    <SalesShell
      title="Listas de precios"
      description={isAdmin
        ? "Armá una lista por tipo de cliente, con costo, margen y ganancia a la vista. Los precios se guardan sin IVA."
        : "Precios vigentes por producto para consultar antes de vender (sin IVA y con IVA)."}
      actions={actions}
    >
      {lists.error && <p role="alert" className="error">{friendlyError(lists.error)}</p>}

      {!lists.isPending && !allLists.length && (
        <section className="mod-card pl-empty">
          <Tags size={28} aria-hidden="true" />
          <h2>Todavía no hay listas de precios</h2>
          <p className="mod-muted">
            {isAdmin
              ? "Creá la primera (por ejemplo Mayorista o Minorista), cargá los precios a mano o importalos desde una planilla."
              : "La administración todavía no cargó listas de precios."}
          </p>
          {isAdmin && <button type="button" className="button primary" onClick={() => setDialog("new")}>Crear la primera lista</button>}
        </section>
      )}

      {current && (
        <section className="mod-card pl-card" aria-label="Productos de la lista">
          <div className="pl-bar">
            <label className="pl-listpick">Lista
              <select value={listId} onChange={(event) => setSelectedId(event.target.value)} aria-label="Lista de precios">
                {allLists.map((entry) => (
                  <option key={entry.id} value={entry.id}>
                    {entry.name} · {entry.currency}{entry.is_default ? " · predeterminada" : ""}{entry.archived ? " · archivada" : ""}
                  </option>
                ))}
              </select>
            </label>
            <p className="pl-meta">
              {validity(current)}
              {current.base_list_id && ` · base: ${allLists.find((l) => l.id === current.base_list_id)?.name ?? "—"} ${percent(-current.base_discount_percent)}`}
              {Number(current.rounding_step) > 0 && ` · redondeo ${current.rounding_step}`}
            </p>
            {isAdmin && (
              <div className="pl-tools">
                <button type="button" className="button outline" onClick={() => setDialog("edit")}><Pencil size={15} aria-hidden="true" /> Editar lista</button>
                <button type="button" className="button outline" disabled={current.archived} onClick={() => setDialog("import")}><FileUp size={15} aria-hidden="true" /> Importar</button>
                <button type="button" className="button outline" disabled={current.archived} onClick={() => setDialog("bulk")}><Percent size={15} aria-hidden="true" /> Cambio masivo</button>
                <button type="button" className="button outline" onClick={() => setDialog("history")}><History size={15} aria-hidden="true" /> Historial</button>
              </div>
            )}
          </div>

          {isAdmin && <PriceSimulator settings={settings.data} currency={currency} />}

          <div className="mod-filters">
            <label className="mod-filter-grow">Buscar producto
              <span className="pl-search"><Search size={17} aria-hidden="true" />
                <input aria-label="Buscar producto" placeholder="Nombre o código" value={search}
                  onChange={(event) => setSearch(event.target.value)} />
              </span>
            </label>
          </div>
          <div className="mod-segments" role="group" aria-label="Filtrar productos">
            {FILTERS.filter((f) => isAdmin || !f.admin).map((f) => (
              <button key={f.key} type="button" className="mod-segment" aria-pressed={filter === f.key} onClick={() => setFilter(f.key)}>
                {f.label}
              </button>
            ))}
          </div>

          {rows.error && <p role="alert" className="error">{friendlyError(rows.error)}</p>}
          {rows.isPending && <p className="mod-muted">Cargando precios…</p>}
          {!rows.isPending && !data.length && !rows.error && (
            <p className="mod-muted">No hay productos para esta búsqueda o filtro.</p>
          )}

          {data.length > 0 && (
            <>
              <div className="mod-table-wrap pl-desktop">
                <table className="mod-table">
                  <thead>
                    <tr>
                      <th>Producto</th><th>Unidad</th>
                      {isAdmin && <th className="is-num">Costo</th>}
                      <th className="is-num">Precio neto</th>
                      {isAdmin && <><th className="is-num">Margen</th><th className="is-num">Recargo</th><th className="is-num" title="Después de comisión y gastos">Ganancia</th></>}
                      {!isAdmin && <><th className="is-num">IVA</th><th className="is-num">Precio final</th><th className="is-num">Por contenido</th></>}
                      {isAdmin && <th><span className="sr-only">Acciones</span></th>}
                    </tr>
                  </thead>
                  <tbody>
                    {data.map((row) => (
                      <tr key={row.item_id} className={row.low_margin ? "is-urgent" : row.net_price == null || row.cost_changed ? "is-attention" : ""}>
                        <td className="is-name"><strong>{row.name}</strong><small>{row.code}</small><Chips row={row} admin={isAdmin} /></td>
                        <td>{row.unit_symbol}</td>
                        {isAdmin && <td className="is-num">{row.cost == null ? <span className="pl-chip is-warn">Sin costo</span> : money(row.cost, currency)}</td>}
                        <td className="is-num"><strong>{money(row.net_price, currency)}</strong></td>
                        {isAdmin && <>
                          <td className="is-num">{percent(row.margin_percent)}</td>
                          <td className="is-num">{percent(row.markup_percent)}</td>
                          <td className="is-num">{money(row.profit_after_costs, currency)}</td>
                        </>}
                        {!isAdmin && <>
                          <td className="is-num">{percent(row.tax_percent)}</td>
                          <td className="is-num">{money(row.gross_price, currency)}</td>
                          <td className="is-num">{row.price_per_content != null ? `${money(row.price_per_content, currency)} / ${row.content_unit_symbol}` : "—"}</td>
                        </>}
                        {isAdmin && <td className="is-num">
                          <button type="button" className="button outline" disabled={current.archived} onClick={() => setEditRow(row)}
                            aria-label={`Editar precio de ${row.name}`}>Precio</button>
                        </td>}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <ul className="pl-cards" aria-label="Productos">
                {data.map((row) => (
                  <li key={row.item_id} className="pl-pcard">
                    <div className="pl-pcard-top">
                      <div><strong>{row.name}</strong><small>{row.code} · {row.unit_symbol}</small></div>
                      <strong className="pl-pcard-price">{money(row.net_price, currency)}</strong>
                    </div>
                    <Chips row={row} admin={isAdmin} />
                    {!isAdmin && row.net_price != null && <p className="pl-pcard-sub">Con IVA ({percent(row.tax_percent)}): <strong>{money(row.gross_price, currency)}</strong></p>}
                    {isAdmin && (
                      <dl className="pl-pcard-grid">
                        <div><dt>Costo</dt><dd>{money(row.cost, currency)}</dd></div>
                        <div><dt>Margen</dt><dd>{percent(row.margin_percent)}</dd></div>
                        <div><dt>Ganancia</dt><dd>{money(row.profit_after_costs, currency)}</dd></div>
                      </dl>
                    )}
                    {isAdmin && <button type="button" className="button outline" disabled={current.archived} onClick={() => setEditRow(row)}>Editar precio</button>}
                  </li>
                ))}
              </ul>

              <nav className="mod-pager" aria-label="Paginación de productos">
                <span className="mod-pager-count">{page * size + 1}–{Math.min(total, page * size + data.length)} de {total} productos</span>
                <label className="mod-pager-size">Por página
                  <select value={size} onChange={(event) => setSize(Number(event.target.value))}>
                    {SIZES.map((n) => <option key={n} value={n}>{n}</option>)}
                  </select>
                </label>
                <span className="mod-pager-buttons">
                  <button type="button" aria-label="Página anterior" disabled={page === 0} onClick={() => setPage(page - 1)}><ChevronLeft size={18} /></button>
                  <span aria-live="polite">{page + 1} / {pages}</span>
                  <button type="button" aria-label="Página siguiente" disabled={page + 1 >= pages} onClick={() => setPage(page + 1)}><ChevronRight size={18} /></button>
                </span>
              </nav>
            </>
          )}
        </section>
      )}

      <ListFormDialog open={dialog === "new" || dialog === "edit"} list={dialog === "edit" ? current : null}
        lists={allLists} onClose={() => setDialog(null)} onSaved={async (id) => { await refreshAll(); if (dialog === "new" && id) setSelectedId(id); }} />
      <SettingsDialog open={dialog === "settings"} onClose={() => setDialog(null)}
        onSaved={async () => { await client.invalidateQueries({ queryKey: ["price-settings", ...scope] }); await refresh(); }} />
      <BulkDialog open={dialog === "bulk"} list={current} onClose={() => setDialog(null)} onApplied={refresh} />
      <ImportDialog open={dialog === "import"} list={current} onClose={() => setDialog(null)} onApplied={refresh} />
      <HistoryDialog open={dialog === "history"} list={current} onClose={() => setDialog(null)} />
      <ItemPriceDialog row={editRow} list={current} settings={settings.data} onClose={() => setEditRow(null)} onSaved={refresh} />
    </SalesShell>
  );
}

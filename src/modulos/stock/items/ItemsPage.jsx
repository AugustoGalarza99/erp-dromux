import CleanupButton from "../../../compartido/componentes/CleanupButton";
import { friendlyError } from "../../../compartido/utilidades/notifications";
import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, useSearchParams } from "react-router-dom";
import {
  ArrowRightLeft,
  Boxes,
  ChevronLeft,
  ChevronRight,
  FileUp,
  Pencil,
  Plus,
  Search,
  Warehouse,
  X,
} from "lucide-react";
import { useAuth } from "../../../compartido/contextos/AuthContext";
import { listItems } from "./items";
import ItemImport from "./importacion/ItemImport";
import StockShell from "../compartido/StockShell";
import { itemTypeLabels } from "./itemTypes";
import "./items.css";

const typeLabels = itemTypeLabels;

const typeTabs = [
  ["", "Todos"],
  ["materia_prima", "Materias primas"],
  ["semielaborado", "Semielaborados"],
  ["producto_terminado", "Productos"],
  ["insumo", "Insumos"],
];

export default function ItemsPage() {
  const { user, activeCompanyId, can } = useAuth();
  const [params, setParams] = useSearchParams();
  const [inputSearch, setInputSearch] = useState(params.get("q") ?? "");
  const [showImport, setShowImport] = useState(
    params.get("import") === "1" && can("items", "crear"),
  );
  const page = Math.max(0, Number.parseInt(params.get("page") || "0", 10) || 0);
  const search = params.get("q") ?? "";
  const type = typeLabels[params.get("type")] ? params.get("type") : "";
  const status = ["active", "inactive", "all"].includes(params.get("status"))
    ? params.get("status")
    : "active";

  const query = useQuery({
    queryKey: ["items", user?.id, activeCompanyId, page, search, type, status],
    queryFn: () => listItems(activeCompanyId, { page, search, type, status }),
    enabled: Boolean(activeCompanyId),
  });

  const rows = query.data?.rows ?? [];
  const count = query.data?.count ?? 0;
  const pages = Math.max(1, Math.ceil(count / 25));
  const hasFilters = Boolean(search || type || status !== "active");

  const updateFilter = (field, value) => {
    const next = new URLSearchParams(params);
    if (value) next.set(field, value);
    else next.delete(field);
    if (field !== "page") next.delete("page");
    setParams(next);
  };

  useEffect(() => {
    if (query.isSuccess && page >= pages && page > 0)
      updateFilter("page", String(pages - 1));
  }, [query.isSuccess, count, page]);

  // El parámetro ?import=1 solo abre el asistente una vez.
  useEffect(() => {
    if (params.get("import") === "1") updateFilter("import", "");
  }, []);

  const clearFilters = () => {
    setInputSearch("");
    setParams({});
  };

  const closeImport = () => setShowImport(false);

  return (
    <StockShell
      title="Ítems"
      description="Un solo catálogo para materias primas, semielaborados, productos terminados e insumos."
      actions={can("items", "crear") && (
        <>
          <button type="button" className="button outline" onClick={() => setShowImport(true)}>
            <FileUp size={17} aria-hidden="true" /> Importar
          </button>
          <Link className="button outline" to="/archivados?type=items">Archivados</Link>
          <Link to="/inventory/items/new" className="button primary">
            <Plus size={17} aria-hidden="true" /> Nuevo ítem
          </Link>
        </>
      )}
    >
      <div className="items-page">
        <section className="items-panel">
          <div className="items-type-tabs" role="tablist" aria-label="Tipo de ítem">
            {typeTabs.map(([value, label]) => (
              <button
                key={value || "all"}
                type="button"
                role="tab"
                aria-selected={type === value}
                data-type={value || undefined}
                className={`items-type-tab ${type === value ? "is-active" : ""}`}
                onClick={() => updateFilter("type", value)}
              >
                {value && <i className="type-dot" aria-hidden="true" />}
                {label}
              </button>
            ))}
          </div>

          <div className="items-toolbar">
            <div className="items-search">
              <Search size={17} aria-hidden="true" />
              <input
                type="search"
                aria-label="Buscar ítems por nombre"
                placeholder="Buscar por nombre"
                value={inputSearch}
                onChange={(event) => setInputSearch(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter") updateFilter("q", inputSearch.trim());
                }}
              />
            </div>
            <button
              type="button"
              className="button items-search-button"
              onClick={() => updateFilter("q", inputSearch.trim())}
            >
              Buscar
            </button>
            <select
              aria-label="Filtrar por estado"
              value={status}
              onChange={(event) => updateFilter("status", event.target.value)}
            >
              <option value="active">Activos</option>
              <option value="inactive">Inactivos</option>
              <option value="all">Todos los estados</option>
            </select>
            {hasFilters && (
              <button type="button" className="button outline" onClick={clearFilters}>
                <X size={15} aria-hidden="true" /> Limpiar filtros
              </button>
            )}
          </div>

          {query.error && (
            <p role="alert" className="error">{friendlyError(query.error)}</p>
          )}
          {query.isPending && <p className="items-muted">Cargando ítems…</p>}
          {!query.isPending && !query.error && rows.length === 0 && (
            <div className="items-empty">
              <Boxes size={30} aria-hidden="true" />
              <h2>{hasFilters ? "No hay ítems con esos filtros" : "Todavía no cargaste ítems"}</h2>
              <p>
                {hasFilters
                  ? "Probá con otra búsqueda o limpiá los filtros."
                  : "Empezá creando una materia prima o un producto, o importá una planilla."}
              </p>
            </div>
          )}

          {rows.map((item) => (
            <div className="item-row-shell" key={item.id} data-type={item.item_type}>
              <Link to={`/inventory/items/${item.id}`} className="item-list-row">
                <span className="item-list-icon"><Boxes size={20} aria-hidden="true" /></span>
                <span className="item-list-copy">
                  <strong>{item.name}</strong>
                  <small>
                    {item.code}
                    {item.infinite_stock ? " · Stock infinito" : ""}
                  </small>
                </span>
                <span className="item-type-tag">{typeLabels[item.item_type]}</span>
                <span className={`item-status ${item.active ? "" : "inactive"}`}>
                  {item.active ? "Activo" : "Inactivo"}
                </span>
              </Link>
              <div className="item-row-actions">
                {can("items", "editar") && (
                  <Link className="button outline" to={`/inventory/items/${item.id}`}
                    aria-label={`Editar ${item.name}`}>
                    <Pencil size={15} aria-hidden="true" /> <span>Editar</span>
                  </Link>
                )}
                {can("stock_saldos", "ver") && !item.infinite_stock && (
                  <>
                    <Link className="button outline"
                      to={`/inventory/stock?q=${encodeURIComponent(item.code)}`}
                      aria-label={`Ver stock de ${item.name}`}>
                      <Warehouse size={15} aria-hidden="true" /> <span>Stock</span>
                    </Link>
                    <Link className="button outline"
                      to={`/inventory/movements?item=${item.id}&code=${encodeURIComponent(item.code)}`}
                      aria-label={`Ver movimientos de ${item.name}`}>
                      <ArrowRightLeft size={15} aria-hidden="true" /> <span>Movimientos</span>
                    </Link>
                  </>
                )}
                <CleanupButton
                  resource="items"
                  id={item.id}
                  label={`${item.code} · ${item.name}`}
                />
              </div>
            </div>
          ))}

          <div className="items-pagination">
            <span>{count} ítems · página {page + 1} de {pages}</span>
            <div>
              <button
                type="button"
                aria-label="Página anterior"
                disabled={page === 0}
                onClick={() => updateFilter("page", String(page - 1))}
              >
                <ChevronLeft size={18} />
              </button>
              <button
                type="button"
                aria-label="Página siguiente"
                disabled={page + 1 >= pages}
                onClick={() => updateFilter("page", String(page + 1))}
              >
                <ChevronRight size={18} />
              </button>
            </div>
          </div>
        </section>
        {showImport && <ItemImport onClose={closeImport} />}
      </div>
    </StockShell>
  );
}

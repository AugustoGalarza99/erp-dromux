import CleanupButton from "../../components/CleanupButton";
import { friendlyError } from "../../lib/notifications";
import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, useSearchParams } from "react-router-dom";
import {
  ArrowUpRight,
  Boxes,
  ChevronLeft,
  ChevronRight,
  FileUp,
  Plus,
  Search,
} from "lucide-react";
import { useAuth } from "../../contexts/AuthContext";
import { listItems } from "../../services/items";
import ItemImport from "./ItemImport";
import "./items.css";

const typeLabels = {
  raw_material: "Materia prima",
  semi_finished: "Semielaborado",
  finished_product: "Producto terminado",
  consumable: "Insumo",
};

export default function ItemsPage() {
  const { user, activeCompanyId, can } = useAuth();
  const [params, setParams] = useSearchParams();
  const [inputSearch, setInputSearch] = useState(params.get("q") ?? "");
  const [showImport, setShowImport] = useState(false);
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

  useEffect(() => {
    if (query.isSuccess && page >= pages && page > 0)
      updateFilter("page", String(pages - 1));
  }, [query.isSuccess, count, page]);

  const updateFilter = (field, value) => {
    const next = new URLSearchParams(params);
    if (value) next.set(field, value);
    else next.delete(field);
    if (field !== "page") next.delete("page");
    setParams(next);
  };

  return (
    <div className="items-page">
      <div className="page-head">
        <div>
          <span className="eyebrow">INVENTARIO / MAESTRO DE ÍTEMS</span>
          <h1>Ítems</h1>
          <p>
            Un catálogo para materiales, semielaborados, productos e insumos.
          </p>
        </div>
        {can("items", "insert") && (
          <div className="items-header-actions">
            <Link className="button" to="/archivados?type=items">
              Ver archivados
            </Link>
            <button
              type="button"
              className="button"
              onClick={() => setShowImport(true)}
            >
              <FileUp size={18} /> Importar productos
            </button>
            <Link
              to="/inventory/items/new"
              className="button primary items-add"
            >
              <Plus size={18} /> Nuevo ítem
            </Link>
          </div>
        )}
      </div>

      <div className="items-note">
        <Boxes size={20} />
        <span>
          Las existencias se calculan a partir de movimientos por depósito. Los
          ítems con stock infinito se pueden usar sin cargar un saldo inicial.
        </span>
      </div>

      <section className="items-panel">
        <div className="items-toolbar">
          <div className="items-search">
            <Search size={17} />
            <input
              aria-label="Buscar ítems por nombre"
              placeholder="Buscar por nombre"
              value={inputSearch}
              onChange={(event) => setInputSearch(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter")
                  updateFilter("q", inputSearch.trim());
              }}
            />
          </div>
          <button
            className="button items-search-button"
            onClick={() => updateFilter("q", inputSearch.trim())}
          >
            Buscar
          </button>
          <select
            aria-label="Filtrar por tipo"
            value={type}
            onChange={(event) => updateFilter("type", event.target.value)}
          >
            <option value="">Todos los tipos</option>
            {Object.entries(typeLabels).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
          <select
            aria-label="Filtrar por estado"
            value={status}
            onChange={(event) => updateFilter("status", event.target.value)}
          >
            <option value="active">Activos</option>
            <option value="inactive">Inactivos</option>
            <option value="all">Todos</option>
          </select>
        </div>

        {query.error && (
          <p role="alert" className="error">
            {friendlyError(query.error)}
          </p>
        )}
        {query.isPending && <p className="items-muted">Cargando ítems…</p>}
        {!query.isPending && !query.error && rows.length === 0 && (
          <div className="items-empty">
            <Boxes size={30} />
            <h2>Todavía no hay ítems para este filtro</h2>
            <p>Comenzá con una materia prima o un producto.</p>
          </div>
        )}

        {rows.map((item) => (
          <div className="item-row-shell" key={item.id}>
            <Link to={`/inventory/items/${item.id}`} className="item-list-row">
              <span className="item-list-icon">
                <Boxes size={20} />
              </span>
              <span className="item-list-copy">
                <strong>{item.name}</strong>
                <small>
                  {item.code}
                  {item.infinite_stock ? " · Stock infinito" : ""}
                </small>
              </span>
              <span className="item-type-tag">
                {typeLabels[item.item_type]}
              </span>
              <span className={`item-status ${item.active ? "" : "inactive"}`}>
                {item.active ? "Activo" : "Inactivo"}
              </span>
              <ArrowUpRight size={17} className="item-open" />
            </Link>
            <CleanupButton
              resource="items"
              id={item.id}
              label={`${item.code} · ${item.name}`}
            />
          </div>
        ))}

        <div className="items-pagination">
          <span>
            {count} ítems · página {page + 1} de {pages}
          </span>
          <div>
            <button
              aria-label="Página anterior"
              disabled={page === 0}
              onClick={() => updateFilter("page", String(page - 1))}
            >
              <ChevronLeft size={18} />
            </button>
            <button
              aria-label="Página siguiente"
              disabled={page + 1 >= pages}
              onClick={() => updateFilter("page", String(page + 1))}
            >
              <ChevronRight size={18} />
            </button>
          </div>
        </div>
      </section>
      {showImport && <ItemImport onClose={() => setShowImport(false)} />}
    </div>
  );
}

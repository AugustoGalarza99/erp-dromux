import { useMemo, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Plus, Search, Trash2 } from "lucide-react";
import ListPager, { usePagedList } from "../../components/ListPager";
import { useDebouncedValue } from "../../hooks/useDebouncedValue";
import { friendlyError } from "../../lib/notifications";
import { findPurchaseItems } from "../../services/purchases";

const normalize = (text) =>
  String(text ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "");
const money = (value) =>
  Number(value || 0).toLocaleString("es-AR", { style: "currency", currency: "ARS", maximumFractionDigits: 2 });

/*
 * Líneas de una orden de compra, pensadas para muchas líneas (D-007): se agregan con un
 * buscador, se listan en una tabla compacta con subtotal, filtro y paginación, y el precio
 * se carga solo desde la cotización del proveedor (se puede ajustar para esta orden).
 */
export default function PurchaseLinesEditor({
  companyId,
  userId,
  supplierId,
  lines,
  limit,
  disabled,
  onChange,
}) {
  const [query, setQuery] = useState("");
  const [picked, setPicked] = useState(null);
  const [amount, setAmount] = useState("");
  const [price, setPrice] = useState("");
  const [filter, setFilter] = useState("");
  const amountRef = useRef(null);
  const term = useDebouncedValue(query);
  const used = useMemo(() => new Set(lines.map((line) => line.item_id)), [lines]);

  const search = useQuery({
    queryKey: ["purchase-item-choices", userId, companyId, supplierId || null, term],
    queryFn: () => findPurchaseItems(companyId, term, supplierId || null),
    enabled: Boolean(companyId && !disabled && term.trim().length > 0 && !picked),
  });
  const matches = (search.data ?? []).filter((item) => !used.has(item.id)).slice(0, 8);

  const shown = useMemo(() => {
    const words = normalize(filter).split(/\s+/).filter(Boolean);
    return lines.filter((line) => words.every((word) => normalize(
      `${line.item?.code} ${line.item?.name}`).includes(word)));
  }, [lines, filter]);
  const pager = usePagedList(shown, { pageSize: 15, resetKey: filter });
  const full = lines.length >= limit;
  const validAmount = Number(amount) > 0 && Number(amount) < 1e12;
  const validPrice = price !== "" && Number(price) >= 0;
  const missingPrice = lines.filter((line) => line.unit_price === "" || line.unit_price == null).length;

  function pick(item) {
    setPicked(item);
    setPrice(String(supplierId ? item.supplier_unit_price ?? "" : item.reference_unit_cost ?? ""));
    setTimeout(() => amountRef.current?.focus(), 0);
  }

  function add(event) {
    event?.preventDefault?.();
    if (!picked || !validAmount || !validPrice || full) return;
    onChange([
      { id: crypto.randomUUID(), item_id: picked.id, item: picked, quantity: amount, unit_price: price },
      ...lines,
    ]);
    setPicked(null);
    setAmount("");
    setPrice("");
    setQuery("");
  }

  const update = (id, patch) => onChange(lines.map((line) => (line.id === id ? { ...line, ...patch } : line)));

  return (
    <div className="po-lines">
      <div className="po-lines-head">
        <h3>
          Ítems de la orden <span className="mod-chip">{lines.length} de {limit}</span>
        </h3>
        {missingPrice > 0 && (
          <span className="mod-chip is-urgent">
            {missingPrice} sin precio
          </span>
        )}
      </div>

      {!disabled && (
        <div className="po-add" role="group" aria-label="Agregar ítem">
          <div className="po-add-search">
            <label>
              Agregar ítem
              <span className="po-search-field">
                <Search size={16} aria-hidden="true" />
                <input
                  type="search"
                  value={picked ? `${picked.code} · ${picked.name}` : query}
                  maxLength={100}
                  disabled={full}
                  placeholder={supplierId
                    ? "Buscá entre los ítems de este proveedor…"
                    : "Buscá por código, nombre o código de barras…"}
                  onChange={(event) => {
                    setPicked(null);
                    setQuery(event.target.value);
                  }}
                />
              </span>
            </label>
            {!picked && matches.length > 0 && (
              <ul className="po-matches" role="listbox" aria-label="Resultados">
                {matches.map((item) => (
                  <li key={item.id} role="option" aria-selected="false">
                    <button type="button" onClick={() => pick(item)}>
                      <strong>{item.name}</strong>
                      <small>{item.code} · {item.unit_symbol}</small>
                      <span>
                        {supplierId
                          ? (item.supplier_unit_price != null ? money(item.supplier_unit_price) : "Sin cotización")
                          : (item.reference_unit_cost != null ? money(item.reference_unit_cost) : "Sin costo")}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
            {!picked && term.trim() && !search.isFetching && !matches.length && (
              <p className="mod-muted">
                {supplierId
                  ? "Este proveedor no tiene ítems con ese texto. Cargá su cotización en Proveedores."
                  : "No hay ítems con ese texto (los ya agregados no se repiten)."}
              </p>
            )}
            {search.error && <small className="error">{friendlyError(search.error)}</small>}
          </div>
          <label>
            Cantidad {picked?.unit_symbol ? `(${picked.unit_symbol})` : ""}
            <input
              ref={amountRef}
              type="number"
              min="0.000001"
              max="999999999999"
              step="0.000001"
              value={amount}
              disabled={!picked}
              onChange={(event) => setAmount(event.target.value)}
            />
          </label>
          <label>
            Precio unitario
            <input
              type="number"
              min="0"
              step="0.01"
              value={price}
              disabled={!picked}
              placeholder="0,00"
              onChange={(event) => setPrice(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter") add(event);
              }}
            />
          </label>
          <button type="button" className="button primary" disabled={!picked || !validAmount || !validPrice || full}
            onClick={add}>
            <Plus size={16} aria-hidden="true" /> Agregar
          </button>
        </div>
      )}
      {full && (
        <p className="production-form-error" role="alert">
          Se alcanzó el máximo de {limit} ítems por orden. Creá otra orden para el resto.
        </p>
      )}

      {lines.length > 8 && (
        <label className="po-filter">
          <span className="sr-only">Filtrar los ítems de la orden</span>
          <input type="search" value={filter} placeholder="Filtrar los ítems de esta orden"
            onChange={(event) => setFilter(event.target.value)} />
        </label>
      )}

      {!lines.length ? (
        <p className="replenishment-empty">
          Todavía no agregaste ítems. Buscá uno arriba, indicá cantidad y precio y presioná Agregar.
        </p>
      ) : (
        <div className="mod-table-wrap">
          <table className="mod-table po-table">
            <thead>
              <tr>
                <th scope="col">Ítem</th>
                <th scope="col" className="is-num">Cantidad</th>
                <th scope="col" className="is-num">Precio unitario</th>
                <th scope="col" className="is-num">Subtotal</th>
                <th scope="col"><span className="sr-only">Quitar</span></th>
              </tr>
            </thead>
            <tbody>
              {pager.visible.map((line) => {
                const subtotal = Number(line.quantity || 0) * Number(line.unit_price || 0);
                return (
                  <tr key={line.id} className={line.unit_price === "" ? "is-attention" : ""}>
                    <td className="is-name" data-label="Ítem">
                      <strong>{line.item?.name ?? "Ítem"}</strong>
                      <small>{line.item?.code} · {line.item?.unit_symbol}</small>
                    </td>
                    <td className="is-num" data-label="Cantidad">
                      <input
                        aria-label={`Cantidad de ${line.item?.name ?? "ítem"}`}
                        type="number"
                        required
                        min="0.000001"
                        max="999999999999"
                        step="0.000001"
                        disabled={disabled}
                        value={line.quantity}
                        onChange={(event) => update(line.id, { quantity: event.target.value })}
                      />
                    </td>
                    <td className="is-num" data-label="Precio unitario">
                      <input
                        aria-label={`Precio de ${line.item?.name ?? "ítem"}`}
                        type="number"
                        required
                        min="0"
                        step="0.01"
                        disabled={disabled}
                        value={line.unit_price}
                        onChange={(event) => update(line.id, { unit_price: event.target.value })}
                      />
                    </td>
                    <td className="is-num" data-label="Subtotal"><strong>{money(subtotal)}</strong></td>
                    <td data-label="">
                      <button
                        type="button"
                        className="production-icon"
                        aria-label={`Quitar ${line.item?.name ?? "ítem"}`}
                        disabled={disabled}
                        onClick={() => onChange(lines.filter((entry) => entry.id !== line.id))}
                      >
                        <Trash2 size={17} />
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
      <ListPager pager={pager} noun="ítems" sizes={[15, 30, 60]} />
    </div>
  );
}

import { useMemo, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { PencilLine, Plus, Search, Trash2 } from "lucide-react";
import ListPager, { usePagedList } from "../../../compartido/componentes/ListPager";
import { useDebouncedValue } from "../../../compartido/hooks/useDebouncedValue";
import { friendlyError } from "../../../compartido/utilidades/notifications";
import { findRequestItems } from "./purchaseRequests";
import { itemTypeLabels } from "../../stock/items/itemTypes";

const normalize = (text) =>
  String(text ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "");

/*
 * Líneas de un pedido interno. Se elige un material del catálogo con el buscador o, si no existe o
 * no está cargado, se escribe a mano ("No lo encuentro"). No muestra costos ni precios.
 */
export default function PurchaseRequestLinesEditor({ companyId, userId, lines, limit, disabled, onChange }) {
  const [mode, setMode] = useState("catalog");
  const [query, setQuery] = useState("");
  const [picked, setPicked] = useState(null);
  const [freeName, setFreeName] = useState("");
  const [freeUnit, setFreeUnit] = useState("");
  const [amount, setAmount] = useState("");
  const [lineNote, setLineNote] = useState("");
  const [filter, setFilter] = useState("");
  const amountRef = useRef(null);
  const term = useDebouncedValue(query);
  const used = useMemo(() => new Set(lines.map((line) => line.item_id).filter(Boolean)), [lines]);

  const search = useQuery({
    queryKey: ["request-item-options", userId, companyId, term],
    queryFn: () => findRequestItems(companyId, term),
    enabled: Boolean(companyId && !disabled && mode === "catalog" && term.trim().length > 0 && !picked),
  });
  const matches = (search.data ?? []).filter((item) => !used.has(item.id)).slice(0, 8);

  const shown = useMemo(() => {
    const words = normalize(filter).split(/\s+/).filter(Boolean);
    return lines.filter((line) => words.every((word) => normalize(`${line.name} ${line.code}`).includes(word)));
  }, [lines, filter]);
  const pager = usePagedList(shown, { pageSize: 15, resetKey: filter });
  const full = lines.length >= limit;
  const validAmount = Number(amount) > 0 && Number(amount) < 1e12;
  const canAdd = validAmount && !full
    && (mode === "catalog" ? Boolean(picked) : freeName.trim().length >= 2);

  function add(event) {
    event?.preventDefault?.();
    if (!canAdd) return;
    const base = { id: crypto.randomUUID(), quantity: amount, note: lineNote };
    onChange([
      mode === "catalog"
        ? { ...base, item_id: picked.id, name: picked.name, code: picked.code, unit: picked.unit_symbol, type: picked.item_type }
        : { ...base, item_id: null, name: freeName.trim(), code: "", unit: freeUnit.trim(), type: "" },
      ...lines,
    ]);
    setPicked(null);
    setQuery("");
    setFreeName("");
    setFreeUnit("");
    setAmount("");
    setLineNote("");
  }

  const update = (id, patch) => onChange(lines.map((line) => (line.id === id ? { ...line, ...patch } : line)));

  return (
    <div className="po-lines">
      <div className="po-lines-head">
        <h3>
          Lo que necesitás <span className="mod-chip">{lines.length} de {limit}</span>
        </h3>
        {lines.some((line) => !line.item_id) && (
          <span className="mod-chip">
            {lines.filter((line) => !line.item_id).length} escrito{lines.filter((line) => !line.item_id).length === 1 ? "" : "s"} a mano
          </span>
        )}
      </div>

      {!disabled && (
        <div className="pr-add" role="group" aria-label="Agregar material">
          <div className="mod-segments" role="group" aria-label="Cómo agregar">
            <button type="button" className="mod-segment" aria-pressed={mode === "catalog"}
              onClick={() => { setMode("catalog"); setPicked(null); }}>
              <Search size={15} aria-hidden="true" /> Buscar en el catálogo
            </button>
            <button type="button" className="mod-segment" aria-pressed={mode === "free"}
              onClick={() => { setMode("free"); setPicked(null); }}>
              <PencilLine size={15} aria-hidden="true" /> No lo encuentro: escribirlo
            </button>
          </div>

          <div className="pr-add-fields">
            {mode === "catalog" ? (
              <div className="po-add-search">
                <label>
                  Material o insumo
                  <span className="po-search-field">
                    <Search size={16} aria-hidden="true" />
                    <input
                      type="search"
                      value={picked ? `${picked.code} · ${picked.name}` : query}
                      maxLength={100}
                      disabled={full}
                      placeholder="Buscá por nombre o código…"
                      onChange={(event) => { setPicked(null); setQuery(event.target.value); }}
                    />
                  </span>
                </label>
                {!picked && matches.length > 0 && (
                  <ul className="po-matches" role="listbox" aria-label="Resultados">
                    {matches.map((item) => (
                      <li key={item.id} role="option" aria-selected="false">
                        <button type="button" onClick={() => { setPicked(item); setTimeout(() => amountRef.current?.focus(), 0); }}>
                          <strong>{item.name}</strong>
                          <small>{item.code} · {item.unit_symbol}</small>
                          <span>{itemTypeLabels[item.item_type]}</span>
                        </button>
                      </li>
                    ))}
                  </ul>
                )}
                {!picked && term.trim() && !search.isFetching && !matches.length && (
                  <p className="mod-muted">
                    No hay nada con ese texto. Si el material no está cargado, usá “No lo encuentro: escribirlo”.
                  </p>
                )}
                {search.error && <small className="error">{friendlyError(search.error)}</small>}
              </div>
            ) : (
              <>
                <label className="pr-free-name">
                  Qué necesitás *
                  <input value={freeName} maxLength={160} disabled={full}
                    placeholder="Ej.: guantes talle M, tornillos de 5 cm, etiquetas adhesivas"
                    onChange={(event) => setFreeName(event.target.value)} />
                </label>
                <label>
                  Unidad
                  <input value={freeUnit} maxLength={20} disabled={full} placeholder="un, kg, caja…"
                    onChange={(event) => setFreeUnit(event.target.value)} />
                </label>
              </>
            )}
            <label>
              Cantidad {picked?.unit_symbol ? `(${picked.unit_symbol})` : ""}
              <input ref={amountRef} type="number" min="0.000001" max="999999999999" step="0.000001"
                value={amount} disabled={full || (mode === "catalog" && !picked)}
                onChange={(event) => setAmount(event.target.value)} />
            </label>
            <label className="pr-line-note">
              Detalle (opcional)
              <input value={lineNote} maxLength={200} disabled={full}
                placeholder="Marca, medida, para qué se usa…"
                onChange={(event) => setLineNote(event.target.value)}
                onKeyDown={(event) => { if (event.key === "Enter") add(event); }} />
            </label>
            <button type="button" className="button primary" disabled={!canAdd} onClick={add}>
              <Plus size={16} aria-hidden="true" /> Agregar
            </button>
          </div>
        </div>
      )}
      {full && (
        <p className="production-form-error" role="alert">
          Se alcanzó el máximo de {limit} líneas por pedido. Hacé otro pedido para el resto.
        </p>
      )}

      {lines.length > 8 && (
        <label className="po-filter">
          <span className="sr-only">Filtrar las líneas del pedido</span>
          <input type="search" value={filter} placeholder="Filtrar las líneas de este pedido"
            onChange={(event) => setFilter(event.target.value)} />
        </label>
      )}

      {!lines.length ? (
        <p className="replenishment-empty">
          Todavía no agregaste nada. Buscá un material arriba o escribí lo que necesitás.
        </p>
      ) : (
        <div className="mod-table-wrap">
          <table className="mod-table po-table">
            <thead>
              <tr>
                <th scope="col">Material</th>
                <th scope="col" className="is-num">Cantidad</th>
                <th scope="col">Detalle</th>
                <th scope="col"><span className="sr-only">Quitar</span></th>
              </tr>
            </thead>
            <tbody>
              {pager.visible.map((line) => (
                <tr key={line.id} className={line.item_id ? "" : "is-attention"}>
                  <td className="is-name" data-label="Material">
                    <strong>{line.name}</strong>
                    <small>
                      {line.item_id ? `${line.code} · ${line.unit}` : "Escrito a mano · no está en el catálogo"}
                    </small>
                  </td>
                  <td className="is-num" data-label="Cantidad">
                    <input
                      aria-label={`Cantidad de ${line.name}`}
                      type="number" required min="0.000001" max="999999999999" step="0.000001"
                      disabled={disabled} value={line.quantity}
                      onChange={(event) => update(line.id, { quantity: event.target.value })}
                    />
                    {!line.item_id && line.unit && <small> {line.unit}</small>}
                  </td>
                  <td data-label="Detalle">
                    <input
                      aria-label={`Detalle de ${line.name}`} maxLength={200} disabled={disabled}
                      value={line.note} placeholder="—"
                      onChange={(event) => update(line.id, { note: event.target.value })}
                    />
                  </td>
                  <td data-label="">
                    <button type="button" className="production-icon" aria-label={`Quitar ${line.name}`}
                      disabled={disabled} onClick={() => onChange(lines.filter((entry) => entry.id !== line.id))}>
                      <Trash2 size={17} />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <ListPager pager={pager} noun="líneas" sizes={[15, 30, 60]} />
    </div>
  );
}

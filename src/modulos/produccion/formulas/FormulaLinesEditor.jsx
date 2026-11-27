import { useMemo, useRef, useState } from "react";
import { Plus, Search, Trash2, Undo2 } from "lucide-react";
import ListPager, { usePagedList } from "../../components/ListPager";
import { itemTypeLabels } from "../inventory/itemTypes";

const normalize = (text) =>
  String(text ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "");

/*
 * Editor de componentes de una fórmula, pensado para muchos componentes (D-007):
 * se agregan con un buscador (no con un renglón en blanco por componente), se listan en
 * una tabla compacta con filtro y paginación, y cada línea indica si es nueva o cambió
 * respecto de la versión guardada. Los componentes quitados se pueden recuperar.
 */
export default function FormulaLinesEditor({
  components,
  lines,
  baseline,
  limit,
  disabled,
  onChange,
}) {
  const [query, setQuery] = useState("");
  const [picked, setPicked] = useState(null);
  const [amount, setAmount] = useState("");
  const [filter, setFilter] = useState("");
  const amountRef = useRef(null);
  const byId = useMemo(() => new Map(components.map((item) => [item.id, item])), [components]);
  const used = useMemo(() => new Set(lines.map((line) => line.componentId)), [lines]);
  const saved = useMemo(
    () => new Map(baseline.map((line) => [line.componentId, String(line.quantity)])),
    [baseline],
  );

  const matches = useMemo(() => {
    const words = normalize(query).split(/\s+/).filter(Boolean);
    if (!words.length) return [];
    return components
      .filter((item) => !used.has(item.id)
        && words.every((word) => normalize(`${item.code} ${item.name}`).includes(word)))
      .slice(0, 8);
  }, [components, used, query]);

  const removed = baseline.filter((line) => !used.has(line.componentId));
  const stateOf = (line) => (!saved.has(line.componentId)
    ? "new"
    : Number(saved.get(line.componentId)) !== Number(line.quantity) ? "changed" : "same");

  const shown = useMemo(() => {
    const words = normalize(filter).split(/\s+/).filter(Boolean);
    return lines.filter((line) => {
      const item = byId.get(line.componentId);
      return words.every((word) => normalize(`${item?.code} ${item?.name}`).includes(word));
    });
  }, [lines, filter, byId]);
  const pager = usePagedList(shown, { pageSize: 15, resetKey: filter });

  const counts = {
    added: lines.filter((line) => stateOf(line) === "new").length,
    changed: lines.filter((line) => stateOf(line) === "changed").length,
    removed: removed.length,
  };
  const full = lines.length >= limit;
  const validAmount = Number(amount) > 0 && Number(amount) < 1e12;

  // No es un <form>: este editor vive dentro del formulario de la fórmula y los formularios no se anidan.
  function add(event) {
    event?.preventDefault?.();
    if (!picked || !validAmount || full) return;
    onChange([{ key: crypto.randomUUID(), componentId: picked.id, quantity: amount }, ...lines]);
    setPicked(null);
    setAmount("");
    setQuery("");
  }

  function update(key, patch) {
    onChange(lines.map((line) => (line.key === key ? { ...line, ...patch } : line)));
  }

  return (
    <div className="formula-lines">
      <div className="formula-lines-head">
        <h3>
          Componentes <span className="mod-chip">{lines.length} de {limit}</span>
        </h3>
        {(counts.added > 0 || counts.changed > 0 || counts.removed > 0) && (
          <p className="formula-changes" role="status">
            Cambios sin guardar:
            {counts.added > 0 && <b className="is-new">{counts.added} nuevo{counts.added === 1 ? "" : "s"}</b>}
            {counts.changed > 0 && <b className="is-changed">{counts.changed} modificado{counts.changed === 1 ? "" : "s"}</b>}
            {counts.removed > 0 && <b className="is-removed">{counts.removed} quitado{counts.removed === 1 ? "" : "s"}</b>}
          </p>
        )}
      </div>

      {!disabled && (
        <div className="formula-add" role="group" aria-label="Agregar componente">
          <div className="formula-add-search">
            <label>
              Agregar componente
              <span className="formula-search-field">
                <Search size={16} aria-hidden="true" />
                <input
                  type="search"
                  value={picked ? `${picked.code} · ${picked.name}` : query}
                  placeholder="Buscá por nombre o código…"
                  disabled={full}
                  onChange={(event) => {
                    setPicked(null);
                    setQuery(event.target.value);
                  }}
                />
              </span>
            </label>
            {!picked && matches.length > 0 && (
              <ul className="formula-matches" role="listbox" aria-label="Resultados">
                {matches.map((item) => (
                  <li key={item.id} role="option" aria-selected="false">
                    <button
                      type="button"
                      data-type={item.item_type}
                      onClick={() => {
                        setPicked(item);
                        setTimeout(() => amountRef.current?.focus(), 0);
                      }}
                    >
                      <strong>{item.name}</strong>
                      <small>{item.code} · {item.units?.symbol}</small>
                      <span className="formula-type">{itemTypeLabels[item.item_type]}</span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
            {!picked && query.trim() && matches.length === 0 && (
              <p className="mod-muted">No hay materiales disponibles con ese texto (los ya agregados no se repiten).</p>
            )}
          </div>
          <label>
            Cantidad {picked?.units?.symbol ? `(${picked.units.symbol})` : ""}
            <input
              ref={amountRef}
              type="number"
              min="0.000001"
              max="999999999999"
              step="0.000001"
              value={amount}
              disabled={!picked}
              placeholder="0"
              onChange={(event) => setAmount(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter") add(event);
              }}
            />
          </label>
          <button type="button" className="button primary" disabled={!picked || !validAmount || full}
            onClick={add}>
            <Plus size={16} aria-hidden="true" /> Agregar
          </button>
        </div>
      )}
      {full && (
        <p className="production-form-error" role="alert">
          Se alcanzó el máximo de {limit} componentes por fórmula.
        </p>
      )}

      {lines.length > 8 && (
        <label className="formula-filter">
          <span className="sr-only">Filtrar componentes de la fórmula</span>
          <input type="search" value={filter} placeholder="Filtrar los componentes de esta fórmula"
            onChange={(event) => setFilter(event.target.value)} />
        </label>
      )}

      {!lines.length ? (
        <p className="replenishment-empty">
          Todavía no hay componentes. Buscá un material arriba y agregalo con su cantidad.
        </p>
      ) : (
        <div className="mod-table-wrap">
          <table className="mod-table formula-table">
            <thead>
              <tr>
                <th scope="col">Componente</th>
                <th scope="col" className="is-num">Cantidad</th>
                <th scope="col">Cambio</th>
                <th scope="col"><span className="sr-only">Quitar</span></th>
              </tr>
            </thead>
            <tbody>
              {pager.visible.map((line) => {
                const item = byId.get(line.componentId);
                const state = stateOf(line);
                return (
                  <tr key={line.key} className={`formula-row is-${state}`}>
                    <td className="is-name" data-label="Componente">
                      <strong>{item?.name ?? "Componente"}</strong>
                      <small>
                        {item?.code}
                        {item?.item_type && (
                          <span className="formula-type" data-type={item.item_type}>
                            {itemTypeLabels[item.item_type]}
                          </span>
                        )}
                      </small>
                    </td>
                    <td className="is-num" data-label="Cantidad">
                      <span className="formula-qty">
                        <input
                          aria-label={`Cantidad de ${item?.name ?? "componente"}`}
                          type="number"
                          required
                          min="0.000001"
                          max="999999999999"
                          step="0.000001"
                          disabled={disabled}
                          value={line.quantity}
                          onChange={(event) => update(line.key, { quantity: event.target.value })}
                        />
                        <span>{item?.units?.symbol}</span>
                      </span>
                    </td>
                    <td data-label="Cambio">
                      {state === "new" && <span className="mod-chip is-ok">Nuevo</span>}
                      {state === "changed" && (
                        <span className="mod-chip formula-chip-changed">
                          Antes {saved.get(line.componentId)}
                        </span>
                      )}
                      {state === "same" && <span className="mod-muted">Sin cambios</span>}
                    </td>
                    <td data-label="">
                      <button
                        type="button"
                        className="production-icon"
                        aria-label={`Quitar ${item?.name ?? "componente"}`}
                        disabled={disabled}
                        onClick={() => onChange(lines.filter((entry) => entry.key !== line.key))}
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
      <ListPager pager={pager} noun="componentes" sizes={[15, 30, 60]} />

      {removed.length > 0 && (
        <details className="formula-removed">
          <summary>{removed.length} componente{removed.length === 1 ? "" : "s"} quitado{removed.length === 1 ? "" : "s"} (se eliminan al guardar)</summary>
          <ul>
            {removed.map((line) => {
              const item = byId.get(line.componentId);
              return (
                <li key={line.componentId}>
                  <span>{item?.name ?? "Componente"} · {line.quantity} {item?.units?.symbol}</span>
                  <button
                    type="button"
                    className="button outline"
                    disabled={full}
                    onClick={() => onChange([...lines, {
                      key: crypto.randomUUID(),
                      componentId: line.componentId,
                      quantity: String(line.quantity),
                    }])}
                  >
                    <Undo2 size={15} aria-hidden="true" /> Recuperar
                  </button>
                </li>
              );
            })}
          </ul>
        </details>
      )}
    </div>
  );
}

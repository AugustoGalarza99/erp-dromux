import { useMemo, useState } from "react";
import { PackageCheck } from "lucide-react";
import ListPager, { usePagedList } from "../../../compartido/componentes/ListPager";
import { lotLabel } from "../../../compartido/utilidades/display";
import { formatQuantity } from "../../stock/compartido/stockNumber";

const normalize = (text) =>
  String(text ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "");

/*
 * Insumos de una orden: resumen de avance + tabla compacta con filtros y paginación.
 * Pensada para fórmulas de 200+ componentes (D-007): lo pendiente va primero y el
 * detalle de depósitos/lotes asignados queda plegado en cada fila.
 */
export default function JobComponentsTable({
  expected,
  net,
  allocations,
  warehouses,
  items,
  active,
}) {
  // Orden activa: interesa lo que falta entregar. Cerrada: lo usado frente a la fórmula.
  const [filter, setFilter] = useState(active ? "pending" : "all");
  const [search, setSearch] = useState("");
  const itemOf = (id) => items.find((item) => item.id === id);

  const rows = useMemo(() => {
    const planned = expected.map((entry) => {
      const issued = net.get(entry.component_id) ?? 0;
      const slots = allocations.filter((row) => row.component_id === entry.component_id);
      return {
        id: entry.component_id,
        expected: Number(entry.quantity),
        issued,
        pending: Math.max(0, Number(entry.quantity) - issued),
        assigned: slots.reduce((sum, row) => sum + Number(row.quantity), 0),
        slots,
        extra: false,
      };
    });
    const known = new Set(expected.map((entry) => entry.component_id));
    const extras = [...net]
      .filter(([id, quantity]) => quantity > 0.000001 && !known.has(id))
      .map(([id, quantity]) => ({
        id, expected: 0, issued: quantity, pending: 0, assigned: 0, slots: [], extra: true,
      }));
    return [...planned, ...extras].map((row) => ({
      ...row,
      name: itemOf(row.id)?.name ?? "Insumo",
      code: itemOf(row.id)?.code ?? "",
      unit: itemOf(row.id)?.units?.symbol ?? "",
      done: active
        ? row.pending <= 0.000001
        : !row.extra && Math.abs(row.issued - row.expected) <= 0.000001,
    }));
  }, [expected, net, allocations, items, active]);

  const counts = {
    pending: rows.filter((row) => !row.done && (active || !row.extra)).length,
    done: rows.filter((row) => row.done && !row.extra).length,
    extra: rows.filter((row) => row.extra).length,
  };
  const total = expected.length;
  const covered = counts.done;
  const percent = total ? Math.round((covered / total) * 100) : 100;

  const filtered = useMemo(() => {
    const words = normalize(search).split(/\s+/).filter(Boolean);
    return rows
      .filter((row) => (filter === "all"
        || (filter === "pending" && !row.done && (active || !row.extra))
        || (filter === "done" && row.done && !row.extra)
        || (filter === "extra" && row.extra))
        && words.every((word) => normalize(`${row.name} ${row.code}`).includes(word)))
      .sort((a, b) => Number(a.done) - Number(b.done) || b.pending - a.pending
        || a.name.localeCompare(b.name));
  }, [rows, filter, search]);

  const pager = usePagedList(filtered, { pageSize: 15, resetKey: `${filter}|${search}` });
  const segments = [
    ["pending", active ? "Pendientes" : "Con diferencia", counts.pending],
    ["done", active ? "Cubiertos" : "Según fórmula", counts.done],
    ...(counts.extra ? [["extra", "Adicionales", counts.extra]] : []),
    ["all", "Todos", rows.length],
  ];
  if (!rows.length) return null;

  return (
    <details className="job-components" open={rows.length <= 8 || undefined}>
      <summary>
        <PackageCheck size={16} aria-hidden="true" />
        Insumos de la fórmula ·{" "}
        {active ? `${covered} de ${total} cubiertos` : `${covered} de ${total} según lo previsto`}
        {counts.extra > 0 && ` · ${counts.extra} adicionales`}
      </summary>
      {active && (
        <div
          className="job-progress-bar"
          role="progressbar"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={percent}
          aria-label="Insumos cubiertos"
        >
          <span style={{ width: `${percent}%` }} />
        </div>
      )}

      {rows.length > 8 && (
        <div className="job-components-tools">
          <div className="mod-segments" role="group" aria-label="Filtrar insumos">
            {segments.map(([value, label, count]) => (
              <button key={value} type="button" className="mod-segment"
                aria-pressed={filter === value} onClick={() => setFilter(value)}>
                {label} <b>{count}</b>
              </button>
            ))}
          </div>
          <label className="job-components-search">
            <span className="sr-only">Buscar insumo</span>
            <input type="search" value={search} placeholder="Buscar insumo por nombre o código"
              onChange={(event) => setSearch(event.target.value)} />
          </label>
        </div>
      )}

      {!filtered.length ? (
        <p className="mod-muted">
          {filter === "pending" ? "No quedan insumos pendientes de entrega." : "No hay insumos con este filtro."}
        </p>
      ) : (
        <div className="mod-table-wrap">
          <table className="mod-table job-components-table">
            <thead>
              <tr>
                <th scope="col">Insumo</th>
                <th scope="col" className="is-num">Previsto</th>
                <th scope="col" className="is-num">{active ? "Entregado" : "Usado"}</th>
                {active && <th scope="col" className="is-num">Asignado</th>}
                <th scope="col">Estado</th>
              </tr>
            </thead>
            <tbody>
              {pager.visible.map((row) => (
                <tr key={row.id} className={row.done || !active ? "" : "is-attention"}>
                  <td className="is-name" data-label="Insumo">
                    <strong>{row.name}</strong>
                    <small>{row.code}{row.extra ? " · adicional" : ""}</small>
                    {row.slots.length > 0 && (
                      <details className="mod-row-detail">
                        <summary>Dónde está asignado</summary>
                        <ul className="job-slots">
                          {row.slots.map((slot) => (
                            <li key={`${slot.warehouse_id}:${slot.lot_code ?? ""}`}>
                              {warehouses.find((entry) => entry.id === slot.warehouse_id)?.name ?? "Depósito"}
                              {slot.lot_code && ` · Lote ${lotLabel(slot.lot_code)}`}
                              {" · "}{formatQuantity(slot.quantity)} {row.unit}
                            </li>
                          ))}
                        </ul>
                      </details>
                    )}
                  </td>
                  <td className="is-num" data-label="Previsto">{row.extra ? "—" : `${formatQuantity(row.expected)} ${row.unit}`}</td>
                  <td className="is-num" data-label={active ? "Entregado" : "Usado"}>{formatQuantity(row.issued.toFixed(6))} {row.unit}</td>
                  {active && (
                    <td className="is-num" data-label="Asignado">{formatQuantity(row.assigned.toFixed(6))} {row.unit}</td>
                  )}
                  <td data-label="Estado">
                    {row.extra ? (
                      <span className="mod-chip">Adicional</span>
                    ) : row.done ? (
                      <span className="mod-chip is-ok">{active ? "Cubierto" : "Según fórmula"}</span>
                    ) : !active ? (
                      <span className="mod-chip">
                        {row.issued <= 0.000001
                          ? "No se usó"
                          : `Se usó ${formatQuantity(Math.abs(row.issued - row.expected).toFixed(6))} ${row.unit} ${row.issued > row.expected ? "más" : "menos"}`}
                      </span>
                    ) : (
                      <span className="mod-chip is-urgent">
                        Falta {formatQuantity(row.pending.toFixed(6))} {row.unit}
                      </span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <ListPager pager={pager} noun="insumos" sizes={[15, 30, 60]} />
    </details>
  );
}

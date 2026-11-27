import { useMemo, useRef, useState } from "react";
import { AlertTriangle, ArrowDownToLine, ArrowUpFromLine } from "lucide-react";
import ActionDialog from "../../../compartido/componentes/ActionDialog";
import ListPager, { usePagedList } from "../../../compartido/componentes/ListPager";
import { notifyError, notifySuccess } from "../../../compartido/utilidades/notifications";
import { lotLabel } from "../../../compartido/utilidades/display";
import { finishProductionJobAdjusted } from "../compartido/production";
import { formatQuantity } from "../../stock/compartido/stockNumber";
import "./finishJob.css";

/*
 * Terminar la fabricación en dos pasos:
 *  1) Cargar lo que realmente salió, lo que realmente se usó de cada insumo y el recuento de envases.
 *  2) Revisar y confirmar los movimientos de stock que se van a hacer (ingreso del producto, insumos
 *     adicionales que descuentan y sobrantes que vuelven). Todo se registra en una sola operación.
 * Sirve para cualquier rubro: la fórmula define los insumos; los envases son datos configurables.
 */
const EPS = 0.000001;
const validNumber = (value) => /^\d+(?:\.\d{1,6})?$/.test(String(value)) && Number(value) < 1000000000000;
const q = (value) => formatQuantity(Number(value ?? 0).toFixed(6));
const round6 = (value) => Number(Number(value).toFixed(6));

const migrationMissing = (error) =>
  /Could not find the function|PGRST202|42883/i.test(`${error?.code ?? ""} ${error?.message ?? ""}`);

export default function FinishJobDialog({
  job,
  product,
  items,
  warehouses,
  events,
  allocations = [],
  companyId,
  onClose,
  onFinished,
}) {
  const unit = product?.units?.symbol ?? "";
  const expectedOutput = Number(job.expected_output ?? job.planned_quantity);
  const formula = job.formula_snapshot ?? [];
  const itemById = useMemo(() => new Map(items.map((item) => [item.id, item])), [items]);
  const warehouseName = (id) => warehouses.find((entry) => entry.id === id)?.name ?? "Depósito";

  const [step, setStep] = useState("form");
  const [actual, setActual] = useState(String(job.actual_quantity ?? expectedOutput));
  const [outputLot, setOutputLot] = useState(job.output_lot ?? "");
  const [expiresOn, setExpiresOn] = useState(job.output_expiry ?? "");
  const [varianceNote, setVarianceNote] = useState(job.variance_note ?? "");
  const [search, setSearch] = useState("");
  const [onlyDiff, setOnlyDiff] = useState(false);
  const [busy, setBusy] = useState(false);
  const [errorMsg, setErrorMsg] = useState("");
  const request = useRef(null);

  // Entregado neto por insumo y último origen (depósito y lote) de cada uno.
  const { delivered, origin } = useMemo(() => {
    const net = new Map();
    const last = new Map();
    const sorted = [...events].sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
    for (const event of sorted) {
      net.set(event.component_id, (net.get(event.component_id) ?? 0)
        + (event.kind === "entrega" ? 1 : -1) * Number(event.quantity));
      if (event.kind === "entrega") {
        last.set(event.component_id, { warehouseId: event.warehouse_id, lotCode: event.lot_code ?? "" });
      }
    }
    return { delivered: net, origin: last };
  }, [events]);

  const rows = useMemo(() => {
    const ids = new Set(formula.map((line) => line.component_id));
    for (const [id, amount] of delivered) if (amount > EPS) ids.add(id);
    return [...ids].map((id) => {
      const item = itemById.get(id);
      const planned = Number(formula.find((line) => line.component_id === id)?.quantity ?? 0);
      const given = round6(Math.max(0, delivered.get(id) ?? 0));
      return {
        id,
        name: item?.name ?? "Insumo",
        code: item?.code ?? "",
        unit: item?.units?.symbol ?? "",
        trackLots: Boolean(item?.track_lots),
        planned,
        delivered: given,
        outside: !formula.some((line) => line.component_id === id),
      };
    }).sort((a, b) =>
      Number(b.planned !== b.delivered) - Number(a.planned !== a.delivered)
      || a.name.localeCompare(b.name, "es"));
  }, [formula, delivered, itemById]);

  const [used, setUsed] = useState(() => ({}));
  const [sources, setSources] = useState(() => ({}));
  const usedOf = (row) => used[row.id] ?? String(row.delivered);

  function sourceFor(row) {
    const previous = origin.get(row.id);
    const allocation = allocations.find((entry) => entry.component_id === row.id);
    return {
      warehouseId: sources[row.id] ?? previous?.warehouseId ?? allocation?.warehouse_id ?? job.warehouse_id,
      lotCode: previous?.lotCode ?? allocation?.lot_code ?? "",
    };
  }

  const analysis = useMemo(() => {
    const adjustments = [];
    const invalid = [];
    let mismatch = Math.abs(Number(actual) - expectedOutput) > EPS;
    for (const row of rows) {
      const text = used[row.id] ?? String(row.delivered);
      if (!validNumber(text)) { invalid.push(row.id); continue; }
      const value = round6(Number(text));
      if (Math.abs(value - row.planned) > EPS) mismatch = true;
      const delta = round6(value - row.delivered);
      if (delta > EPS) {
        const previous = origin.get(row.id);
        const allocation = allocations.find((entry) => entry.component_id === row.id);
        const lotCode = previous?.lotCode ?? allocation?.lot_code ?? "";
        adjustments.push({
          kind: "entrega",
          componentId: row.id,
          warehouseId: sources[row.id] ?? previous?.warehouseId ?? allocation?.warehouse_id ?? job.warehouse_id,
          lotCode,
          quantity: String(delta),
          note: "se usó más de lo entregado",
          row,
        });
        if (row.trackLots && !lotCode) invalid.push(row.id);
      } else if (delta < -EPS) {
        adjustments.push({
          kind: "devolucion",
          componentId: row.id,
          quantity: String(round6(-delta)),
          note: "se usó menos de lo entregado",
          row,
        });
      }
    }
    return { adjustments, invalid, mismatch };
  }, [rows, used, sources, actual, expectedOutput, origin, allocations, job.warehouse_id]);

  const issues = analysis.adjustments.filter((entry) => entry.kind === "entrega");
  const returns = analysis.adjustments.filter((entry) => entry.kind === "devolucion");
  const differing = rows.filter((row) => {
    const text = used[row.id] ?? String(row.delivered);
    return validNumber(text) && Math.abs(Number(text) - row.planned) > EPS;
  });

  const words = search.toLowerCase().split(/\s+/).filter(Boolean);
  const visibleRows = rows.filter((row) =>
    (!onlyDiff || differing.some((entry) => entry.id === row.id))
    && words.every((word) => `${row.name} ${row.code}`.toLowerCase().includes(word)));
  const pager = usePagedList(visibleRows, { pageSize: 10, resetKey: `${search}|${onlyDiff}` });

  // Envases: recuento real por tipo y resto sin envasar (solo si todos usan la unidad del producto).
  const packs = job.work_options?.packaging ?? [];
  const [counts, setCounts] = useState(() => Object.fromEntries(
    packs.map((entry) => [entry.id, entry.actual_count == null ? "" : String(entry.actual_count)])));
  const packInvalid = packs.some((entry) => counts[entry.id] !== "" && !/^\d{1,9}$/.test(counts[entry.id]));
  const packComplete = packs.length > 0
    && packs.every((entry) => counts[entry.id] !== "" && entry.unit === unit);
  const packaged = packs.reduce((sum, entry) => sum + Number(counts[entry.id] || 0) * Number(entry.capacity), 0);
  const unpackaged = packComplete && validNumber(actual) ? round6(Number(actual) - packaged) : null;

  const actualOk = validNumber(actual) && Number(actual) > 0;
  const lotOk = !product?.track_lots || outputLot.trim().length > 0;
  const noteOk = !analysis.mismatch || varianceNote.trim().length >= 5;
  const tooMany = analysis.adjustments.length > 300;
  const canReview = actualOk && lotOk && noteOk && !analysis.invalid.length && !packInvalid && !tooMany;
  const outputDiff = actualOk ? ((Number(actual) - expectedOutput) / expectedOutput) * 100 : 0;

  async function confirm() {
    if (busy || !canReview) return;
    setBusy(true);
    setErrorMsg("");
    try {
      const values = { actualQuantity: actual, outputLot, expiresOn, varianceNote };
      const packaging = Object.fromEntries(packs.map((entry) => [
        entry.id, counts[entry.id] === "" ? null : Number(counts[entry.id])]));
      const fingerprint = JSON.stringify({ values, adjustments: analysis.adjustments.map(({ row, ...rest }) => rest), packaging });
      if (request.current?.fingerprint !== fingerprint) {
        request.current = { fingerprint, id: crypto.randomUUID() };
      }
      await finishProductionJobAdjusted(
        companyId,
        job.id,
        values,
        analysis.adjustments.map(({ row, ...rest }) => rest),
        packaging,
        request.current.id,
      );
      request.current = null;
      notifySuccess(
        "Fabricación completada",
        `Ingresaron ${q(actual)} ${unit} al stock${issues.length ? ` · ${issues.length} insumo(s) descontado(s)` : ""}${returns.length ? ` · ${returns.length} insumo(s) devuelto(s)` : ""}.`,
      );
      await onFinished();
    } catch (error) {
      setErrorMsg(notifyError(migrationMissing(error)
        ? new Error("Falta aplicar la migración 043 en la base para terminar con ajustes.")
        : error));
    } finally {
      setBusy(false);
    }
  }

  return (
    <ActionDialog
      open
      title={step === "form" ? "Terminar fabricación" : "Confirmá los movimientos de stock"}
      description={step === "form"
        ? "Cargá lo que realmente salió y lo que realmente se usó. El stock solo cambia cuando confirmes en el paso siguiente."
        : "Revisá el resumen. Al confirmar se modifica el stock y no se puede deshacer desde esta pantalla."}
      busy={busy}
      onClose={onClose}
    >
      {step === "form" && (
        <form className="finish-form" onSubmit={(event) => { event.preventDefault(); if (canReview) setStep("review"); }}>
          <section className="finish-block" aria-labelledby="finish-output">
            <h3 id="finish-output">1. Producto obtenido</h3>
            <div className="finish-grid">
              <label>
                Cantidad real fabricada ({unit})
                <input required inputMode="decimal" value={actual} onChange={(event) => setActual(event.target.value)} />
                <small>Previsto: {q(expectedOutput)} {unit}</small>
              </label>
              <label>
                Lote del producto {product?.track_lots ? "(obligatorio)" : "(no aplica)"}
                <input required={Boolean(product?.track_lots)} disabled={!product?.track_lots} maxLength={80}
                  value={outputLot} placeholder="Ej.: FAB-2026-001" onChange={(event) => setOutputLot(event.target.value)} />
              </label>
              <label>
                Vencimiento (opcional)
                <input type="date" disabled={!product?.track_lots} value={expiresOn}
                  onChange={(event) => setExpiresOn(event.target.value)} />
              </label>
            </div>
            {actualOk && Math.abs(outputDiff) > 0.0001 && (
              <p className={`finish-note ${outputDiff < 0 ? "is-less" : "is-more"}`} role="status">
                {outputDiff < 0 ? "Salió de menos" : "Salió de más"}: {q(Math.abs(Number(actual) - expectedOutput))} {unit}
                {" "}({Math.abs(outputDiff).toFixed(1)} % {outputDiff < 0 ? "menos" : "más"} de lo previsto). Solo ingresa al stock lo real.
              </p>
            )}
          </section>

          {packs.length > 0 && (
            <section className="finish-block" aria-labelledby="finish-packs">
              <h3 id="finish-packs">2. Envases y presentaciones</h3>
              <p className="finish-help">Indicá cuántos envases salieron de cada tipo. Es un registro de lo envasado: no mueve stock por sí solo.</p>
              <div className="finish-grid">
                {packs.map((entry) => (
                  <label key={entry.id}>
                    {entry.name} · {q(entry.capacity)} {entry.unit} c/u
                    <input inputMode="numeric" placeholder={`Previsto ${entry.count}`} value={counts[entry.id]}
                      onChange={(event) => setCounts({ ...counts, [entry.id]: event.target.value })} />
                  </label>
                ))}
              </div>
              {packInvalid && <p role="alert" className="error">Usá números enteros en los envases.</p>}
              {unpackaged != null && (
                <p className={`finish-note ${Math.abs(unpackaged) < EPS ? "" : unpackaged < 0 ? "is-more" : "is-less"}`} role="status">
                  {Math.abs(unpackaged) < EPS
                    ? "Todo lo fabricado quedó envasado."
                    : unpackaged > 0
                      ? `Quedan ${q(unpackaged)} ${unit} sin envasar (resto o merma).`
                      : `Los envases suman ${q(-unpackaged)} ${unit} más de lo fabricado: revisá los recuentos.`}
                </p>
              )}
              {packs.some((entry) => entry.unit !== unit) && (
                <p className="finish-help">Algún envase usa otra unidad que el producto, por eso no se calcula el resto sin envasar.</p>
              )}
            </section>
          )}

          <section className="finish-block" aria-labelledby="finish-inputs">
            <h3 id="finish-inputs">{packs.length ? "3" : "2"}. Insumos realmente usados</h3>
            <p className="finish-help">
              Por defecto se da por usado lo entregado. Si usaste más, se descuenta la diferencia del stock; si usaste menos, el sobrante vuelve al stock.
            </p>
            <div className="finish-summary" role="status">
              <span><strong>{rows.length}</strong> insumos</span>
              <span className={issues.length ? "is-warn" : ""}><strong>{issues.length}</strong> con uso de más</span>
              <span className={returns.length ? "is-info" : ""}><strong>{returns.length}</strong> con sobrante</span>
              <span><strong>{rows.filter((row) => row.delivered + EPS < row.planned).length}</strong> entregados de menos</span>
            </div>
            <div className="finish-tools">
              <label className="finish-search">Buscar insumo
                <input type="search" value={search} placeholder="Nombre o código" onChange={(event) => setSearch(event.target.value)} />
              </label>
              <label className="finish-check">
                <input type="checkbox" checked={onlyDiff} onChange={(event) => setOnlyDiff(event.target.checked)} />
                Solo los que difieren de la fórmula ({differing.length})
              </label>
              <button type="button" className="button outline" onClick={() => setUsed({})}>Dar por usado lo entregado</button>
              <button type="button" className="button outline"
                onClick={() => setUsed(Object.fromEntries(rows.map((row) => [row.id, String(row.planned)])))}>
                Igualar todo a lo previsto
              </button>
            </div>
            <div className="mod-table-wrap">
              <table className="mod-table finish-table">
                <thead>
                  <tr>
                    <th scope="col">Insumo</th>
                    <th scope="col" className="is-num">Previsto</th>
                    <th scope="col" className="is-num">Entregado</th>
                    <th scope="col" className="is-num">Usado realmente</th>
                    <th scope="col">Efecto en el stock</th>
                  </tr>
                </thead>
                <tbody>
                  {pager.visible.map((row) => {
                    const text = usedOf(row);
                    const bad = !validNumber(text);
                    const delta = bad ? 0 : round6(Number(text) - row.delivered);
                    const source = sourceFor(row);
                    const lotMissing = delta > EPS && row.trackLots && !source.lotCode;
                    return (
                      <tr key={row.id} className={delta > EPS ? "is-attention" : ""}>
                        <td className="is-name" data-label="Insumo">
                          <strong>{row.name}</strong>
                          <small>{row.code}{row.outside ? " · fuera de la fórmula" : ""}</small>
                        </td>
                        <td className="is-num" data-label="Previsto">{q(row.planned)} {row.unit}</td>
                        <td className="is-num" data-label="Entregado">{q(row.delivered)} {row.unit}</td>
                        <td className="is-num" data-label="Usado realmente">
                          <input aria-label={`Cantidad usada de ${row.name}`} inputMode="decimal"
                            aria-invalid={bad} value={text}
                            onChange={(event) => setUsed({ ...used, [row.id]: event.target.value })} />
                        </td>
                        <td data-label="Efecto en el stock">
                          {bad && <span className="finish-bad">Cantidad inválida</span>}
                          {!bad && Math.abs(delta) <= EPS && <span className="finish-same">Sin cambios</span>}
                          {!bad && delta > EPS && (
                            <span className="finish-out">
                              <ArrowUpFromLine size={14} aria-hidden="true" /> Descuenta {q(delta)} {row.unit}
                              <small>
                                de {warehouseName(source.warehouseId)}{source.lotCode ? ` · lote ${lotLabel(source.lotCode)}` : ""}
                              </small>
                              <select aria-label={`Depósito de origen de ${row.name}`} value={source.warehouseId}
                                onChange={(event) => setSources({ ...sources, [row.id]: event.target.value })}>
                                {warehouses.map((entry) => <option key={entry.id} value={entry.id}>{entry.name}</option>)}
                              </select>
                              {lotMissing && <span className="finish-bad">Elegí el lote con “Agregar insumo sin remito”.</span>}
                            </span>
                          )}
                          {!bad && delta < -EPS && (
                            <span className="finish-in">
                              <ArrowDownToLine size={14} aria-hidden="true" /> Devuelve {q(-delta)} {row.unit}
                              <small>al depósito y lote de origen</small>
                            </span>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            <ListPager pager={pager} noun="insumos" sizes={[10, 25, 50]} />
          </section>

          {tooMany && (
            <p role="alert" className="error">
              Hay {analysis.adjustments.length} ajustes y el máximo por cierre es 300. Dejá sin cambios los insumos que coincidan con lo entregado.
            </p>
          )}
          {analysis.mismatch && (
            <label className="finish-block">
              Motivo de la diferencia frente a la fórmula (obligatorio)
              <textarea required minLength={5} maxLength={400} value={varianceNote}
                placeholder="Ej.: se corrigió la mezcla; merma por limpieza; faltó material"
                onChange={(event) => setVarianceNote(event.target.value)} />
            </label>
          )}

          <div className="erp-action-dialog-actions">
            <button type="button" className="button outline" onClick={onClose}>Volver</button>
            <button className="button primary" disabled={!canReview}>Revisar y confirmar</button>
          </div>
        </form>
      )}

      {step === "review" && (
        <div className="finish-review">
          <p className="finish-alert" role="alert">
            <AlertTriangle size={20} aria-hidden="true" />
            <span><strong>Este movimiento modifica el stock.</strong> Se registra una sola vez: si se corta la conexión, reintentar no duplica nada.</span>
          </p>
          <ul className="finish-effects">
            <li className="is-in">
              <ArrowDownToLine size={17} aria-hidden="true" />
              <span>
                <strong>Ingresa {q(actual)} {unit} de {product?.name ?? "producto"}</strong>
                <small>Depósito {warehouseName(job.warehouse_id)}{outputLot ? ` · lote ${outputLot}` : ""}
                  {Math.abs(outputDiff) > 0.0001 ? ` · ${Math.abs(outputDiff).toFixed(1)} % ${outputDiff < 0 ? "menos" : "más"} que lo previsto` : " · igual a lo previsto"}</small>
              </span>
            </li>
            {issues.length > 0 && (
              <li className="is-out">
                <ArrowUpFromLine size={17} aria-hidden="true" />
                <span>
                  <strong>Descuenta {issues.length} insumo(s) usado(s) de más</strong>
                  {issues.slice(0, 8).map((entry) => (
                    <small key={entry.componentId}>{entry.row.name}: {q(entry.quantity)} {entry.row.unit} de {warehouseName(entry.warehouseId)}</small>
                  ))}
                  {issues.length > 8 && <small>y {issues.length - 8} más</small>}
                </span>
              </li>
            )}
            {returns.length > 0 && (
              <li className="is-in">
                <ArrowDownToLine size={17} aria-hidden="true" />
                <span>
                  <strong>Devuelve {returns.length} insumo(s) sobrante(s) al stock</strong>
                  {returns.slice(0, 8).map((entry) => (
                    <small key={entry.componentId}>{entry.row.name}: {q(entry.quantity)} {entry.row.unit}</small>
                  ))}
                  {returns.length > 8 && <small>y {returns.length - 8} más</small>}
                </span>
              </li>
            )}
            {!issues.length && !returns.length && (
              <li><span><strong>Los insumos usados coinciden con lo entregado.</strong><small>No hay ajustes de insumos.</small></span></li>
            )}
            {packs.length > 0 && (
              <li>
                <span>
                  <strong>Envases</strong>
                  {packs.map((entry) => (
                    <small key={entry.id}>{entry.name}: {counts[entry.id] === "" ? "sin recuento" : `${counts[entry.id]} (previsto ${entry.count})`}</small>
                  ))}
                  {unpackaged != null && Math.abs(unpackaged) > EPS && <small>Sin envasar: {q(unpackaged)} {unit}</small>}
                </span>
              </li>
            )}
            {varianceNote.trim() && (
              <li><span><strong>Motivo de la diferencia</strong><small>{varianceNote.trim()}</small></span></li>
            )}
          </ul>
          {errorMsg && <p role="alert" className="error">{errorMsg}</p>}
          <div className="erp-action-dialog-actions">
            <button type="button" className="button outline" disabled={busy} onClick={() => { setErrorMsg(""); setStep("form"); }}>Volver a editar</button>
            <button type="button" className="button primary" disabled={busy} onClick={confirm}>
              {busy ? "Procesando…" : "Confirmar y mover stock"}
            </button>
          </div>
        </div>
      )}
    </ActionDialog>
  );
}

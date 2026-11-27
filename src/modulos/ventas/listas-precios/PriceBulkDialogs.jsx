import { useEffect, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight } from "lucide-react";
import ActionDialog from "../../../compartido/componentes/ActionDialog";
import ListPager, { usePagedList } from "../../../compartido/componentes/ListPager";
import { useAuth } from "../../../compartido/contextos/AuthContext";
import { friendlyError, notifyError, notifySuccess } from "../../../compartido/utilidades/notifications";
import { money, parseAmount, parsePriceRows } from "../compartido/pricing";
import { dateEs } from "../../../compartido/utilidades/display";
import { bulkPriceChange, importPriceRows, listPriceHistory } from "./priceLists";

const newId = () => crypto.randomUUID();

/* Tabla de cambios (antes → después) con paginación, para vistas previas de 200+ filas. */
function ChangesTable({ rows, currency }) {
  const pager = usePagedList(rows, { pageSize: 10 });
  if (!rows.length) return <p className="pl-note">No hay cambios de precio para mostrar.</p>;
  return (
    <>
      <div className="mod-table-wrap">
        <table className="mod-table">
          <thead><tr><th>Producto</th><th className="is-num">Antes</th><th className="is-num">Después</th></tr></thead>
          <tbody>
            {pager.visible.map((row) => (
              <tr key={row.item_id}>
                <td className="is-name"><strong>{row.name ?? row.code}</strong><small>{row.code}</small></td>
                <td className="is-num">{money(row.old_price, currency)}</td>
                <td className="is-num"><strong>{money(row.new_price, currency)}</strong></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ListPager pager={pager} noun="cambios" sizes={[10, 25, 50]} />
    </>
  );
}

function Summary({ items }) {
  return (
    <dl className="pl-facts">
      {items.map(([label, value]) => (
        <div key={label}><dt>{label}</dt><dd>{value}</dd></div>
      ))}
    </dl>
  );
}

/* Subir o bajar toda la lista un porcentaje, o recalcular desde el costo vigente. Siempre con vista previa. */
export function BulkDialog({ open, list, onClose, onApplied }) {
  const { activeCompanyId } = useAuth();
  const [mode, setMode] = useState("percent");
  const [pct, setPct] = useState("");
  const [reason, setReason] = useState("");
  const [preview, setPreview] = useState(null);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const requestId = useRef(newId());

  useEffect(() => {
    if (!open) return;
    setMode("percent"); setPct(""); setReason(""); setPreview(null); setConfirming(false);
    requestId.current = newId();
  }, [open]);

  const reset = () => { setPreview(null); setConfirming(false); requestId.current = newId(); };
  const percentValue = parseAmount(pct);
  const ready = mode === "recalc" || (percentValue != null && percentValue > -100 && percentValue <= 1000 && percentValue !== 0);

  async function run(apply) {
    setBusy(true);
    try {
      const result = await bulkPriceChange(activeCompanyId, list.id, {
        mode, percent: percentValue, apply, reason, requestId: requestId.current,
      });
      if (apply) {
        notifySuccess("Precios actualizados", `${result.changed} producto${result.changed === 1 ? "" : "s"} en ${list.name}`);
        await onApplied();
        onClose();
      } else {
        setPreview(result);
      }
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <ActionDialog open={open} busy={busy} onClose={onClose} title="Cambio masivo de precios"
      description={list ? `Lista ${list.name}. Primero ves cuánto cambia cada producto; recién después se aplica.` : ""}>
      <div className="pl-form">
        <fieldset className="pl-derived">
          <legend>¿Qué querés hacer?</legend>
          <label className="pl-check"><input type="radio" name="bulk-mode" checked={mode === "percent"}
            onChange={() => { setMode("percent"); reset(); }} />
            Subir o bajar todos los precios un porcentaje</label>
          <label className="pl-check"><input type="radio" name="bulk-mode" checked={mode === "recalc"}
            onChange={() => { setMode("recalc"); reset(); }} />
            Recalcular desde el costo vigente (productos con margen o recargo)</label>
        </fieldset>
        {mode === "percent" && (
          <label>Porcentaje (usá negativo para bajar)
            <input inputMode="decimal" value={pct} placeholder="Ej.: 8 o -5" aria-label="Porcentaje de cambio"
              onChange={(event) => { setPct(event.target.value); reset(); }} />
          </label>
        )}
        {mode === "percent" && <p className="pl-note">Los productos afectados pasan a precio fijo con el nuevo valor.</p>}
        <label>Motivo (opcional)
          <input maxLength={200} value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Ej.: aumento general de noviembre" />
        </label>

        {preview && (
          <>
            <Summary items={[
              ["Productos con precio", preview.total], ["Cambiarían", preview.changed],
              ...(mode === "recalc" ? [["Omitidos (sin costo o precio fijo)", preview.skipped]] : []),
            ]} />
            <ChangesTable rows={preview.sample ?? []} currency={list?.currency} />
            {preview.changed > (preview.sample?.length ?? 0) && (
              <p className="pl-note">Se muestran los primeros {preview.sample.length}; el cambio alcanza a {preview.changed}.</p>
            )}
          </>
        )}

        {confirming ? (
          <div className="pl-confirm" role="alertdialog" aria-label="Confirmar cambio masivo">
            <p><strong>Se van a modificar {preview.changed} precios de la lista {list.name}.</strong> El cambio queda en el historial.</p>
            <div className="pl-footer">
              <button type="button" className="button outline" disabled={busy} onClick={() => setConfirming(false)}>Volver</button>
              <button type="button" className="button primary" disabled={busy} onClick={() => run(true)}>
                {busy ? "Aplicando…" : "Sí, aplicar cambios"}
              </button>
            </div>
          </div>
        ) : (
          <div className="pl-footer">
            <button type="button" className="button outline" onClick={onClose} disabled={busy}>Cancelar</button>
            <button type="button" className="button outline" disabled={busy || !ready} onClick={() => run(false)}>
              {busy && !preview ? "Calculando…" : "Ver vista previa"}
            </button>
            <button type="button" className="button primary" disabled={busy || !preview || preview.changed === 0}
              onClick={() => setConfirming(true)}>
              Aplicar cambios
            </button>
          </div>
        )}
      </div>
    </ActionDialog>
  );
}

const CHUNK = 500;
const MAX_ROWS = 5000;

/* Importar precios netos (sin IVA) pegando dos columnas —código y precio— desde una planilla. */
export function ImportDialog({ open, list, onClose, onApplied }) {
  const { activeCompanyId } = useAuth();
  const [text, setText] = useState("");
  const [reason, setReason] = useState("");
  const [preview, setPreview] = useState(null);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const ids = useRef([]);

  useEffect(() => {
    if (!open) return;
    setText(""); setReason(""); setPreview(null); setConfirming(false); ids.current = [];
  }, [open]);

  const parsed = parsePriceRows(text);
  const tooMany = parsed.rows.length > MAX_ROWS;
  const chunks = [];
  for (let i = 0; i < parsed.rows.length && i < MAX_ROWS; i += CHUNK) chunks.push(parsed.rows.slice(i, i + CHUNK));

  async function readFile(event) {
    const file = event.target.files?.[0];
    if (!file) return;
    if (file.size > 2_000_000) { notifyError(new Error("El archivo es demasiado grande (máximo 2 MB).")); return; }
    setText(await file.text());
    setPreview(null);
    event.target.value = "";
  }

  async function run(apply) {
    setBusy(true);
    try {
      if (!apply || ids.current.length !== chunks.length) ids.current = chunks.map(newId);
      const total = { matched: 0, changed: 0, unchanged: 0, unmatched: [], invalid: [], sample: [] };
      for (let i = 0; i < chunks.length; i += 1) {
        const result = await importPriceRows(activeCompanyId, list.id, chunks[i], {
          apply, reason, requestId: ids.current[i],
        });
        total.matched += result.matched; total.changed += result.changed; total.unchanged += result.unchanged;
        total.unmatched.push(...result.unmatched); total.invalid.push(...result.invalid);
        total.sample.push(...(result.sample ?? []).map((row) => ({ ...row, name: row.code })));
      }
      if (apply) {
        notifySuccess("Precios importados", `${total.changed} actualizado${total.changed === 1 ? "" : "s"} en ${list.name}`);
        await onApplied();
        onClose();
      } else {
        setPreview(total);
      }
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
      setConfirming(false);
    }
  }

  return (
    <ActionDialog open={open} busy={busy} onClose={onClose} title="Importar precios desde una planilla"
      description={list ? `Lista ${list.name}. Los productos se reconocen por su código; los precios van sin IVA.` : ""}>
      <div className="pl-form">
        <p className="pl-note">
          En Excel copiá las columnas <strong>Código</strong> y <strong>Precio sin IVA</strong> y pegalas acá, o guardá la hoja como CSV y elegí el archivo.
          Acepta formato argentino (16.500,50).
        </p>
        <label>Datos pegados
          <textarea rows={6} value={text} aria-label="Datos de la planilla" placeholder={"000001\t4056,25\n000002\t5569,12"}
            onChange={(event) => { setText(event.target.value); setPreview(null); }} />
        </label>
        <label>…o un archivo CSV / texto
          <input type="file" accept=".csv,.txt,.tsv,text/csv,text/plain" onChange={readFile} />
        </label>
        <label>Motivo (opcional)
          <input maxLength={200} value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Ej.: lista nueva del proveedor" />
        </label>
        {text.trim() && (
          <p className="pl-note" aria-live="polite">
            Se leyeron <strong>{parsed.rows.length}</strong> filas válidas
            {parsed.invalid.length ? ` y ${parsed.invalid.length} con errores` : ""}.
            {tooMany && ` Solo se importan las primeras ${MAX_ROWS}.`}
          </p>
        )}
        {preview && (
          <>
            <Summary items={[
              ["Productos encontrados", preview.matched], ["Cambiarían", preview.changed], ["Sin cambios", preview.unchanged],
              ["Código no encontrado", preview.unmatched.length], ["Filas inválidas", preview.invalid.length + parsed.invalid.length],
            ]} />
            {(preview.unmatched.length > 0 || parsed.invalid.length > 0) && (
              <details className="pl-extra">
                <summary>Ver códigos no encontrados y filas con errores</summary>
                <p className="pl-note">No encontrados: {preview.unmatched.slice(0, 50).join(", ") || "ninguno"}.</p>
                <p className="pl-note">Con errores: {[...parsed.invalid, ...preview.invalid].slice(0, 50).join(" · ") || "ninguna"}.</p>
              </details>
            )}
            <ChangesTable rows={preview.sample} currency={list?.currency} />
          </>
        )}
        {confirming ? (
          <div className="pl-confirm" role="alertdialog" aria-label="Confirmar importación">
            <p><strong>Se van a actualizar {preview.changed} precios de la lista {list.name}.</strong> El cambio queda en el historial.</p>
            <div className="pl-footer">
              <button type="button" className="button outline" disabled={busy} onClick={() => setConfirming(false)}>Volver</button>
              <button type="button" className="button primary" disabled={busy} onClick={() => run(true)}>
                {busy ? "Importando…" : "Sí, importar"}
              </button>
            </div>
          </div>
        ) : (
          <div className="pl-footer">
            <button type="button" className="button outline" onClick={onClose} disabled={busy}>Cancelar</button>
            <button type="button" className="button outline" disabled={busy || !parsed.rows.length} onClick={() => run(false)}>
              {busy && !preview ? "Revisando…" : "Revisar antes de importar"}
            </button>
            <button type="button" className="button primary" disabled={busy || !preview || preview.changed === 0}
              onClick={() => setConfirming(true)}>
              Importar
            </button>
          </div>
        )}
      </div>
    </ActionDialog>
  );
}

const sourceText = { manual: "Manual", bulk: "Cambio masivo", recalc: "Recálculo", import: "Importación", remove: "Quitado" };

/* Quién cambió qué precio y cuándo (solo administración). */
export function HistoryDialog({ open, list, onClose }) {
  const { activeCompanyId, user } = useAuth();
  const [page, setPage] = useState(0);
  useEffect(() => { if (open) setPage(0); }, [open, list?.id]);
  const query = useQuery({
    queryKey: ["price-history", user?.id, activeCompanyId, list?.id, page],
    queryFn: () => listPriceHistory(activeCompanyId, list.id, null, page),
    enabled: open && Boolean(list),
  });
  const rows = query.data ?? [];
  const total = Number(rows[0]?.total_count ?? 0);
  const pages = Math.max(1, Math.ceil(total / 50));

  return (
    <ActionDialog open={open} onClose={onClose} title="Historial de precios"
      description={list ? `Lista ${list.name}: los cambios más recientes primero.` : ""}>
      <div className="pl-form">
        {query.error && <p role="alert" className="error">{friendlyError(query.error)}</p>}
        {query.isPending && <p className="pl-note">Cargando…</p>}
        {!query.isPending && !rows.length && <p className="pl-note">Todavía no hay cambios registrados.</p>}
        {rows.length > 0 && (
          <div className="mod-table-wrap">
            <table className="mod-table">
              <thead><tr><th>Fecha</th><th>Producto</th><th className="is-num">Antes</th><th className="is-num">Después</th><th>Origen</th><th>Usuario</th></tr></thead>
              <tbody>
                {rows.map((row, index) => (
                  <tr key={`${row.changed_at}-${row.item_id}-${index}`}>
                    <td>{dateEs(row.changed_at)}</td>
                    <td className="is-name"><strong>{row.item_name}</strong><small>{row.item_code}{row.reason ? ` · ${row.reason}` : ""}</small></td>
                    <td className="is-num">{money(row.old_net_price, list?.currency)}</td>
                    <td className="is-num">{money(row.new_net_price, list?.currency)}</td>
                    <td>{sourceText[row.source] ?? row.source}</td>
                    <td>{row.changed_by_label}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <nav className="mod-pager" aria-label="Paginación del historial">
          <span className="mod-pager-count">Página {page + 1} de {pages} · {total} cambios</span>
          <span className="mod-pager-buttons">
            <button type="button" aria-label="Página anterior" disabled={page === 0} onClick={() => setPage(page - 1)}><ChevronLeft size={18} /></button>
            <button type="button" aria-label="Página siguiente" disabled={page + 1 >= pages} onClick={() => setPage(page + 1)}><ChevronRight size={18} /></button>
          </span>
        </nav>
      </div>
    </ActionDialog>
  );
}

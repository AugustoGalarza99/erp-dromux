import CleanupButton from "../../components/CleanupButton";
import ConfirmDeleteDialog from "../../components/ConfirmDeleteDialog";
import ListPager, { usePagedList } from "../../components/ListPager";
import "../../components/cleanup.css";
import { useEffect, useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { FlaskConical, Save } from "lucide-react";
import { useAuth } from "../../contexts/AuthContext";
import {
  notifyError,
  notifySuccess,
  friendlyError,
} from "../../lib/notifications";
import {
  FORMULA_LINE_LIMIT,
  getFormulaCost,
  listFormulas,
  listProductionItems,
  saveFormula,
} from "../../services/production";
import { formatQuantity } from "../inventory/stockNumber";
import FormulaLinesEditor from "./FormulaLinesEditor";
import ProductionShell from "./ProductionShell";
import "./production.css";

const normalize = (text) =>
  String(text ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "");

const snapshot = (batch, yieldEnabled, yieldFactor, lines) =>
  JSON.stringify({
    batch: Number(batch),
    yieldEnabled,
    yieldFactor: yieldEnabled ? Number(yieldFactor) : 1,
    lines: lines
      .map((line) => [line.componentId, Number(line.quantity)])
      .sort((a, b) => String(a[0]).localeCompare(String(b[0]))),
  });

export default function FormulasPage() {
  const { activeCompanyId, user, can, role } = useAuth();
  const client = useQueryClient();
  const [productId, setProductId] = useState("");
  const [batch, setBatch] = useState("1");
  const [productSearch, setProductSearch] = useState("");
  const [formulaSearch, setFormulaSearch] = useState("");
  const [yieldEnabled, setYieldEnabled] = useState(false);
  const [yieldFactor, setYieldFactor] = useState("1");
  const [lines, setLines] = useState([]);
  const [baseline, setBaseline] = useState({ lines: [], key: snapshot("1", false, "1", []) });
  const [pendingProduct, setPendingProduct] = useState(null);
  const [busy, setBusy] = useState(false);
  const [cost, setCost] = useState(null);
  const [formError, setFormError] = useState("");
  const canSeeCost = role === "admin" && can("finance", "read");
  const canEdit = can("production", "update");

  const itemsQuery = useQuery({
    queryKey: ["production-items", user?.id, activeCompanyId],
    queryFn: () => listProductionItems(activeCompanyId),
    enabled: !!activeCompanyId,
  });
  const formulasQuery = useQuery({
    queryKey: ["production-formulas", user?.id, activeCompanyId],
    queryFn: () => listFormulas(activeCompanyId),
    enabled: !!activeCompanyId,
  });
  const items = itemsQuery.data ?? [];
  const formulas = formulasQuery.data ?? [];
  const products = items.filter((item) =>
    ["semi_finished", "finished_product"].includes(item.item_type),
  );
  const components = useMemo(
    () => items.filter((item) =>
      ["raw_material", "semi_finished", "consumable"].includes(item.item_type)
      && item.id !== productId && item.active !== false),
    [items, productId],
  );
  const byId = Object.fromEntries(items.map((item) => [item.id, item]));
  const currentKey = snapshot(batch, yieldEnabled, yieldFactor, lines);
  const dirty = Boolean(productId) && currentKey !== baseline.key;

  const visibleFormulas = useMemo(() => {
    const words = normalize(formulaSearch).split(/\s+/).filter(Boolean);
    return formulas
      .filter((entry) => words.every((word) => normalize(
        `${byId[entry.product_id]?.code ?? ""} ${byId[entry.product_id]?.name ?? ""}`).includes(word)))
      .sort((a, b) => String(byId[a.product_id]?.name).localeCompare(String(byId[b.product_id]?.name)));
  }, [formulas, formulaSearch, items]);
  const formulasPager = usePagedList(visibleFormulas, { pageSize: 10, resetKey: formulaSearch });

  useEffect(() => {
    load("");
  }, [activeCompanyId]);

  // Aviso del navegador si se cierra la pestaña con una fórmula a medio editar.
  useEffect(() => {
    if (!dirty) return undefined;
    const warn = (event) => {
      event.preventDefault();
      event.returnValue = "";
    };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);

  function load(id) {
    const product = items.find((item) => item.id === id);
    const formula = formulas.find((entry) => entry.product_id === id);
    const nextBatch = formula ? String(formula.batch_quantity) : "1";
    const nextYieldOn = Boolean(product?.yield_enabled);
    const nextYield = String(product?.yield_factor ?? 1);
    const nextLines = (formula?.production_formula_lines ?? []).map((line) => ({
      key: crypto.randomUUID(),
      componentId: line.component_id,
      quantity: String(line.quantity),
    }));
    setProductId(id);
    setBatch(nextBatch);
    setYieldEnabled(nextYieldOn);
    setYieldFactor(nextYield);
    setLines(nextLines);
    setBaseline({
      lines: nextLines.map(({ componentId, quantity }) => ({ componentId, quantity })),
      key: snapshot(nextBatch, nextYieldOn, nextYield, nextLines),
    });
    setCost(null);
    setFormError("");
    if (formula && canSeeCost) {
      getFormulaCost(activeCompanyId, id).then(setCost).catch(notifyError);
    }
  }

  function chooseProduct(id) {
    if (dirty && id !== productId) setPendingProduct(id);
    else load(id);
  }

  async function submit(event) {
    event.preventDefault();
    if (busy) return;
    if (!lines.length) {
      setFormError("Agregá al menos un componente a la fórmula.");
      return;
    }
    if (new Set(lines.map((line) => line.componentId)).size !== lines.length) {
      setFormError("No repitas componentes en la misma fórmula.");
      return;
    }
    const withoutCost = lines
      .map((line) => byId[line.componentId])
      .find(
        (item) =>
          item &&
          item.has_reference_cost === false &&
          (["raw_material", "consumable"].includes(item.item_type) ||
            !formulas.some((formula) => formula.product_id === item.id)),
      );
    if (withoutCost) {
      const message =
        withoutCost.item_type === "semi_finished"
          ? `${withoutCost.name} es un semielaborado sin fórmula. Creá primero su fórmula en esta pantalla.`
          : `${withoutCost.name} no tiene costo de referencia. Abrí su ficha en Stock, completá el costo por unidad y volvé a guardar.`;
      setFormError(message);
      return;
    }
    setFormError("");
    setBusy(true);
    try {
      await saveFormula(
        activeCompanyId,
        productId,
        batch,
        lines,
        yieldEnabled,
        yieldFactor,
      );
      // Lo guardado pasa a ser el nuevo punto de comparación.
      setBaseline({
        lines: lines.map(({ componentId, quantity }) => ({ componentId, quantity })),
        key: currentKey,
      });
      await client.invalidateQueries({ queryKey: ["production-items"] });
      await client.invalidateQueries({ queryKey: ["product-costs"] });
      if (canSeeCost) {
        setCost(await getFormulaCost(activeCompanyId, productId));
      }
      await client.invalidateQueries({
        queryKey: ["production-formulas", user?.id, activeCompanyId],
      });
      notifySuccess(
        "Fórmula guardada",
        `${byId[productId]?.name ?? "Producto"} · ${lines.length} componente${lines.length === 1 ? "" : "s"}${canSeeCost ? ". El costo estimado se actualizó." : "."}`,
      );
    } catch (error) {
      setFormError(notifyError(error));
    } finally {
      setBusy(false);
    }
  }

  const expectedOutput = Number(batch) * (yieldEnabled ? Number(yieldFactor) : 1);

  return (
    <ProductionShell
      title="Fórmulas"
      description="Definí cuánto obtenés de un producto y qué cantidad de cada material necesitás. Cada orden guarda la versión de la fórmula con la que se fabricó."
      actions={(
        <Link className="button outline" to="/production/orders">
          Ver órdenes
        </Link>
      )}
    >
    <section className="production-page">
      <div className="production-grid">
        <form className="production-card formula-form" onSubmit={submit}>
          <h2>
            <FlaskConical size={20} aria-hidden="true" /> Producto y cantidad base
          </h2>
          <div className="production-two-columns">
            <label>
              Buscar producto
              <input
                type="search"
                value={productSearch}
                placeholder="Nombre o código"
                onChange={(event) => setProductSearch(event.target.value)}
              />
            </label>
            <label>
              Producto a fabricar
              <select
                required
                value={productId}
                onChange={(event) => chooseProduct(event.target.value)}
              >
                <option value="">Seleccionar producto…</option>
                {products
                  .filter(
                    (item) =>
                      item.id === productId ||
                      normalize(`${item.code} ${item.name}`).includes(normalize(productSearch)),
                  )
                  .map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.code} · {item.name}
                    </option>
                  ))}
              </select>
            </label>
          </div>

          {!productId ? (
            <p className="replenishment-empty">
              Elegí un producto para ver o crear su fórmula. También podés abrir una de la lista de la derecha.
            </p>
          ) : (
            <>
              <div className="production-two-columns">
                <label>
                  Cantidad base de la fórmula
                  <div className="production-input-row">
                    <input
                      required
                      type="number"
                      min="0.000001"
                      max="999999999999"
                      step="0.000001"
                      value={batch}
                      onChange={(event) => setBatch(event.target.value)}
                    />
                    <span>{byId[productId]?.units?.symbol ?? "unidades"}</span>
                  </div>
                </label>
                <label className="production-density-toggle">
                  <span>
                    ¿Aplica factor de rendimiento?
                  </span>
                  <input
                    type="checkbox"
                    checked={yieldEnabled}
                    onChange={(event) => {
                      setYieldEnabled(event.target.checked);
                      if (!event.target.checked) setYieldFactor("1");
                    }}
                  />
                </label>
              </div>
              {yieldEnabled && (
                <label>
                  Factor de rendimiento
                  <input
                    type="number"
                    required
                    min="0.000001"
                    max="1000"
                    step="0.000001"
                    value={yieldFactor}
                    onChange={(event) => setYieldFactor(event.target.value)}
                  />
                </label>
              )}
              <p className="formula-output">
                Salida esperada:{" "}
                <strong>
                  {expectedOutput.toLocaleString("es-AR", { maximumFractionDigits: 6 })}{" "}
                  {byId[productId]?.units?.symbol}
                </strong>
                {yieldEnabled && (
                  <small>
                    {" "}Un factor 0,98 convierte 100 en 98 y uno 1,2 convierte 100 en 120. Es un
                    rendimiento, no una conversión física entre unidades.
                  </small>
                )}
              </p>

              <FormulaLinesEditor
                components={components}
                lines={lines}
                baseline={baseline.lines}
                limit={FORMULA_LINE_LIMIT}
                disabled={!canEdit}
                onChange={(next) => {
                  setFormError("");
                  setLines(next);
                }}
              />

              {formError && (
                <p className="production-form-error" role="alert">
                  {formError}
                </p>
              )}
              <div className="formula-savebar">
                <span className={`formula-dirty ${dirty ? "is-dirty" : ""}`} role="status">
                  {dirty
                    ? "Tenés cambios sin guardar"
                    : canSeeCost
                      ? cost === null
                        ? "El costo se calcula al guardar."
                        : `Costo estimado por unidad: $ ${Number(cost).toLocaleString("es-AR", { minimumFractionDigits: 2 })}`
                      : "La fórmula determina los insumos previstos."}
                </span>
                {dirty && (
                  <button type="button" className="button outline" disabled={busy}
                    onClick={() => load(productId)}>
                    Descartar cambios
                  </button>
                )}
                <button className="button primary" disabled={busy || !canEdit || !dirty}>
                  <Save size={16} aria-hidden="true" /> {busy ? "Guardando…" : "Guardar fórmula"}
                </button>
              </div>
            </>
          )}
        </form>

        <aside className="production-card">
          <h2>Fórmulas guardadas</h2>
          <Link to="/archivados?type=formulas">Ver archivadas</Link>
          {formulasQuery.isError && (
            <p className="production-error">
              {friendlyError(formulasQuery.error)}
            </p>
          )}
          {!formulas.length && (
            <p className="production-muted">
              Todavía no hay fórmulas cargadas.
            </p>
          )}
          {formulas.length > 0 && (
            <label>
              Buscar fórmula
              <input
                type="search"
                value={formulaSearch}
                placeholder="Nombre o código del producto"
                onChange={(event) => setFormulaSearch(event.target.value)}
              />
            </label>
          )}
          {formulasPager.visible.map((formula) => (
            <div key={formula.product_id} className={`formula-item ${formula.product_id === productId ? "is-open" : ""}`}>
              <button
                type="button"
                className="production-list-item"
                aria-current={formula.product_id === productId ? "true" : undefined}
                onClick={() => chooseProduct(formula.product_id)}
              >
                <strong>
                  {byId[formula.product_id]?.name ?? "Producto inactivo"}
                </strong>
                <small>
                  Versión {formula.version} · {formula.production_formula_lines.length} componentes · Base{" "}
                  {formatQuantity(formula.batch_quantity)}
                </small>
              </button>
              <CleanupButton
                resource="formulas"
                id={formula.product_id}
                label={byId[formula.product_id]?.name ?? "Fórmula"}
                onRemoved={() => {
                  if (productId === formula.product_id) load("");
                }}
              />
            </div>
          ))}
          <ListPager pager={formulasPager} noun="fórmulas" sizes={[10, 25, 50]} />
          <p className="production-muted">
            Los semielaborados con fórmula toman el costo de sus componentes.
            Sin fórmula, necesitan costo de referencia.
          </p>
        </aside>
      </div>
      <ConfirmDeleteDialog
        open={Boolean(pendingProduct) || pendingProduct === ""}
        intent="primary"
        title="¿Descartar los cambios de esta fórmula?"
        description="Cambiaste la fórmula y todavía no la guardaste. Si abrís otra, esos cambios se pierden."
        confirmLabel="Descartar y abrir"
        onCancel={() => setPendingProduct(null)}
        onConfirm={() => {
          const next = pendingProduct;
          setPendingProduct(null);
          load(next);
        }}
      />
    </section>
    </ProductionShell>
  );
}

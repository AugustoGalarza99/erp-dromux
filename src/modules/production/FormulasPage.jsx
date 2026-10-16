import CleanupButton from "../../components/CleanupButton";
import "../../components/cleanup.css";
import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { FlaskConical, Plus, Save, Trash2 } from "lucide-react";
import { useAuth } from "../../contexts/AuthContext";
import {
  notifyError,
  notifySuccess,
  friendlyError,
} from "../../lib/notifications";
import {
  getFormulaCost,
  listFormulas,
  listProductionItems,
  saveFormula,
} from "../../services/production";
import { formatQuantity } from "../inventory/stockNumber";
import "./production.css";

const newLine = () => ({
  key: crypto.randomUUID(),
  componentId: "",
  quantity: "",
  search: "",
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
  const [lines, setLines] = useState([newLine()]);
  const [busy, setBusy] = useState(false);
  const [cost, setCost] = useState(null);
  const [formError, setFormError] = useState("");
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
  const components = items.filter(
    (item) =>
      ["raw_material", "semi_finished", "consumable"].includes(
        item.item_type,
      ) && item.id !== productId,
  );
  const byId = Object.fromEntries(items.map((item) => [item.id, item]));

  useEffect(() => {
    setProductId("");
    setBatch("1");
    setLines([newLine()]);
    setCost(null);
    setFormError("");
  }, [activeCompanyId]);

  function chooseProduct(id) {
    setYieldEnabled(Boolean(byId[id]?.yield_enabled));
    setYieldFactor(String(byId[id]?.yield_factor ?? 1));
    setProductId(id);
    setCost(null);
    setFormError("");
    const formula = formulas.find((entry) => entry.product_id === id);
    setBatch(formula ? String(formula.batch_quantity) : "1");
    setLines(
      formula?.production_formula_lines?.length
        ? formula.production_formula_lines.map((line) => ({
            key: crypto.randomUUID(),
            componentId: line.component_id,
            quantity: String(line.quantity),
          }))
        : [newLine()],
    );
    if (formula && role === "admin" && can("finance", "read")) {
      getFormulaCost(activeCompanyId, id).then(setCost).catch(notifyError);
    }
  }

  function changeLine(key, value) {
    setFormError("");
    setLines((current) =>
      current.map((line) => (line.key === key ? { ...line, ...value } : line)),
    );
  }

  async function submit(event) {
    event.preventDefault();
    if (busy) return;
    if (new Set(lines.map((line) => line.componentId)).size !== lines.length) {
      setFormError("No repitas componentes en la misma fórmula.");
      return;
    }
    const withoutCost = lines
      .map((line) => byId[line.componentId])
      .find(
        (item) =>
          item &&
          item.reference_unit_cost == null &&
          (["raw_material", "consumable"].includes(item.item_type) ||
            !formulas.some((formula) => formula.product_id === item.id)),
      );
    if (withoutCost) {
      const message =
        withoutCost.item_type === "semi_finished"
          ? `${withoutCost.name} es un semielaborado sin fórmula. Creá primero su fórmula en esta pantalla.`
          : `${withoutCost.name} no tiene costo de referencia. Abrí su ficha en Inventario, completá el costo por unidad y volvé a guardar.`;
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
      await client.invalidateQueries({ queryKey: ["production-items"] });
      await client.invalidateQueries({ queryKey: ["product-costs"] });
      if (role === "admin" && can("finance", "read")) {
        setCost(await getFormulaCost(activeCompanyId, productId));
      }
      await client.invalidateQueries({
        queryKey: ["production-formulas", user?.id, activeCompanyId],
      });
      notifySuccess("Fórmula guardada", "El costo estimado se actualizó.");
    } catch (error) {
      setFormError(notifyError(error));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="production-page">
      <div className="production-heading">
        <div>
          <span className="eyebrow">PRODUCCIÓN / FÓRMULAS</span>
          <h1>Recetas de fabricación</h1>
          <p>Definí cuánto obtenés y qué cantidad de cada insumo necesitás.</p>
        </div>
        <Link className="button" to="/production/orders">
          Ver órdenes
        </Link>
      </div>
      <div className="production-grid">
        <form className="production-card" onSubmit={submit}>
          <h2>
            <FlaskConical size={20} /> Composición del producto
          </h2>
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
                    `${item.code} ${item.name}`
                      .toLowerCase()
                      .includes(productSearch.toLowerCase()),
                )
                .map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.code} · {item.name}
                  </option>
                ))}
            </select>
          </label>
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
            <span>¿Aplica densidad?</span>
            <input
              type="checkbox"
              checked={yieldEnabled}
              onChange={(event) => {
                setYieldEnabled(event.target.checked);
                if (!event.target.checked) setYieldFactor("1");
              }}
            />
          </label>
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
          <p>
            Salida esperada:{" "}
            {(
              Number(batch) * (yieldEnabled ? Number(yieldFactor) : 1)
            ).toLocaleString("es-AR", {
              maximumFractionDigits: 6,
            })}{" "}
            {byId[productId]?.units?.symbol}. Factor 0,98: 100 pasa a 98. Factor
            1,2: 100 pasa a 120. Es un factor de rendimiento, no una conversión
            física kg/litro.
          </p>
          <div className="production-subtitle">
            Componentes para esa cantidad base
          </div>
          {lines.map((line, index) => (
            <div className="production-component" key={line.key}>
              <div>
                <label>
                  Buscar insumo {index + 1}
                  <input
                    type="search"
                    value={line.search ?? ""}
                    placeholder="Nombre o código"
                    onChange={(event) =>
                      changeLine(line.key, { search: event.target.value })
                    }
                  />
                </label>
                <label>
                  Insumo {index + 1}
                  <select
                    required
                    value={line.componentId}
                    onChange={(event) =>
                      changeLine(line.key, { componentId: event.target.value })
                    }
                  >
                    <option value="">Seleccionar…</option>
                    {components
                      .filter(
                        (item) =>
                          item.id === line.componentId ||
                          `${item.code} ${item.name}`
                            .toLowerCase()
                            .includes((line.search ?? "").toLowerCase()),
                      )
                      .map((item) => (
                        <option key={item.id} value={item.id}>
                          {item.code} · {item.name}
                        </option>
                      ))}
                  </select>
                </label>
              </div>
              <label>
                Cantidad
                <input
                  required
                  type="number"
                  min="0.000001"
                  max="999999999999"
                  step="0.000001"
                  value={line.quantity}
                  onChange={(event) =>
                    changeLine(line.key, { quantity: event.target.value })
                  }
                />
              </label>
              <button
                type="button"
                className="production-icon"
                aria-label="Quitar componente"
                disabled={lines.length === 1}
                onClick={() =>
                  setLines((current) =>
                    current.filter((entry) => entry.key !== line.key),
                  )
                }
              >
                <Trash2 size={17} />
              </button>
            </div>
          ))}
          <button
            type="button"
            className="production-link"
            disabled={lines.length >= 40}
            onClick={() => setLines((current) => [...current, newLine()])}
          >
            <Plus size={16} /> Agregar componente
          </button>
          <div className="production-actions">
            <span>
              {role === "admin" && can("finance", "read")
                ? cost === null
                  ? "El costo se calcula al guardar."
                  : `Costo estimado por unidad: $ ${Number(cost).toLocaleString("es-AR", { minimumFractionDigits: 2 })}`
                : "La fórmula determina los insumos previstos."}
            </span>
            <button
              className="button primary"
              disabled={busy || !can("production", "update")}
            >
              <Save size={16} /> {busy ? "Guardando…" : "Guardar fórmula"}
            </button>
          </div>
          {formError && (
            <p className="production-form-error" role="alert">
              {formError}
            </p>
          )}
        </form>
        <aside className="production-card">
          <h2>Fórmulas disponibles</h2>
          <Link to="/archivados?type=formulas">Ver procesos archivados</Link>
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
          <label>
            Buscar fórmula
            <input
              type="search"
              value={formulaSearch}
              placeholder="Nombre o código del producto"
              onChange={(event) => setFormulaSearch(event.target.value)}
            />
          </label>
          {formulas
            .filter((entry) =>
              `${byId[entry.product_id]?.code ?? ""} ${byId[entry.product_id]?.name ?? ""}`
                .toLowerCase()
                .includes(formulaSearch.toLowerCase()),
            )
            .map((formula) => (
              <div key={formula.product_id}>
                <button
                  type="button"
                  className="production-list-item"
                  onClick={() => chooseProduct(formula.product_id)}
                >
                  <strong>
                    {byId[formula.product_id]?.name ?? "Producto inactivo"}
                  </strong>
                  <small>
                    Versión {formula.version} · Base{" "}
                    {formatQuantity(formula.batch_quantity)} · Salida{" "}
                    {formatQuantity(
                      Number(
                        (
                          Number(formula.batch_quantity) *
                          (byId[formula.product_id]?.yield_enabled
                            ? Number(byId[formula.product_id].yield_factor)
                            : 1)
                        ).toFixed(6),
                      ),
                    )}{" "}
                    · {formula.production_formula_lines.length} insumos
                  </small>
                </button>
                <CleanupButton
                  resource="formulas"
                  id={formula.product_id}
                  label={byId[formula.product_id]?.name ?? "Fórmula"}
                  onRemoved={() => {
                    if (productId === formula.product_id) chooseProduct("");
                  }}
                />
              </div>
            ))}
          <p className="production-muted">
            Los semielaborados con fórmula toman el costo de sus componentes.
            Sin fórmula, necesitan costo de referencia.
          </p>
        </aside>
      </div>
    </section>
  );
}

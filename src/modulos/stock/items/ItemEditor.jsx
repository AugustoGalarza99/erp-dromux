import CleanupButton from "../../../compartido/componentes/CleanupButton";
import ConfirmDeleteDialog from "../../../compartido/componentes/ConfirmDeleteDialog";
import { useEffect, useRef, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Link, useNavigate, useParams } from "react-router-dom";
import {
  ArrowLeft,
  ArrowRightLeft,
  Boxes,
  Ruler,
  Save,
  Tag,
  Warehouse,
  Wallet,
} from "lucide-react";
import { useAuth } from "../../../compartido/contextos/AuthContext";
import {
  activateItemLots,
  getItem,
  getItemCostContext,
  getUntrackedStock,
  saveItem,
  searchItemOptions,
  setItemActive,
} from "./items";
import { listStockBalances } from "../compartido/stock";
import {
  notifyError,
  notifySuccess,
  friendlyError,
} from "../../../compartido/utilidades/notifications";
import ItemCostFields, { emptyPurchaseCost } from "./ItemCostFields";
import { itemTypeHelp, itemTypeLabels, itemTypeOrder } from "./itemTypes";
import StockShell from "../compartido/StockShell";
import { formatQuantity } from "../compartido/stockNumber";
import { refreshSupplierData } from "../../compras/compartido/supplierUi";
import "./items.css";

const emptyForm = {
  code: "",
  name: "",
  item_type: "materia_prima",
  category_id: "",
  unit_id: "",
  barcode: "",
  description: "",
  minimum_stock: "0",
  track_lots: false,
  infinite_stock: false,
  reference_unit_cost: "",
};

const snapshotOf = (form, cost) => JSON.stringify({ form, cost });

function SelectCatalog({ label, value, onChange, query, selected }) {
  const options = query.data ?? [];
  const chosen =
    selected && !options.some((option) => option.id === selected.id)
      ? [selected, ...options]
      : options;

  return (
    <label>
      {label}
      <select required={label.includes("*")} value={value} onChange={onChange}>
        <option value="">Seleccionar</option>
        {chosen.map((option) => (
          <option key={option.id} value={option.id}>
            {option.name}
            {option.symbol ? ` (${option.symbol})` : ""}
            {option.active === false ? " · inactiva" : ""}
          </option>
        ))}
      </select>
      {query.error && (
        <small className="error">{friendlyError(query.error)}</small>
      )}
    </label>
  );
}

function Section({ icon: Icon, title, hint, children }) {
  return (
    <fieldset className="item-section">
      <legend>
        <span className="item-form-icon">
          <Icon size={18} aria-hidden="true" />
        </span>
        <span>
          <strong>{title}</strong>
          {hint && <small>{hint}</small>}
        </span>
      </legend>
      <div className="item-section-body">{children}</div>
    </fieldset>
  );
}

export default function ItemEditor() {
  const { itemId } = useParams();
  const isNew = !itemId;
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { user, activeCompanyId, can, role } = useAuth();
  // El costo de referencia lo ve el administrador o quien tenga el permiso "Ver costos de materiales". El servidor lo
  // vuelve a validar: aquí solo evitamos mostrar un campo vacío que parecería editable.
  const canSeeCost = role === "administrador" || can("costos_materiales", "ver");
  const [form, setForm] = useState(emptyForm);
  const [purchaseCost, setPurchaseCost] = useState(emptyPurchaseCost);
  const [categorySearch, setCategorySearch] = useState("");
  const [unitSearch, setUnitSearch] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [confirmDeactivate, setConfirmDeactivate] = useState(false);
  const [confirmLeave, setConfirmLeave] = useState(false);
  const baseline = useRef(snapshotOf(emptyForm, emptyPurchaseCost));

  const detailQuery = useQuery({
    queryKey: ["item-detail", user?.id, activeCompanyId, itemId],
    queryFn: () => getItem(activeCompanyId, itemId),
    enabled: Boolean(activeCompanyId && itemId),
  });

  const costContext = useQuery({
    queryKey: ["item-cost-context", user?.id, activeCompanyId, itemId],
    queryFn: () => getItemCostContext(activeCompanyId, itemId),
    enabled: Boolean(activeCompanyId && itemId && can("costos_materiales", "ver")),
  });

  const categoryQuery = useQuery({
    queryKey: [
      "item-options",
      user?.id,
      activeCompanyId,
      "category",
      categorySearch,
    ],
    queryFn: () =>
      searchItemOptions(activeCompanyId, "category", categorySearch),
    enabled: Boolean(activeCompanyId),
  });

  const unitQuery = useQuery({
    queryKey: ["item-options", user?.id, activeCompanyId, "unit", unitSearch],
    queryFn: () => searchItemOptions(activeCompanyId, "unit", unitSearch),
    enabled: Boolean(activeCompanyId),
  });

  const item = detailQuery.data;
  const balancesQuery = useQuery({
    queryKey: ["stock-balances", user?.id, activeCompanyId, itemId],
    queryFn: () => listStockBalances(activeCompanyId, itemId),
    enabled: Boolean(
      activeCompanyId && itemId && can("stock_saldos", "ver") && item && !item.infinite_stock,
    ),
    staleTime: 15_000,
  });

  useEffect(() => {
    if (!detailQuery.data) return;
    const loaded = detailQuery.data;

    const nextCost = {
      ...emptyPurchaseCost,
      currency: loaded.reference_cost_usd == null ? "ARS" : "USD",
      usd:
        loaded.reference_cost_usd == null ? "" : String(loaded.reference_cost_usd),
      exchangeType: loaded.reference_exchange_rate_type_id ?? "",
    };
    const nextForm = {
      code: loaded.code,
      name: loaded.name,
      item_type: loaded.item_type,
      category_id: loaded.category_id ?? "",
      unit_id: loaded.unit_id,
      barcode: loaded.barcode ?? "",
      description: loaded.description ?? "",
      minimum_stock: String(loaded.minimum_stock ?? 0),
      track_lots: loaded.track_lots,
      infinite_stock: loaded.infinite_stock ?? false,
      reference_unit_cost:
        loaded.reference_unit_cost == null
          ? ""
          : String(loaded.reference_unit_cost),
    };
    setPurchaseCost(nextCost);
    setForm(nextForm);
    baseline.current = snapshotOf(nextForm, nextCost);
  }, [detailQuery.data]);

  useEffect(() => {
    if (isNew) {
      setForm(emptyForm);
      setPurchaseCost(emptyPurchaseCost);
      baseline.current = snapshotOf(emptyForm, emptyPurchaseCost);
    }
    setError("");
  }, [isNew, activeCompanyId]);

  const dirty = snapshotOf(form, purchaseCost) !== baseline.current;
  const canSave = can("items", isNew ? "crear" : "editar") && !item?.archived;

  // Avisa si se intenta cerrar la pestaña con cambios sin guardar.
  useEffect(() => {
    if (!dirty) return undefined;
    const warn = (event) => {
      event.preventDefault();
      event.returnValue = "";
    };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);

  const setField = (name, value) => {
    setForm((current) => ({ ...current, [name]: value }));
  };

  const invalidate = () =>
    Promise.all([
      refreshSupplierData(queryClient),
      queryClient.invalidateQueries({
        queryKey: ["item-cost-context", user?.id, activeCompanyId],
      }),
      queryClient.invalidateQueries({
        queryKey: ["item-detail", user?.id, activeCompanyId],
      }),
      queryClient.invalidateQueries({
        queryKey: ["items", user?.id, activeCompanyId],
      }),
      queryClient.invalidateQueries({
        queryKey: ["stock-options", user?.id, activeCompanyId, "items"],
      }),
      queryClient.invalidateQueries({
        queryKey: ["stock-summary", user?.id, activeCompanyId],
      }),
      queryClient.invalidateQueries({
        queryKey: ["supplier-quotes", user?.id, activeCompanyId],
      }),
      queryClient.invalidateQueries({
        queryKey: ["product-costs", user?.id, activeCompanyId],
      }),
      queryClient.invalidateQueries({
        queryKey: ["purchase-items", user?.id, activeCompanyId],
      }),
    ]);

  const handleSubmit = async (event) => {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError("");

    let convertedStock = false;
    let savedId = itemId;
    try {
      if (itemId && !item?.track_lots && form.track_lots) {
        const balances = await getUntrackedStock(activeCompanyId, itemId);
        if (balances.length) {
          await activateItemLots(activeCompanyId, itemId);
          convertedStock = true;
        }
      }
      const latestItem = convertedStock
        ? await getItem(activeCompanyId, itemId)
        : item;
      const unchangedCost =
        !purchaseCost.supplier &&
        String(item?.reference_unit_cost ?? "") === form.reference_unit_cost &&
        String(item?.reference_cost_usd ?? "") === purchaseCost.usd &&
        (item?.reference_exchange_rate_type_id ?? "") ===
          purchaseCost.exchangeType &&
        (item?.reference_cost_usd == null ? "ARS" : "USD") ===
          purchaseCost.currency;
      const input = {
        ...form,
        purchaseCost,
        active: item?.active ?? true,
        expectedUpdatedAt: latestItem?.updated_at,
        preserveReferenceCost: Boolean(itemId && unchangedCost),
      };
      const saved = await saveItem(activeCompanyId, itemId, input);
      savedId = saved.id;
      // Lo guardado pasa a ser el nuevo punto de partida: ya no hay cambios pendientes.
      baseline.current = snapshotOf(form, purchaseCost);
      await invalidate();
      if (isNew) navigate(`/inventory/items/${saved.id}`, { replace: true });
      notifySuccess(
        isNew
          ? "Ítem creado"
          : convertedStock
            ? "Lotes activados con saldos iniciales"
            : "Ítem actualizado",
        form.name.trim(),
      );
    } catch (err) {
      const finalError = convertedStock
        ? new Error(
            `Los lotes se activaron, pero no se guardaron los otros cambios: ${err.message}. Reabrí la ficha y guardá nuevamente.`,
          )
        : err;
      // El alta de un solo ítem usa el mismo servidor que la importación: se oculta el "Fila N" que no tiene sentido acá.
      if (finalError?.message) finalError.message = finalError.message.replace(/Fila d+(, [^:]+)?:s*/g, "");
      setError(notifyError(finalError));
      if (!itemId && savedId)
        navigate(`/inventory/items/${savedId}`, { replace: true });
      if (convertedStock) await invalidate().catch(() => {});
    } finally {
      setBusy(false);
    }
  };

  const handleActive = async () => {
    if (busy) return;
    setBusy(true);
    setError("");
    try {
      await setItemActive(activeCompanyId, itemId, !item.active);
      await invalidate();
      notifySuccess(
        item.active ? "Ítem desactivado" : "Ítem activado",
        item.active
          ? `${item.name} ya no aparece al registrar movimientos ni remitos.`
          : `${item.name} vuelve a estar disponible.`,
      );
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
      setConfirmDeactivate(false);
    }
  };

  const goBack = () => {
    if (dirty) setConfirmLeave(true);
    else navigate("/inventory/items");
  };

  if (!isNew && detailQuery.isPending) {
    return (
      <StockShell title="Cargando ítem…">
        <p className="items-muted">Cargando ficha…</p>
      </StockShell>
    );
  }

  if (!isNew && detailQuery.error) {
    return (
      <StockShell title="Ítem">
        <p role="alert" className="error">
          {friendlyError(detailQuery.error)}
        </p>
      </StockShell>
    );
  }

  const balances = balancesQuery.data ?? [];
  const totalStock = balances.reduce(
    (sum, balance) => sum + Number(balance.quantity ?? 0),
    0,
  );
  const unitSymbol =
    unitQuery.data?.find((entry) => entry.id === form.unit_id)?.symbol ??
    item?.unit?.symbol;
  const saveDisabled =
    busy ||
    unitQuery.isPending ||
    categoryQuery.isPending ||
    (!isNew && !dirty) ||
    Boolean(itemId && can("costos_materiales", "ver") && costContext.isPending);

  return (
    <StockShell
      title={isNew ? "Nuevo ítem" : item?.name}
      description={
        isNew
          ? "Definí qué es, cómo se mide y cómo se controla. Las existencias no se cargan acá: se registran como una entrada en Stock."
          : `Código ${item?.code}. Los cambios se aplican al guardar.`
      }
      actions={
        <>
          <button type="button" className="button outline" onClick={goBack}>
            <ArrowLeft size={16} aria-hidden="true" /> Volver a ítems
          </button>
          {!isNew && (
            <span className={`item-status ${item.active ? "" : "inactive"}`}>
              {item.archived ? "Archivado" : item.active ? "Activo" : "Inactivo"}
            </span>
          )}
        </>
      }
    >
      <div className="item-editor-page" data-type={form.item_type}>
        {error && (
          <p role="alert" className="error item-feedback">
            {error}
          </p>
        )}

        <div className="item-editor-grid">
          <form className="item-form" onSubmit={handleSubmit}>
            <Section
              icon={Tag}
              title="1. Qué es"
              hint="El tipo ordena el ítem en listas y fórmulas."
            >
              <fieldset className="item-type-picker">
                <legend>Tipo de ítem *</legend>
                <div>
                  {itemTypeOrder.map((value) => (
                    <label
                      key={value}
                      data-type={value}
                      className={`item-type-card ${form.item_type === value ? "is-selected" : ""}`}
                    >
                      <input
                        type="radio"
                        name="item_type"
                        value={value}
                        checked={form.item_type === value}
                        onChange={() => setField("item_type", value)}
                      />
                      <strong>{itemTypeLabels[value]}</strong>
                      <small>{itemTypeHelp[value]}</small>
                    </label>
                  ))}
                </div>
              </fieldset>

              <div className="item-form-pair">
                <label>
                  Código interno *
                  <input
                    required
                    maxLength={50}
                    pattern="[A-Za-z0-9][A-Za-z0-9._\-]*"
                    placeholder="Ej.: MP-001"
                    value={form.code}
                    onChange={(event) => setField("code", event.target.value)}
                  />
                  <small className="field-hint">
                    Letras, números, punto, guion. Es único en tu empresa.
                  </small>
                </label>
                <label>
                  Nombre *
                  <input
                    required
                    maxLength={160}
                    placeholder="Ej.: Material A, lote de 25 kg"
                    value={form.name}
                    onChange={(event) => setField("name", event.target.value)}
                  />
                </label>
              </div>

              <div className="item-form-pair">
                <div className="item-lookup">
                  <span>Buscar categoría</span>
                  <input
                    value={categorySearch}
                    onChange={(event) => setCategorySearch(event.target.value)}
                    placeholder="Filtrar categorías"
                  />
                  <SelectCatalog
                    label="Categoría"
                    value={form.category_id}
                    onChange={(event) =>
                      setField("category_id", event.target.value)
                    }
                    query={categoryQuery}
                    selected={item?.category}
                  />
                </div>
                <label>
                  Descripción
                  <textarea
                    maxLength={1500}
                    rows={4}
                    placeholder="Especificaciones técnicas o notas (opcional)"
                    value={form.description}
                    onChange={(event) =>
                      setField("description", event.target.value)
                    }
                  />
                </label>
              </div>
            </Section>

            <Section
              icon={Ruler}
              title="2. Cómo se mide y se controla"
              hint="Unidad, mínimo de reposición y trazabilidad."
            >
              <div className="item-form-pair">
                <div className="item-lookup">
                  <span>Buscar unidad</span>
                  <input
                    value={unitSearch}
                    onChange={(event) => setUnitSearch(event.target.value)}
                    placeholder="Filtrar unidades"
                  />
                  <SelectCatalog
                    label="Unidad de medida *"
                    value={form.unit_id}
                    onChange={(event) => setField("unit_id", event.target.value)}
                    query={unitQuery}
                    selected={item?.unit}
                  />
                </div>
                <label>
                  Stock mínimo de referencia {unitSymbol ? `(${unitSymbol})` : ""}
                  <input
                    type="number"
                    min="0"
                    step="0.000001"
                    required
                    disabled={form.infinite_stock}
                    value={form.minimum_stock}
                    onChange={(event) =>
                      setField("minimum_stock", event.target.value)
                    }
                  />
                  <small className="field-hint">
                    Cuando el total baja de este valor, el ítem aparece como “en mínimo”.
                  </small>
                </label>
              </div>
              <label>
                Código de barras
                <input
                  maxLength={80}
                  placeholder="Opcional"
                  value={form.barcode}
                  onChange={(event) => setField("barcode", event.target.value)}
                />
              </label>

              <label className="item-checkbox">
                <input
                  type="checkbox"
                  checked={form.track_lots}
                  disabled={form.infinite_stock}
                  onChange={(event) => setField("track_lots", event.target.checked)}
                />
                <span>
                  <strong>Seguir por lotes</strong>
                  <small>
                    Cada entrada tendrá un lote; salidas y transferencias descontarán
                    de uno. Si ya tiene stock, se abrirá un lote inicial por depósito
                    con el saldo actual y quedará registrado quién hizo la apertura.
                  </small>
                </span>
              </label>

              <label className="item-checkbox">
                <input
                  type="checkbox"
                  checked={form.infinite_stock}
                  onChange={(event) =>
                    setForm((current) => ({
                      ...current,
                      infinite_stock: event.target.checked,
                      minimum_stock: event.target.checked
                        ? "0"
                        : current.minimum_stock,
                      track_lots: event.target.checked ? false : current.track_lots,
                    }))
                  }
                />
                <span>
                  <strong>Stock infinito</strong>
                  <small>
                    Para recursos como agua: permite consumos y entregas sin cargar
                    existencias. Las operaciones quedan registradas. No admite lotes
                    ni stock mínimo. Para activarlo en un ítem existente, primero
                    debe quedar sin saldo físico.
                  </small>
                </span>
              </label>
            </Section>

            <Section
              icon={Wallet}
              title="3. Costo de referencia"
              hint="Alimenta las fórmulas y los márgenes."
            >
              {canSeeCost ? (
                <ItemCostFields
                  form={form}
                  cost={purchaseCost}
                  onCostChange={setPurchaseCost}
                  onPesosChange={(value) => setField("reference_unit_cost", value)}
                  context={costContext}
                  unitSymbol={unitSymbol}
                />
              ) : (
                <p className="field-hint">
                  El costo de referencia lo gestionan Administración y Compras.
                  Una materia prima nueva necesita costo, así que debe crearla
                  alguno de esos roles.
                </p>
              )}
            </Section>

            {canSave && (
              <div className="item-savebar">
                <span className={`item-dirty ${dirty ? "is-dirty" : ""}`} role="status">
                  {dirty ? "Tenés cambios sin guardar" : isNew ? "Completá los datos para crear el ítem" : "Sin cambios pendientes"}
                </span>
                <button type="button" className="button outline" onClick={goBack} disabled={busy}>
                  Cancelar
                </button>
                <button className="button primary item-save" disabled={saveDisabled}>
                  <Save size={17} aria-hidden="true" />{" "}
                  {busy ? "Guardando…" : isNew ? "Crear ítem" : "Guardar cambios"}
                </button>
              </div>
            )}
          </form>

          <aside className="item-side-card" aria-label="Estado del ítem">
            <span className="item-type-badge" data-type={form.item_type}>
              {itemTypeLabels[form.item_type]}
            </span>
            {isNew ? (
              <>
                <h2>Qué pasa después</h2>
                <ol className="item-next-steps">
                  <li>Se crea la ficha del ítem.</li>
                  <li>Cargá las existencias con una entrada en Stock.</li>
                  <li>Ya podés usarlo en remitos, compras y fórmulas.</li>
                </ol>
              </>
            ) : (
              <>
                <h2>Existencias</h2>
                {item.infinite_stock ? (
                  <p>Stock infinito: no se controlan existencias.</p>
                ) : !can("stock_saldos", "ver") ? (
                  <p>Tu rol no consulta existencias.</p>
                ) : balancesQuery.isPending ? (
                  <p>Cargando existencias…</p>
                ) : (
                  <>
                    <p className="item-stock-total">
                      <strong>{formatQuantity(String(totalStock))}</strong> {unitSymbol}
                      <small>
                        {Number(item.minimum_stock) > 0 && totalStock <= Number(item.minimum_stock)
                          ? " · En mínimo"
                          : ` · ${balances.length} ${balances.length === 1 ? "depósito" : "depósitos"}`}
                      </small>
                    </p>
                    {balances.length === 0 && (
                      <p>Todavía no hay unidades en ningún depósito.</p>
                    )}
                    <ul className="item-stock-list">
                      {balances.slice(0, 6).map((balance) => (
                        <li key={balance.warehouse_id}>
                          <span>{balance.warehouse?.name ?? "Depósito"}</span>
                          <strong>{formatQuantity(balance.quantity)} {unitSymbol}</strong>
                        </li>
                      ))}
                    </ul>
                  </>
                )}
                {can("stock_saldos", "ver") && (
                  <div className="item-side-links">
                    {can("stock", "crear") && (
                      <Link className="button outline" to={`/inventory/stock?q=${encodeURIComponent(item.code)}`}>
                        <Warehouse size={15} aria-hidden="true" /> Registrar entrada o salida
                      </Link>
                    )}
                    <Link className="button outline" to={`/inventory/movements?item=${itemId}&code=${encodeURIComponent(item.code)}`}>
                      <ArrowRightLeft size={15} aria-hidden="true" /> Ver movimientos
                    </Link>
                  </div>
                )}
                {!item.archived && can("items", "editar") && (
                  <div className="item-side-danger">
                    <h3>Estado del ítem</h3>
                    <p>
                      {item.active
                        ? "Si lo desactivás deja de ofrecerse en movimientos y remitos. El historial se conserva."
                        : "Está inactivo: no se ofrece en movimientos ni remitos."}
                    </p>
                    <button
                      type="button"
                      className="button outline"
                      disabled={busy}
                      onClick={() =>
                        item.active ? setConfirmDeactivate(true) : handleActive()
                      }
                    >
                      <Boxes size={15} aria-hidden="true" />{" "}
                      {item.active ? "Desactivar ítem" : "Volver a activar ítem"}
                    </button>
                    <CleanupButton
                      resource="items"
                      id={itemId}
                      label={item.name}
                      onRemoved={() => navigate("/inventory/items")}
                    />
                  </div>
                )}
              </>
            )}
          </aside>
        </div>
      </div>

      <ConfirmDeleteDialog
        open={confirmDeactivate}
        busy={busy}
        title="¿Desactivar este ítem?"
        description={`${item?.name ?? ""} dejará de ofrecerse al registrar movimientos y remitos. El historial y las existencias se conservan y podés volver a activarlo cuando quieras.`}
        confirmLabel="Desactivar"
        onCancel={() => setConfirmDeactivate(false)}
        onConfirm={handleActive}
      />
      <ConfirmDeleteDialog
        open={confirmLeave}
        intent="primary"
        title="¿Salir sin guardar?"
        description="Hiciste cambios que todavía no se guardaron. Si salís ahora se pierden."
        confirmLabel="Salir sin guardar"
        onCancel={() => setConfirmLeave(false)}
        onConfirm={() => {
          baseline.current = snapshotOf(form, purchaseCost);
          setConfirmLeave(false);
          navigate("/inventory/items");
        }}
      />
    </StockShell>
  );
}

import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import ActionDialog from "../../components/ActionDialog";
import ConfirmDeleteDialog from "../../components/ConfirmDeleteDialog";
import { useAuth } from "../../contexts/AuthContext";
import { friendlyError, notifyError, notifySuccess } from "../../lib/notifications";
import {
  markupOf, marginOf, methodLabels, money, parseAmount, percent, previewPrice, withTax,
} from "../../lib/pricing";
import {
  getItemSaleSettings, getPriceSettings, listCompanyUnits, removePriceListItem, savePriceList,
  savePriceSettings, saveItemSaleSettings, setPriceListItem,
} from "../../services/priceLists";

const emptyList = {
  name: "", currency: "ARS", valid_from: "", valid_to: "", is_default: false,
  base_list_id: "", base_discount: "0", rounding_step: "0", note: "", archived: false,
};

/* Crear o editar una lista. Una lista derivada toma el precio de otra lista menos un descuento. */
export function ListFormDialog({ open, list, lists, onClose, onSaved }) {
  const { activeCompanyId } = useAuth();
  const [form, setForm] = useState(emptyList);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!open) return;
    setForm(list ? {
      name: list.name, currency: list.currency, valid_from: list.valid_from ?? "", valid_to: list.valid_to ?? "",
      is_default: list.is_default, base_list_id: list.base_list_id ?? "",
      base_discount: String(list.base_discount_percent ?? 0), rounding_step: String(list.rounding_step ?? 0),
      note: list.note ?? "", archived: list.archived,
    } : emptyList);
  }, [open, list]);

  const set = (key) => (event) => setForm((current) => ({
    ...current, [key]: event.target.type === "checkbox" ? event.target.checked : event.target.value,
  }));
  const bases = lists.filter((entry) => !entry.archived && !entry.base_list_id && entry.id !== list?.id);

  async function submit(event) {
    event.preventDefault();
    setBusy(true);
    try {
      const id = await savePriceList(activeCompanyId, list?.id, {
        ...form, base_discount: parseAmount(form.base_discount) ?? 0, rounding_step: parseAmount(form.rounding_step) ?? 0,
      });
      notifySuccess(list ? "Lista actualizada" : "Lista creada", form.name);
      await onSaved(id);
      onClose();
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <ActionDialog open={open} busy={busy} onClose={onClose}
      title={list ? "Editar lista de precios" : "Nueva lista de precios"}
      description="Una lista agrupa los precios para un tipo de cliente o canal (por ejemplo Mayorista, Minorista o Distribuidor).">
      <form className="pl-form" onSubmit={submit}>
        <label>Nombre
          <input required maxLength={80} value={form.name} onChange={set("name")} placeholder="Ej.: Mayorista" />
        </label>
        <div className="pl-two">
          <label>Moneda
            <select value={form.currency} onChange={set("currency")} disabled={Boolean(list)}>
              <option value="ARS">Pesos (ARS)</option>
              <option value="USD">Dólares (USD)</option>
            </select>
          </label>
          <label>Redondeo del precio
            <input inputMode="decimal" value={form.rounding_step} onChange={set("rounding_step")} />
            <small>0 = sin redondeo. Ej.: 10 redondea al múltiplo de 10 más cercano.</small>
          </label>
        </div>
        <div className="pl-two">
          <label>Vigente desde<input type="date" value={form.valid_from} onChange={set("valid_from")} /></label>
          <label>Vigente hasta<input type="date" value={form.valid_to} min={form.valid_from || undefined} onChange={set("valid_to")} /></label>
        </div>
        <fieldset className="pl-derived">
          <legend>Calcular desde otra lista (opcional)</legend>
          <div className="pl-two">
            <label>Lista base
              <select value={form.base_list_id} onChange={set("base_list_id")}>
                <option value="">Ninguna: cargo los precios a mano</option>
                {bases.map((entry) => <option key={entry.id} value={entry.id}>{entry.name} ({entry.currency})</option>)}
              </select>
            </label>
            <label>Descuento sobre la base (%)
              <input inputMode="decimal" disabled={!form.base_list_id} value={form.base_discount} onChange={set("base_discount")} />
              <small>Negativo = recargo. Podés fijar un precio propio producto por producto.</small>
            </label>
          </div>
        </fieldset>
        <label>Nota<textarea maxLength={300} rows={2} value={form.note} onChange={set("note")} /></label>
        <div className="pl-checks">
          <label className="pl-check"><input type="checkbox" checked={form.is_default} disabled={form.archived} onChange={set("is_default")} />
            Lista predeterminada (la que se ofrece al vender)</label>
          {list && <label className="pl-check"><input type="checkbox" checked={form.archived} onChange={set("archived")} />
            Archivada (deja de ofrecerse; el historial se conserva)</label>}
        </div>
        <div className="pl-footer">
          <button type="button" className="button outline" onClick={onClose} disabled={busy}>Cancelar</button>
          <button type="submit" className="button primary" disabled={busy || !form.name.trim()}>
            {busy ? "Guardando…" : "Guardar lista"}
          </button>
        </div>
      </form>
    </ActionDialog>
  );
}

/* Parámetros de la empresa: IVA general, margen mínimo y costos de venta que bajan la ganancia. */
export function SettingsDialog({ open, onClose, onSaved }) {
  const { activeCompanyId, user } = useAuth();
  const [form, setForm] = useState({ tax: "21", minMargin: "0", commission: "0", structure: "0", maxDiscount: "0" });
  const [busy, setBusy] = useState(false);
  const query = useQuery({
    queryKey: ["price-settings", user?.id, activeCompanyId],
    queryFn: () => getPriceSettings(activeCompanyId),
    enabled: open && Boolean(activeCompanyId),
  });
  useEffect(() => {
    const s = query.data;
    if (open && s) setForm({
      tax: String(s.default_tax_percent), minMargin: String(s.min_margin_percent),
      commission: String(s.commission_percent), structure: String(s.structure_percent),
      maxDiscount: String(s.max_discount_percent ?? "0"),
    });
  }, [open, query.data]);
  const set = (key) => (event) => setForm((current) => ({ ...current, [key]: event.target.value }));

  async function submit(event) {
    event.preventDefault();
    setBusy(true);
    try {
      await savePriceSettings(activeCompanyId, {
        tax: parseAmount(form.tax), minMargin: parseAmount(form.minMargin),
        commission: parseAmount(form.commission), structure: parseAmount(form.structure),
        maxDiscount: query.data?.max_discount_percent === undefined ? undefined : parseAmount(form.maxDiscount),
      });
      notifySuccess("Parámetros guardados");
      await onSaved();
      onClose();
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <ActionDialog open={open} busy={busy} onClose={onClose} title="Parámetros de precios"
      description="Valores generales de la empresa. Solo los ve y edita la administración.">
      <form className="pl-form" onSubmit={submit}>
        {query.error && <p role="alert" className="error">{friendlyError(query.error)}</p>}
        <div className="pl-two">
          <label>IVA general (%)<input inputMode="decimal" value={form.tax} onChange={set("tax")} />
            <small>Se usa en los productos que no tienen su propia alícuota.</small></label>
          <label>Margen mínimo (%)<input inputMode="decimal" value={form.minMargin} onChange={set("minMargin")} />
            <small>Bajo este margen sobre el precio se marca una alerta.</small></label>
        </div>
        <div className="pl-two">
          <label>Comisión de venta (%)<input inputMode="decimal" value={form.commission} onChange={set("commission")} />
            <small>Sobre el precio neto; resta de la ganancia.</small></label>
          <label>Estructura / gastos (%)<input inputMode="decimal" value={form.structure} onChange={set("structure")} />
            <small>Porcentaje del precio que cubre gastos fijos.</small></label>
        </div>
        {query.data?.max_discount_percent !== undefined && (
          <label>Descuento máximo al vender (%)<input inputMode="decimal" value={form.maxDiscount} onChange={set("maxDiscount")} />
            <small>Lo que puede descontar quien registra una venta. 0 = sin descuentos. La administración puede superarlo con un motivo.</small></label>
        )}
        <div className="pl-footer">
          <button type="button" className="button outline" onClick={onClose} disabled={busy}>Cancelar</button>
          <button type="submit" className="button primary" disabled={busy || query.isPending}>
            {busy ? "Guardando…" : "Guardar parámetros"}
          </button>
        </div>
      </form>
    </ActionDialog>
  );
}

/* Precio de un producto en la lista, con costo, margen y vista previa antes de guardar. */
export function ItemPriceDialog({ row, list, settings, onClose, onSaved }) {
  const { activeCompanyId, user } = useAuth();
  const open = Boolean(row);
  const [method, setMethod] = useState("fixed");
  const [value, setValue] = useState("");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [removing, setRemoving] = useState(false);
  const [sale, setSale] = useState({ tax: "", content: "", unitId: "" });

  useEffect(() => {
    if (!row) return;
    setMethod(row.method ?? "fixed");
    setValue(row.method_value != null ? String(row.method_value) : row.net_price != null ? String(row.net_price) : "");
    setReason("");
  }, [row]);

  const saleQuery = useQuery({
    queryKey: ["item-sale-settings", user?.id, activeCompanyId, row?.item_id],
    queryFn: () => getItemSaleSettings(activeCompanyId, row.item_id),
    enabled: open,
  });
  const units = useQuery({
    queryKey: ["company-units", user?.id, activeCompanyId],
    queryFn: () => listCompanyUnits(activeCompanyId),
    enabled: open,
    staleTime: 300_000,
  });
  useEffect(() => {
    if (!open || saleQuery.isPending) return;
    const s = saleQuery.data;
    setSale({
      tax: s?.tax_percent != null ? String(s.tax_percent) : "",
      content: s?.content_quantity != null ? String(s.content_quantity) : "",
      unitId: s?.content_unit_id ?? "",
    });
  }, [open, saleQuery.data, saleQuery.isPending]);

  const cost = row?.cost != null ? Number(row.cost) : null;
  const needsCost = method !== "fixed";
  const price = previewPrice(method, parseAmount(value), cost, list?.rounding_step);
  const margin = marginOf(price, cost);
  const markup = markupOf(price, cost);
  const taxRate = parseAmount(sale.tax) ?? Number(settings?.default_tax_percent ?? 21);
  const afterCosts = price != null && cost != null
    ? price - cost - (price * (Number(settings?.commission_percent ?? 0) + Number(settings?.structure_percent ?? 0))) / 100
    : null;
  const lowMargin = margin != null && settings && margin < Number(settings.min_margin_percent ?? 0);
  const canSave = price != null && (!needsCost || cost != null);

  async function run(action, success) {
    setBusy(true);
    try {
      await action();
      notifySuccess(success, row.name);
      await onSaved();
      onClose();
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
      setRemoving(false);
    }
  }

  async function saveSale() {
    setBusy(true);
    try {
      const content = parseAmount(sale.content);
      await saveItemSaleSettings(activeCompanyId, row.item_id, {
        tax: sale.tax === "" ? null : parseAmount(sale.tax),
        content: sale.content === "" || !sale.unitId ? null : content,
        unitId: sale.content === "" || !sale.unitId ? null : sale.unitId,
      });
      notifySuccess("Datos de venta guardados", row.name);
      await onSaved();
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <ActionDialog open={open && !removing} busy={busy} onClose={onClose}
        title={row ? `${row.code} · ${row.name}` : "Precio"}
        description={list ? `Lista ${list.name} (${list.currency}). Los precios se guardan sin IVA.` : ""}>
        {row && (
          <div className="pl-form">
            <dl className="pl-facts">
              <div><dt>Costo vigente</dt><dd>{cost != null ? money(cost, list?.currency) : "Sin costo"}</dd></div>
              <div><dt>Precio actual</dt><dd>{money(row.net_price, list?.currency)}</dd></div>
              <div><dt>Margen actual</dt><dd>{percent(row.margin_percent)}</dd></div>
            </dl>
            {row.source === "derived" && (
              <p className="mod-hint" role="note">Hoy este precio se calcula desde la lista base. Si guardás uno, pasa a ser propio.</p>
            )}
            <div className="pl-two">
              <label>Cómo fijar el precio
                <select value={method} onChange={(event) => setMethod(event.target.value)}>
                  {Object.entries(methodLabels).map(([key, label]) => (
                    <option key={key} value={key} disabled={key !== "fixed" && cost == null}>{label}</option>
                  ))}
                </select>
              </label>
              <label>{method === "fixed" ? "Precio neto (sin IVA)" : method === "margin" ? "Margen sobre el precio (%)" : "Recargo sobre el costo (%)"}
                <input inputMode="decimal" value={value} onChange={(event) => setValue(event.target.value)} aria-label="Valor del precio" />
              </label>
            </div>
            <div className="pl-preview" aria-live="polite">
              <div><small>Precio neto</small><strong>{money(price, list?.currency)}</strong></div>
              <div><small>Con IVA ({percent(taxRate)})</small><strong>{money(withTax(price, taxRate), list?.currency)}</strong></div>
              <div><small>Margen / recargo</small><strong>{percent(margin)} / {percent(markup)}</strong></div>
              <div><small>Ganancia después de comisión y gastos</small><strong>{money(afterCosts, list?.currency)}</strong></div>
            </div>
            {lowMargin && <p role="alert" className="pl-warn">El margen queda por debajo del mínimo configurado ({percent(settings.min_margin_percent)}).</p>}
            <label>Motivo del cambio (opcional)
              <input maxLength={200} value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Ej.: suba del costo de insumos" />
            </label>
            <div className="pl-footer">
              {row.net_price != null && row.source === "own" && (
                <button type="button" className="button outline pl-danger" disabled={busy} onClick={() => setRemoving(true)}>
                  Quitar de la lista
                </button>
              )}
              <button type="button" className="button outline" onClick={onClose} disabled={busy}>Cancelar</button>
              <button type="button" className="button primary" disabled={busy || !canSave}
                onClick={() => run(() => setPriceListItem(activeCompanyId, list.id, row.item_id, method, parseAmount(value), reason), "Precio actualizado")}>
                {busy ? "Guardando…" : "Guardar precio"}
              </button>
            </div>

            <details className="pl-extra">
              <summary>Datos de venta del producto (IVA y contenido)</summary>
              <p className="pl-note">Valen para todas las listas. Dejá el IVA vacío para usar el general ({percent(settings?.default_tax_percent ?? 21)}).</p>
              <div className="pl-three">
                <label>IVA del producto (%)
                  <input inputMode="decimal" value={sale.tax} placeholder="General"
                    onChange={(event) => setSale((s) => ({ ...s, tax: event.target.value }))} />
                </label>
                <label>Contenido por unidad
                  <input inputMode="decimal" value={sale.content} placeholder="Ej.: 4"
                    onChange={(event) => setSale((s) => ({ ...s, content: event.target.value }))} />
                </label>
                <label>Unidad del contenido
                  <select value={sale.unitId} onChange={(event) => setSale((s) => ({ ...s, unitId: event.target.value }))}>
                    <option value="">Sin dato</option>
                    {(units.data ?? []).map((unit) => <option key={unit.id} value={unit.id}>{unit.symbol}</option>)}
                  </select>
                </label>
              </div>
              <button type="button" className="button outline" disabled={busy || saleQuery.isPending} onClick={saveSale}>
                Guardar datos de venta
              </button>
            </details>
          </div>
        )}
      </ActionDialog>
      <ConfirmDeleteDialog open={removing} busy={busy} confirmLabel="Quitar" title="¿Quitar el producto de la lista?"
        description={`Se quita el precio de "${row?.name ?? ""}" en esta lista. El cambio queda en el historial.`}
        onCancel={() => setRemoving(false)}
        onConfirm={() => run(() => removePriceListItem(activeCompanyId, list.id, row.item_id, reason), "Precio quitado")} />
    </>
  );
}

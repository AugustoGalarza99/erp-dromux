import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Eye, Plus, Search, Trash2 } from "lucide-react";
import ActionDialog from "../../../compartido/componentes/ActionDialog";
import ListPager, { usePagedList } from "../../../compartido/componentes/ListPager";
import { useAuth } from "../../../compartido/contextos/AuthContext";
import { friendlyError, notifyError, notifySuccess } from "../../../compartido/utilidades/notifications";
import { createQuote, getCompanyProfile, getQuote } from "./quotes";
import { getDiscountPolicy, getSalePrices, listCustomers, listSaleProducts } from "../compartido/sales";

const money = (value) => Number(value ?? 0).toLocaleString("es-AR", { style: "currency", currency: "ARS" });

// Aritmética en centavos: igual al redondeo del servidor (round half up sobre decimales exactos).
const toCents = (value) => BigInt(Math.round(Number(value) * 100));
const fromCents = (cents) => Number(cents) / 100;
const discountOf = (line) => {
  const value = Number(line.discount);
  return Number.isFinite(value) && value > 0 ? value : 0;
};
const unitPrice = (base, line) =>
  base == null ? null : fromCents((toCents(base) * BigInt(10000 - Math.round(discountOf(line) * 100)) + 5000n) / 10000n);
const lineTotal = (quantity, unit) =>
  unit == null ? 0 : fromCents((BigInt(Math.round(Number(quantity) * 1e6)) * toCents(unit) + 500000n) / 1000000n);

const todayBA = () => new Date().toLocaleDateString("en-CA", { timeZone: "America/Argentina/Buenos_Aires" });
const addDays = (iso, days) => {
  const date = new Date(`${iso}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
};

const defaultNote = "Forma de pago: a convenir.\nPlazo de entrega: a convenir.";

/* Armado de un presupuesto: cliente o interesado, productos con precio de lista, descuento y vista previa. */
export default function QuoteEditor({ onCancel, onCreated }) {
  const { activeCompanyId, user } = useAuth();
  const scope = [user?.id, activeCompanyId];
  const [customerId, setCustomerId] = useState("");
  const [prospect, setProspect] = useState({ name: "", taxId: "", email: "", phone: "", address: "" });
  const [validUntil, setValidUntil] = useState(() => addDays(todayBA(), 15));
  const [note, setNote] = useState(defaultNote);
  const [showTax, setShowTax] = useState(true);
  const [taxIncluded, setTaxIncluded] = useState(false); // sumar el IVA al total sin discriminarlo
  const [previewUrl, setPreviewUrl] = useState("");
  const [previewBusy, setPreviewBusy] = useState(false);
  const [lines, setLines] = useState([]);
  const [search, setSearch] = useState("");
  const [busy, setBusy] = useState(false);
  const [requestId, setRequestId] = useState(() => crypto.randomUUID());

  const customers = useQuery({ queryKey: ["sales-customers", ...scope], queryFn: () => listCustomers(activeCompanyId), enabled: !!activeCompanyId });
  const products = useQuery({ queryKey: ["sales-products", ...scope], queryFn: () => listSaleProducts(activeCompanyId), enabled: !!activeCompanyId });
  const policyQuery = useQuery({
    queryKey: ["sale-discount-policy", ...scope], queryFn: () => getDiscountPolicy(activeCompanyId),
    enabled: !!activeCompanyId, retry: false, staleTime: 60_000,
  });
  const policy = policyQuery.data ?? { max_discount_percent: 0, can_exceed: false };
  const canDiscount = Number(policy.max_discount_percent) > 0 || policy.can_exceed;

  const ids = lines.map((line) => line.itemId);
  const prices = useQuery({
    queryKey: ["quote-prices", ...scope, customerId, [...ids].sort().join(",")],
    queryFn: () => getSalePrices(activeCompanyId, customerId || null, ids),
    enabled: !!activeCompanyId && ids.length > 0 && ids.length <= 200,
    retry: false,
  });
  const priceById = useMemo(() => Object.fromEntries((prices.data ?? []).map((row) => [row.item_id, row])), [prices.data]);
  const pricesReady = prices.isSuccess && !prices.isFetching;
  const baseOf = (itemId) => (pricesReady ? priceById[itemId]?.net_price ?? null : null);

  const activeProducts = (products.data ?? []).filter((item) => item.active);
  const term = search.trim().toLowerCase();
  const matches = term
    ? activeProducts.filter((item) => !ids.includes(item.id) && `${item.name} ${item.code}`.toLowerCase().includes(term)).slice(0, 8)
    : [];
  const byId = Object.fromEntries(activeProducts.map((item) => [item.id, item]));

  const pager = usePagedList(lines, { pageSize: 25, resetKey: lines.length });
  const change = (key, patch) => {
    setLines((current) => current.map((line) => (line.key === key ? { ...line, ...patch } : line)));
    setRequestId(crypto.randomUUID());
  };
  const add = (item) => {
    setLines((current) => [...current, { key: crypto.randomUUID(), itemId: item.id, quantity: "1", discount: "", discountReason: "" }]);
    setSearch("");
    setRequestId(crypto.randomUUID());
  };

  // Totales (vista previa; el servidor los recalcula y es el que manda)
  const computed = lines.map((line) => {
    const unit = unitPrice(baseOf(line.itemId), line);
    return { line, unit, total: lineTotal(line.quantity, unit), tax: priceById[line.itemId]?.tax_percent ?? null };
  });
  const net = computed.reduce((sum, row) => sum + Number(toCents(row.total)), 0) / 100;
  const groups = new Map();
  computed.forEach((row) => {
    if (row.tax == null) return;
    groups.set(row.tax, (groups.get(row.tax) ?? 0n) + toCents(row.total));
  });
  const taxOfCents = (cents, rate) => (cents * BigInt(Math.round(Number(rate) * 100)) + 5000n) / 10000n;
  // Discriminado: IVA sobre la base de cada alícuota. Sumado sin discriminar: línea por línea (igual que el servidor).
  const lineTaxByRate = new Map();
  computed.forEach((row) => {
    if (row.tax == null) return;
    lineTaxByRate.set(row.tax, (lineTaxByRate.get(row.tax) ?? 0n) + taxOfCents(toCents(row.total), row.tax));
  });
  const breakdown = [...groups.entries()].sort((a, b) => a[0] - b[0]).map(([rate, base]) => ({
    rate: Number(rate), base: fromCents(base),
    tax: fromCents(taxIncluded ? lineTaxByRate.get(rate) ?? 0n : taxOfCents(base, rate)),
  }));
  const taxTotal = breakdown.reduce((sum, row) => sum + row.tax, 0);

  const discountsOk = lines.every((line) => discountOf(line) <= Number(policy.max_discount_percent)
    || (policy.can_exceed && line.discountReason.trim().length >= 3));
  const qtyOk = lines.every((line) => /^\d{1,12}(\.\d{1,6})?$/.test(line.quantity) && Number(line.quantity) > 0);
  const customerOk = customerId || prospect.name.trim().length >= 2;
  const ready = lines.length > 0 && lines.length <= 200 && pricesReady && lines.every((l) => baseOf(l.itemId) != null)
    && discountsOk && qtyOk && customerOk && validUntil >= todayBA();

  async function submit(event) {
    event.preventDefault();
    if (!ready || busy) return;
    setBusy(true);
    try {
      const id = await createQuote(activeCompanyId, {
        customerId, ...prospect, validUntil, note, showTax, taxIncluded, lines,
      }, requestId);
      const [detail, profile] = await Promise.all([getQuote(activeCompanyId, id), getCompanyProfile(activeCompanyId)]);
      notifySuccess("Presupuesto creado", `Nº ${String(detail.number).padStart(5, "0")} · ${detail.customer_name}`);
      await onCreated(detail, profile);
    } catch (error) {
      notifyError(error);
      setRequestId(crypto.randomUUID());
    } finally {
      setBusy(false);
    }
  }

  // Vista previa: arma el mismo PDF con los datos cargados (el número y los importes definitivos los fija el servidor).
  async function openPreview() {
    setPreviewBusy(true);
    try {
      const customer = (customers.data ?? []).find((c) => c.id === customerId);
      const [profile, pdf] = await Promise.all([getCompanyProfile(activeCompanyId), import("./quotePdf")]);
      const rows = computed.map(({ line, unit, total, tax }, index) => {
        const item = byId[line.itemId];
        return {
          line_no: index + 1, item_code: item?.code ?? "", item_name: item?.name ?? "", unit_symbol: item?.units?.symbol ?? "",
          quantity: Number(line.quantity), list_unit_price: baseOf(line.itemId), discount_percent: discountOf(line),
          unit_price: unit, line_total: total, tax_percent: tax ?? 0,
        };
      });
      const pdfDoc = pdf.buildQuotePdf({
        preview: true, number: 0, created_at: new Date().toISOString(), valid_until: validUntil, note,
        show_tax: showTax, tax_included: taxIncluded && !showTax,
        customer_name: customer ? customer.name : prospect.name || "Cliente",
        customer_tax_id: customer ? customer.tax_id : prospect.taxId,
        customer_email: customer ? customer.email : prospect.email,
        customer_phone: customer ? customer.phone : prospect.phone,
        customer_address: customer ? customer.address : prospect.address,
        net_total: net, tax_total: taxTotal, gross_total: Math.round((net + taxTotal) * 100) / 100,
        tax_breakdown: breakdown, lines: rows,
      }, profile);
      setPreviewUrl(pdfDoc.output("bloburl"));
    } catch (error) {
      notifyError(error);
    } finally {
      setPreviewBusy(false);
    }
  }
  const closePreview = () => {
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    setPreviewUrl("");
  };

  return (
    <form className="qe" onSubmit={submit}>
      <section className="mod-card qe-card">
        <div className="mod-card-head"><h2>1. ¿Para quién es?</h2></div>
        <label>Cliente
          <select value={customerId} onChange={(event) => { setCustomerId(event.target.value); setRequestId(crypto.randomUUID()); }}>
            <option value="">Interesado que todavía no es cliente</option>
            {(customers.data ?? []).filter((c) => c.active).map((c) => (
              <option key={c.id} value={c.id}>{c.name}{c.tax_id ? ` · ${c.tax_id}` : ""}</option>
            ))}
          </select>
          <small>Con un cliente se usa su lista de precios. Sin cliente, la lista predeterminada.</small>
        </label>
        {!customerId && (
          <div className="pl-two">
            <label>Nombre o razón social *<input required minLength={2} maxLength={160} value={prospect.name}
              onChange={(event) => setProspect({ ...prospect, name: event.target.value })} /></label>
            <label>CUIT / documento<input maxLength={30} value={prospect.taxId} onChange={(event) => setProspect({ ...prospect, taxId: event.target.value })} /></label>
            <label>Correo<input type="email" maxLength={160} value={prospect.email} onChange={(event) => setProspect({ ...prospect, email: event.target.value })} /></label>
            <label>Teléfono<input maxLength={40} value={prospect.phone} onChange={(event) => setProspect({ ...prospect, phone: event.target.value })} /></label>
            <label className="qe-wide">Domicilio<input maxLength={240} value={prospect.address} onChange={(event) => setProspect({ ...prospect, address: event.target.value })} /></label>
          </div>
        )}
      </section>

      <section className="mod-card qe-card">
        <div className="mod-card-head"><h2>2. Productos</h2><span className="mod-chip">{lines.length} / 200</span></div>
        <div className="qe-picker">
          <span className="pl-search"><Search size={17} aria-hidden="true" />
            <input aria-label="Buscar producto para agregar" placeholder="Escribí el nombre o código para agregar un producto" value={search}
              onChange={(event) => setSearch(event.target.value)} disabled={lines.length >= 200} />
          </span>
          {matches.length > 0 && (
            <ul className="qe-results" role="listbox" aria-label="Productos encontrados">
              {matches.map((item) => (
                <li key={item.id}>
                  <button type="button" onClick={() => add(item)}>
                    <Plus size={15} aria-hidden="true" /> <strong>{item.name}</strong><small>{item.code} · {item.units?.symbol}</small>
                  </button>
                </li>
              ))}
            </ul>
          )}
          {term && !matches.length && <p className="pl-note">No se encontró ese producto (o ya está en el presupuesto).</p>}
        </div>
        {prices.error && <p role="alert" className="error">{friendlyError(prices.error)}</p>}
        {!lines.length && <p className="mod-muted">Todavía no agregaste productos.</p>}
        {lines.length > 0 && (
          <>
            <div className="mod-table-wrap pl-desktop">
              <table className="mod-table">
                <thead><tr><th>Producto</th><th className="is-num">Cantidad</th>{canDiscount && <th className="is-num">Desc. %</th>}<th className="is-num">Precio unit.</th><th className="is-num">Importe</th><th><span className="sr-only">Quitar</span></th></tr></thead>
                <tbody>
                  {pager.visible.map((line) => {
                    const item = byId[line.itemId];
                    const base = baseOf(line.itemId);
                    const unit = unitPrice(base, line);
                    const overCap = discountOf(line) > Number(policy.max_discount_percent);
                    return (
                      <tr key={line.key}>
                        <td className="is-name"><strong>{item?.name}</strong><small>{item?.code} · {priceById[line.itemId]?.list_name ?? "Precio del producto"}</small>
                          {base == null && pricesReady && <small className="sales-error">Sin precio de venta</small>}
                          {overCap && policy.can_exceed && (
                            <input className="qe-reason" required minLength={3} maxLength={200} placeholder="Motivo del descuento" aria-label="Motivo del descuento"
                              value={line.discountReason} onChange={(event) => change(line.key, { discountReason: event.target.value })} />
                          )}
                        </td>
                        <td className="is-num"><input className="qe-num" inputMode="decimal" aria-label={`Cantidad de ${item?.name}`} value={line.quantity}
                          onChange={(event) => change(line.key, { quantity: event.target.value })} /> {item?.units?.symbol}</td>
                        {canDiscount && <td className="is-num"><input className="qe-num" inputMode="decimal" aria-label={`Descuento de ${item?.name}`} value={line.discount} placeholder="0"
                          onChange={(event) => change(line.key, { discount: event.target.value })} /></td>}
                        <td className="is-num">{unit == null ? "—" : money(unit)}</td>
                        <td className="is-num"><strong>{unit == null ? "—" : money(lineTotal(line.quantity, unit))}</strong></td>
                        <td className="is-num"><button type="button" className="qe-remove" aria-label={`Quitar ${item?.name}`}
                          onClick={() => { setLines((current) => current.filter((entry) => entry.key !== line.key)); setRequestId(crypto.randomUUID()); }}><Trash2 size={16} /></button></td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            <ul className="pl-cards">
              {pager.visible.map((line) => {
                const item = byId[line.itemId];
                const unit = unitPrice(baseOf(line.itemId), line);
                return (
                  <li key={line.key} className="pl-pcard">
                    <div className="pl-pcard-top"><div><strong>{item?.name}</strong><small>{item?.code}</small></div>
                      <strong className="pl-pcard-price">{unit == null ? "—" : money(lineTotal(line.quantity, unit))}</strong></div>
                    <div className="pl-two">
                      <label>Cantidad ({item?.units?.symbol})<input inputMode="decimal" value={line.quantity} onChange={(event) => change(line.key, { quantity: event.target.value })} /></label>
                      {canDiscount && <label>Descuento %<input inputMode="decimal" value={line.discount} placeholder="0" onChange={(event) => change(line.key, { discount: event.target.value })} /></label>}
                    </div>
                    {discountOf(line) > Number(policy.max_discount_percent) && policy.can_exceed && (
                      <label>Motivo del descuento<input minLength={3} maxLength={200} value={line.discountReason} onChange={(event) => change(line.key, { discountReason: event.target.value })} /></label>
                    )}
                    <button type="button" className="button outline" onClick={() => setLines((current) => current.filter((entry) => entry.key !== line.key))}>Quitar</button>
                  </li>
                );
              })}
            </ul>
            <ListPager pager={pager} noun="productos" sizes={[25, 50, 100]} />
          </>
        )}
      </section>

      <section className="mod-card qe-card">
        <div className="mod-card-head"><h2>3. Condiciones</h2></div>
        <div className="pl-two">
          <label>Válido hasta<input type="date" required value={validUntil} min={todayBA()} max={addDays(todayBA(), 365)} onChange={(event) => setValidUntil(event.target.value)} /></label>
          <div className="qe-checks">
            <label className="pl-check qe-check"><input type="checkbox" checked={showTax}
              onChange={(event) => { setShowTax(event.target.checked); if (event.target.checked) setTaxIncluded(false); }} />
              Mostrar el IVA discriminado en el presupuesto</label>
            <label className="pl-check qe-check"><input type="checkbox" checked={taxIncluded && !showTax} disabled={showTax}
              onChange={(event) => setTaxIncluded(event.target.checked)} />
              Sumar el IVA al total sin mostrarlo (consumidor final)</label>
          </div>
        </div>
        <label>Observaciones y condiciones (aparecen en el PDF)
          <textarea rows={3} maxLength={1000} value={note} onChange={(event) => setNote(event.target.value)} />
        </label>
      </section>

      <section className="mod-card qe-card qe-total" aria-live="polite">
        <dl>
          {(showTax || taxIncluded) && <div><dt>Subtotal neto</dt><dd>{money(net)}</dd></div>}
          {breakdown.map((row) => <div key={row.rate}><dt>IVA {row.rate.toLocaleString("es-AR")} %{taxIncluded && !showTax ? " (no se muestra en el PDF)" : ""}</dt><dd>{money(row.tax)}</dd></div>)}
          <div className="qe-grand"><dt>Total {showTax ? "con IVA" : taxIncluded ? "(IVA incluido, sin discriminar)" : "(IVA no incluido)"}</dt>
            <dd>{money(showTax || taxIncluded ? net + taxTotal : net)}</dd></div>
        </dl>
        <p className="pl-note">Vista previa. El precio final lo confirma el sistema al crear el presupuesto y queda guardado con esos valores.</p>
        <div className="pl-footer">
          <button type="button" className="button outline" onClick={onCancel} disabled={busy}>Cancelar</button>
          <button type="button" className="button outline" disabled={!ready || busy || previewBusy} onClick={openPreview}>
            <Eye size={16} aria-hidden="true" /> {previewBusy ? "Preparando…" : "Vista previa"}
          </button>
          <button type="submit" className="button primary" disabled={!ready || busy}>{busy ? "Creando…" : "Crear presupuesto y descargar PDF"}</button>
        </div>
      </section>

      <ActionDialog open={Boolean(previewUrl)} busy={busy} onClose={closePreview} title="Vista previa del presupuesto"
        description="Así lo va a ver tu cliente. El número y los importes definitivos los confirma el sistema al crearlo.">
        {previewUrl && <iframe className="qe-preview" title="Vista previa del presupuesto en PDF" src={`${previewUrl}#navpanes=0&view=FitH`} />}
        <div className="pl-footer">
          <button type="button" className="button outline" onClick={closePreview} disabled={busy}>Volver a editar</button>
          <button type="submit" className="button primary" disabled={!ready || busy}>{busy ? "Creando…" : "Crear presupuesto y descargar PDF"}</button>
        </div>
      </ActionDialog>
    </form>
  );
}

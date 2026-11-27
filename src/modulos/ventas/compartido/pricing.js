/*
 * Cálculos de precio del lado del cliente: SOLO para vista previa y simulación.
 * El precio que se guarda lo calcula siempre el servidor (set_price_list_item).
 */

/* Convierte "16.500,50", "$ 16500.5" o "1.234" a número. Devuelve null si no es válido. */
export function parseAmount(raw) {
  if (raw == null) return null;
  let text = String(raw).replace(/[$\s ]/g, "");
  if (!text || !/^-?[\d.,]+$/.test(text)) return null;
  const lastComma = text.lastIndexOf(",");
  const lastDot = text.lastIndexOf(".");
  if (lastComma >= 0 && lastDot >= 0) {
    const decimal = lastComma > lastDot ? "," : ".";
    const thousands = decimal === "," ? "." : ",";
    text = text.split(thousands).join("").replace(decimal, ".");
  } else if (lastComma >= 0) {
    text = text.replace(",", ".");
  } else if (lastDot >= 0 && /^-?\d{1,3}(\.\d{3})+$/.test(text)) {
    text = text.replace(/\./g, "");
  }
  const value = Number(text);
  return Number.isFinite(value) ? value : null;
}

/* Texto pegado desde una planilla (código y precio por línea) → filas + líneas inválidas. */
export function parsePriceRows(text) {
  const rows = [];
  const invalid = [];
  const lines = String(text ?? "").split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  lines.forEach((line, index) => {
    let code;
    let priceText;
    if (line.includes("\t") || line.includes(";")) {
      const parts = line.split(/\t|;/).map((part) => part.trim());
      code = parts[0];
      priceText = parts[parts.length - 1];
    } else {
      const cut = line.indexOf(",");
      code = cut < 0 ? line : line.slice(0, cut).trim();
      priceText = cut < 0 ? "" : line.slice(cut + 1).trim();
    }
    const price = parseAmount(priceText);
    if (!code || price == null || price < 0) {
      // La primera línea suele ser el encabezado de la planilla: se ignora sin avisar.
      if (index > 0) invalid.push(line.slice(0, 60));
      return;
    }
    rows.push({ code: code.replace(/^"|"$/g, ""), price: Math.round(price * 100) / 100 });
  });
  return { rows, invalid };
}

export function roundToStep(value, step) {
  const s = Number(step) || 0;
  if (value == null || Number.isNaN(value)) return null;
  return s > 0 ? Math.round(Math.round(value / s) * s * 100) / 100 : Math.round(value * 100) / 100;
}

/* method: margin (sobre precio de venta), markup (sobre costo) o fixed. */
export function previewPrice(method, value, cost, step = 0) {
  const v = Number(value);
  if (value === "" || value == null || !Number.isFinite(v) || v < 0) return null;
  if (method === "fixed") return roundToStep(v, step);
  const c = Number(cost);
  if (cost == null || cost === "" || !Number.isFinite(c) || c < 0) return null;
  if (method === "margin") return v >= 100 ? null : roundToStep(c / (1 - v / 100), step);
  if (method === "markup") return roundToStep(c * (1 + v / 100), step);
  return null;
}

export const marginOf = (price, cost) => (price > 0 && cost != null ? ((price - cost) / price) * 100 : null);
export const markupOf = (price, cost) => (cost > 0 && price != null ? ((price - cost) / cost) * 100 : null);
export const withTax = (net, tax) => (net == null ? null : Math.round(net * (1 + Number(tax) / 100) * 100) / 100);

export const money = (value, currency = "ARS") =>
  value == null || value === "" ? "—" : Number(value).toLocaleString("es-AR", { style: "currency", currency });
export const percent = (value) =>
  value == null ? "—" : `${Number(value).toLocaleString("es-AR", { maximumFractionDigits: 2 })} %`;

export const methodLabels = {
  margin: "Margen sobre precio",
  markup: "Recargo sobre costo",
  fixed: "Precio fijo",
};

/* La función no existe todavía en la base (migración 039 sin aplicar). */
export const isMissingFunction = (error) =>
  ["PGRST202", "PGRST205", "42883", "42P01"].includes(error?.code) ||
  /Could not find the (function|table)|does not exist/i.test(error?.message ?? "");

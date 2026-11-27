import { jsPDF } from "jspdf";
import { autoTable } from "jspdf-autotable";

/*
 * PDF del presupuesto para el cliente. Solo precios finales: no contiene costos, márgenes ni listas internas.
 * Todo sale del documento guardado (erp_quote_detail) y de los datos de la empresa: el PDF coincide con lo registrado.
 */
const GREEN = [21, 128, 61];
const INK = [24, 38, 48];
const MUTED = [90, 106, 118];
const LINE = [214, 224, 228];
const SOFT = [243, 249, 245];

const money = (value) =>
  Number(value ?? 0).toLocaleString("es-AR", { style: "currency", currency: "ARS", minimumFractionDigits: 2 });
const qty = (value) => Number(value ?? 0).toLocaleString("es-AR", { maximumFractionDigits: 6 });
const pct = (value) => `${Number(value ?? 0).toLocaleString("es-AR", { maximumFractionDigits: 2 })} %`;
const dateOnly = (iso) => {
  const [y, m, d] = String(iso).slice(0, 10).split("-");
  return `${d}/${m}/${y}`;
};
const dateTime = (iso) =>
  new Date(iso).toLocaleDateString("es-AR", { timeZone: "America/Argentina/Buenos_Aires" });

export const quoteNumber = (number) => `P-${String(number).padStart(5, "0")}`;

// Aritmética en centavos: coincide con el redondeo del servidor (round half up sobre decimales exactos).
const toCents = (value) => BigInt(Math.round(Number(value) * 100));
const taxCents = (cents, rate) => (cents * BigInt(Math.round(Number(rate) * 100)) + 5000n) / 10000n;
const grossValue = (value, rate) => {
  const cents = toCents(value);
  return Number(cents + taxCents(cents, rate)) / 100;
};

function logoFormat(data) {
  return /^data:image\/jpeg/.test(data) ? "JPEG" : /^data:image\/webp/.test(data) ? "WEBP" : "PNG";
}

export function buildQuotePdf(quote, profile) {
  const pdf = new jsPDF({ unit: "mm", format: "a4", compress: true });
  const width = pdf.internal.pageSize.getWidth();
  const height = pdf.internal.pageSize.getHeight();
  const left = 16;
  const right = width - 16;
  const lines = [...(quote.lines ?? [])].sort((a, b) => a.line_no - b.line_no);
  const hasDiscount = lines.some((line) => Number(line.discount_percent) > 0);
  const showTax = quote.show_tax;
  const included = !showTax && Boolean(quote.tax_included); // IVA sumado al precio, sin discriminar
  const preview = Boolean(quote.preview);
  const priceOf = (value, rate) => (included ? grossValue(value, rate) : Number(value));

  // Franja superior y membrete
  pdf.setFillColor(...GREEN);
  pdf.rect(0, 0, width, 5, "F");

  let textX = left;
  if (profile?.logo_data) {
    try {
      const image = pdf.getImageProperties(profile.logo_data);
      const ratio = Math.min(46 / image.width, 22 / image.height);
      const w = image.width * ratio;
      const h = image.height * ratio;
      pdf.addImage(profile.logo_data, logoFormat(profile.logo_data), left, 12, w, h);
      textX = left + w + 6;
    } catch {
      textX = left;
    }
  }
  pdf.setFont("helvetica", "bold");
  pdf.setFontSize(14);
  pdf.setTextColor(...INK);
  const nameLines = pdf.splitTextToSize(profile?.legal_name || "Empresa", 78);
  pdf.text(nameLines, textX, 17);
  let infoY = 17 + nameLines.length * 5.2;
  pdf.setFont("helvetica", "normal");
  pdf.setFontSize(8.5);
  pdf.setTextColor(...MUTED);
  const info = [
    [profile?.tax_id && `CUIT ${profile.tax_id}`, profile?.tax_condition].filter(Boolean).join("  ·  "),
    profile?.address,
    [profile?.phone, profile?.email].filter(Boolean).join("  ·  "),
    profile?.website,
  ].filter(Boolean);
  info.forEach((text) => {
    pdf.text(pdf.splitTextToSize(text, 78), textX, infoY);
    infoY += 4.4;
  });

  // Título y datos del documento (derecha)
  pdf.setFont("helvetica", "bold");
  pdf.setFontSize(22);
  pdf.setTextColor(...GREEN);
  pdf.text("PRESUPUESTO", right, 20, { align: "right" });
  pdf.setFontSize(11);
  pdf.setTextColor(...INK);
  pdf.text(preview ? "Nº (se asigna al crearlo)" : `Nº ${quoteNumber(quote.number)}`, right, 27, { align: "right" });
  pdf.setFont("helvetica", "normal");
  pdf.setFontSize(9);
  pdf.setTextColor(...MUTED);
  pdf.text(`Fecha: ${dateTime(quote.created_at)}`, right, 33, { align: "right" });
  pdf.setFont("helvetica", "bold");
  pdf.setTextColor(...INK);
  pdf.text(`Válido hasta: ${dateOnly(quote.valid_until)}`, right, 38.5, { align: "right" });

  // Bloque del cliente
  const boxY = Math.max(infoY, 44) + 3;
  const customerLines = [
    quote.customer_tax_id && `CUIT / documento: ${quote.customer_tax_id}`,
    quote.customer_address,
    [quote.customer_phone, quote.customer_email].filter(Boolean).join("  ·  "),
  ].filter(Boolean);
  const boxH = 14 + customerLines.length * 4.6;
  pdf.setFillColor(...SOFT);
  pdf.setDrawColor(...LINE);
  pdf.roundedRect(left, boxY, right - left, boxH, 2, 2, "FD");
  pdf.setFont("helvetica", "bold");
  pdf.setFontSize(7.5);
  pdf.setTextColor(...GREEN);
  pdf.text("PRESUPUESTO PARA", left + 4, boxY + 5.5);
  pdf.setFontSize(11);
  pdf.setTextColor(...INK);
  pdf.text(pdf.splitTextToSize(quote.customer_name, right - left - 8)[0], left + 4, boxY + 11);
  pdf.setFont("helvetica", "normal");
  pdf.setFontSize(8.5);
  pdf.setTextColor(...MUTED);
  customerLines.forEach((text, index) => pdf.text(pdf.splitTextToSize(text, right - left - 8)[0], left + 4, boxY + 16 + index * 4.6));

  // Tabla de productos
  const head = ["CÓDIGO", "DESCRIPCIÓN", "CANT.", ...(hasDiscount ? ["P. LISTA", "DESC."] : []), "P. UNIT.", "IMPORTE"];
  const body = lines.map((line) => [
    line.item_code,
    line.item_name,
    `${qty(line.quantity)} ${line.unit_symbol}`,
    ...(hasDiscount
      ? [money(priceOf(line.list_unit_price, line.tax_percent)), Number(line.discount_percent) > 0 ? pct(line.discount_percent) : "—"]
      : []),
    money(priceOf(line.unit_price, line.tax_percent)),
    // Con IVA sumado: importe de línea calculado por el servidor (line_gross); si falta, mismo cálculo en centavos.
    money(included
      ? (line.line_gross ?? Number(toCents(line.line_total) + taxCents(toCents(line.line_total), line.tax_percent)) / 100)
      : line.line_total),
  ]);
  const numericCols = hasDiscount ? [2, 3, 4, 5, 6] : [2, 3, 4];
  const columnStyles = Object.fromEntries(numericCols.map((index) => [index, { halign: "right", cellWidth: "wrap" }]));
  columnStyles[0] = { cellWidth: 22 };
  autoTable(pdf, {
    startY: boxY + boxH + 6,
    head: [head],
    body,
    theme: "plain",
    margin: { left, right: 16, bottom: 26 },
    rowPageBreak: "avoid",
    styles: { font: "helvetica", fontSize: 8.5, textColor: INK, cellPadding: { top: 2.6, bottom: 2.6, left: 2.5, right: 2.5 }, lineColor: LINE, lineWidth: { bottom: 0.15 }, overflow: "linebreak", valign: "middle" },
    headStyles: { fillColor: GREEN, textColor: 255, fontStyle: "bold", fontSize: 8, lineWidth: 0 },
    alternateRowStyles: { fillColor: [249, 252, 250] },
    columnStyles,
    showHead: "everyPage",
  });

  // Totales (a la derecha) y condiciones
  let y = (pdf.lastAutoTable?.finalY ?? 80) + 8;
  const rows = showTax
    ? [
        ["Subtotal neto", money(quote.net_total)],
        ...(quote.tax_breakdown ?? []).map((entry) => [`IVA ${pct(entry.rate)}`, money(entry.tax)]),
      ]
    : [];
  const boxWidth = 78;
  const totalsHeight = rows.length * 6 + 14;
  if (y + totalsHeight > height - 30) {
    pdf.addPage();
    y = 22;
  }
  const x0 = right - boxWidth;
  pdf.setFont("helvetica", "normal");
  pdf.setFontSize(9);
  rows.forEach(([label, value], index) => {
    pdf.setTextColor(...MUTED);
    pdf.text(label, x0, y + index * 6);
    pdf.setTextColor(...INK);
    pdf.text(value, right, y + index * 6, { align: "right" });
  });
  const totalY = y + rows.length * 6 - (rows.length ? 2 : 0);
  pdf.setFillColor(...GREEN);
  pdf.roundedRect(x0 - 3, totalY + 1, boxWidth + 3, 10, 1.5, 1.5, "F");
  pdf.setFont("helvetica", "bold");
  pdf.setFontSize(11);
  pdf.setTextColor(255, 255, 255);
  pdf.text(showTax || included ? "TOTAL" : "TOTAL (IVA no incluido)", x0, totalY + 7.6);
  pdf.text(money(showTax || included ? quote.gross_total : quote.net_total), right - 2, totalY + 7.6, { align: "right" });
  y = totalY + 20;

  const conditions = [
    quote.note && String(quote.note).trim(),
    `Presupuesto válido hasta el ${dateOnly(quote.valid_until)}. Pasada esa fecha los precios pueden modificarse.`,
    "Importes expresados en pesos argentinos.",
    showTax
      ? "Los precios unitarios no incluyen IVA; se detalla aparte y está sumado en el total."
      : included ? "Precios finales, IVA incluido." : "Los precios no incluyen IVA.",
  ].filter(Boolean);
  pdf.setFont("helvetica", "bold");
  pdf.setFontSize(8.5);
  pdf.setTextColor(...GREEN);
  const textLines = conditions.flatMap((text) => pdf.splitTextToSize(text, right - left));
  if (y + 8 + textLines.length * 4.2 > height - 24) {
    pdf.addPage();
    y = 22;
  }
  pdf.text("CONDICIONES", left, y);
  pdf.setFont("helvetica", "normal");
  pdf.setTextColor(...MUTED);
  let cy = y + 5;
  conditions.forEach((text) => {
    const wrapped = pdf.splitTextToSize(text, right - left);
    pdf.text(wrapped, left, cy);
    cy += wrapped.length * 4.2 + 1.5;
  });

  // Pie de página en todas las hojas
  const pages = pdf.internal.getNumberOfPages();
  for (let page = 1; page <= pages; page += 1) {
    pdf.setPage(page);
    pdf.setDrawColor(...LINE);
    pdf.line(left, height - 16, right, height - 16);
    pdf.setFont("helvetica", "normal");
    pdf.setFontSize(7.5);
    pdf.setTextColor(...MUTED);
    pdf.text(
      [profile?.legal_name, profile?.phone, profile?.email].filter(Boolean).join("  ·  ") || "Presupuesto",
      left, height - 11,
    );
    pdf.text("Documento no válido como factura", left, height - 7.5);
    pdf.text(`${preview ? "Vista previa" : quoteNumber(quote.number)}  ·  Página ${page} de ${pages}`, right, height - 11, { align: "right" });
    if (preview) {
      pdf.setGState(new pdf.GState({ opacity: 0.09 }));
      pdf.setFont("helvetica", "bold");
      pdf.setFontSize(64);
      pdf.setTextColor(...GREEN);
      pdf.text("VISTA PREVIA", width / 2, height / 2, { align: "center", angle: 40 });
      pdf.setGState(new pdf.GState({ opacity: 1 }));
    }
  }
  return pdf;
}

const safeName = (text) => String(text).normalize("NFD").replace(/[^\w-]+/g, "_").slice(0, 40);

export function downloadQuotePdf(quote, profile) {
  buildQuotePdf(quote, profile).save(`Presupuesto_${quoteNumber(quote.number)}_${safeName(quote.customer_name)}.pdf`);
}

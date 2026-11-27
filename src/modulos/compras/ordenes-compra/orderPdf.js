import { jsPDF } from 'jspdf';
import { autoTable } from 'jspdf-autotable';

const money = (value) => Number(value).toLocaleString('es-AR', {
  style: 'currency',
  currency: 'ARS',
  minimumFractionDigits: 2,
});

export function createPurchaseOrderPdf(order, companyName) {
  const pdf = new jsPDF({ unit: 'mm', format: 'a4', compress: true });
  const teal = [22, 133, 123];
  const ink = [25, 43, 59];
  const muted = [76, 96, 109];
  const width = pdf.internal.pageSize.getWidth();

  pdf.setFillColor(...ink);
  pdf.rect(0, 0, width, 7, 'F');

  pdf.setFont('helvetica', 'bold');
  pdf.setFontSize(21);
  pdf.setTextColor(...ink);
  pdf.text('ORDEN DE COMPRA', 18, 27);

  pdf.setFontSize(11);
  pdf.setTextColor(...teal);
  pdf.text(`OC-${String(order.number).padStart(5, '0')}`, width - 18, 26, {
    align: 'right',
  });

  pdf.setDrawColor(221, 231, 234);
  pdf.line(18, 33, width - 18, 33);

  pdf.setTextColor(...muted);
  pdf.setFontSize(9);
  pdf.setFont('helvetica', 'normal');
  pdf.text('EMPRESA', 18, 42);
  pdf.text('PROVEEDOR', 110, 42);
  pdf.setFont('helvetica', 'bold');
  pdf.setTextColor(...ink);
  pdf.setFontSize(11);
  pdf.text(pdf.splitTextToSize(companyName || 'Empresa', 83), 18, 48);
  pdf.text(pdf.splitTextToSize(order.supplier_name, 80), 110, 48);

  pdf.setFont('helvetica', 'normal');
  pdf.setTextColor(...muted);
  pdf.setFontSize(9);
  pdf.text(`Fecha: ${new Date(order.created_at).toLocaleDateString('es-AR', {
    timeZone: 'America/Argentina/Buenos_Aires',
  })}`, 18, 67);
  const statusLabels = {
    open: 'Abierta',
    partial: 'Recibida parcialmente',
    received: 'Recibida',
    cancelled: 'Cancelada',
  };
  pdf.text(`Estado: ${statusLabels[order.status] ?? order.status}`, 110, 67);

  const rows = [...(order.lines ?? [])]
    .sort((a, b) => a.line_no - b.line_no)
    .map((line) => [
      `${line.item_code}\n${line.item_name || ''}`,
      `${Number(line.quantity).toLocaleString('es-AR')} ${line.unit_symbol}`,
      money(line.unit_price),
      money(Number(line.quantity) * Number(line.unit_price)),
    ]);

  autoTable(pdf, {
    startY: 75,
    head: [['MATERIAL', 'CANTIDAD', 'PRECIO / UNIDAD', 'IMPORTE']],
    body: rows,
    theme: 'plain',
    rowPageBreak: 'avoid',
    margin: { left: 18, right: 18, bottom: 25 },
    styles: {
      font: 'helvetica',
      fontSize: 9,
      textColor: ink,
      cellPadding: 4,
      lineColor: [228, 236, 238],
      lineWidth: 0.15,
      overflow: 'linebreak',
      valign: 'middle',
    },
    headStyles: { fillColor: teal, textColor: 255, fontStyle: 'bold' },
    columnStyles: {
      0: { cellWidth: 72 },
      1: { cellWidth: 30, halign: 'right' },
      2: { cellWidth: 36, halign: 'right' },
      3: { cellWidth: 36, halign: 'right' },
    },
    alternateRowStyles: { fillColor: [246, 250, 249] },
  });

  const total = (order.lines ?? []).reduce((sum, line) => (
    sum + Number(line.quantity) * Number(line.unit_price)
  ), 0);
  let y = (pdf.lastAutoTable?.finalY ?? 80) + 12;
  if (y > 258) {
    pdf.addPage();
    y = 25;
  }

  pdf.setFont('helvetica', 'bold');
  pdf.setFontSize(12);
  pdf.setTextColor(...ink);
  pdf.text(`TOTAL ESTIMADO: ${money(total)}`, width - 18, y, { align: 'right' });

  if (order.note) {
    const noteLines = pdf.splitTextToSize(`Nota: ${order.note}`, width - 36);
    y += 12;
    if (y + noteLines.length * 5 > 270) {
      pdf.addPage();
      y = 25;
    }
    pdf.setFont('helvetica', 'normal');
    pdf.setTextColor(...muted);
    pdf.setFontSize(9);
    pdf.text(noteLines, 18, y);
  }

  for (let page = 1; page <= pdf.internal.getNumberOfPages(); page += 1) {
    pdf.setPage(page);
    const pageHeight = pdf.internal.pageSize.getHeight();
    pdf.setDrawColor(221, 231, 234);
    pdf.line(18, pageHeight - 18, width - 18, pageHeight - 18);
    pdf.setFont('helvetica', 'normal');
    pdf.setTextColor(...muted);
    pdf.setFontSize(8);
    pdf.text('ERP Dromux · Documento de compra · No registra recepción ni pago',
      18, pageHeight - 12);
    pdf.text(`${page} / ${pdf.internal.getNumberOfPages()}`,
      width - 18, pageHeight - 12, { align: 'right' });
  }

  return pdf;
}

export function downloadPurchaseOrderPdf(order, companyName) {
  createPurchaseOrderPdf(order, companyName)
    .save(`orden-compra-${String(order.number).padStart(5, '0')}.pdf`);
}

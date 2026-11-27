import { jsPDF } from 'jspdf';
import { autoTable } from 'jspdf-autotable';

const amount = (value) => Number(value).toLocaleString('es-AR', {
  maximumFractionDigits: 6,
});

export function downloadDeliveryNotePdf(note, companyName, productName) {
  const pdf = new jsPDF({ unit: 'mm', format: 'a4', compress: true });
  pdf.setFillColor(22, 56, 68);
  pdf.rect(0, 0, 210, 7, 'F');
  pdf.setTextColor(21, 47, 57);
  pdf.setFont('helvetica', 'bold');
  pdf.setFontSize(19);
  pdf.text('REMITO DE ENTREGA', 16, 24);
  pdf.setFontSize(12);
  pdf.text(`Nº ${note.number}`, 194, 24, { align: 'right' });
  pdf.setFont('helvetica', 'normal');
  pdf.setFontSize(10);
  const lines = [
    `Empresa: ${companyName || 'Empresa'}`,
    `Fecha: ${new Date(note.created_at).toLocaleString('es-AR')}`,
    `Destino: ${note.recipient}`,
    `Tipo: ${{ production: 'Para fabricación', materials: 'Materiales',
      products: 'Semielaborados y productos', sale: 'Entrega de venta' }[note.kind]}`,
    ...(note.sale?.number ? [`Venta Nº ${note.sale.number} · ${note.sale.customer_name}`] : []),
    ...(productName ? [`Orden de fabricación: ${productName}`] : []),
    `Observaciones: ${note.note}`,
  ];
  let y = 35;
  for (const line of lines) {
    const parts = pdf.splitTextToSize(line, 178);
    pdf.text(parts, 16, y);
    y += parts.length * 5 + 2;
  }
  autoTable(pdf, {
    startY: y + 4,
    head: [['CÓDIGO / ÍTEM', 'CANTIDAD', 'ORIGEN', 'LOTE']],
    body: [...(note.delivery_note_lines ?? [])]
      .sort((a, b) => a.line_no - b.line_no)
      .map((entry) => [
        `${entry.item_code} · ${entry.item_name}`,
        `${amount(entry.quantity)} ${entry.unit_symbol}`,
        entry.warehouse_name,
        entry.lot_code || '—',
      ]),
    theme: 'striped',
    headStyles: { fillColor: [22, 135, 124] },
    margin: { left: 16, right: 16, bottom: 36 },
    styles: { fontSize: 9, cellPadding: 3 },
  });
  let signY = (pdf.lastAutoTable?.finalY ?? y) + 20;
  if (signY > 256) { pdf.addPage(); signY = 34; }
  pdf.setFontSize(9);
  pdf.text('Entregó: ____________________   Recibió: ____________________', 16, signY);
  pdf.text('Aclaración: __________________   Fecha: _____________________', 16, signY + 9);
  if (note.status === 'voided') {
    pdf.setTextColor(177, 48, 54);
    pdf.setFont('helvetica', 'bold');
    pdf.text('ANULADO · Documento sin vigencia', 16, signY + 23);
  }
  const pages = pdf.internal.getNumberOfPages();
  for (let page = 1; page <= pages; page += 1) {
    pdf.setPage(page);
    pdf.setTextColor(94, 109, 115);
    pdf.setFontSize(8);
    pdf.text(`${page}/${pages}`, 194, 289, { align: 'right' });
  }
  pdf.save(`remito-${note.number}.pdf`);
}

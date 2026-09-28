import { jsPDF } from 'jspdf';
import { autoTable } from 'jspdf-autotable';

const quantity = (value) => Number(value).toLocaleString('es-AR', {
  maximumFractionDigits: 6,
});
const money = (value) => Number(value).toLocaleString('es-AR', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

export function downloadProductionJobPdf(job, items, warehouses, companyName) {
  const pdf = new jsPDF({ unit: 'mm', format: 'a4', compress: true });
  const itemName = (id) => items.find((item) => item.id === id)?.name ?? id;
  const warehouseName = (id) => warehouses.find((entry) => entry.id === id)?.name ?? 'Depósito';
  const events = [...(job.production_job_events ?? [])].sort((a, b) =>
    new Date(a.created_at) - new Date(b.created_at));
  const ink = [21, 43, 57];
  const teal = [22, 133, 123];
  const width = pdf.internal.pageSize.getWidth();
  pdf.setFillColor(...ink);
  pdf.rect(0, 0, width, 7, 'F');
  pdf.setFont('helvetica', 'bold');
  pdf.setTextColor(...ink);
  pdf.setFontSize(19);
  pdf.text('ORDEN DE FABRICACIÓN', 16, 23);
  pdf.setFontSize(10);
  pdf.setTextColor(...teal);
  pdf.text(job.id.slice(0, 8).toUpperCase(), width - 16, 23, { align: 'right' });
  pdf.setDrawColor(216, 229, 230);
  pdf.line(16, 29, width - 16, 29);
  pdf.setFont('helvetica', 'normal');
  pdf.setFontSize(10);
  pdf.setTextColor(...ink);
  const header = [
    companyName || 'Empresa',
    `Producto: ${itemName(job.product_id)}`,
    `Objetivo: ${quantity(job.planned_quantity)} · Real: ${job.actual_quantity == null
      ? 'Pendiente' : quantity(job.actual_quantity)}`,
    `Depósito: ${warehouseName(job.warehouse_id)} · Fórmula v${job.formula_version}`,
    `Creada: ${new Date(job.created_at).toLocaleString('es-AR')} · Estado: ${{
      queued: 'En cola', in_progress: 'En proceso', completed: 'Completada',
      cancelled: 'Cancelada',
    }[job.status] ?? job.status}`,
    `Nota: ${job.note}`,
  ];
  let y = 36;
  header.forEach((line) => {
    const lines = pdf.splitTextToSize(line, width - 32);
    pdf.text(lines, 16, y);
    y += lines.length * 5 + 2;
  });
  if (job.output_lot) {
    pdf.text(`Lote fabricado: ${job.output_lot}`, 16, y);
    y += 7;
  }
  autoTable(pdf, {
    startY: y + 2,
    head: [['INSUMO TEÓRICO', 'CANTIDAD', 'COSTO PREVISTO/UNIDAD']],
    body: (job.formula_snapshot ?? []).map((entry) => [
      itemName(entry.component_id),
      quantity(entry.quantity),
      `$ ${money(entry.unit_cost)}`,
    ]),
    theme: 'striped',
    headStyles: { fillColor: teal },
    margin: { left: 16, right: 16, bottom: 24 },
    styles: { fontSize: 9, cellPadding: 3 },
  });
  if (events.length) {
    autoTable(pdf, {
      startY: (pdf.lastAutoTable?.finalY ?? y) + 12,
      head: [['MOVIMIENTO REAL', 'INSUMO', 'CANTIDAD', 'DEPÓSITO / LOTE']],
      body: events.map((event) => [
        event.kind === 'issue' ? 'Consumo' : 'Devolución',
        itemName(event.component_id),
        quantity(event.quantity),
        `${warehouseName(event.warehouse_id)}${event.lot_code ? ` · ${event.lot_code}` : ''}`,
      ]),
      theme: 'striped',
      headStyles: { fillColor: ink },
      margin: { left: 16, right: 16, bottom: 24 },
      styles: { fontSize: 8.4, cellPadding: 3 },
    });
  }
  let noteY = (pdf.lastAutoTable?.finalY ?? y) + 12;
  if (noteY > 250) { pdf.addPage(); noteY = 22; }
  pdf.setTextColor(...ink);
  pdf.setFontSize(9);
  if (job.variance_note) {
    const lines = pdf.splitTextToSize(`Diferencias: ${job.variance_note}`, width - 32);
    pdf.text(lines, 16, noteY);
    noteY += lines.length * 5 + 6;
  }
  pdf.text('Responsable: ______________________    Fecha: ______________________', 16, noteY);
  const pages = pdf.internal.getNumberOfPages();
  for (let i = 1; i <= pages; i += 1) {
    pdf.setPage(i);
    pdf.setFontSize(8);
    pdf.setTextColor(90, 109, 115);
    pdf.text(`Documento interno · ${i}/${pages}`, width - 16, 289, { align: 'right' });
  }
  pdf.save(`fabricacion-${job.id.slice(0, 8)}.pdf`);
}

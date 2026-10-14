import { jsPDF } from 'jspdf';
import { autoTable } from 'jspdf-autotable';

const quantity = (value) =>
  Number(value ?? 0).toLocaleString('es-AR', { maximumFractionDigits: 6 });

export function buildProductionJobPdf(job, items, warehouses, companyName, settings = {}) {
  const pdf = new jsPDF({ unit: 'mm', format: 'a4', compress: true });
  const product = items.find((item) => item.id === job.product_id);
  const itemById = Object.fromEntries(items.map((item) => [item.id, item]));
  const net = new Map();
  for (const event of job.production_job_events ?? []) {
    net.set(
      event.component_id,
      (net.get(event.component_id) ?? 0) +
        Number(event.quantity) * (event.kind === 'return' ? -1 : 1),
    );
  }
  const snapshot = job.document_snapshot ?? {};
  const work = job.work_options ?? {};
  const code = snapshot.code ?? settings?.document_code ?? 'OP';
  const revision = snapshot.revision ?? settings?.revision ?? '01';
  const margin = { left: 12, right: 12, bottom: 18 };
  const style = {
    theme: 'grid',
    margin,
    styles: { fontSize: 8, cellPadding: 2.5, lineColor: [100, 115, 120], lineWidth: 0.15 },
    headStyles: { fillColor: [225, 232, 233], textColor: [20, 35, 40], fontStyle: 'bold' },
  };
  pdf.setDrawColor(90, 105, 110);
  pdf.rect(12, 12, 186, 31);
  pdf.line(82, 12, 82, 43);
  if (settings?.logo_data) {
    const image = pdf.getImageProperties(settings.logo_data);
    const ratio = Math.min(58 / image.width, 20 / image.height);
    pdf.addImage(settings.logo_data, 'PNG', 18, 16, image.width * ratio, image.height * ratio);
  } else {
    pdf.setFontSize(11);
    pdf.setFont('helvetica', 'bold');
    pdf.text(pdf.splitTextToSize(companyName || 'Empresa', 58), 17, 24);
  }
  pdf.setFont('helvetica', 'bold');
  pdf.setFontSize(11);
  pdf.text(`ORDEN DE PRODUCCION ${job.number ?? ''}`, 87, 20);
  pdf.setFont('helvetica', 'normal');
  pdf.setFontSize(8);
  pdf.text(
    pdf.splitTextToSize(`${code}  |  Revision ${revision}  |  Formula ${job.formula_version}`, 104),
    87,
    27,
  );
  pdf.setFont('helvetica', 'bold');
  pdf.setFontSize(10);
  pdf.text(pdf.splitTextToSize(product?.name || 'Producto', 104), 87, 34);
  autoTable(pdf, {
    ...style,
    startY: 46,
    body: [
      [
        'Fecha',
        new Date(job.created_at).toLocaleDateString('es-AR'),
        'Lote',
        job.output_lot || '________________',
      ],
      [
        'Cantidad base',
        `${quantity(job.planned_quantity)} ${product?.units?.symbol ?? ''}`,
        'Factor de rendimiento',
        quantity(job.yield_factor ?? 1),
      ],
      [
        'Salida esperada',
        `${quantity(job.expected_output ?? job.planned_quantity)} ${product?.units?.symbol ?? ''}`,
        'Salida real',
        job.actual_quantity == null
          ? '________________'
          : `${quantity(job.actual_quantity)} ${product?.units?.symbol ?? ''}`,
      ],
      [
        'Deposito',
        warehouses.find((entry) => entry.id === job.warehouse_id)?.name ?? 'Deposito',
        'Estado',
        {
          queued: 'En cola',
          in_progress: 'En proceso',
          completed: 'Completada',
          cancelled: 'Cancelada',
        }[job.status] ?? '',
      ],
    ],
    columnStyles: {
      0: { fontStyle: 'bold', cellWidth: 32 },
      1: { cellWidth: 61 },
      2: { fontStyle: 'bold', cellWidth: 38 },
      3: { cellWidth: 55 },
    },
  });
  const materials = [...(job.formula_snapshot ?? [])];
  for (const [id] of net)
    if (!materials.some((line) => line.component_id === id))
      materials.push({ component_id: id, quantity: 0 });
  autoTable(pdf, {
    ...style,
    startY: pdf.lastAutoTable.finalY + 4,
    head: [['N', 'OK', 'MATERIAL / INSUMO', 'PREVISTO', 'UNIDAD', 'REAL', 'OBSERVACIONES']],
    body: materials.map((line, index) => [
      index + 1,
      '',
      itemById[line.component_id]?.name ?? 'Insumo',
      quantity(line.quantity),
      itemById[line.component_id]?.units?.symbol ?? '',
      net.has(line.component_id) ? quantity(net.get(line.component_id)) : '',
      '',
    ]),
    columnStyles: {
      0: { cellWidth: 10 },
      1: { cellWidth: 10 },
      2: { cellWidth: 53 },
      3: { cellWidth: 22 },
      4: { cellWidth: 16 },
      5: { cellWidth: 22 },
      6: { cellWidth: 53 },
    },
    didDrawCell: (cell) => {
      if (cell.section === 'body' && cell.column.index === 1)
        pdf.rect(cell.cell.x + 3, cell.cell.y + 2.5, 3.5, 3.5);
    },
  });
  autoTable(pdf, {
    ...style,
    startY: pdf.lastAutoTable.finalY + 5,
    head: [['ENVASADO', 'CAPACIDAD', 'ENVASES PREVISTOS', 'ENVASES REALES']],
    body: (work.packaging ?? []).length
      ? work.packaging.map((entry) => [
          entry.name,
          `${quantity(entry.capacity)} ${entry.unit}`,
          quantity(entry.count),
          entry.actual_count == null ? '' : quantity(entry.actual_count),
        ])
      : [['Sin envasado definido', '', '', '']],
  });
  const labels = snapshot.labels ?? settings?.observation_labels ?? [];
  const controls = labels.map((label) => [label, work.observations?.[label] || '']);
  controls.push(['Observaciones del proceso', job.note || '']);
  if (job.variance_note) controls.push(['Diferencias frente a lo previsto', job.variance_note]);
  autoTable(pdf, {
    ...style,
    startY: pdf.lastAutoTable.finalY + 5,
    head: [['CONTROL / OBSERVACION', 'RESULTADO / DETALLE']],
    body: controls,
    margin: { ...margin, bottom: 30 },
    columnStyles: { 0: { cellWidth: 60 }, 1: { cellWidth: 126 } },
    styles: { ...style.styles, minCellHeight: 12 },
  });
  let y = pdf.lastAutoTable.finalY + 10;
  if (y > 280) {
    pdf.addPage();
    y = 24;
  }
  pdf.setFontSize(9);
  pdf.text('Elaborado por: ____________________   Verificado por: ____________________', 12, y);
  for (let page = 1; page <= pdf.getNumberOfPages(); page++) {
    pdf.setPage(page);
    pdf.setFont('helvetica', 'normal');
    pdf.setFontSize(8);
    pdf.text(`OF ${job.number ?? ''} - ${page}/${pdf.getNumberOfPages()}`, 198, 289, {
      align: 'right',
    });
  }
  return pdf;
}

export function downloadProductionJobPdf(job, items, warehouses, companyName, settings) {
  buildProductionJobPdf(job, items, warehouses, companyName, settings).save(
    `orden-produccion-${job.number ?? 'documento'}.pdf`,
  );
}

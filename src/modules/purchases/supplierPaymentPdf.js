import { jsPDF } from 'jspdf';
import { autoTable } from 'jspdf-autotable';

export function buildPaymentOrderPdf(row, company) {
  const pdf = new jsPDF();
  const money = (value) =>
    `$ ${Number(value).toLocaleString('es-AR', { minimumFractionDigits: 2 })}`;
  pdf.setFontSize(18);
  pdf.text(`ORDEN DE PAGO ${row.number}`, 16, 23);
  pdf.setFontSize(10);
  const header = pdf.splitTextToSize(
    `${company || 'Empresa'}\nProveedor: ${row.supplier?.name}\nCuenta: ${row.account?.name}\nFecha: ${row.paid_on}\nEstado: ${{ draft: 'BORRADOR - NO PAGADO', paid: 'PAGADA', cancelled: 'ANULADA' }[row.status]}\nReferencia: ${row.reference || '-'}\n${row.note}`,
    178,
  );
  pdf.text(header, 16, 34);
  autoTable(pdf, {
    startY: 34 + header.length * 4 + 8,
    head: [['ORDEN DE COMPRA', 'IMPORTE']],
    body: (row.lines ?? []).map((line) => [
      `OC ${line.order?.number}`,
      money(line.amount),
    ]),
    margin: { left: 16, right: 16, bottom: 40 },
    headStyles: { fillColor: [21, 65, 70] },
  });
  pdf.text(`TOTAL: ${money(row.amount)}`, 16, pdf.lastAutoTable.finalY + 12);
  pdf.text(
    'Autorizado por: ____________________   Recibido por: ____________________',
    16,
    pdf.lastAutoTable.finalY + 26,
  );
  return pdf;
}

export function downloadPaymentOrder(row, company) {
  buildPaymentOrderPdf(row, company).save(`orden-pago-${row.number}.pdf`);
}

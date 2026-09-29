import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useSearchParams } from 'react-router-dom';
import { FileDown, Plus, RotateCcw } from 'lucide-react';
import ActionDialog from '../../components/ActionDialog';
import { useAuth } from '../../contexts/AuthContext';
import { friendlyError, notifyError, notifySuccess } from '../../lib/notifications';
import { listDeliveryNotes, listDeliveryItems, voidDeliveryNote } from '../../services/deliveryNotes';
import {
  listProductionJobs, listProductionReservationLocations, listProductionWarehouses,
} from '../../services/production';
import { formatQuantity } from './stockNumber';
import { listSales } from '../../services/sales';
import DeliveryNoteComposer from './DeliveryNoteComposer';
import './deliveryNotes.css';

const kinds = {
  production: 'Para fabricación',
  materials: 'Materiales',
  products: 'Productos y semielaborados',
  sale: 'Entrega de venta',
};

export default function DeliveryNotesPage() {
  const { activeCompanyId, activeCompany, user, can } = useAuth();
  const client = useQueryClient();
  const [params, setParams] = useSearchParams();
  const linkedJobId = params.get('job') ?? '';
  const linkedSaleId = params.get('sale') ?? '';
  const [createOpen, setCreateOpen] = useState(Boolean(linkedJobId || linkedSaleId));
  const [voidTarget, setVoidTarget] = useState(null);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [issuing, setIssuing] = useState(false);
  const [search, setSearch] = useState('');
  const notesQuery = useQuery({
    queryKey: ['delivery-notes', user?.id, activeCompanyId],
    queryFn: () => listDeliveryNotes(activeCompanyId),
    enabled: Boolean(activeCompanyId),
  });
  const itemsQuery = useQuery({
    queryKey: ['delivery-items', user?.id, activeCompanyId],
    queryFn: () => listDeliveryItems(activeCompanyId),
    enabled: Boolean(activeCompanyId && can('items', 'read')),
  });
  const warehousesQuery = useQuery({
    queryKey: ['production-warehouses', user?.id, activeCompanyId],
    queryFn: () => listProductionWarehouses(activeCompanyId),
    enabled: Boolean(activeCompanyId),
  });
  const salesQuery = useQuery({
    queryKey: ['sales-history', user?.id, activeCompanyId],
    queryFn: () => listSales(activeCompanyId),
    enabled: Boolean(activeCompanyId && can('sales', 'read')),
  });
  const jobsQuery = useQuery({
    queryKey: ['production-jobs', user?.id, activeCompanyId],
    queryFn: () => listProductionJobs(activeCompanyId),
    enabled: Boolean(activeCompanyId && can('production', 'read')),
  });
  const allocationsQuery = useQuery({
    queryKey: ['production-reservation-locations', user?.id, activeCompanyId],
    queryFn: () => listProductionReservationLocations(activeCompanyId),
    enabled: Boolean(activeCompanyId && can('production', 'read') && can('stock', 'read')),
  });
  const items = itemsQuery.data ?? [];
  const jobs = jobsQuery.data ?? [];
  const rows = (notesQuery.data ?? []).filter((entry) =>
    `${entry.number} ${entry.recipient} ${entry.note} ${entry.delivery_note_lines
      ?.map((line) => line.item_name).join(' ')}`.toLowerCase()
      .includes(search.toLowerCase()));

  useEffect(() => {
    setSearch('');
    setVoidTarget(null);
    setCreateOpen(Boolean(linkedJobId || linkedSaleId));
  }, [activeCompanyId, linkedJobId, linkedSaleId]);

  function closeCreate(force = false) {
    if (issuing && force !== true) return;
    setCreateOpen(false);
    if (linkedJobId || linkedSaleId) setParams({}, { replace: true });
  }

  function refresh() {
    return Promise.all([
      client.invalidateQueries({ queryKey: ['delivery-notes', user?.id, activeCompanyId] }),
      client.invalidateQueries({ queryKey: ['production-jobs', user?.id, activeCompanyId] }),
      client.invalidateQueries({ queryKey: ['stock'] }),
      client.invalidateQueries({ queryKey: ['stock-movements'] }),
      client.invalidateQueries({ queryKey: ['job-material-balance'] }),
      client.invalidateQueries({ queryKey: ['job-material-lots'] }),
      client.invalidateQueries({ queryKey: ['delivery-balance'] }),
      client.invalidateQueries({ queryKey: ['delivery-lots'] }),
      client.invalidateQueries({ queryKey: ['erp-dashboard'] }),
      client.invalidateQueries({ queryKey: ['operational-alerts'] }),
      client.invalidateQueries({ queryKey: ['production-reservations'] }),
      client.invalidateQueries({ queryKey: ['production-reservation-locations'] }),
      client.invalidateQueries({ queryKey: ['planning-availability'] }),
    ]);
  }

  async function printNote(note) {
    try {
      const { downloadDeliveryNotePdf } = await import('./deliveryNotePdf');
      const productName = jobs.find((job) => job.id === note.job_id)?.product_id;
      downloadDeliveryNotePdf(note, activeCompany?.name,
        items.find((item) => item.id === productName)?.name);
    } catch (error) { notifyError(error); }
  }

  async function confirmVoid(event) {
    event.preventDefault();
    if (!voidTarget || reason.trim().length < 5 || busy) return;
    setBusy(true);
    try {
      await voidDeliveryNote(activeCompanyId, voidTarget.id, reason);
      setVoidTarget(null);
      setReason('');
      await refresh();
      notifySuccess('Remito anulado', voidTarget.kind === 'sale'
        ? 'Se anuló el documento. El stock de la venta no cambió.'
        : 'El stock volvió al depósito de origen.');
    } catch (error) { notifyError(error); } finally { setBusy(false); }
  }

  return (
    <section className="delivery-page">
      <header className="delivery-page-head">
        <div>
          <span className="eyebrow">INVENTARIO / ENTREGAS</span>
          <h1>Remitero</h1>
          <p>Documentá las entregas y descontá stock al confirmar.
            Las entregas para fabricación también quedan asociadas a su orden.</p>
        </div>
        {can('stock', 'insert') && can('items', 'read') &&
          <button type="button" className="button primary" onClick={() => setCreateOpen(true)}>
            <Plus size={17} /> Nuevo remito
          </button>}
      </header>
      <label className="delivery-search">Buscar número, destinatario o producto
        <input type="search" value={search} placeholder="Buscar en los últimos 100 remitos…"
          onChange={(event) => setSearch(event.target.value)} />
      </label>
      {(notesQuery.error || itemsQuery.error || jobsQuery.error) &&
        <p role="alert" className="error">
          {friendlyError(notesQuery.error || itemsQuery.error || jobsQuery.error)}
        </p>}
      {notesQuery.isPending && <p>Cargando remitos…</p>}
      {!notesQuery.isPending && !rows.length &&
        <p>No hay remitos para esta búsqueda. Usá «Nuevo remito» para registrar una entrega.</p>}
      <div className="delivery-list">
        {rows.map((note) => <article className="delivery-card" key={note.id}>
          <div className="delivery-card-head">
            <div>
              <h2>Remito Nº {note.number} · {note.recipient}</h2>
              <p>{kinds[note.kind]} · {new Date(note.created_at).toLocaleString('es-AR')}</p>
            </div>
            <span className={`delivery-status ${note.status}`}>
              {note.status === 'voided' ? 'Anulado' : 'Entregado'}
            </span>
          </div>
          {note.sale_id && <p>Venta Nº {note.sale?.number ?? '—'}
            {' · '}{note.sale?.customer_name ?? note.recipient}</p>}
          {note.job_id && can('production', 'read') &&
            <Link to={`/production/orders?job=${note.job_id}`}>
              Ver orden de fabricación
            </Link>}
          <details>
            <summary>{note.delivery_note_lines?.length ?? 0} ítems · Ver detalle</summary>
            <ul>{[...(note.delivery_note_lines ?? [])]
              .sort((a, b) => a.line_no - b.line_no).map((line) => <li key={line.line_no}>
                {line.item_name} · {formatQuantity(line.quantity)} {line.unit_symbol}
                {' · '}{line.warehouse_name}
                {line.lot_code && ` · Lote ${line.lot_code}`}
              </li>)}</ul>
            <small>{note.note}</small>
            {note.void_reason && <p>Motivo de anulación: {note.void_reason}</p>}
          </details>
          <div className="delivery-card-actions">
            <button type="button" className="button outline" onClick={() => printNote(note)}>
              <FileDown size={16} /> Descargar PDF
            </button>
            {note.status === 'issued' && can('stock', 'delete') &&
              <button type="button" className="button outline" onClick={() => {
                setVoidTarget(note);
                setReason('');
              }}>
                <RotateCcw size={16} /> Anular entrega
              </button>}
          </div>
        </article>)}
      </div>
      <ActionDialog open={createOpen} busy={issuing} title="Nuevo remito de entrega"
        description="Confirmar un remito registra la salida de stock. En fabricación también suma el consumo real."
        onClose={closeCreate}>
        {createOpen && <DeliveryNoteComposer
          items={items} warehouses={warehousesQuery.data ?? []} jobs={jobs}
          allocations={allocationsQuery.data ?? []}
          initialKind={linkedJobId ? 'production' : linkedSaleId ? 'sale' : 'materials'}
          initialJobId={linkedJobId} initialSaleId={linkedSaleId}
          sales={salesQuery.data ?? []} notes={notesQuery.data ?? []}
          onCancel={closeCreate} onBusyChange={setIssuing}
          onIssued={async () => { await refresh(); closeCreate(true); }} />}
      </ActionDialog>
      <ActionDialog open={!!voidTarget} busy={busy}
        title={`¿Seguro que querés anular el remito Nº ${voidTarget?.number ?? ''}?`}
        description={voidTarget?.kind === 'sale'
          ? 'El remito se anula, pero la venta y su descuento de stock siguen vigentes.'
          : 'La anulación reingresa los ítems al depósito original y queda registrada en el historial.'}
        onClose={() => setVoidTarget(null)}>
        <form className="delivery-void-form" onSubmit={confirmVoid}>
          <p>{voidTarget?.kind === 'sale'
            ? 'Para modificar la venta, usá su gestión de devoluciones. Este botón solo anula el remito.'
            : 'Si está vinculado a fabricación, la orden debe seguir en proceso y los ítems no pueden haber sido devueltos.'}</p>
          <label>Motivo de anulación
            <textarea required minLength={5} maxLength={300} value={reason}
              onChange={(event) => setReason(event.target.value)} />
          </label>
          <div className="erp-action-dialog-actions">
            <button type="button" className="button outline" disabled={busy}
              onClick={() => setVoidTarget(null)}>Volver</button>
            <button className="button erp-confirm-danger" disabled={busy || reason.trim().length < 5}>
              {busy ? 'Anulando…'
                : voidTarget?.kind === 'sale' ? 'Anular documento' : 'Anular y devolver stock'}
            </button>
          </div>
        </form>
      </ActionDialog>
    </section>
  );
}

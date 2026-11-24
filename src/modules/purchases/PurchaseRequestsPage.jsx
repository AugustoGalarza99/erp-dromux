import { useEffect, useMemo, useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { ClipboardPlus, Info, Plus, ShoppingCart, X } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import ActionDialog from '../../components/ActionDialog';
import ConfirmDeleteDialog from '../../components/ConfirmDeleteDialog';
import ListPager, { usePagedList } from '../../components/ListPager';
import { SupplierPagination } from './SupplierCatalog';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import { dateEs } from '../../lib/display';
import { LINE_LIMITS } from '../../lib/limits';
import { friendlyError, notifyError, notifySuccess } from '../../lib/notifications';
import {
  cancelPurchaseRequest,
  createPurchaseRequest,
  listPurchaseRequests,
  rejectPurchaseRequest,
} from '../../services/purchaseRequests';
import PurchaseRequestLinesEditor from './PurchaseRequestLinesEditor';
import PurchasesShell from './PurchasesShell';
import './suppliers.css';
import './purchases.css';

const statusLabels = { pending: 'Pendiente', ordered: 'Ordenado', rejected: 'Rechazado', cancelled: 'Cancelado' };
const statusSegments = [['pending', 'Pendientes'], ['', 'Todos'], ['ordered', 'Ordenados'],
  ['rejected', 'Rechazados'], ['cancelled', 'Cancelados']];
const today = () => {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
};

/* Líneas de un pedido: plegadas y paginadas; marca las que no están en el catálogo. */
function RequestLines({ request }) {
  const sorted = useMemo(
    () => [...(request.lines ?? [])].sort((a, b) => a.line_no - b.line_no),
    [request.lines],
  );
  const pager = usePagedList(sorted, { pageSize: 10 });
  const handwritten = sorted.filter((line) => !line.item_id).length;
  return (
    <details className="po-order-details">
      <summary>
        Ver lo que se pidió ({sorted.length})
        {handwritten > 0 && ` · ${handwritten} escrito${handwritten === 1 ? '' : 's'} a mano`}
      </summary>
      <div className="mod-table-wrap">
        <table className="mod-table">
          <thead>
            <tr>
              <th scope="col">Material</th>
              <th scope="col" className="is-num">Cantidad</th>
              <th scope="col">Detalle</th>
            </tr>
          </thead>
          <tbody>
            {pager.visible.map((line) => (
              <tr key={line.line_no} className={line.item_id ? '' : 'is-attention'}>
                <td className="is-name" data-label="Material">
                  <strong>{line.item_name}</strong>
                  <small>{line.item_id ? line.item_code : 'No está en el catálogo'}</small>
                </td>
                <td className="is-num" data-label="Cantidad">{line.quantity} {line.unit_symbol}</td>
                <td data-label="Detalle">{line.note || '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ListPager pager={pager} noun="líneas" sizes={[10, 25, 50]} />
    </details>
  );
}

export default function PurchaseRequestsPage() {
  const { activeCompanyId, user, can } = useAuth();
  const client = useQueryClient();
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const manager = can('purchases', 'read');
  const canRequest = can('purchase_requests', 'insert') || can('purchases', 'insert');
  const canConvert = can('purchases', 'insert');
  const canReject = can('purchases', 'update');
  const [status, setStatus] = useState(manager ? 'pending' : '');
  const [search, setSearch] = useState('');
  const term = useDebouncedValue(search);
  const [page, setPage] = useState(0);
  const [createOpen, setCreateOpen] = useState(params.get('new') === '1' && canRequest);
  const [priority, setPriority] = useState('normal');
  const [neededBy, setNeededBy] = useState('');
  const [note, setNote] = useState('');
  const [lines, setLines] = useState([]);
  const [confirmCreate, setConfirmCreate] = useState(false);
  const [cancelTarget, setCancelTarget] = useState(null);
  const [rejectTarget, setRejectTarget] = useState(null);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const submission = useRef({ fingerprint: null, id: crypto.randomUUID() });

  useEffect(() => {
    setCreateOpen(false); setConfirmCreate(false); setCancelTarget(null); setRejectTarget(null);
    setLines([]); setNote(''); setNeededBy(''); setPriority('normal');
    setPage(0); setSearch('');
    submission.current = { fingerprint: null, id: crypto.randomUUID() };
  }, [activeCompanyId]);
  useEffect(() => {
    if (params.get('new')) setParams((current) => { const next = new URLSearchParams(current); next.delete('new'); return next; }, { replace: true });
  }, []);
  useEffect(() => setPage(0), [status, term]);

  const query = useQuery({
    queryKey: ['purchase-requests', user?.id, activeCompanyId, page, status, term, manager],
    queryFn: () => listPurchaseRequests(activeCompanyId, { page, status, search: term, userId: user?.id, mine: !manager }),
    enabled: Boolean(activeCompanyId),
  });
  const rows = query.data?.rows ?? [];
  const hasFilters = Boolean(search) || status !== (manager ? 'pending' : '');
  const refresh = () => client.invalidateQueries({ queryKey: ['purchase-requests'] });

  const review = (event) => {
    event.preventDefault();
    if (busy) return;
    if (!lines.length) { notifyError(new Error('Agregá al menos un material al pedido.')); return; }
    if (lines.some((line) => !(Number(line.quantity) > 0))) {
      notifyError(new Error('Revisá que todas las líneas tengan una cantidad mayor que cero.'));
      return;
    }
    setConfirmCreate(true);
  };

  const submit = async () => {
    if (busy) return;
    setBusy(true);
    try {
      const values = { note, neededBy, priority, lines };
      const fingerprint = JSON.stringify([note.trim(), neededBy, priority,
        lines.map((line) => [line.item_id, line.name, line.unit, line.quantity, line.note])]);
      if (submission.current.fingerprint !== fingerprint) {
        submission.current = { fingerprint, id: crypto.randomUUID() };
      }
      await createPurchaseRequest(activeCompanyId, values, submission.current.id);
      submission.current = { fingerprint: null, id: crypto.randomUUID() };
      await refresh();
      notifySuccess(
        'Pedido enviado a Compras',
        `${lines.length} línea${lines.length === 1 ? '' : 's'}${priority === 'urgent' ? ' · marcado como urgente' : ''}. Compras lo va a revisar.`,
      );
      setConfirmCreate(false);
      setCreateOpen(false);
      setLines([]); setNote(''); setNeededBy(''); setPriority('normal');
    } catch (error) {
      setConfirmCreate(false);
      notifyError(error);
    } finally {
      setBusy(false);
    }
  };

  async function cancel() {
    if (!cancelTarget || busy) return;
    setBusy(true);
    try {
      await cancelPurchaseRequest(activeCompanyId, cancelTarget.id);
      await refresh();
      notifySuccess(`Pedido Nº ${cancelTarget.number} cancelado`);
      setCancelTarget(null);
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  async function reject(event) {
    event.preventDefault();
    if (!rejectTarget || busy || reason.trim().length < 5) return;
    setBusy(true);
    try {
      await rejectPurchaseRequest(activeCompanyId, rejectTarget.id, reason);
      await refresh();
      notifySuccess(`Pedido Nº ${rejectTarget.number} rechazado`, 'El motivo quedó visible para quien lo pidió.');
      setRejectTarget(null);
      setReason('');
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <PurchasesShell
      title={manager ? 'Pedidos de compra internos' : 'Mis pedidos de compra'}
      description={manager
        ? 'Lo que pide el equipo. Revisalos, convertí los aprobados en una orden de compra o rechazalos con un motivo.'
        : 'Pedí lo que te falta para trabajar. Compras lo revisa y lo compra; acá ves en qué estado está.'}
      actions={canRequest && (
        <button type="button" className="button primary" onClick={() => setCreateOpen(true)}>
          <Plus size={17} aria-hidden="true" /> Nuevo pedido
        </button>
      )}
    >
    <div className="purchase-page">
      <p className="mod-hint">
        <Info size={17} aria-hidden="true" />
        Un pedido no compra nada ni suma stock: avisa a Compras qué hace falta. Si el material no está
        cargado, podés escribirlo a mano y Compras lo da de alta.
      </p>

      <div className="mod-segments" role="group" aria-label="Filtrar por estado">
        {statusSegments.map(([value, label]) => (
          <button key={value || 'all'} type="button" className="mod-segment"
            aria-pressed={status === value} onClick={() => setStatus(value)}>{label}</button>
        ))}
      </div>
      {manager && (
        <div className="mod-filters">
          <label className="mod-filter-grow">
            Buscar pedido
            <input type="search" value={search} maxLength={100}
              placeholder="Número de pedido o nombre de quien lo pidió"
              onChange={(event) => setSearch(event.target.value)} />
          </label>
          {hasFilters && (
            <button type="button" className="button outline"
              onClick={() => { setSearch(''); setStatus('pending'); }}>
              <X size={15} aria-hidden="true" /> Limpiar filtros
            </button>
          )}
        </div>
      )}

      {query.isPending && <p className="mod-muted">Cargando pedidos…</p>}
      {query.error && (
        <p role="alert" className="error">
          {/purchase_requests|PGRST205|42P01/.test(`${query.error.code} ${query.error.message}`)
            ? 'Los pedidos internos se habilitan cuando se aplica la actualización 038 de la base. Pedile al administrador que la aplique.'
            : friendlyError(query.error)}
        </p>
      )}
      {!query.isPending && !query.error && !rows.length && (
        <div className="replenishment-empty">
          <strong>
            {hasFilters ? 'No hay pedidos con esos filtros.'
              : manager ? 'No hay pedidos pendientes.' : 'Todavía no hiciste pedidos.'}
          </strong>
          <p className="mod-muted">
            {canRequest ? 'Cuando te falte un material, creá un pedido y Compras lo recibe.' : 'Los pedidos del equipo aparecerán acá.'}
          </p>
          {canRequest && !hasFilters && (
            <button type="button" className="button primary" onClick={() => setCreateOpen(true)}>
              <ClipboardPlus size={16} aria-hidden="true" /> Nuevo pedido
            </button>
          )}
        </div>
      )}

      <div className="po-list">
        {rows.map((request) => {
          const mine = request.requested_by === user?.id;
          const pending = request.status === 'pending';
          const lateNeeded = pending && request.needed_by && request.needed_by < today();
          return (
            <article className={`po-order pr-${request.status} ${request.priority === 'urgent' && pending ? 'is-urgent-request' : ''}`} key={request.id}>
              <header className="po-order-head">
                <div>
                  <strong>Pedido Nº {request.number} · {request.requester_label}</strong>
                  <small>
                    {dateEs(request.created_at)} · {request.lines?.length ?? 0} línea{(request.lines?.length ?? 0) === 1 ? '' : 's'}
                    {request.needed_by && ` · lo necesita para el ${dateEs(request.needed_by)}`}
                  </small>
                </div>
                <div className="pr-chips">
                  {request.priority === 'urgent' && pending && <span className="mod-chip is-urgent">Urgente</span>}
                  {lateNeeded && <span className="mod-chip is-urgent">Fecha vencida</span>}
                  <span className={`mod-chip pr-status-${request.status}`}>{statusLabels[request.status]}</span>
                </div>
              </header>
              {request.note && <p className="mod-muted">“{request.note}”</p>}
              {request.status === 'rejected' && (
                <p className="pr-resolution">Motivo del rechazo: {request.resolution_note}</p>
              )}
              {request.status === 'ordered' && (
                <p className="pr-resolution is-ok">
                  Convertido en orden de compra{request.order?.number ? ` Nº ${request.order.number}` : ''}.
                  {manager && <> <Link to="/purchases/orders">Ver órdenes</Link></>}
                </p>
              )}
              <RequestLines request={request} />
              {pending && (
                <div className="po-order-actions">
                  {manager && canConvert && (
                    <button type="button" className="button primary"
                      onClick={() => navigate(`/purchases/orders?request=${request.id}`)}>
                      <ShoppingCart size={16} aria-hidden="true" /> Crear orden de compra
                    </button>
                  )}
                  {manager && canReject && (
                    <button type="button" className="button outline" onClick={() => { setReason(''); setRejectTarget(request); }}>
                      Rechazar
                    </button>
                  )}
                  {mine && can('purchase_requests', 'update') && (
                    <button type="button" className="button outline po-cancel" onClick={() => setCancelTarget(request)}>
                      Cancelar pedido
                    </button>
                  )}
                </div>
              )}
            </article>
          );
        })}
      </div>
      <SupplierPagination page={page} count={query.data?.count ?? 0} onChange={setPage} />

      {createOpen && canRequest && (
        <ActionDialog open title="Nuevo pedido de compra" busy={busy}
          description="Indicá qué necesitás y, si querés, para cuándo. Compras lo revisa y lo compra."
          onClose={() => setCreateOpen(false)}>
          <form className="po-compose" onSubmit={review}>
            <section className="po-step">
              <h3>1. Datos del pedido</h3>
              <div className="pr-meta">
                <label>
                  Prioridad
                  <select value={priority} onChange={(event) => setPriority(event.target.value)}>
                    <option value="normal">Normal</option>
                    <option value="urgent">Urgente (frena el trabajo)</option>
                  </select>
                </label>
                <label>
                  Lo necesito para el (opcional)
                  <input type="date" min={today()} value={neededBy} onChange={(event) => setNeededBy(event.target.value)} />
                </label>
              </div>
              <label>
                ¿Para qué lo necesitás? (opcional)
                <textarea rows={2} maxLength={500} value={note} placeholder="Ej.: para la orden de fabricación de esta semana"
                  onChange={(event) => setNote(event.target.value)} />
              </label>
            </section>
            <section className="po-step">
              <h3>2. Qué necesitás</h3>
              <PurchaseRequestLinesEditor
                companyId={activeCompanyId} userId={user?.id} lines={lines}
                limit={LINE_LIMITS.purchaseOrder} disabled={busy} onChange={setLines}
              />
            </section>
            <div className="po-savebar">
              <div className="po-total">
                <span>Líneas del pedido</span>
                <strong>{lines.length}</strong>
              </div>
              <button type="button" className="button outline" disabled={busy} onClick={() => setCreateOpen(false)}>
                Cerrar y conservar borrador
              </button>
              <button className="button primary" disabled={busy || !lines.length}>Revisar y enviar</button>
            </div>
          </form>
        </ActionDialog>
      )}

      <ConfirmDeleteDialog
        open={confirmCreate} intent="primary" busy={busy}
        title="¿Enviar el pedido a Compras?"
        description={`${lines.length} línea${lines.length === 1 ? '' : 's'}${priority === 'urgent' ? ', marcado como urgente' : ''}${neededBy ? `, para el ${dateEs(neededBy)}` : ''}. No se compra nada hasta que Compras lo apruebe.`}
        confirmLabel="Enviar pedido"
        onCancel={() => setConfirmCreate(false)} onConfirm={submit}
      />
      <ConfirmDeleteDialog
        open={Boolean(cancelTarget)} busy={busy}
        title="¿Cancelar este pedido?"
        description={`El pedido Nº ${cancelTarget?.number ?? ''} quedará cancelado y Compras ya no lo verá como pendiente.`}
        confirmLabel="Cancelar pedido"
        onCancel={() => setCancelTarget(null)} onConfirm={cancel}
      />
      <ActionDialog open={Boolean(rejectTarget)} busy={busy} title={`Rechazar el pedido Nº ${rejectTarget?.number ?? ''}`}
        description="El motivo lo va a ver quien hizo el pedido."
        onClose={() => setRejectTarget(null)}>
        <form onSubmit={reject} className="pr-reject">
          <label>
            Motivo del rechazo *
            <textarea required minLength={5} maxLength={500} rows={3} value={reason}
              placeholder="Ej.: ya hay stock suficiente, o se compra el mes próximo"
              onChange={(event) => setReason(event.target.value)} />
          </label>
          <div className="erp-action-dialog-actions">
            <button type="button" className="button outline" disabled={busy} onClick={() => setRejectTarget(null)}>Volver</button>
            <button className="button erp-confirm-danger" disabled={busy || reason.trim().length < 5}>
              {busy ? 'Rechazando…' : 'Rechazar pedido'}
            </button>
          </div>
        </form>
      </ActionDialog>
    </div>
    </PurchasesShell>
  );
}

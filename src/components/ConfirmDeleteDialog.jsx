import { useEffect, useRef } from 'react';
import { AlertTriangle } from 'lucide-react';

export default function ConfirmDeleteDialog({
  open,
  description,
  title = '¿Seguro que quieres eliminar?',
  busy = false,
  confirmLabel = 'Eliminar',
  onCancel,
  onConfirm,
}) {
  const dialogRef = useRef(null);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  }, [open]);

  return (
    <dialog
      ref={dialogRef}
      className="erp-confirm-dialog"
      aria-labelledby="confirm-delete-title"
      aria-describedby="confirm-delete-description"
      onCancel={(event) => {
        event.preventDefault();
        if (!busy) onCancel();
      }}
    >
      <span className="erp-confirm-icon"><AlertTriangle size={24} /></span>
      <h2 id="confirm-delete-title">{title}</h2>
      <p id="confirm-delete-description">{description}</p>
      <div className="erp-confirm-actions">
        <button type="button" className="button outline" disabled={busy} onClick={onCancel}>
          Cancelar
        </button>
        <button type="button" className="button erp-confirm-danger" disabled={busy} onClick={onConfirm}>
          {busy ? 'Procesando…' : confirmLabel}
        </button>
      </div>
    </dialog>
  );
}

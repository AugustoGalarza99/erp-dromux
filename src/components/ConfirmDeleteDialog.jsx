import { useEffect, useId, useRef } from "react";
import { AlertTriangle } from "lucide-react";

export default function ConfirmDeleteDialog({
  open,
  description,
  title = "¿Seguro que quieres eliminar?",
  busy = false,
  confirmLabel = "Eliminar",
  intent = "danger",
  onCancel,
  onConfirm,
}) {
  const dialogRef = useRef(null);
  const titleId = useId();
  const descriptionId = useId();

  useEffect(() => {
    const dialog = dialogRef.current;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  }, [open]);

  return (
    <dialog
      ref={dialogRef}
      className="erp-confirm-dialog"
      aria-labelledby={titleId}
      aria-describedby={descriptionId}
      onCancel={(event) => {
        event.preventDefault();
        if (!busy) onCancel();
      }}
    >
      <span className="erp-confirm-icon">
        <AlertTriangle size={24} />
      </span>
      <h2 id={titleId}>{title}</h2>
      <p id={descriptionId}>{description}</p>
      <div className="erp-confirm-actions">
        <button
          type="button"
          className="button outline"
          disabled={busy}
          onClick={onCancel}
        >
          Cancelar
        </button>
        <button
          type="button"
          className={`button ${intent === "primary" ? "primary" : "erp-confirm-danger"}`}
          disabled={busy}
          onClick={onConfirm}
        >
          {busy ? "Procesando…" : confirmLabel}
        </button>
      </div>
    </dialog>
  );
}

import { useEffect, useRef } from 'react';
import { X } from 'lucide-react';
import './actionDialog.css';

export default function ActionDialog({ open, title, description, onClose, children, busy = false }) {
  const ref = useRef(null);

  useEffect(() => {
    const dialog = ref.current;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  }, [open]);

  return (
    <dialog
      ref={ref}
      className="erp-action-dialog"
      aria-label={title}
      onCancel={(event) => {
        event.preventDefault();
        if (!busy) onClose();
      }}
    >
      <header className="erp-action-dialog-head">
        <div>
          <h2>{title}</h2>
          {description && <p>{description}</p>}
        </div>
        <button type="button" className="erp-action-close" disabled={busy}
          onClick={onClose} aria-label="Cerrar ventana">
          <X size={20} />
        </button>
      </header>
      <div className="erp-action-dialog-content">{children}</div>
    </dialog>
  );
}

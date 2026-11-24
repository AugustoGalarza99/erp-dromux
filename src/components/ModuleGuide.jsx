import { useState } from "react";
import { CircleHelp, ChevronDown } from "lucide-react";

const storageKey = (scope, id) => `dromux.guide.${scope}.${id}`;

function readClosed(key) {
  try {
    return window.localStorage.getItem(key) === "closed";
  } catch {
    return false;
  }
}

/*
 * Guía colapsable "Cómo usar este módulo". 3 a 5 pasos; recuerda por usuario
 * y módulo si se cerró (solo una preferencia de pantalla, sin datos de negocio).
 * Props: id (módulo), scope (id de usuario), title, steps[], hint, footer.
 */
export default function ModuleGuide({ id, scope = "anon", title, steps, hint, footer }) {
  const key = storageKey(scope, id);
  const [open, setOpen] = useState(() => !readClosed(key));
  const list = (steps ?? []).slice(0, 5);
  if (list.length < 3) return null;

  function toggle() {
    const next = !open;
    setOpen(next);
    try {
      if (next) window.localStorage.removeItem(key);
      else window.localStorage.setItem(key, "closed");
    } catch {
      /* sin almacenamiento: la guía igual funciona, solo no recuerda */
    }
  }

  const panelId = `guide-${id}`;
  return (
    <section className="module-guide" aria-label={`Cómo usar ${title}`}>
      <button
        type="button"
        className="module-guide-toggle"
        aria-expanded={open}
        aria-controls={panelId}
        onClick={toggle}
      >
        <CircleHelp size={17} aria-hidden="true" />
        <span>Cómo usar {title}</span>
        <ChevronDown size={16} aria-hidden="true" className={open ? "rotated" : ""} />
        <span className="module-guide-state">{open ? "Ocultar" : "Mostrar"}</span>
      </button>
      {open && (
        <div id={panelId} className="module-guide-body">
          <ol>
            {list.map((step) => (
              <li key={step}>{step}</li>
            ))}
          </ol>
          {hint && <p className="module-guide-hint">{hint}</p>}
          {footer}
        </div>
      )}
    </section>
  );
}

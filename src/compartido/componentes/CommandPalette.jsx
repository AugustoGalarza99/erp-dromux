import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { CornerDownLeft, Lock, Search } from "lucide-react";
import { useAuth } from "../contextos/AuthContext";
import { searchEntries } from "./navConfig";

const normalize = (text) =>
  (text ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "");

const isTyping = (target) =>
  target instanceof HTMLElement &&
  (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName));

/*
 * Búsqueda global. Atajos: Ctrl/⌘+K abre; "g" y una letra navega al módulo
 * (g i Inicio, g s Stock, g p Producción, g v Ventas, g c Compras,
 * g f Finanzas, g r Reportes, g a Ajustes). No actúa mientras se escribe.
 */
export default function CommandPalette({ open, onOpenChange }) {
  const { can, role } = useAuth();
  const navigate = useNavigate();
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const inputRef = useRef(null);
  const returnFocus = useRef(null);
  const listRef = useRef(null);

  const entries = useMemo(() => searchEntries({ can, role }), [can, role]);

  const results = useMemo(() => {
    const words = normalize(query).split(/\s+/).filter(Boolean);
    if (!words.length) return entries.slice(0, 40);
    return entries
      .filter((entry) => {
        const haystack = normalize(`${entry.label} ${entry.area} ${entry.keywords}`);
        return words.every((word) => haystack.includes(word));
      })
      .slice(0, 40);
  }, [entries, query]);

  // Atajos globales.
  useEffect(() => {
    let pending = 0;
    function onKeyDown(event) {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        onOpenChange(true);
        return;
      }
      if (open || event.ctrlKey || event.metaKey || event.altKey) return;
      if (isTyping(event.target)) return;
      const key = event.key.toLowerCase();
      if (pending && Date.now() - pending < 1200) {
        pending = 0;
        const target = entries.find((entry) => entry.shortcut === key);
        if (target) {
          event.preventDefault();
          navigate(target.to);
        }
        return;
      }
      if (key === "g") pending = Date.now();
      else if (key === "/") {
        event.preventDefault();
        onOpenChange(true);
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [entries, navigate, onOpenChange, open]);

  useEffect(() => {
    if (open) {
      returnFocus.current = document.activeElement;
      setQuery("");
      setActive(0);
      requestAnimationFrame(() => inputRef.current?.focus());
    } else if (returnFocus.current instanceof HTMLElement) {
      returnFocus.current.focus();
      returnFocus.current = null;
    }
  }, [open]);

  useEffect(() => setActive(0), [query]);

  useEffect(() => {
    listRef.current
      ?.querySelector('[aria-selected="true"]')
      ?.scrollIntoView({ block: "nearest" });
  }, [active, results]);

  function choose(entry) {
    if (!entry) return;
    onOpenChange(false);
    navigate(entry.to);
  }

  function onKeyDown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      onOpenChange(false);
    } else if (event.key === "ArrowDown") {
      event.preventDefault();
      setActive((index) => Math.min(index + 1, results.length - 1));
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      setActive((index) => Math.max(index - 1, 0));
    } else if (event.key === "Enter") {
      event.preventDefault();
      choose(results[active]);
    } else if (event.key === "Tab") {
      event.preventDefault(); // el foco permanece en el buscador
    }
  }

  if (!open) return null;

  return (
    <div
      className="cmdk-backdrop"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onOpenChange(false);
      }}
    >
      <div
        className="cmdk"
        role="dialog"
        aria-modal="true"
        aria-label="Buscar en el sistema"
        onKeyDown={onKeyDown}
      >
        <label className="cmdk-field">
          <Search size={18} aria-hidden="true" />
          <span className="sr-only">Buscar pantallas y acciones</span>
          <input
            ref={inputRef}
            type="search"
            role="combobox"
            aria-expanded="true"
            aria-controls="cmdk-list"
            aria-activedescendant={results[active] ? `cmdk-${active}` : undefined}
            autoComplete="off"
            placeholder="Buscar pantalla… (ej.: remitos, fórmulas, clientes)"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
          />
        </label>
        <ul id="cmdk-list" className="cmdk-list" role="listbox" ref={listRef}>
          {results.map((entry, index) => {
            const Icon = entry.icon;
            return (
              <li
                key={`${entry.to}-${entry.label}`}
                id={`cmdk-${index}`}
                role="option"
                aria-selected={index === active}
                className={`cmdk-item mod-${entry.module} ${entry.locked ? "is-locked" : ""}`}
                onMouseMove={() => setActive(index)}
                onClick={() => choose(entry)}
              >
                <span className="cmdk-dot" aria-hidden="true">
                  {Icon ? <Icon size={16} /> : null}
                </span>
                <span className="cmdk-text">
                  <strong>{entry.label}</strong>
                  <small>{entry.locked ? `${entry.area} · Acceso restringido` : entry.area}</small>
                </span>
                {entry.locked && <Lock size={14} aria-label="Acceso restringido" />}
                {entry.shortcut && (
                  <kbd aria-label={`Atajo: g y ${entry.shortcut}`}>g {entry.shortcut}</kbd>
                )}
                {index === active && <CornerDownLeft size={14} aria-hidden="true" />}
              </li>
            );
          })}
          {!results.length && (
            <li className="cmdk-empty" role="presentation">
              No encontramos pantallas con “{query}”. Probá con otra palabra.
            </li>
          )}
        </ul>
        <p className="cmdk-foot">
          <kbd>↑</kbd> <kbd>↓</kbd> moverse · <kbd>Enter</kbd> abrir ·{" "}
          <kbd>Esc</kbd> cerrar · fuera de un campo: <kbd>g</kbd> + letra salta a un módulo
        </p>
      </div>
    </div>
  );
}

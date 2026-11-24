import { useEffect, useMemo, useState } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";

/*
 * Paginación en cliente para listas que pueden tener cientos de filas (D-007).
 * `resetKey` vuelve a la primera página cuando cambian filtros o búsqueda.
 */
export function usePagedList(rows, { pageSize = 25, resetKey = "" } = {}) {
  const [page, setPage] = useState(0);
  const [size, setSize] = useState(pageSize);
  const pages = Math.max(1, Math.ceil(rows.length / size));

  useEffect(() => setPage(0), [resetKey, size]);
  useEffect(() => {
    if (page >= pages) setPage(pages - 1);
  }, [page, pages]);

  const visible = useMemo(
    () => rows.slice(page * size, page * size + size),
    [rows, page, size],
  );

  return { visible, page, pages, size, setPage, setSize, total: rows.length };
}

export default function ListPager({ pager, noun = "filas", sizes = [25, 50, 100] }) {
  const { page, pages, size, setPage, setSize, total } = pager;
  if (total <= Math.min(...sizes)) {
    return total ? <p className="mod-pager-count">{total} {noun}</p> : null;
  }
  const from = page * size + 1;
  const to = Math.min(total, page * size + size);

  return (
    <nav className="mod-pager" aria-label={`Paginación de ${noun}`}>
      <span className="mod-pager-count">
        {from}–{to} de {total} {noun}
      </span>
      <label className="mod-pager-size">
        Por página
        <select value={size} onChange={(event) => setSize(Number(event.target.value))}>
          {sizes.map((value) => (
            <option key={value} value={value}>{value}</option>
          ))}
        </select>
      </label>
      <div className="mod-pager-buttons">
        <button type="button" aria-label="Página anterior" disabled={page === 0}
          onClick={() => setPage(page - 1)}>
          <ChevronLeft size={18} />
        </button>
        <span aria-live="polite">Página {page + 1} de {pages}</span>
        <button type="button" aria-label="Página siguiente" disabled={page + 1 >= pages}
          onClick={() => setPage(page + 1)}>
          <ChevronRight size={18} />
        </button>
      </div>
    </nav>
  );
}

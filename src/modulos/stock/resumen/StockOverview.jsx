import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import {
  AlertTriangle,
  ArrowDownToLine,
  ArrowRightLeft,
  ArrowUpFromLine,
  ArrowUpRight,
  Boxes,
  FileUp,
  Plus,
  Truck,
  Warehouse,
} from "lucide-react";
import { useAuth } from "../../../compartido/contextos/AuthContext";
import { supabase } from "../../../compartido/utilidades/supabase";
import { friendlyError } from "../../../compartido/utilidades/notifications";
import { listItems } from "../items/items";
import { listDeliveryNotes } from "../remitos/deliveryNotes";
import { listStockMovements } from "../compartido/stock";
import { formatQuantity } from "../compartido/stockNumber";
import StockShell from "../compartido/StockShell";

const movementKinds = {
  ingreso: ["Entrada", ArrowDownToLine],
  egreso: ["Salida", ArrowUpFromLine],
  transferencia_salida: ["Transferencia (sale)", ArrowRightLeft],
  transferencia_entrada: ["Transferencia (entra)", ArrowRightLeft],
};

const todayIso = () => {
  const now = new Date();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const dayOfMonth = String(now.getDate()).padStart(2, "0");
  return `${now.getFullYear()}-${month}-${dayOfMonth}`;
};

/* Cuenta ítems activos de un tipo (solo se usa el total, no las filas). */
function useItemCount(type) {
  const { activeCompanyId, user, can } = useAuth();
  return useQuery({
    queryKey: ["stock-overview-items", user?.id, activeCompanyId, type],
    queryFn: () => listItems(activeCompanyId, { page: 0, search: "", type, status: "active" }),
    enabled: Boolean(activeCompanyId) && can("items", "ver"),
    staleTime: 60_000,
  });
}

/* Resumen del módulo: qué hay, qué falta y qué pasó hoy, con salto a cada pantalla. */
export default function StockOverview() {
  const { activeCompanyId, user, can } = useAuth();
  const scope = [user?.id, activeCompanyId];
  const canItems = can("items", "ver");
  const canStock = (can("stock_saldos", "ver") || can("inventario", "ver"));
  const enabled = Boolean(activeCompanyId);

  const allItems = useItemCount("");
  const rawItems = useItemCount("materia_prima");
  const products = useItemCount("producto_terminado");

  const dashboard = useQuery({
    queryKey: ["erp-dashboard", ...scope],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("erp_operational_dashboard", {
        p_company: activeCompanyId,
      });
      if (error) throw error;
      return data;
    },
    enabled: enabled && canStock && canItems,
    staleTime: 60_000,
  });
  const today = todayIso();
  const movementsToday = useQuery({
    queryKey: ["stock-movements", ...scope, "overview-today", today],
    queryFn: () => listStockMovements(activeCompanyId, {
      page: 0, itemId: "", warehouseId: "", kind: "", from: today, to: today,
    }),
    enabled: enabled && canStock,
    staleTime: 30_000,
  });
  const notes = useQuery({
    queryKey: ["delivery-notes", ...scope],
    queryFn: () => listDeliveryNotes(activeCompanyId),
    enabled: enabled && canStock,
    staleTime: 30_000,
  });

  const total = allItems.data?.count;
  const raw = rawItems.data?.count;
  const finished = products.data?.count;
  const others = total != null && raw != null && finished != null
    ? Math.max(0, total - raw - finished) : null;
  const lowStock = dashboard.data?.low_stock;
  const monthPrefix = today.slice(0, 7);
  const recentNotes = (notes.data ?? []).slice(0, 5);
  const notesThisMonth = (notes.data ?? []).filter((note) => note.status !== "anulado"
    && String(note.created_at).startsWith(monthPrefix)).length;
  const error = allItems.error || movementsToday.error || notes.error || dashboard.error;
  const show = (value) => (value == null ? "…" : value);

  const cards = [
    canItems && { key: "items", label: "Ítems activos", value: show(total), icon: Boxes,
      note: others == null ? "" : `${show(raw)} materias primas · ${show(finished)} productos · ${others} otros`,
      to: "/inventory/items" },
    canStock && canItems && { key: "low", label: "Bajo el mínimo", icon: AlertTriangle,
      value: show(lowStock), warn: Number(lowStock) > 0,
      note: Number(lowStock) > 0 ? "Conviene reponer o ajustar el mínimo" : "Todo por encima del mínimo",
      to: "/inventory/stock" },
    canStock && { key: "moves", label: "Movimientos de hoy", icon: ArrowRightLeft,
      value: show(movementsToday.data?.count), note: "Entradas, salidas y transferencias",
      to: `/inventory/movements?from=${today}&to=${today}` },
    canStock && { key: "notes", label: "Remitos del mes", icon: Truck,
      value: notes.data ? notesThisMonth : "…", note: "Entregas no anuladas",
      to: "/inventory/delivery-notes" },
  ].filter(Boolean);

  const actions = [
    can("items", "crear") && { to: "/inventory/items/new", label: "Nuevo ítem", icon: Plus, primary: true },
    can("stock", "crear") && { to: "/inventory/stock", label: "Registrar entrada o salida", icon: ArrowDownToLine },
    can("stock", "crear") && can("items", "ver") && { to: "/inventory/delivery-notes", label: "Emitir remito", icon: Truck },
    can("items", "crear") && { to: "/inventory/items?import=1", label: "Importar desde planilla", icon: FileUp },
  ].filter(Boolean);

  return (
    <StockShell
      title="Resumen de stock"
      description="Lo que tenés, lo que falta y lo que se movió hoy. Desde acá llegás a cada pantalla del módulo."
    >
      {error && <p role="alert" className="error">{friendlyError(error)}</p>}

      <div className="stock-kpis">
        {cards.map(({ key, label, value, note, icon: Icon, to, warn }) => (
          <Link key={key} to={to} className={`stock-kpi ${warn ? "is-warn" : ""}`}>
            <span className="stock-kpi-top">
              <span className="stock-kpi-icon"><Icon size={18} aria-hidden="true" /></span>
              {label}
            </span>
            <strong>{value}</strong>
            {note && <small>{note}</small>}
          </Link>
        ))}
      </div>

      {actions.length > 0 && (
        <section className="stock-card stock-quick" aria-label="Acciones frecuentes">
          <h2>Acciones frecuentes</h2>
          <div>
            {actions.map(({ to, label, icon: Icon, primary }) => (
              <Link key={label} to={to} className={`button ${primary ? "primary" : "outline"}`}>
                <Icon size={16} aria-hidden="true" /> {label}
              </Link>
            ))}
          </div>
        </section>
      )}

      <div className="stock-overview-columns">
        {canStock && (
          <section className="stock-card" aria-labelledby="ov-moves">
            <div className="stock-card-head">
              <h2 id="ov-moves">Últimos movimientos de hoy</h2>
              <Link to="/inventory/movements">Ver todos <ArrowUpRight size={14} aria-hidden="true" /></Link>
            </div>
            {movementsToday.isPending && <p className="stock-muted">Cargando…</p>}
            {!movementsToday.isPending && !(movementsToday.data?.rows ?? []).length && (
              <p className="stock-muted">Todavía no hubo movimientos hoy.</p>
            )}
            {(movementsToday.data?.rows ?? []).slice(0, 6).map((row) => {
              const [label, Icon] = movementKinds[row.kind] ?? ["Movimiento", ArrowRightLeft];
              const positive = !String(row.delta).startsWith("-");
              return (
                <Link key={row.id} className="stock-line"
                  to={`/inventory/movements?item=${row.item_id}&code=${encodeURIComponent(row.item_code)}`}>
                  <span className={`movement-icon ${positive ? "positive" : "negative"}`}>
                    <Icon size={17} aria-hidden="true" />
                  </span>
                  <span className="stock-line-text">
                    <strong>{label} · {row.item_code}</strong>
                    <small>{row.warehouse_code} · {new Date(row.created_at).toLocaleTimeString("es-AR", { hour: "2-digit", minute: "2-digit", hourCycle: "h23" })}</small>
                  </span>
                  <strong className={positive ? "positive" : "negative"}>
                    {positive ? "+" : "−"}{formatQuantity(String(row.delta).replace("-", ""))} {row.unit_symbol}
                  </strong>
                </Link>
              );
            })}
          </section>
        )}

        {canStock && (
          <section className="stock-card" aria-labelledby="ov-notes">
            <div className="stock-card-head">
              <h2 id="ov-notes">Últimos remitos</h2>
              <Link to="/inventory/delivery-notes">Ver remitos <ArrowUpRight size={14} aria-hidden="true" /></Link>
            </div>
            {notes.isPending && <p className="stock-muted">Cargando…</p>}
            {!notes.isPending && !recentNotes.length && (
              <p className="stock-muted">Todavía no emitiste remitos.</p>
            )}
            {recentNotes.map((note) => (
              <Link key={note.id} className="stock-line" to="/inventory/delivery-notes">
                <span className="movement-icon"><Truck size={17} aria-hidden="true" /></span>
                <span className="stock-line-text">
                  <strong>Remito Nº {note.number} · {note.recipient}</strong>
                  <small>{new Date(note.created_at).toLocaleDateString("es-AR")} · {note.delivery_note_lines?.length ?? 0} ítems</small>
                </span>
                <span className={`delivery-status ${note.status}`}>
                  {note.status === "anulado" ? "Anulado" : "Entregado"}
                </span>
              </Link>
            ))}
          </section>
        )}
      </div>

      <section className="stock-card stock-guide" aria-label="Cómo se conecta Stock">
        <h2>Cómo se conecta todo</h2>
        <ol>
          <li>Creá los <strong>ítems</strong> (materias primas, productos) y sus unidades.</li>
          <li>Cargá existencias con una <strong>entrada</strong> en el depósito correspondiente.</li>
          <li>Cada entrada, salida o remito queda en <strong>Movimientos</strong>, con quién y cuándo.</li>
          <li>Los <strong>remitos</strong> descuentan el stock al confirmarse; si se anulan, vuelve al depósito.</li>
        </ol>
        <p><Warehouse size={14} aria-hidden="true" /> El stock real siempre sale de los movimientos: no se edita a mano.</p>
      </section>
    </StockShell>
  );
}

import { Eye, LogOut } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../contextos/AuthContext";

/*
 * Barra fija de "Ver como rol". Es solo interfaz: no cambia la sesión ni escribe nada.
 * El servidor sigue respondiendo con los permisos reales del administrador.
 */
export default function ViewAsBar() {
  const { viewingAs, stopViewAs } = useAuth();
  const navigate = useNavigate();

  if (!viewingAs) return null;

  return (
    <div className="view-as-bar" role="status" aria-live="polite">
      <span className="view-as-icon"><Eye size={17} aria-hidden="true" /></span>
      <div className="view-as-text">
        <strong>Estás viendo como: {viewingAs.name}</strong>
        <small>
          {viewingAs.loading
            ? "Cargando los permisos de este rol…"
            : "Es solo una vista del menú, las pantallas y los botones. El servidor sigue respondiendo con tus permisos reales de administrador."}
        </small>
      </div>
      <button
        type="button"
        className="button"
        onClick={() => {
          stopViewAs();
          navigate("/settings/roles");
        }}
      >
        <LogOut size={15} aria-hidden="true" /> Salir de esta vista
      </button>
    </div>
  );
}

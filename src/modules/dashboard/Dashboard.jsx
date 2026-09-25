import {
  ArrowUpRight,
  Boxes,
  Factory,
  PackageCheck,
  TrendingUp,
} from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';

const modules = [
  { icon: Boxes, title: 'Inventario', detail: 'Stock, depósitos y movimientos' },
  { icon: Factory, title: 'Producción', detail: 'Órdenes, fórmulas y consumo' },
  { icon: PackageCheck, title: 'Compras', detail: 'Proveedores y recepciones' },
  { icon: TrendingUp, title: 'Finanzas', detail: 'Costos y rentabilidad' },
];

export default function Dashboard() {
  const { activeCompany, role } = useAuth();

  return (
    <>
      <div className="page-head">
        <div>
          <span className="eyebrow">VISTA GENERAL / INICIO</span>
          <h1>Buen día, bienvenido a bordo.</h1>
          <p>Así se va a ver el centro operativo de {activeCompany?.name}.</p>
        </div>
        <span className="date-pill">ESPACIO DE TRABAJO · V1</span>
      </div>

      <div className="welcome-card">
        <div>
          <span className="eyebrow light">PRIMER HITO COMPLETADO</span>
          <h2>Todo comienza con una buena base.</h2>
          <p>
            Tu empresa, acceso y permisos están conectados. Los indicadores
            aparecerán cuando activemos inventario y producción.
          </p>
          <span className="welcome-chip">Rol activo · {role}</span>
        </div>
        <div className="welcome-art" aria-hidden="true">
          <span /><span /><span /><span />
        </div>
      </div>

      <div className="section-heading">
        <div>
          <span className="eyebrow">EN PREPARACIÓN</span>
          <h2>Una vista de toda tu operación</h2>
        </div>
        <ArrowUpRight size={20} />
      </div>

      <div className="metric-grid">
        {modules.map(({ icon: Icon, title, detail }) => (
          <article className="metric-card" key={title}>
            <span className="metric-icon"><Icon size={23} /></span>
            <h3>{title}</h3>
            <p>{detail}</p>
            <span className="coming">
              PRÓXIMAMENTE <ArrowUpRight size={14} />
            </span>
          </article>
        ))}
      </div>

      <div className="info-strip">
        <span className="status-dot" />
        <div>
          <strong>Entorno inicial listo</strong>
          <p>
            Los datos operativos se incorporarán módulo por módulo,
            con acceso controlado según tus permisos.
          </p>
        </div>
      </div>
    </>
  );
}

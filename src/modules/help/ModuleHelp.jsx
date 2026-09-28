import { Link, useLocation } from 'react-router-dom';
import { CircleHelp, ArrowUpRight } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { guideSections } from './guideContent';
import './help.css';

export default function ModuleHelp() {
  const { pathname } = useLocation();
  const { can } = useAuth();
  const section = guideSections.find((entry) =>
    entry.routes.some((route) => pathname.startsWith(route)));
  if (!section || !can(section.resource, 'read')) return null;

  return (
    <details className="module-help" key={section.title}>
      <summary><CircleHelp size={18} /> ¿Cómo funciona {section.title.toLowerCase()}?</summary>
      <p>{section.hint}</p>
      <Link to={`/ayuda#${section.title.toLowerCase()}`}>
        Ver los pasos <ArrowUpRight size={15} />
      </Link>
    </details>
  );
}

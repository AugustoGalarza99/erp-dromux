import { Link, useLocation } from 'react-router-dom';
import { ArrowUpRight } from 'lucide-react';
import { useAuth } from '../../compartido/contextos/AuthContext';
import ModuleGuide from '../../compartido/componentes/ModuleGuide';
import { guideSections } from './guideContent';
import './help.css';

export default function ModuleHelp() {
  const { pathname } = useLocation();
  const { can, user } = useAuth();
  const section = guideSections.find((entry) =>
    entry.routes.some((route) => pathname.startsWith(route)));
  if (!section || !can(section.resource, 'read')) return null;

  return (
    <ModuleGuide
      key={section.title}
      id={section.title.toLowerCase()}
      scope={user?.id ?? 'anon'}
      title={section.title.toLowerCase()}
      steps={section.steps}
      hint={section.hint}
      footer={(
        <Link className="module-guide-link" to={`/ayuda#${section.title.toLowerCase()}`}>
          Ver la guía completa <ArrowUpRight size={15} />
        </Link>
      )}
    />
  );
}

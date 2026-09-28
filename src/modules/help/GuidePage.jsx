import { useEffect, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { ArrowUpRight, Search } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { guideSections } from './guideContent';
import './help.css';

export default function GuidePage() {
  const { can } = useAuth();
  const [search, setSearch] = useState('');
  const { hash } = useLocation();
  const entries = guideSections.filter((entry) => can(entry.resource, 'read')
    && `${entry.title} ${entry.description} ${entry.steps.join(' ')}`
      .toLocaleLowerCase('es').includes(search.toLocaleLowerCase('es').trim()));

  useEffect(() => {
    if (hash) document.getElementById(decodeURIComponent(hash.slice(1)))
      ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  }, [hash, entries.length]);

  return (
    <section className="guide-page">
      <div className="page-head">
        <div>
          <span className="eyebrow">AYUDA / PRIMEROS PASOS</span>
          <h1>Guía para trabajar</h1>
          <p>Buscá una tarea o seguí los pasos de cada módulo.</p>
        </div>
      </div>
      <label className="guide-search">
        <Search size={18} />
        <span className="sr-only">Buscar una tarea</span>
        <input type="search" value={search} placeholder="Ej.: recibir mercadería, vender, fabricar…"
          onChange={(event) => setSearch(event.target.value)} />
      </label>
      {!entries.length && <p>No hay resultados. Probá otra palabra.</p>}
      <div className="guide-grid">
        {entries.map((entry) => (
          <article className="guide-card" id={entry.title.toLowerCase()} key={entry.title}>
            <h2>{entry.title}</h2>
            <p>{entry.description}</p>
            <ol>{entry.steps.map((step) => <li key={step}>{step}</li>)}</ol>
            <p className="guide-tip">{entry.hint}</p>
            <Link to={entry.path}>Ir a {entry.title.toLowerCase()} <ArrowUpRight size={16} /></Link>
          </article>
        ))}
      </div>
    </section>
  );
}

import { useQuery } from '@tanstack/react-query';
import { Sparkles } from 'lucide-react';
import './updates.css';

async function loadUpdates() {
  const response = await fetch(`/updates.json?check=${Date.now()}`, { cache: 'no-store' });
  if (!response.ok) throw new Error('No pudimos cargar las novedades.');
  return response.json();
}

export default function UpdatesPage() {
  const query = useQuery({ queryKey: ['product-updates'], queryFn: loadUpdates,
    staleTime: 120_000 });
  return <section className="updates-page">
    <header className="page-head">
      <div><span className="eyebrow">SISTEMA / NOVEDADES</span>
        <h1>Actualizaciones</h1>
        <p>Mejoras incorporadas al ERP para que tu equipo sepa qué cambió.</p>
      </div>
    </header>
    {query.isPending && <p>Cargando novedades…</p>}
    {query.isError && <p role="alert" className="error">{query.error.message}</p>}
    <div className="updates-list">
      {(query.data ?? []).map((release, index) => <article className="updates-card"
        key={release.version}>
        <div className="updates-icon"><Sparkles size={19} /></div>
        <div>
          <span className="eyebrow">VERSIÓN {release.version}
            {index === 0 ? ' · MÁS RECIENTE' : ''}</span>
          <h2>{release.title}</h2>
          <time dateTime={release.publishedAt}>{new Date(`${release.publishedAt}T12:00:00`)
            .toLocaleDateString('es-AR')}</time>
          <ul>{release.changes.map((change) => <li key={change}>{change}</li>)}</ul>
        </div>
      </article>)}
    </div>
  </section>;
}

import { useEffect, useState } from 'react';
import { RefreshCw, X } from 'lucide-react';
import { useLocation } from 'react-router-dom';
import './versionMonitor.css';

const storageKey = 'erp:dromux:version';

async function readVersion() {
  const response = await fetch(`/meta.json?check=${Date.now()}`, {
    cache: 'no-store',
  });
  if (!response.ok) throw new Error('No se pudo consultar la versión');
  const meta = await response.json();
  if (!meta.version || typeof meta.version !== 'string') {
    throw new Error('Versión inválida');
  }
  return meta;
}

export default function VersionMonitor() {
  const [available, setAvailable] = useState(null);
  const location = useLocation();

  useEffect(() => {
    let mounted = true;
    async function check() {
      try {
        const current = await readVersion();
        if (!mounted) return;
        const saved = localStorage.getItem(storageKey);
        if (!saved) {
          localStorage.setItem(storageKey, current.version);
        } else if (saved !== current.version) {
          setAvailable(current);
        }
      } catch {
        // Una desconexión temporal no interrumpe la operación.
      }
    }
    check();
    const interval = window.setInterval(check, 120_000);
    const onFocus = () => check();
    window.addEventListener('focus', onFocus);
    return () => {
      mounted = false;
      window.clearInterval(interval);
      window.removeEventListener('focus', onFocus);
    };
  }, []);

  useEffect(() => {
    if (available) return;
    readVersion().then((current) => {
      const saved = localStorage.getItem(storageKey);
      if (saved && saved !== current.version) setAvailable(current);
    }).catch(() => {});
  }, [location.pathname, available]);

  if (!available) return null;

  return <div className="erp-version-banner" role="status">
    <div>
      <strong>Hay una actualización disponible</strong>
      <span>Versión {available.version} · {available.title}. Guardá lo que estés editando antes de actualizar.</span>
    </div>
    <button type="button" className="button primary" onClick={() => {
      localStorage.setItem(storageKey, available.version);
      window.location.reload();
    }}><RefreshCw size={16} /> Actualizar ahora</button>
    <button type="button" className="erp-version-dismiss" aria-label="Recordar más tarde"
      onClick={() => setAvailable(null)}><X size={18} /></button>
  </div>;
}

import { useEffect, useRef, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Bell, Check, CircleAlert, RefreshCw } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import { markOperationalAlertRead } from '../../services/operational';
import { useOperationalAlerts } from './useOperationalAlerts';
import './operations.css';

export default function NotificationCenter() {
  const { user, activeCompanyId } = useAuth();
  const client = useQueryClient();
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState('');
  const root = useRef(null);
  const { alerts, unread, isPending, error, refetch } = useOperationalAlerts();

  useEffect(() => {
    setOpen(false);
  }, [activeCompanyId]);

  useEffect(() => {
    if (!open) return undefined;
    const onPointerDown = (event) => {
      if (!root.current?.contains(event.target)) setOpen(false);
    };
    const onKeyDown = (event) => {
      if (event.key === 'Escape') setOpen(false);
    };
    document.addEventListener('pointerdown', onPointerDown);
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('pointerdown', onPointerDown);
      document.removeEventListener('keydown', onKeyDown);
    };
  }, [open]);

  async function markRead(alert) {
    if (!alert.unread || saving) return;
    setSaving(alert.alert_key);
    try {
      await markOperationalAlertRead(activeCompanyId, user.id, alert);
      await client.invalidateQueries({
        queryKey: ['operational-alert-reads', user.id, activeCompanyId],
      });
      notifySuccess('Aviso marcado como leído');
    } catch (cause) {
      notifyError(cause);
    } finally {
      setSaving('');
    }
  }

  return (
    <div className="erp-notifications" ref={root}>
      <button
        type="button"
        className="erp-bell"
        aria-label={unread ? `Avisos: ${unread} sin leer` : 'Avisos operativos'}
        aria-expanded={open}
        aria-controls="erp-notification-panel"
        onClick={() => setOpen((current) => !current)}
      >
        <Bell size={19} />
        {unread > 0 && <span className="erp-bell-count">{unread > 99 ? '99+' : unread}</span>}
      </button>
      {open && (
        <section id="erp-notification-panel" className="erp-notification-panel" aria-label="Avisos operativos">
          <header>
            <div><strong>Avisos de producción</strong><small>{unread} pendientes de leer</small></div>
            <button type="button" onClick={() => refetch()} aria-label="Actualizar avisos">
              <RefreshCw size={17} />
            </button>
          </header>
          {isPending && <p className="erp-notification-empty">Cargando avisos…</p>}
          {error && <p className="erp-notification-error" role="alert">{friendlyError(error)}</p>}
          {!isPending && !error && !alerts.length && (
            <p className="erp-notification-empty">No hay faltantes ni órdenes próximas a vencer.</p>
          )}
          <div className="erp-notification-list">
            {alerts.map((alert) => (
              <article key={alert.alert_key} className={`erp-notification-item ${alert.unread ? 'unread' : ''}`}>
                <CircleAlert size={18} className={alert.severity === 'critical' ? 'critical' : 'warning'} />
                <div>
                  <strong>{alert.title}</strong>
                  <p>{alert.detail}</p>
                  <div className="erp-notification-actions">
                    <Link to={alert.destination} onClick={() => setOpen(false)}>Ver detalle</Link>
                    {alert.unread && (
                      <button type="button" disabled={Boolean(saving)} onClick={() => markRead(alert)}>
                        <Check size={15} /> Leído
                      </button>
                    )}
                  </div>
                </div>
              </article>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}

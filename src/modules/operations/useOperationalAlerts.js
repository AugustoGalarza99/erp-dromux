import { useQuery } from '@tanstack/react-query';
import { useAuth } from '../../contexts/AuthContext';
import { listOperationalAlerts, listReadAlerts } from '../../services/operational';

export function useOperationalAlerts() {
  const { activeCompanyId, user } = useAuth();
  const enabled = Boolean(activeCompanyId && user);
  const alertsQuery = useQuery({
    queryKey: ['operational-alerts', user?.id, activeCompanyId],
    queryFn: () => listOperationalAlerts(activeCompanyId),
    enabled,
    refetchInterval: 60_000,
    refetchOnWindowFocus: true,
  });
  const readsQuery = useQuery({
    queryKey: ['operational-alert-reads', user?.id, activeCompanyId],
    queryFn: () => listReadAlerts(activeCompanyId),
    enabled,
    refetchInterval: 60_000,
  });
  const read = new Map((readsQuery.data ?? [])
    .map((entry) => [entry.alert_key, entry.fingerprint]));
  const alerts = (alertsQuery.data ?? []).map((entry) => ({
    ...entry,
    unread: read.get(entry.alert_key) !== entry.fingerprint,
  })).sort((a, b) => Number(b.unread) - Number(a.unread)
    || Number(b.severity === 'critical') - Number(a.severity === 'critical')
    || String(a.occurred_on).localeCompare(String(b.occurred_on)));

  return {
    alerts,
    unread: alerts.filter((entry) => entry.unread).length,
    isPending: alertsQuery.isPending || readsQuery.isPending,
    error: alertsQuery.error || readsQuery.error,
    refetch: () => Promise.all([alertsQuery.refetch(), readsQuery.refetch()]),
  };
}

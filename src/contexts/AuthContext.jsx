import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '../lib/supabase';
import { queryClient } from '../lib/queryClient';
import { beginSupportSession, getMemberships, getPermissions } from '../services/core';

const AuthContext = createContext(null);

export const useAuth = () => useContext(AuthContext);

export function AuthProvider({ children }) {
  const [session, setSession] = useState(null);
  const [ready, setReady] = useState(false);
  const [activeId, setActiveId] = useState(null);
  const [supportSession, setSupportSession] = useState(null);
  const [clock, setClock] = useState(Date.now());
  // "Ver como rol": solo interfaz, en memoria. No cambia la sesión ni escribe nada; el servidor sigue respondiendo con los permisos reales.
  const [viewAs, setViewAs] = useState(null);
  const previousUserId = useRef(null);

  useEffect(() => {
    let mounted = true;

    supabase.auth.getSession()
      .then(({ data }) => {
        if (!mounted) return;

        setSession(data.session);
        previousUserId.current = data.session?.user?.id ?? null;
        setReady(true);
      })
      .catch(() => {
        if (mounted) setReady(true);
      });

    const { data: listener } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next);

      const nextUserId = next?.user?.id ?? null;
      if (previousUserId.current !== nextUserId) {
        previousUserId.current = nextUserId;
        setActiveId(null);
        setSupportSession(null);
        setViewAs(null);
        queryClient.clear();
      }
    });

    return () => {
      mounted = false;
      listener.subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    const interval = window.setInterval(() => setClock(Date.now()), 30_000);
    return () => window.clearInterval(interval);
  }, []);

  const user = session?.user ?? null;

  const membershipQuery = useQuery({
    queryKey: ['memberships', user?.id],
    queryFn: getMemberships,
    enabled: Boolean(user),
    staleTime: 15_000,
    refetchOnWindowFocus: true,
    refetchInterval: 60_000,
  });

  const allMemberships = membershipQuery.data ?? [];
  const suspendedCompanies = allMemberships.filter((item) => !item.company_active);
  const memberships = allMemberships.filter((item) => item.company_active);
  const storageKey = user ? `erp:active-company:${user.id}` : null;
  const preferredId = activeId ?? (storageKey ? localStorage.getItem(storageKey) : null);
  const membership = memberships.find((item) => item.company_id === preferredId)
    ?? memberships[0]
    ?? null;
  const roleId = membership?.role_id;
  const support = membership?.roles?.code === 'support';
  const supportActive = support && supportSession?.companyId === membership?.company_id
    && supportSession.expiresAt > clock;

  const permissionsQuery = useQuery({
    queryKey: ['permissions', user?.id, membership?.company_id, roleId],
    queryFn: () => getPermissions(roleId, support),
    enabled: Boolean(user && (roleId || supportActive)),
    staleTime: 15_000,
    refetchOnWindowFocus: true,
  });

  const realPermissions = permissionsQuery.data ?? [];
  const realRole = membership?.roles?.code ?? null;
  const companyId = membership?.company_id ?? null;

  // Solo un administrador real puede mirar como otro rol, y solo dentro de la empresa donde empezó.
  const viewAsActive = Boolean(viewAs && realRole === 'admin' && viewAs.companyId === companyId);
  const viewAsQuery = useQuery({
    queryKey: ['view-as-permissions', user?.id, companyId, viewAs?.id],
    queryFn: () => getPermissions(viewAs.id, false),
    enabled: viewAsActive,
    staleTime: 15_000,
  });
  const viewingAs = viewAsActive ? { id: viewAs.id, code: viewAs.code, name: viewAs.name, loading: viewAsQuery.isPending } : null;
  const permissions = viewAsActive ? (viewAsQuery.data ?? []) : realPermissions;

  const can = (resource, action = 'read') => permissions.some(
    (permission) => permission.resource === resource && permission.action === action,
  );

  const startViewAs = (target) => {
    if (realRole !== 'admin' || !target?.id || !companyId) return;
    setViewAs({ id: target.id, code: target.code, name: target.name, companyId });
    // Lo ya cargado con los permisos reales no debe quedar a la vista: se vuelve a pedir lo que la vista permita.
    queryClient.removeQueries({ predicate: (query) => query.queryKey[0] !== 'memberships' && query.queryKey[0] !== 'permissions' });
  };

  const stopViewAs = () => {
    setViewAs(null);
    queryClient.removeQueries({ predicate: (query) => query.queryKey[0] !== 'memberships' && query.queryKey[0] !== 'permissions' });
  };

  const setActiveCompanyId = (id) => {
    const target = memberships.find((item) => item.company_id === id);
    if (!target || target.roles?.code === 'support') return;

    setViewAs(null);
    setActiveId(id);
    localStorage.setItem(storageKey, id);
  };

  const openSupportCompany = async (id, reason) => {
    if (!memberships.some((item) => item.company_id === id
      && item.roles?.code === 'support')) {
      throw new Error('Empresa no disponible para soporte.');
    }
    const expires = await beginSupportSession(id, reason);
    setSupportSession({ companyId: id, expiresAt: Date.parse(expires) });
    setActiveId(id);
    localStorage.setItem(storageKey, id);
    await queryClient.invalidateQueries();
  };

  const signOut = async () => {
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
    queryClient.clear();
    setSupportSession(null);
    setViewAs(null);
    if (storageKey) localStorage.removeItem(storageKey);
  };

  const value = useMemo(() => ({
    user,
    ready,
    authLoading: !ready || Boolean(
      user && (membershipQuery.isPending || ((roleId || supportActive) && permissionsQuery.isPending)),
    ),
    error: membershipQuery.error || permissionsQuery.error,
    memberships,
    suspendedCompanies,
    activeCompany: membership?.companies ?? null,
    activeCompanyId: membership?.company_id ?? null,
    role: viewingAs ? viewingAs.code : realRole,
    realRole,
    viewingAs,
    startViewAs,
    stopViewAs,
    supportNeedsAccess: support && !supportActive,
    supportActive,
    permissions,
    can,
    setActiveCompanyId,
    openSupportCompany,
    signOut,
    refresh: () => queryClient.invalidateQueries({ queryKey: ['memberships', user?.id] }),
  }), [
    user,
    ready,
    membershipQuery.status,
    membershipQuery.error,
    memberships,
    suspendedCompanies,
    permissionsQuery.status,
    permissionsQuery.error,
    permissions,
    viewAs,
    viewAsQuery.status,
    membership,
    activeId,
    supportSession,
    clock,
  ]);

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
}

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '../utilidades/supabase';
import { queryClient } from '../utilidades/queryClient';
import {
  beginSupportSession,
  endSupportSession,
  getMemberships,
  getPermissions,
} from '../servicios/core';
import { moduloHabilitado } from '../valores';

const AuthContext = createContext(null);

export const useAuth = () => useContext(AuthContext);

// La sesión de soporte se recuerda al recargar (solo en esta pestaña). El servidor decide si sigue vigente.
const supportKey = (userId) => `erp:support:${userId}`;
const readSupportSession = (userId) => {
  try {
    return JSON.parse(sessionStorage.getItem(supportKey(userId))) ?? null;
  } catch {
    return null;
  }
};
// Quita lo ya cargado de una empresa cuando cambia lo que se puede ver.
const dropCompanyData = () =>
  queryClient.removeQueries({ predicate: (query) => query.queryKey[0] !== 'memberships' });

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
  // Sin preferencia, primero una empresa propia: entrar a otra como soporte es una decisión explícita.
  const membership = memberships.find((item) => item.company_id === preferredId)
    ?? memberships.find((item) => item.roles?.code !== 'soporte')
    ?? memberships[0]
    ?? null;
  const roleId = membership?.role_id;
  const support = membership?.roles?.code === 'soporte';
  const currentSupport = supportSession ?? (user ? readSupportSession(user.id) : null);
  const supportActive = support && currentSupport?.companyId === membership?.company_id
    && currentSupport.expiresAt > clock;

  const permissionsQuery = useQuery({
    queryKey: ['permissions', user?.id, membership?.company_id, roleId],
    queryFn: () => getPermissions(roleId, support),
    enabled: Boolean(user && (roleId || supportActive)),
    staleTime: 15_000,
    refetchOnWindowFocus: true,
  });

  const realPermissions = permissionsQuery.data ?? [];
  // Con la sesión de soporte abierta se trabaja como administrador (igual que en el servidor).
  const realRole = supportActive ? 'administrador' : (membership?.roles?.code ?? null);
  const companyId = membership?.company_id ?? null;

  const wasSupportActive = useRef(false);
  useEffect(() => {
    if (wasSupportActive.current && !supportActive) dropCompanyData();
    wasSupportActive.current = supportActive;
  }, [supportActive]);

  // Solo un administrador real puede mirar como otro rol, y solo dentro de la empresa donde empezó.
  const viewAsActive = Boolean(viewAs && realRole === 'administrador' && viewAs.companyId === companyId);
  const viewAsQuery = useQuery({
    queryKey: ['view-as-permissions', user?.id, companyId, viewAs?.id],
    queryFn: () => getPermissions(viewAs.id, false),
    enabled: viewAsActive,
    staleTime: 15_000,
  });
  const viewingAs = viewAsActive ? { id: viewAs.id, code: viewAs.code, name: viewAs.name, loading: viewAsQuery.isPending } : null;
  const permissions = viewAsActive ? (viewAsQuery.data ?? []) : realPermissions;

  // Un módulo no contratado por la empresa bloquea sus pantallas aunque el rol tenga el permiso.
  const planIncluye = (resource) => moduloHabilitado(resource, membership?.companies?.modules);

  const can = (resource, action = 'ver') => planIncluye(resource) && permissions.some(
    (permission) => permission.resource === resource && permission.action === action,
  );

  const startViewAs = (target) => {
    if (realRole !== 'administrador' || !target?.id || !companyId) return;
    setViewAs({ id: target.id, code: target.code, name: target.name, companyId });
    // Lo ya cargado con los permisos reales no debe quedar a la vista: se vuelve a pedir lo que la vista permita.
    queryClient.removeQueries({ predicate: (query) => query.queryKey[0] !== 'memberships' && query.queryKey[0] !== 'permissions' });
  };

  const stopViewAs = () => {
    setViewAs(null);
    queryClient.removeQueries({ predicate: (query) => query.queryKey[0] !== 'memberships' && query.queryKey[0] !== 'permissions' });
  };

  // Termina el acceso de soporte en el servidor. Si falla, vence solo a las 4 horas.
  const closeSupportSession = async () => {
    if (!user || !(supportSession ?? readSupportSession(user.id))) return;
    sessionStorage.removeItem(supportKey(user.id));
    setSupportSession(null);
    try {
      await endSupportSession();
    } catch (error) {
      console.warn('No se pudo cerrar la sesión de soporte', error?.message);
    }
  };

  const setActiveCompanyId = (id) => {
    const target = memberships.find((item) => item.company_id === id);
    if (!target || target.roles?.code === 'soporte') return;

    closeSupportSession();
    if (support) dropCompanyData();
    setViewAs(null);
    setActiveId(id);
    localStorage.setItem(storageKey, id);
  };

  const openSupportCompany = async (id, reason) => {
    if (!memberships.some((item) => item.company_id === id
      && item.roles?.code === 'soporte')) {
      throw new Error('Empresa no disponible para soporte.');
    }
    const expires = await beginSupportSession(id, reason);
    const opened = { companyId: id, expiresAt: Date.parse(expires) };
    sessionStorage.setItem(supportKey(user.id), JSON.stringify(opened));
    // Nada de la empresa anterior debe quedar a la vista.
    dropCompanyData();
    setSupportSession(opened);
    setViewAs(null);
    setActiveId(id);
    localStorage.setItem(storageKey, id);
    await queryClient.invalidateQueries();
  };

  const signOut = async () => {
    await closeSupportSession();
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
    queryClient.clear();
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
    isSupport: support,
    permissions,
    can,
    planIncluye,
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

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
import { getMemberships, getPermissions } from '../services/core';

const AuthContext = createContext(null);

export const useAuth = () => useContext(AuthContext);

export function AuthProvider({ children }) {
  const [session, setSession] = useState(null);
  const [ready, setReady] = useState(false);
  const [activeId, setActiveId] = useState(null);
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
        queryClient.clear();
      }
    });

    return () => {
      mounted = false;
      listener.subscription.unsubscribe();
    };
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

  const permissionsQuery = useQuery({
    queryKey: ['permissions', user?.id, membership?.company_id, roleId],
    queryFn: () => getPermissions(roleId),
    enabled: Boolean(user && roleId),
    staleTime: 15_000,
    refetchOnWindowFocus: true,
  });

  const permissions = permissionsQuery.data ?? [];

  const can = (resource, action = 'read') => permissions.some(
    (permission) => permission.resource === resource && permission.action === action,
  );

  const setActiveCompanyId = (id) => {
    if (!memberships.some((item) => item.company_id === id)) return;

    setActiveId(id);
    localStorage.setItem(storageKey, id);
  };

  const signOut = async () => {
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
    queryClient.clear();
    if (storageKey) localStorage.removeItem(storageKey);
  };

  const value = useMemo(() => ({
    user,
    ready,
    authLoading: !ready || Boolean(
      user && (membershipQuery.isPending || (roleId && permissionsQuery.isPending)),
    ),
    error: membershipQuery.error || permissionsQuery.error,
    memberships,
    suspendedCompanies,
    activeCompany: membership?.companies ?? null,
    activeCompanyId: membership?.company_id ?? null,
    role: membership?.roles?.code ?? null,
    permissions,
    can,
    setActiveCompanyId,
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
    membership,
    activeId,
  ]);

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
}

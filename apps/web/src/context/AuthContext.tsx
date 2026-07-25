import { createContext, useContext, useEffect, useState } from 'react';
import type { Session, User } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import { SessionKillSwitch } from '../components/auth/SessionKillSwitch';

interface AuthContextType {
  session: Session | null;
  user: User | null;
  userRole: 'super_admin' | 'fleet_manager' | 'supervisor' | 'driver' | null;
  fleetStatus: 'trialing' | 'active' | 'past_due' | 'canceled' | 'suspended' | null;
  currentAal: 'aal1' | 'aal2' | null;
  loading: boolean;
}

const AuthContext = createContext<AuthContextType>({
  session: null,
  user: null,
  userRole: null,
  fleetStatus: null,
  currentAal: null,
  loading: true,
});

export const AuthProvider = ({ children }: { children: React.ReactNode }) => {
  const [session, setSession] = useState<Session | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [userRole, setUserRole] = useState<AuthContextType['userRole']>(null);
  const [fleetStatus, setFleetStatus] = useState<AuthContextType['fleetStatus']>(null);
  const [currentAal, setCurrentAal] = useState<'aal1' | 'aal2' | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchProfileRole = async (userId: string) => {
    try {
      // Usar un inner join implícito en Supabase para obtener el status de la flota
      const { data, error } = await supabase
        .from('profiles')
        .select('role, fleet_id, fleets(status)')
        .eq('id', userId)
        .maybeSingle();
        
      if (error) {
        console.error('Error fetching role:', error);
        setUserRole('driver'); // Fallback seguro
        setFleetStatus('suspended');
      } else {
        setUserRole(data?.role || 'driver');
        // @ts-ignore: Supabase returns a joined object or array depending on relation type (one-to-one or many-to-one)
        const fStatus = data?.fleets?.status || data?.fleets?.[0]?.status || 'suspended';
        setFleetStatus(fStatus);
      }
    } catch (err) {
      console.error('Failed to fetch profile', err);
      setUserRole('driver');
      setFleetStatus('suspended');
    }
  };

  useEffect(() => {
    const fetchAal = async () => {
      const { data, error } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
      if (!error && data) {
        setCurrentAal(data.currentLevel as 'aal1' | 'aal2');
      } else {
        setCurrentAal(null);
      }
    };

    // Obtener sesión inicial
    supabase.auth.getSession().then(async ({ data: { session } }) => {
      setSession(session);
      setUser(session?.user ?? null);
      if (session?.user?.id) {
        await fetchAal();
        await fetchProfileRole(session.user.id);
        setLoading(false);
      } else {
        setLoading(false);
      }
    });

    // Suscribirse a cambios (login, logout, refresh, mfa)
    const { data: { subscription } } = supabase.auth.onAuthStateChange(async (event, session) => {
      if (event === 'TOKEN_REFRESHED' || event === 'MFA_CHALLENGE_VERIFIED') {
        setSession(session);
        setUser(session?.user ?? null);
        if (session?.user) await fetchAal();
        return;
      }

      setSession(session);
      setUser(session?.user ?? null);
      if (session?.user?.id) {
        if (event === 'SIGNED_IN') setLoading(true);
        await fetchAal();
        await fetchProfileRole(session.user.id);
        if (event === 'SIGNED_IN') setLoading(false);
      } else {
        setUserRole(null);
        setFleetStatus(null);
        setCurrentAal(null);
      }
    });

    return () => subscription.unsubscribe();
  }, []);

  const value = {
    session,
    user,
    userRole,
    fleetStatus,
    currentAal,
    loading,
  };

  return (
    <AuthContext.Provider value={value}>
      <SessionKillSwitch />
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  return useContext(AuthContext);
};

import React, { useEffect, useState, createContext, useContext } from 'react';
import { supabase } from '../lib/supabase';
import AsyncStorage from '@react-native-async-storage/async-storage';
import NetInfo from '@react-native-community/netinfo';
import { Session } from '@supabase/supabase-js';

const PENDING_FLEET_LINK_KEY = '@fuelflow_pending_fleet_link';

interface AuthContextType {
  session: Session | null;
  isReady: boolean;
  setPendingFleetLink: (token: string) => Promise<void>;
}

const AuthContext = createContext<AuthContextType>({
  session: null,
  isReady: false,
  setPendingFleetLink: async () => {},
});

export const useAuth = () => useContext(AuthContext);

export const AuthProvider = ({ children }: { children: React.ReactNode }) => {
  const [session, setSession] = useState<Session | null>(null);
  const [isReady, setIsReady] = useState(false);
  const [isReconciling, setIsReconciling] = useState(false);

  // 1. Initial Session Check
  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      setIsReady(true);
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
    });

    return () => subscription.unsubscribe();
  }, []);

  // 2. AuthSyncWorker (Two-Phase Onboarding Reconciliator)
  const reconcileFleetLink = async () => {
    if (isReconciling || !session) return;
    
    try {
      setIsReconciling(true);
      const pendingToken = await AsyncStorage.getItem(PENDING_FLEET_LINK_KEY);
      
      if (pendingToken) {
        console.log('[AuthSyncWorker] Found pending fleet link. Attempting reconciliation...');
        const { data, error } = await supabase.rpc('fn_consume_fleet_invite', {
          invite_token_val: pendingToken
        });

        if (error) {
          if (error.message.includes('expired') || error.message.includes('invalid')) {
            console.error('[AuthSyncWorker] Token is permanently invalid. Dropping from queue.');
            await AsyncStorage.removeItem(PENDING_FLEET_LINK_KEY);
          } else {
            console.warn('[AuthSyncWorker] Transient error consuming token (network/db). Will retry later.', error);
          }
        } else {
          console.log('[AuthSyncWorker] Fleet link reconciliation successful.');
          await AsyncStorage.removeItem(PENDING_FLEET_LINK_KEY);
        }
      }
    } catch (e) {
      console.warn('[AuthSyncWorker] Reconciliation failed:', e);
    } finally {
      setIsReconciling(false);
    }
  };

  // Run reconciliation when network comes online
  useEffect(() => {
    const unsubscribe = NetInfo.addEventListener(state => {
      if (state.isConnected && session) {
        reconcileFleetLink();
      }
    });

    // Also try on mount if we have a session
    if (session) {
      reconcileFleetLink();
    }

    return () => unsubscribe();
  }, [session]);

  const setPendingFleetLink = async (token: string) => {
    await AsyncStorage.setItem(PENDING_FLEET_LINK_KEY, token);
    // If we are already logged in, try to reconcile immediately
    if (session) {
      reconcileFleetLink();
    }
  };

  return (
    <AuthContext.Provider value={{ session, isReady, setPendingFleetLink }}>
      {children}
    </AuthContext.Provider>
  );
};

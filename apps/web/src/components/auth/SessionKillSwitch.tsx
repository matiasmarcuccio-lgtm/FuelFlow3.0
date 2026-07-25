import React, { useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../context/AuthContext';

export const SessionKillSwitch: React.FC = () => {
  const { user } = useAuth();

  useEffect(() => {
    if (!user?.id) return;

    // Suscripción de alta prioridad al canal Realtime sobre el propio perfil
    const revocationChannel = supabase
      .channel(`guillotine_guard_${user.id}`)
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'profiles',
          filter: `id=eq.${user.id}`,
        },
        async (payload) => {
          const newRole = payload.new.role;

          // Si el servidor detecta que el perfil fue degradado o revocado
          if (newRole === 'revoked' || !newRole) {
            console.warn('⚠️ ALERTA DE JURISDICCIÓN: Sesión amputada por orden del Command Center.');

            // 1. Destrucción local del almacenamiento de Supabase y cachés de React
            await supabase.auth.signOut({ scope: 'local' });
            localStorage.clear();
            sessionStorage.clear();

            // 2. Redirección forzosa e interrupción de hilos en Vite
            window.location.replace('/lockout?reason=JURISDICTION_REVOKED');
          }
        }
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          console.debug('🔒 Guillotina Realtime AAL2 conectada.');
        }
      });

    return () => {
      supabase.removeChannel(revocationChannel);
    };
  }, [user?.id]);

  return null; // Componente fantasma: sin renderizado visual, solo ejecución de intercepción
};

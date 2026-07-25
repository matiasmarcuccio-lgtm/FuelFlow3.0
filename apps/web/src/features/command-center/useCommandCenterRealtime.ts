import { useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';

export const useCommandCenterRealtime = (fleetId: string) => {
  const queryClient = useQueryClient();

  useEffect(() => {
    if (!fleetId) return;

    // 1. Suscripción a mutaciones de Activos (Taller secuestrando camiones)
    const assetsSub = supabase.channel(`assets_realtime_${Math.random()}`);
    assetsSub.on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'assets' },
        (payload) => {
          console.log('⚡ [Realtime] Asset mutado por la Capa 0:', payload);
          // Destruimos la caché de activos. React Query hará un refetch inmediato.
          queryClient.invalidateQueries({ queryKey: ['assets', fleetId] });
        }
      )
      .subscribe();

    // 2. Suscripción a mutaciones de Despachos (Operadores firmando Pre-Starts, finalizando turnos)
    const assignmentsSub = supabase.channel(`assignments_realtime_${Math.random()}`);
    assignmentsSub.on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'asset_assignments' },
        (payload) => {
          console.log('⚡ [Realtime] Turno mutado por la Capa 0:', payload);
          // Destruimos la caché de asignaciones activas
          queryClient.invalidateQueries({ queryKey: ['active_assignments', fleetId] });
        }
      )
      .subscribe();

    // Limpieza implacable del socket al desmontar
    return () => {
      supabase.removeChannel(assetsSub);
      supabase.removeChannel(assignmentsSub);
    };
  }, [fleetId, queryClient]);
};

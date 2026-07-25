import React from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';
import { ExecutiveRadarPresenter } from './ExecutiveRadarPresenter';
import type { FrictionMetrics } from './ExecutiveRadarPresenter';

export const ExecutiveRadarContainer: React.FC<{ fleetId: string }> = ({ fleetId }) => {
  const { data: metrics, isLoading, error } = useQuery({
    queryKey: ['executive_friction_metrics', fleetId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_fleet_friction_metrics', {
        p_fleet_id: fleetId
      });

      if (error) throw new Error(error.message);
      return data as unknown as FrictionMetrics;
    },
    // Bombardeo táctico: Se refresca cada 10 segundos
    // para reflejar en tiempo real cómo los dólares se queman si un camión está estancado.
    refetchInterval: 10000,
  });

  return (
    <ExecutiveRadarPresenter 
      metrics={metrics || null} 
      isLoading={isLoading} 
      error={error ? error.message : null} 
    />
  );
};

import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';
import { HydrationPayloadSchema } from '../../schemas/core';
import { set } from 'idb-keyval';

export const useCrewRosterSync = (projectId: string | null) => {
  const queryClient = useQueryClient();
  
  return useQuery({
    queryKey: ['crew_hashes', projectId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_project_crew_hashes', { p_project_id: projectId });
      if (error) throw error;
      
      // Aduana Zod: Validar integridad del payload
      const parsedData = HydrationPayloadSchema.parse(data);

      // Inyección Asíncrona a Memoria Local (Offline Geometry)
      // Si la geometría existe, Zod la dejó pasar; extraemos el primer anillo de coordenadas [lng, lat]
      if (parsedData.topology.loading_pad_strict) {
          await set('loading_pad_strict', parsedData.topology.loading_pad_strict.coordinates[0]);
      }
      
      if (parsedData.topology.loading_pad_buffered) {
          await set('loading_pad_buffered', parsedData.topology.loading_pad_buffered.coordinates[0]);
      }

      // Ancla temporal: Registra el momento exacto en que hubo señal y se sincronizó.
      // Si el reloj retrocede en offline, el Handover lo detectará.
      queryClient.setQueryData(['server_time_anchor', projectId], Date.now());
      
      return parsedData.crew;
    },
    enabled: !!projectId, 
    staleTime: 1000 * 60 * 60 * 24, // 24 horas, respaldado en idb-keyval
  });
};

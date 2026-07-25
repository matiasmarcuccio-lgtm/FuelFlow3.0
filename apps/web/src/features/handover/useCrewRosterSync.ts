import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';
import { HydrationPayloadSchema } from '../../schemas/core';
import { set } from 'idb-keyval';

export const useCrewRosterSync = (projectId: string | null) => {
  // const queryClient = useQueryClient();
  
  return useQuery({
    queryKey: ['crew_hashes', projectId],
    queryFn: async () => {
      // 1. Fetch Topology from projects table
      const { data: projectData, error: projectError } = await supabase
        .from('projects')
        .select('hrcw_polygon, loading_pad_strict, loading_pad_buffered')
        .eq('id', projectId || '')
        .single();
        
      if (projectError) throw projectError;

      // 2. Fetch Roster from project_members + profiles
      const { data: rosterData, error: rosterError } = await supabase
        .from('project_members')
        .select(`
          user_id,
          profiles ( full_name )
        `)
        .eq('project_id', projectId || '');

      if (rosterError) throw rosterError;

      const crew = rosterData.map((member: any) => ({
        user_id: member.user_id,
        full_name: member.profiles?.full_name || 'Desconocido'
      }));

      // Aduana Zod: Validar integridad del payload
      const payload = { topology: projectData, crew };
      const parsedData = HydrationPayloadSchema.parse(payload);

      // Inyección Asíncrona a Memoria Local (Offline Geometry)
      if (parsedData.topology.loading_pad_strict) {
          await set('loading_pad_strict', parsedData.topology.loading_pad_strict.coordinates[0]);
      }
      
      if (parsedData.topology.loading_pad_buffered) {
          await set('loading_pad_buffered', parsedData.topology.loading_pad_buffered.coordinates[0]);
      }
      
      return parsedData;
    },
    enabled: !!projectId, 
    staleTime: 1000 * 60 * 60 * 24, // 24 horas, respaldado en idb-keyval
  });
};

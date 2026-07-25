import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';

interface ResolveDefectPayload {
    defectId: string;
    category: 'hydraulic' | 'electrical' | 'engine' | 'wear_and_tear' | 'false_alarm';
    resolutionNotes: string;
    mechanicId: string;
    mechanicPin: string;
}

export const useResolvePlantDefect = () => {
  const queryClient = useQueryClient();

  return useMutation({
    // La mutación se ejecutará inmediatamente si hay red, 
    // o se pausará de forma invisible si el mecánico está en un punto ciego.
    networkMode: 'offlineFirst',
    mutationFn: async (payload: ResolveDefectPayload) => {
      const { data, error } = await supabase.rpc('resolve_plant_defect', {
        p_defect_id: payload.defectId,
        p_category: payload.category,
        p_resolution_notes: payload.resolutionNotes,
        p_mechanic_pin: payload.mechanicPin
      });

      if (error) throw new Error(error.message);
      return data;
    },
    onMutate: async (newDefect) => {
      // Optimizamos la vista local para asumir que el bloqueo se levantará.
      // Si ocurre un fallo cuando se reconecte (PIN incorrecto), React Query
      // revertirá el estado usando onError y onSettled.
      await queryClient.cancelQueries({ queryKey: ['active_defects'] });

      const previousDefects = queryClient.getQueryData(['active_defects']);

      // Removemos visualmente el defecto de la lista de triaje
      queryClient.setQueryData(['active_defects'], (old: any[]) => 
        old ? old.filter(d => d.id !== newDefect.defectId) : []
      );

      return { previousDefects };
    },
    onError: (err, newDefect, context) => {
      // Si el PIN fue incorrecto, revertimos la UI y emitimos un evento de posible sabotaje
      queryClient.setQueryData(['active_defects'], context?.previousDefects);
      
      // Lanzamos un log silencioso para auditoría si el error es de PIN (sabotaje interno)
      if (err.message.includes('PIN criptográfico incorrecto')) {
          supabase.from('webhook_events').insert([{
              event_type: 'security_violation',
              payload: { reason: 'Intentional unauthorized override', defectId: newDefect.defectId }
          }]);
      }
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ['active_defects'] });
    }
  });
};

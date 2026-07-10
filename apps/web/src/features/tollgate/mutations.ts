import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';

export const useReconcileLoadCycle = () => {
  const queryClient = useQueryClient();

  return useMutation({
    networkMode: 'onlineFirst',
    mutationFn: async ({ cycleId, grossWeight, tareWeight }: { cycleId: string; grossWeight: number; tareWeight: number }) => {
      const { data, error } = await supabase.rpc('reconcile_load_cycle', {
        p_cycle_id: cycleId,
        p_gross_weight: grossWeight,
        p_tare_weight: tareWeight
      });

      if (error) throw new Error(error.message);
      return data;
    },
    onSuccess: () => {
      // Invalidar el radar de aproximación para remover el camión procesado inmediatamente
      queryClient.invalidateQueries({ queryKey: ['in_transit_cycles'] });
    }
  });
};

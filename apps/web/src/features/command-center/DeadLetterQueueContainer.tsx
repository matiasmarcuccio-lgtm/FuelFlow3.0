import React from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';
import { DeadLetterQueuePresenter } from './DeadLetterQueuePresenter';
import type { DeadLetter } from './DeadLetterQueuePresenter';

export const DeadLetterQueueContainer: React.FC = () => {
  const queryClient = useQueryClient();

  const { data: deadLetters = [] } = useQuery({
    queryKey: ['dead_letters'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('erp_outbox')
        .select('*')
        .eq('status', 'dead_letter')
        .order('updated_at', { ascending: false });

      if (error) throw error;
      return data as DeadLetter[];
    },
    refetchInterval: 30000, // Barre la cola cada 30 segundos
  });

  const resurrectMutation = useMutation({
    mutationFn: async (outboxId: string) => {
      const { error } = await supabase.rpc('resurrect_dead_letter', {
        p_outbox_id: outboxId
      });

      if (error) {
        if (error.message.includes('WHS_UNAUTHORIZED')) {
          throw new Error('JURISDICCIÓN DENEGADA: Solo un Fleet Manager puede forzar la contabilidad.');
        }
        throw new Error(error.message);
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['dead_letters'] });
    },
    onError: (error: Error) => alert(`FRACTURA: ${error.message}`)
  });

  return (
    <DeadLetterQueuePresenter
      deadLetters={deadLetters}
      onResurrect={(id) => resurrectMutation.mutate(id)}
      isSubmitting={resurrectMutation.isPending}
    />
  );
};

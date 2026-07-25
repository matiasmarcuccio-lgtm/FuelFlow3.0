import React from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';
import { ExpenseQuarantinePresenter } from './ExpenseQuarantinePresenter';
import type { QuarantinedExpense } from './ExpenseQuarantinePresenter';

export const ExpenseQuarantineContainer: React.FC = () => {
  const queryClient = useQueryClient();

  // 1. Barrido de la Cuarentena
  const { data: expenses = [] } = useQuery({
    queryKey: ['quarantined_expenses'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('expense_quarantine')
        .select('*')
        .eq('status', 'pending_review')
        .order('created_at', { ascending: true });

      if (error) throw error;
      return data as QuarantinedExpense[];
    },
    refetchInterval: 15000, // Sondear cada 15s buscando nuevas inyecciones del Kiosco
  });

  // 2. Transacción de Auditoría
  const processMutation = useMutation({
    mutationFn: async ({ id, status, correctedAmount, notes }: { id: string, status: string, correctedAmount: number, notes: string }) => {
      // Invocamos el RPC que forjamos en la Capa 0.
      // El motor PostgreSQL se encargará de validar el rol AAL2 del supervisor y aplicar el impacto financiero.
      const { error } = await supabase.rpc('process_quarantined_expense', {
        p_expense_id: id,
        p_status: status,
        p_corrected_amount: correctedAmount,
        p_notes: notes
      });

      if (error) {
        if (error.message.includes('WHS_UNAUTHORIZED')) {
          throw new Error('JURISDICCIÓN DENEGADA: No tienes nivel de autorización para auditar capital.');
        }
        throw new Error(error.message);
      }
    },
    onSuccess: () => {
      // Destruir caché para remover el recibo de la pantalla instantáneamente
      queryClient.invalidateQueries({ queryKey: ['quarantined_expenses'] });
    },
    onError: (error: Error) => alert(`FRACTURA FINANCIERA: ${error.message}`)
  });

  return (
    <ExpenseQuarantinePresenter
      expenses={expenses}
      isSubmitting={processMutation.isPending}
      onProcessExpense={(id, status, correctedAmount, notes) => 
        processMutation.mutate({ id, status, correctedAmount, notes })
      }
    />
  );
};

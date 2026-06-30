import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';

// Aseguramos un tipado básico, asumiendo que vendrá de shared-types
type LoadOfferInput = any;

export function useCreateLoadOffer() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (newOffer: LoadOfferInput) => {
      const { data, error } = await supabase.from('load_offers').insert(newOffer);
      if (error) {
        // Transformamos el error de Supabase a nuestro contrato FuelFlowError
        throw { 
          name: 'FuelFlowError',
          message: error.message, 
          code: error.message.includes('seguro') ? 'INSURANCE_EXPIRED' : 'VALIDATION_ERROR' 
        };
      }
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['load_offers'] });
    }
  });
}

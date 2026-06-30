import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';

// Espejo del tipo AccessLog devuelto por el RPC
export interface AccessLog {
  id: string;
  user_id: string;
  table_name: string;
  row_id: string;
  action: 'INSERT' | 'UPDATE' | 'DELETE' | 'SELECT';
  timestamp: string;
}

export const useOfferChronology = (offerUuid?: string) => {
  return useQuery({
    queryKey: ['offer_chronology', offerUuid],
    queryFn: async () => {
      if (!offerUuid || offerUuid.trim() === '') return [];

      // Llamada al motor forense en BD
      const { data, error } = await supabase
        .rpc('get_offer_chronology', { offer_uuid: offerUuid });
      
      if (error) throw error;
      return data as AccessLog[];
    },
    enabled: !!offerUuid, // Solo dispara la query si hay un UUID válido
    
    // FÍSICA APLICADA: Cero Caché reiterado para Auditoría
    staleTime: 0,
    gcTime: 0,
    refetchOnMount: 'always',
  });
};

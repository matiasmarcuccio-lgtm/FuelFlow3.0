import { useEffect } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';

export const useLoadOffers = () => {
  const queryClient = useQueryClient();

  const query = useQuery({
    queryKey: ['load_offers_feed'],
    queryFn: async () => {
      // Zero-Trust: La RLS se encarga de filtrar las ofertas por matches_contractor_profile
      const { data, error } = await supabase
        .from('load_offers')
        .select('*')
        .order('created_at', { ascending: false });
        
      if (error) throw error;
      return data;
    },
    staleTime: 1000 * 60 * 5, // 5 minutos, pero se invalida con WebSockets
  });

  // Suscripción Global a Inserciones (Matchmaking Inmediato)
  useEffect(() => {
    const channel = supabase
      .channel('bidding_feed_channel')
      .on('postgres_changes', {
        event: '*', // Escuchamos INSERT, UPDATE o DELETE
        schema: 'public',
        table: 'load_offers'
      }, () => {
        // En cuanto ocurre un cambio, destruimos caché y forzamos re-fetch
        queryClient.invalidateQueries({ queryKey: ['load_offers_feed'] });
      })
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [queryClient]);

  return query;
};

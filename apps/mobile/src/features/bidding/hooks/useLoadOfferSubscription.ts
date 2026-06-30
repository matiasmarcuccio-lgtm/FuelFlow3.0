import { useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';

export const useLoadOfferSubscription = (offerId: string) => {
  // Utilizamos el hook de TanStack en lugar de la exportación global para garantizar la seguridad del contexto de React
  const queryClient = useQueryClient();

  useEffect(() => {
    if (!offerId) return;

    // Escuchamos cambios exclusivamente en esta fila de Postgres (WebSocket selectivo)
    const channel = supabase
      .channel(`offer:${offerId}`)
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'load_offers',
        filter: `id=eq.${offerId}`
      }, (payload) => {
        // Reactividad Asíncrona: Si el motor geoespacial cambia el estado a 'matched'
        if (payload.new.status === 'matched') {
          // Destruimos el caché. TanStack forzará un re-render visual en menos de 500ms.
          queryClient.invalidateQueries({ queryKey: ['load_offer', offerId] });
        }
      })
      .subscribe();

    // LEY DE PREVENCIÓN: El canal se aniquila automáticamente al desmontar el componente.
    // Esto evita agresivos "reconnect loops" si el contratista pierde señal 4G en la obra.
    return () => {
      supabase.removeChannel(channel);
    };
  }, [offerId, queryClient]);
};

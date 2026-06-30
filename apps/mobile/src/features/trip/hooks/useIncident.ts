import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { Alert } from 'react-native';

interface IncidentParams {
  offerId: string;
  description: string;
  lat: number;
  lng: number;
}

export const useIncident = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (params: IncidentParams) => {
      const { error } = await supabase.rpc('report_incident', {
        p_offer_id: params.offerId,
        p_description: params.description,
        p_lat: params.lat,
        p_lng: params.lng
      });
      if (error) throw error;
    },
    onSuccess: () => {
      // Zero-Cache: Invalidar logs forenses inmediatamente
      queryClient.invalidateQueries({ queryKey: ['access_logs'] });
      Alert.alert('Registro Forense', 'El incidente ha sido inmortalizado en la bitácora legal.');
    },
    onError: (err: any) => {
      Alert.alert('Fallo de Registro', err.message);
    }
  });
};

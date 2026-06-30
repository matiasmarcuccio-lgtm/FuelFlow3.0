import { useMutation } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { LoadOfferSchema, LoadOfferInput } from '../schema';

export const useCreateLoadOffer = () => {
  return useMutation({
    mutationFn: async (input: LoadOfferInput) => {
      // 1. Validación Previa (Fail-Fast)
      // Si la carga de datos viola la Física del Sistema (ej. latitudes imposibles o ventanas de tiempo malformadas),
      // Zod lanzará una excepción sincrónica aquí mismo, salvando el viaje de red y el ancho de banda.
      const validatedData = LoadOfferSchema.parse(input);
      
      // 2. Interacción con la base de datos (Punto de No Retorno)
      // Al hacer este insert, despertaremos a los triggers: 
      // trigger_matchmaking_after_load_offer (Motor Turf.js), trigger_block_uninsured_contractor y audit_load_offers.
      const { data, error } = await supabase.from('load_offers').insert(validatedData);
      
      if (error) throw error;
      return data;
    }
  });
};

import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';

export const useSubmitTelemetry = () => {
  const queryClient = useQueryClient();

  return useMutation({
    networkMode: 'offlineFirst', // Obliga a la mutación a encolarse en lugar de fallar inmediatamente
    mutationFn: async (telemetryLog: any) => {
      const { data, error } = await supabase.rpc('submit_telemetry_event', {
        p_asset_id: telemetryLog.asset_id,
        p_recorded_by: telemetryLog.recorded_by,
        p_event_type: telemetryLog.event_type,
        p_payload: telemetryLog.payload,
        p_client_timestamp: telemetryLog.client_timestamp
      });
      if (error) throw error;
      if (data === 'DEAD_LETTER_ROUTED') {
        throw new Error('DEAD_LETTER_ROUTED: Structural collision detected and audited.');
      }
      return data;
    },
    onMutate: async (newLog) => {
      // 1. Cancel cualquier re-fetch entrante de activos para evitar colisiones asíncronas
      await queryClient.cancelQueries({ queryKey: ['assets'] });

      // 2. Capturar el estado previo de la caché para permitir un Rollback forense en caso de fallo real
      const previousAssets = queryClient.getQueryData(['assets']);

      // 3. Ejecutar la proyección en caliente directamente sobre la caché local de lectura
      queryClient.setQueryData(['assets'], (oldAssets: any[] | undefined) => {
        if (!oldAssets) return [];
        return oldAssets.map((asset) => {
          if (asset.id !== newLog.asset_id) return asset;

          // Espejo exacto de la resolución de conflictos del trigger de PostgreSQL
          const currentTimestamp = new Date(asset.last_telemetry_timestamp || 0).getTime();
          const logTimestamp = new Date(newLog.client_timestamp).getTime();

          if (logTimestamp > currentTimestamp) {
            return {
              ...asset,
              status: newLog.payload.status ?? asset.status,
              last_odometer_checkin: newLog.payload.odometer ?? asset.last_odometer_checkin,
              current_project_id: newLog.payload.project_id ?? asset.current_project_id,
              last_telemetry_timestamp: newLog.client_timestamp, // Actualizar marcador temporal local
            };
          }
          return asset;
        });
      });

      // Retornar el contexto con el estado previo para el manejo de errores
      return { previousAssets };
    },
    onError: (err, newLog, context) => {
      // Revertir la caché al estado original si la sincronización online falla de forma definitiva
      if (context?.previousAssets) {
        queryClient.setQueryData(['assets'], context.previousAssets);
      }
    },
  });
};

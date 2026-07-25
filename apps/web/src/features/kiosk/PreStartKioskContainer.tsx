import React, { useEffect, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';
import { PreStartKiosk } from './PreStartKiosk';
import type { AssignedShift } from './PreStartKiosk';
import { ActiveShiftPresenter } from './ActiveShiftPresenter';

interface KioskContainerProps {
  operatorId: string; // Proviene del contexto de autenticación estricto
}

export const PreStartKioskContainer: React.FC<KioskContainerProps> = ({ operatorId }) => {
  const queryClient = useQueryClient();
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // 1. Suscripción de Red Hostil (Escucha la orden del Command Center)
  useEffect(() => {
    if (!operatorId) return;

    const channel = supabase.channel(`operator_trench_${operatorId}`)
      .on(
        'postgres_changes',
        { 
          event: '*', 
          schema: 'public', 
          table: 'asset_assignments', 
          filter: `driver_id=eq.${operatorId}` 
        },
        (payload) => {
          console.log('⚡ [Realtime] Orden de despacho recibida / mutada:', payload);
          // Destruimos la caché al instante para que React Query consulte la Capa 0
          queryClient.invalidateQueries({ queryKey: ['active_shift', operatorId] });
        }
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') console.log('📡 Enlace táctico establecido.');
        if (status === 'CLOSED' || status === 'CHANNEL_ERROR') console.warn('⚠️ ALERTA: Pérdida de telemetría de red.');
      });

    return () => {
      supabase.removeChannel(channel);
    };
  }, [operatorId, queryClient]);

  // 2. Consulta de Asignación Pendiente con Redundancia
  const { data: currentShift, isLoading } = useQuery({
    queryKey: ['active_shift', operatorId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('asset_assignments')
        .select(`
          id,
          status,
          asset_id,
          created_at,
          assets ( internal_code )
        `)
        .eq('driver_id', operatorId)
        .in('status', ['pending_prestart', 'in_progress'])
        .maybeSingle();

      if (error) throw error;
      if (!data) return null;

      // Handle cases where assets is an array or object
      let assetCode = 'DESC';
      if (data.assets) {
         if (Array.isArray(data.assets)) {
             assetCode = data.assets[0]?.internal_code || 'DESC';
         } else {
             assetCode = (data.assets as any).internal_code || 'DESC';
         }
      }

      return {
        id: data.id,
        asset_id: data.asset_id,
        asset_code: assetCode,
        status: data.status,
        created_at: data.created_at || new Date().toISOString(), // Idealmente debes traer created_at en la query
      } as AssignedShift & { status: string; created_at: string };
    },
    // Si el WebSocket se ahoga, el polling de respaldo asegura que el despacho no se pierda
    refetchInterval: 15000, 
  });

  // 3. Mutación de Certificación Biométrica
  const certifyMutation = useMutation({
    mutationFn: async (shiftId: string) => {
      const { error } = await supabase
        .from('asset_assignments')
        .update({ status: 'in_progress' })
        .eq('id', shiftId)
        .eq('driver_id', operatorId);

      if (error) {
        // Traductor Forense de Fallas
        if (error.message.includes('prestart_time_friction')) {
          throw new Error('RECHAZO DE CAPA 0: El servidor detectó evasión temporal. La firma requiere 60 segundos biológicos.');
        }
        throw error;
      }
    },
    onSuccess: () => {
      setErrorMessage(null);
      // El turno cambia a in_progress. La UI del pre-start se limpia.
      queryClient.invalidateQueries({ queryKey: ['active_shift', operatorId] });
    },
    onError: (error: Error) => setErrorMessage(error.message)
  });

  // 4. Mutación Crítica de Avería (Botón Rojo)
  const defectMutation = useMutation({
    mutationFn: async ({ assetId, shiftId, reason }: { assetId: string, shiftId: string, reason: string }) => {
      // Paso A: Insertar el defecto. Esto dispara el trigger de mantenimiento que bloquea el activo.
      const { error: logError } = await supabase
        .from('maintenance_logs')
        .insert({
          asset_id: assetId,
          locked_by_uid: operatorId,
          issue_description: `[FALLA PRE-START] ${reason}`
        });
      
      if (logError) throw logError;

      // Paso B: Revocar el turno abortado
      const { error: revokeError } = await supabase.rpc('revoke_pending_shift', {
        p_assignment_id: shiftId,
        p_reason: 'PRE-START FAILED: Falla mecánica reportada por operador.'
      });

      if (revokeError) throw revokeError;
    },
    onSuccess: () => {
      setErrorMessage(null);
      queryClient.invalidateQueries({ queryKey: ['active_shift', operatorId] });
    },
    onError: (error: Error) => setErrorMessage(error.message)
  });

  // 5. Mutación del Liquidador Financiero (End-of-Shift)
  const endShiftMutation = useMutation({
    mutationFn: async (shiftId: string) => {
      const { data, error } = await supabase.rpc('close_active_shift', {
        p_assignment_id: shiftId
      });
      if (error) throw error;
      return data;
    },
    onSuccess: (data) => {
      setErrorMessage(null);
      // El turno se completó. Volvemos al estado inicial vacío.
      queryClient.invalidateQueries({ queryKey: ['active_shift', operatorId] });
      console.log('Turno cerrado. Certificado:', data?.certificate_id);
    },
    onError: (error: Error) => setErrorMessage(error.message)
  });

  // 6. Mutación de Gasto Analógico (OCR Quarantine)
  const expenseMutation = useMutation({
    mutationFn: async ({ shiftId, base64, category }: { shiftId: string, base64: string, category: string }) => {
      const { data, error } = await supabase.functions.invoke('ocr-quarantine', {
        body: { shift_id: shiftId, base64_image: base64, category }
      });
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      setErrorMessage(null);
      alert("Comprobante cifrado y enviado a Cuarentena Forense.");
    },
    onError: (error: Error) => setErrorMessage(error.message)
  });

  // Estado de carga inicial (Blindado)
  if (isLoading) {
    return (
      <div className="bg-slate-950 flex items-center justify-center min-h-screen">
        <span className="text-white font-mono text-sm animate-pulse">Sincronizando satélite...</span>
      </div>
    );
  }

  return (
    <>
      {errorMessage && (
        <div className="bg-red-900 text-white p-4 text-center font-bold font-mono border-b-4 border-red-950 animate-pulse z-50 relative shadow-2xl">
          FRACTURA LOGÍSTICA: {errorMessage}
        </div>
      )}
      
      {currentShift?.status === 'in_progress' ? (
        <ActiveShiftPresenter
          assetCode={currentShift.asset_code}
          startTime={currentShift.created_at}
          isSubmitting={endShiftMutation.isPending}
          onEndShift={() => endShiftMutation.mutate(currentShift.id)}
          isUploadingExpense={expenseMutation.isPending}
          onCaptureExpense={(base64, category) => expenseMutation.mutate({ shiftId: currentShift.id, base64, category })}
        />
      ) : (
        <PreStartKiosk
          shift={currentShift || null}
          isSubmitting={certifyMutation.isPending || defectMutation.isPending}
          onCertifyShift={(shiftId) => certifyMutation.mutate(shiftId)}
          onReportDefect={(assetId, shiftId, reason) => defectMutation.mutate({ assetId, shiftId, reason })}
        />
      )}
    </>
  );
};

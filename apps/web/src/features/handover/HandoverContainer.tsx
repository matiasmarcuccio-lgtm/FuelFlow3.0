import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useSubmitTelemetry } from '../assets/mutations';
import { HandoverPresenter } from './HandoverPresenter';
import { useGeofence } from './useGeofence';
import { useAcousticDispatch } from './useAcousticDispatch';

interface HandoverContainerProps {
  assetId: string;
  projectId: string;
  onComplete?: () => void;
  mode?: 'handover' | 'shutdown';
}

export const HandoverContainer: React.FC<HandoverContainerProps> = ({ assetId, projectId, onComplete, mode = 'handover' }) => {
  const queryClient = useQueryClient();
  const submitTelemetry = useSubmitTelemetry();
  
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  // Iniciar el Sistema Nervioso Acústico (Hands-Free JIT)
  useAcousticDispatch(assetId);

  // Extraer el payload combinado (Cuadrilla + Polígono GeoJSON) desde la caché offline
  const syncData = queryClient.getQueryData<any>(['crew_hashes', projectId]);
  const roster = syncData?.crew || [];
  
  // Transformar el GeoJSON nativo de PostGIS al formato de coordenadas requerido por el Ray-Casting
  const hrcwPolygon = syncData?.topology?.hrcw_polygon?.coordinates?.[0]?.map((coord: number[]) => ({
    longitude: coord[0],
    latitude: coord[1]
  })) || null;

  // FASE 3: Aserción Geofísica (Bloqueo de polígono HRCW)
  const { isGeolocked, geoMessage, lastKnownCoord } = useGeofence(hrcwPolygon);

  const handleVerifyPin = async (pin: string, incomingUserId: string) => {
    setErrorMsg(null);

    const operator = roster.find((member: any) => member.user_id === incomingUserId);
    if (!operator) {
      const msg = 'Operario no encontrado en la caché del proyecto.';
      setErrorMsg(msg);
      throw new Error(msg);
    }

    // 1. Blind Optimistic Queue: Emitimos el PIN puro en texto plano.
    // El servidor lo evaluará y si es falso detona el Red Tag.
    submitTelemetry.mutate({
      asset_id: assetId,
      recorded_by: incomingUserId,
      event_type: 'handover_signature',
      payload: { 
        status: 'in_site', 
        project_id: projectId,
        pin: pin, // <--- El pin viaja en texto plano al backend (sobre HTTPS) o reposa cifrado por FDE.
        location: lastKnownCoord ? { 
          lat: lastKnownCoord.latitude, 
          lng: lastKnownCoord.longitude,
          speed: lastKnownCoord.speed,
          heading: lastKnownCoord.heading,
          timestamp: lastKnownCoord.timestamp 
        } : null
      },
      client_timestamp: new Date().toISOString(),
    });

    // 2. Escribir en memoria local para que la Máquina de Estados Derivada avance. Asumimos éxito.
    const today = new Date().toISOString().split('T')[0];
    const { set } = await import('idb-keyval');
    await set(`handover_${today}`, {
        isValid: true,
        user_id: incomingUserId,
        timestamp: Date.now()
    });

    if (onComplete) onComplete();
  };

  const handleGracefulShutdown = async (pin: string, incomingUserId: string) => {
    setErrorMsg(null);

    const operator = roster.find((member: any) => member.user_id === incomingUserId);
    if (!operator) {
      const msg = 'Operario no encontrado en la caché del proyecto.';
      setErrorMsg(msg);
      throw new Error(msg);
    }

    // 1. Crear el payload de evacuación con el PIN para validación asíncrona
    const payload = {
      asset_id: assetId,
      recorded_by: incomingUserId,
      event_type: 'graceful_shutdown',
      payload: { 
        status: 'offline', 
        project_id: projectId,
        pin: pin,
        location: lastKnownCoord ? { 
          lat: lastKnownCoord.latitude, 
          lng: lastKnownCoord.longitude,
          speed: 0,
          heading: lastKnownCoord.heading,
          timestamp: lastKnownCoord.timestamp 
        } : null
      },
      client_timestamp: new Date().toISOString(),
    };

    const outboxId = crypto.randomUUID();
    const today = new Date().toISOString().split('T')[0];
    const { set, del } = await import('idb-keyval');

    // 2. Escribir en la Cola de Transacciones Pendientes (Outbox)
    await set(`outbox_${outboxId}`, {
        id: outboxId,
        event_type: 'operator_checkout',
        asset_id: assetId,
        payload,
        timestamp: Date.now()
    });

    // 3. AMNESIA INMEDIATA (Blind Queue). Destruimos la sesión local sin esperar al servidor.
    await del(`handover_${today}`);
    await del(`pre_start_${today}`);

    // 4. Disparamos la mutación hacia el servidor. No bloqueamos la UI si falla.
    submitTelemetry.mutateAsync(payload).catch(() => {
        // Fallo de red tolerado silenciosamente por el frontend (se manejará en background).
    });

    if (onComplete) onComplete();
  };

  return (
    <>
      {errorMsg && (
        <div className="fixed top-20 left-1/2 -translate-x-1/2 z-50 p-4 bg-red-900 border-2 border-red-500 rounded-xl text-red-100 font-bold shadow-2xl">
          {errorMsg}
        </div>
      )}
      <HandoverPresenter 
        onVerify={handleVerifyPin}
        onGracefulShutdown={handleGracefulShutdown}
        isPending={submitTelemetry.isPending} 
        isLocked={false}
        lockoutTimeRemaining={0}
        roster={roster}
        isGeolocked={isGeolocked}
        geoMessage={geoMessage}
        mode={mode}
      />
    </>
  );
};

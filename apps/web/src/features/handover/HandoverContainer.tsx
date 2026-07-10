import React, { useState, useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { verifyOfflinePin } from '../../lib/crypto';
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

const MAX_ATTEMPTS = 3;
const LOCKOUT_DURATION_MS = 60 * 1000; // 60 segundos de bloqueo tras 3 intentos

export const HandoverContainer: React.FC<HandoverContainerProps> = ({ assetId, projectId, onComplete, mode = 'handover' }) => {
  const queryClient = useQueryClient();
  const submitTelemetry = useSubmitTelemetry();
  
  const [attempts, setAttempts] = useState(0);
  const [lockoutUntil, setLockoutUntil] = useState<number | null>(null);
  const [lockoutTimeRemaining, setLockoutTimeRemaining] = useState(0);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  // Iniciar el Sistema Nervioso Acústico (Hands-Free JIT)
  useAcousticDispatch(assetId);

  // Extraer el payload combinado (Cuadrilla + Polígono GeoJSON) desde la caché offline
  const syncData = queryClient.getQueryData<any>(['crew_hashes', projectId]);
  const roster = syncData?.crew || [];
  
  // Transformar el GeoJSON nativo de PostGIS al formato de coordenadas requerido por el Ray-Casting
  const hrcwPolygon = syncData?.hrcw_polygon?.coordinates?.[0]?.map((coord: number[]) => ({
    longitude: coord[0],
    latitude: coord[1]
  })) || null;

  // FASE 3: Aserción Geofísica (Bloqueo de polígono HRCW)
  const { isGeolocked, geoMessage, lastKnownCoord } = useGeofence(hrcwPolygon);

  // Timer del Lockout
  useEffect(() => {
    if (!lockoutUntil) return;

    const interval = setInterval(() => {
      const remaining = Math.ceil((lockoutUntil - Date.now()) / 1000);
      if (remaining <= 0) {
        setLockoutUntil(null);
        setAttempts(0);
        setLockoutTimeRemaining(0);
        clearInterval(interval);
      } else {
        setLockoutTimeRemaining(remaining);
      }
    }, 1000);

    return () => clearInterval(interval);
  }, [lockoutUntil]);

  const handleVerifyPin = async (pin: string, incomingUserId: string) => {
    setErrorMsg(null);
    if (lockoutUntil) throw new Error('Lockout activo');

    const operator = roster.find((member: any) => member.user_id === incomingUserId);
    if (!operator) {
      const msg = 'Operario no encontrado en la caché del proyecto.';
      setErrorMsg(msg);
      throw new Error(msg);
    }

    // 1.5 Validación de Integridad Temporal (Time Drift)
    const lastServerSync = queryClient.getQueryData<number>(['server_time_anchor', projectId]);
    const currentDeviceTime = Date.now();
    if (lastServerSync && currentDeviceTime < lastServerSync) {
      const msg = 'Fallo de integridad: El reloj del dispositivo está desfasado (Time Drift). Conéctese a una red para recalibrar.';
      setErrorMsg(msg);
      throw new Error(msg);
    }

    // 2. Ejecutar la matemática pura asíncrona usando Web Crypto API
    const isValid = await verifyOfflinePin(pin, operator.pin_salt, operator.pin_hash);

    if (!isValid) {
      const newAttempts = attempts + 1;
      setAttempts(newAttempts);
      if (newAttempts >= MAX_ATTEMPTS) {
        setLockoutUntil(Date.now() + LOCKOUT_DURATION_MS);
      }
      const msg = `Firma criptográfica inválida. Intento ${newAttempts}/${MAX_ATTEMPTS}`;
      setErrorMsg(msg);
      throw new Error(msg);
    }

    // Reseteamos intentos tras un éxito
    setAttempts(0);
    setErrorMsg(null);

    // 3. Pin válido: Emitir la mutación de telemetría (Event Sourcing)
    submitTelemetry.mutate({
      asset_id: assetId,
      recorded_by: incomingUserId,
      event_type: 'handover_signature',
      payload: { 
        status: 'in_site', 
        project_id: projectId,
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

    // 4. Escribir en memoria local para que la Máquina de Estados Derivada avance
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
    if (lockoutUntil) throw new Error('Lockout activo');

    const operator = roster.find((member: any) => member.user_id === incomingUserId);
    if (!operator) {
      const msg = 'Operario no encontrado en la caché del proyecto.';
      setErrorMsg(msg);
      throw new Error(msg);
    }

    const isValid = await verifyOfflinePin(pin, operator.pin_salt, operator.pin_hash);

    if (!isValid) {
      const msg = `Firma criptográfica inválida para apagado.`;
      setErrorMsg(msg);
      throw new Error(msg);
    }

    // 1. Crear el payload de evacuación
    const payload = {
      asset_id: assetId,
      recorded_by: incomingUserId,
      event_type: 'graceful_shutdown',
      payload: { 
        status: 'offline', 
        project_id: projectId,
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

    try {
      // 3. Intentar la mutación real hacia el servidor (se pausará si no hay red gracias a offlineFirst)
      await submitTelemetry.mutateAsync(payload);

      // 4. Éxito de red: Borrar Outbox y ejecutar Amnesia Criptográfica
      await del(`outbox_${outboxId}`);
      await del(`handover_${today}`);
      await del(`pre_start_${today}`);

      if (onComplete) onComplete();
    } catch (error) {
      // 5. Fallo o interrupción: NO HAY AMNESIA.
      // Retenemos el outbox y alertamos al operario.
      setErrorMsg('Fallo de red en cierre seguro. Sincronización retenida en Outbox. No apague la tablet.');
    }
  };

  return (
    <>
      {errorMsg && !lockoutUntil && (
        <div className="fixed top-20 left-1/2 -translate-x-1/2 z-50 p-4 bg-red-900 border-2 border-red-500 rounded-xl text-red-100 font-bold shadow-2xl">
          {errorMsg}
        </div>
      )}
      <HandoverPresenter 
        onVerify={handleVerifyPin}
        onGracefulShutdown={handleGracefulShutdown}
        isPending={submitTelemetry.isPending} 
        isLocked={!!lockoutUntil}
        lockoutTimeRemaining={lockoutTimeRemaining}
        roster={roster}
        isGeolocked={isGeolocked}
        geoMessage={geoMessage}
        mode={mode}
      />
    </>
  );
};

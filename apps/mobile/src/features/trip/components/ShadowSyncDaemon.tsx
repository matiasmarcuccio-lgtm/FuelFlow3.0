import React, { useEffect } from 'react';
import NetInfo from '@react-native-community/netinfo';
import { supabase } from '@/lib/supabase';
import { useShadowSyncStore, SyncEvent } from '../stores/useShadowSyncStore';
import * as FileSystem from 'expo-file-system';
import { decode } from 'base64-arraybuffer';

// Demonio invisible montado en la raíz de la app
export const ShadowSyncDaemon = () => {
  const { events, removeEvent, markAsDLQ, incrementRetry } = useShadowSyncStore();

  useEffect(() => {
    // Suscripción a cambios en la red de hardware
    const unsubscribe = NetInfo.addEventListener(state => {
      if (state.isConnected && state.isInternetReachable !== false) {
        flushQueue();
      }
    });

    // Intentar también en el montaje por si ya estamos online
    flushQueue();

    return () => {
      unsubscribe();
    };
  }, [events]);

  const flushQueue = async () => {
    const pendingEvents = useShadowSyncStore.getState().events.filter(e => e.status === 'PENDING');
    if (pendingEvents.length === 0) return;

    for (const event of pendingEvents) {
      // Exponencial backoff: si ya tiene muchos reintentos, podemos abortar o saltarlo (por ahora no limitamos los transitorios)
      // pero evitemos spam
      if (event.retryCount > 10) continue; 

      try {
        if (event.type === 'ARRIVAL') {
          const { error } = await supabase.from('load_offers')
            .update({ 
              status: 'COMPLETED',
              completed_at_local: event.localTimestamp // El sello de tiempo inmutable
            })
            .eq('id', event.offerId);

          if (error) {
            if (error.code === '42501' || error.code?.startsWith('22') || error.code?.startsWith('23')) {
              console.error("[ShadowSync] Falla permanente detectada (RLS/Integridad):", error.message);
              markAsDLQ(event.eventId, error.message);
            } else {
              console.warn("[ShadowSync] Falla transitoria:", error.message);
              incrementRetry(event.eventId);
            }
          } else {
            console.log(`[ShadowSync] Payload ${event.eventId} inyectado exitosamente.`);
            removeEvent(event.eventId);
          }
        } else if (event.type === 'DEPARTURE') {
          // 1. Subir Fotografía Inmutable a Storage (Candado Fotográfico)
          let uploadedPath = null;
          if (event.localImageUri) {
            const base64 = await FileSystem.readAsStringAsync(event.localImageUri, { encoding: FileSystem.EncodingType.Base64 });
            const filePath = `trip_${event.offerId}/${event.eventId}.jpg`;
            
            const { data, error: storageError } = await supabase.storage
              .from('docket_evidence')
              .upload(filePath, decode(base64), { contentType: 'image/jpeg' });
            
            if (storageError) {
              if (storageError.message.includes('row-level security') || storageError.statusCode === '403') {
                markAsDLQ(event.eventId, storageError.message);
              } else {
                incrementRetry(event.eventId);
              }
              continue; // Cancelar actualización de BD si la foto falla
            }
            uploadedPath = data?.path;
          }

          // 2. Transicionar a IN_TRANSIT con masa e imagen
          const { error } = await supabase.from('load_offers')
            .update({ 
              status: 'IN_TRANSIT',
              loaded_gross_mass: event.loadedGrossMass,
              docket_image_path: uploadedPath
            })
            .eq('id', event.offerId);

          if (error) {
            if (error.code === '42501' || error.code?.startsWith('22') || error.code?.startsWith('23')) {
              console.error("[ShadowSync] Falla permanente detectada en BD:", error.message);
              markAsDLQ(event.eventId, error.message);
            } else {
              incrementRetry(event.eventId);
            }
          } else {
            console.log(`[ShadowSync] Departure & Evidencia ${event.eventId} inyectada exitosamente.`);
            removeEvent(event.eventId);
          }
        } else if (event.type === 'EMERGENCY_OVERRIDE') {
          // El conductor forzó la salida sin validar. No hay imagen real garantizada.
          const { error } = await supabase.from('load_offers')
            .update({ 
              status: 'IN_TRANSIT',
              anomaly_flag: 'DRIVER_EMERGENCY_OVERRIDE',
              // El motivo del incidente se podría meter en un campo de notas si existiera,
              // pero como no, lo podemos guardar en la propia anomaly_flag (con sub-tipo) o dejarlo así.
              // Para ser fieles al esquema, 'DRIVER_EMERGENCY_OVERRIDE' despierta a la Torre de Control.
            })
            .eq('id', event.offerId);

          if (error) {
            if (error.code === '42501' || error.code?.startsWith('22') || error.code?.startsWith('23')) {
              markAsDLQ(event.eventId, error.message);
            } else {
              incrementRetry(event.eventId);
            }
          } else {
            removeEvent(event.eventId);
          }
        } else if (event.type === 'BREAKDOWN') {
          // El conductor declaró avería. El viaje queda en BREAKDOWN.
          const { error } = await supabase.from('load_offers')
            .update({ 
              status: 'BREAKDOWN'
            })
            .eq('id', event.offerId);

          if (error) {
            if (error.code === '42501' || error.code?.startsWith('22') || error.code?.startsWith('23')) {
              markAsDLQ(event.eventId, error.message);
            } else {
              incrementRetry(event.eventId);
            }
          } else {
            removeEvent(event.eventId);
          }
        }
      } catch (err: any) {
        // Red puramente caída (Fetch error) -> Transitorio
        incrementRetry(event.eventId);
      }
    }
  };

  return null; // Componente completamente invisible (Motor Headless)
};

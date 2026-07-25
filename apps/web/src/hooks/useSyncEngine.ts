import { useState, useEffect, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { getOutboxQueue, removeOutboxItem } from '../lib/offlineVault';

export const useSyncEngine = () => {
  const [isOnline, setIsOnline] = useState<boolean>(navigator.onLine);
  const [syncing, setSyncing] = useState<boolean>(false);
  const [pendingCount, setPendingCount] = useState<number>(0);

  // Revisa la bóveda y procesa los paquetes atrapados
  const flushOutbox = useCallback(async () => {
    if (!navigator.onLine || syncing) return;
    
    try {
      const queue = await getOutboxQueue();
      setPendingCount(queue.length);
      
      if (queue.length === 0) return;

      setSyncing(true);
      console.log(`[SYNC ENGINE] 📡 Vaciando ${queue.length} transacciones de la caja negra...`);

      for (const item of queue) {
        // Disparo hacia la Capa 0
        const { error } = await supabase.rpc(item.rpc_name, item.payload);
        
        if (!error) {
          // Destruir de IndexedDB si el servidor aceptó la firma
          await removeOutboxItem(item.id);
        } else {
          console.error(`[SYNC ERROR] Fallo al inyectar ${item.rpc_name}:`, error);
          // Si el error es de Aduana Legal (Ej: Fatiga), detenemos la sincronización para no corromper el orden
          if (error.message.includes('WHS_') || error.code === '42501') {
             break;
          }
        }
      }
    } finally {
      const remaining = await getOutboxQueue();
      setPendingCount(remaining.length);
      setSyncing(false);
    }
  }, [syncing]);

  useEffect(() => {
    const handleOnline = () => {
      setIsOnline(true);
      flushOutbox();
    };
    
    const handleOffline = () => {
      setIsOnline(false);
    };

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    // Iniciar vaciado si recargamos la app y tenemos internet
    if (navigator.onLine) flushOutbox();

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, [flushOutbox]);

  // Exponemos el estado de la red y la cantidad de paquetes atrapados
  return { isOnline, syncing, pendingCount, flushOutbox };
};

import { QueryClient } from '@tanstack/react-query';
import { persistQueryClient } from '@tanstack/react-query-persist-client';
import { get, set, del } from 'idb-keyval';

// 1. Instanciamos el cliente con políticas estructurales Offline-First
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      networkMode: 'offlineFirst', // Permite fetchear desde caché sin red
      gcTime: 1000 * 60 * 60 * 24, // 24 horas (Para la persistencia offline prolongada)
      staleTime: 1000 * 10, // 10 segundos para revalidación natural
    },
    mutations: {
      networkMode: 'offlineFirst', // Pausa y encola mutaciones sin red
      retry: (failureCount, error: any) => {
        // Interceptamos fallos de red puros para encolar en lugar de descartar
        if (error instanceof TypeError && error.message.includes('Failed to fetch')) {
          return true; // Fuerza la reintentabilidad infinita (y por ende, la pausa offline)
        }
        // Si el backend ya evacuó el error a la DLQ, no tiene sentido reintentar
        if (error instanceof Error && error.message.includes('DEAD_LETTER_ROUTED')) {
          return false;
        }
        return failureCount < 3;
      },
    },
  },
});

// 2. Creamos el adaptador asíncrono sobre IndexedDB
export const idbPersister = {
  persistClient: async (client: any) => {
    await set('jitsite-offline-cache', client);
  },
  restoreClient: async () => {
    return await get('jitsite-offline-cache');
  },
  removeClient: async () => {
    await del('jitsite-offline-cache');
  },
};

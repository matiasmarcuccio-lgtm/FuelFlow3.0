import { useInfiniteQuery } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';

const PAGE_SIZE = 50;

export const useAccessLogs = () => {
  return useInfiniteQuery({
    queryKey: ['access_logs'],
    queryFn: async ({ pageParam = 0 }) => {
      // ESPEJO EXACTO: Mapeo estricto de las columnas de la tabla access_logs
      const { data, error } = await supabase
        .from('access_logs')
        .select('id, timestamp, action, user_id, table_name, row_id')
        .order('timestamp', { ascending: false }) // Este sort ahora vuela gracias al índice B-Tree
        .range(pageParam, pageParam + PAGE_SIZE - 1);
      
      if (error) throw error;
      return data;
    },
    getNextPageParam: (lastPage, allPages) => {
      // Paginación por rangos. Si la página no vino llena, chocamos con la última fila existente.
      return lastPage.length === PAGE_SIZE ? allPages.length * PAGE_SIZE : undefined;
    },
    initialPageParam: 0,
    
    // FÍSICA APLICADA: Cero Caché reiterado para Auditoría
    staleTime: 0,
    gcTime: 0,
    refetchOnMount: 'always',
  });
};

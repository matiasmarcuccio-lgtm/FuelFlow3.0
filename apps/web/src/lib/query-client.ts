import { QueryCache, MutationCache, QueryClient } from '@tanstack/react-query';
import { handleDatabaseError } from './error-handler';

export const queryClient = new QueryClient({
  queryCache: new QueryCache({
    onError: (error) => handleDatabaseError(error, queryClient),
  }),
  // FIX ARQUITECTÓNICO: Se añade MutationCache para capturar los errores de inserción/actualización globalmente
  mutationCache: new MutationCache({
    onError: (error) => handleDatabaseError(error, queryClient),
  }),
});

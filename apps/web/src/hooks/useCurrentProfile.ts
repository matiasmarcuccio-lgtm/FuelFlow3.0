import { useQuery } from '@tanstack/react-query';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';

export function useCurrentProfile() {
  const { session } = useAuth();

  return useQuery({
    queryKey: ['profile', session?.user.id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', session!.user.id)
        .single();
        
      if (error) throw error;
      return data;
    },
    enabled: !!session?.user.id,
    staleTime: Infinity, // El perfil rara vez cambia durante una sesión activa
  });
}

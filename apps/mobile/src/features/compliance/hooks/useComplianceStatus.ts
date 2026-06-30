import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';

export const useComplianceStatus = () => {
  return useQuery({
    queryKey: ['compliance-status'],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error("Usuario no autenticado");

      const { data: profile } = await supabase
        .from('profiles')
        .select('role, is_verified')
        .eq('id', user.id)
        .single();

      // Verificar si hay algún documento subido que aún no esté verificado
      const { data: docs } = await supabase
        .from('compliance_documents')
        .select('is_verified')
        .eq('profile_id', user.id)
        .order('created_at', { ascending: false })
        .limit(1);

      const hasPendingDoc = docs && docs.length > 0 && docs[0].is_verified === false;

      // Dependencia estricta de la BD
      return {
        insurance_compliant: false, // Temporalmente false hasta que tengamos la tabla de seguros real (para forzar el flujo del bunker)
        is_verified: profile?.is_verified ?? false,
        role: profile?.role || 'driver',
        hasPendingDoc
      };
    },
    staleTime: 0,
    gcTime: 0,
    refetchOnMount: 'always',
  });
};

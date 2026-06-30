import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';

export const useComplianceStatus = () => {
  return useQuery({
    queryKey: ['compliance_status'],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error("Usuario no autenticado");

      // 1. Obtener estado computado del seguro desde el perfil
      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('insurance_compliant')
        .eq('id', user.id)
        .single();
        
      if (profileError) throw profileError;

      // 2. Verificar estado de los documentos de cumplimiento
      const { data: docs, error: docsError } = await supabase
        .from('compliance_documents')
        .select('is_verified')
        .eq('profile_id', user.id);

      if (docsError) throw docsError;

      // Determinamos si todos los documentos obligatorios están verificados
      const has_docs = docs && docs.length > 0;
      const all_verified = has_docs ? docs.every(d => d.is_verified) : false;

      return {
        insurance_compliant: profile.insurance_compliant,
        is_verified: all_verified
      };
    },
    // FÍSICA APLICADA: Cero caché. El estado de cumplimiento nunca debe guardarse en memoria persistente.
    staleTime: 0,
    gcTime: 0,
    refetchOnMount: 'always',
    refetchOnWindowFocus: true
  });
};

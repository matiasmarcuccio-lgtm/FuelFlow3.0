import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';

// Interfaz que simula el objeto File de Web o DocumentPicker de React Native
export interface DocumentFile {
  name: string;
  type: string;
  size: number;
}

export const useUploadDocument = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ file, docType, expiryDate }: { file: DocumentFile, docType: string, expiryDate: string }) => {
      // 1. FILOSOFÍA FAIL-FAST: Validar tamaño y tipo antes de tocar la red
      const MAX_SIZE = 5 * 1024 * 1024; // 5MB
      if (file.size > MAX_SIZE) {
        throw new Error("El archivo es demasiado pesado. Límite: 5MB.");
      }
      
      if (file.type !== 'application/pdf' && !file.type.includes('image')) {
        throw new Error("Formato inválido. Solo se admiten PDF o imágenes.");
      }
      
      // 2. Subir a Supabase Storage
      const { data: authData, error: authError } = await supabase.auth.getUser();
      if (authError || !authData.user) {
        throw new Error("No hay una sesión válida activa.");
      }

      // Convertir URI a Blob nativamente
      const response = await fetch(file.uri);
      const blob = await response.blob();
      
      const fileExt = file.name.split('.').pop();
      const fileName = `${authData.user.id}/${Date.now()}.${fileExt}`;

      const { data: uploadData, error: uploadError } = await supabase.storage
        .from('compliance_docs')
        .upload(fileName, blob, {
          contentType: file.type,
          upsert: false
        });

      if (uploadError) {
        throw new Error(`Fallo al transferir archivo: ${uploadError.message}`);
      }

      // 3. Registrar el documento subido en la tabla compliance_documents
      const { data, error } = await supabase.from('compliance_documents').insert({
        profile_id: authData.user.id,
        doc_type: docType,
        file_url: uploadData.path,
        expiry_date: expiryDate,
        is_verified: false 
      }).select().single();

      if (error) {
        throw new Error(`Rechazo del servidor forense: ${error.message}`);
      }
      
      return data;
    },
    onSuccess: () => {
      // Invalida el estado inmediatamente para que el ComplianceGuard 
      // fuerce una nueva validación en el próximo render (Cero Caché)
      queryClient.invalidateQueries({ queryKey: ['compliance-status'] });
    }
  });
};

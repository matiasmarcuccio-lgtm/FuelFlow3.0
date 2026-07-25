import React, { useState } from 'react';
import { supabase } from '../../../lib/supabase';
import { ComplianceUploadModalPresenter } from './ComplianceUploadModalPresenter';

interface Props {
  driverId: string;
  driverName: string;
  onSuccess: () => void;
  onCancel: () => void;
}

export const ComplianceUploadModal: React.FC<Props> = ({ driverId, driverName, onSuccess, onCancel }) => {
  const [isUploading, setIsUploading] = useState(false);
  const [isRetrying, setIsRetrying] = useState(false);
  const [networkError, setNetworkError] = useState<string | null>(null);

  const handleUpload = async (file: File, expiryDate: string) => {
    setIsUploading(true);
    setIsRetrying(false);
    setNetworkError(null);

    const fileExt = file.name.split('.').pop();
    const fileName = `${driverId}-${Date.now()}.${fileExt}`;
    const filePath = `insurance/${fileName}`;

    let uploadedPath = '';

    try {
      // 1. Subir al Storage (Privado)
      const { data: uploadData, error: uploadError } = await supabase.storage
        .from('compliance_docs')
        .upload(filePath, file);

      if (uploadError) throw uploadError;
      uploadedPath = uploadData.path;

      // 2. Invocar el Sello Forense Transaccional con Exponential Backoff & Jitter
      const MAX_RETRIES = 5;
      let attempt = 0;
      let success = false;
      let lastRpcError = null;

      while (attempt < MAX_RETRIES && !success) {
        const { error: rpcError } = await supabase.rpc('fn_verify_driver_insurance', {
          p_driver_id: driverId,
          p_expiry_date: expiryDate,
          p_file_path: uploadedPath
        });

        if (rpcError) {
          lastRpcError = rpcError;
          // Si es un timeout de pool, 503 o 504, interceptamos
          if (rpcError.code === 'PGRST003' || rpcError.code === '503' || rpcError.code === '504' || rpcError.message.includes('fetch')) {
            attempt++;
            if (attempt < MAX_RETRIES) {
              setIsRetrying(true);
              // Base delay: 500ms -> Exponential Backoff + Full Jitter (0-500ms)
              const baseDelay = Math.pow(2, attempt - 1) * 500;
              const jitter = Math.random() * 500;
              const waitTime = baseDelay + jitter;
              console.warn(`[Sync] RPC falló (intento ${attempt}). Esperando ${Math.round(waitTime)}ms para reintentar...`);
              await new Promise(resolve => setTimeout(resolve, waitTime));
              continue;
            }
          }
          throw rpcError; // Si no es un error de red o superó los intentos
        }
        success = true;
      }

      if (!success) {
        throw lastRpcError;
      }

      // Éxito total
      onSuccess();

    } catch (err: any) {
      console.error('Error WHS:', err);
      setNetworkError(err.message || 'Error en la validación del sello forense.');
      
      // 3. Mecanismo de Anti-Huérfanos (Rollback)
      if (uploadedPath) {
        console.warn('Ejecutando rollback (Anti-Orphan): Eliminando documento de storage...');
        await supabase.storage.from('compliance_docs').remove([uploadedPath]).catch(e => console.error('Rollback failed:', e));
      }
    } finally {
      setIsUploading(false);
      setIsRetrying(false);
    }
  };

  return (
    <ComplianceUploadModalPresenter
      driverName={driverName}
      isUploading={isUploading}
      isRetrying={isRetrying}
      networkError={networkError}
      onCancel={onCancel}
      onSubmit={handleUpload}
    />
  );
};

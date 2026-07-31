import React, { useState, useEffect, useCallback } from 'react';
import { supabase } from '../../lib/supabase';
import { ExecutionCertificateManager } from './ExecutionCertificateManager';

export const FinancialReconciliationContainer: React.FC = () => {
  const [shifts, setShifts] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedShiftIds, setSelectedShiftIds] = useState<string[]>([]);
  const [generating, setGenerating] = useState(false);

  const fetchCompletedShifts = useCallback(async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('asset_assignments')
        .select(`
          id,
          shift_start,
          shift_end,
          status,
          assets (
            internal_code,
            type,
            operational_cost_per_hour
          ),
          profiles (
            first_name,
            last_name
          )
        `)
        .eq('status', 'completed')
        .is('certificate_id', null);

      if (error) throw error;
      setShifts(data || []);
    } catch (err: any) {
      setError(`Error fetching shifts: ${err.message}`);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchCompletedShifts();
  }, [fetchCompletedShifts]);

  const handleToggleShift = (id: string) => {
    setSelectedShiftIds((prev) => 
      prev.includes(id) ? prev.filter((sid) => sid !== id) : [...prev, id]
    );
  };

  const handleGenerateCertificate = async () => {
    if (selectedShiftIds.length === 0) return;
    
    try {
      setGenerating(true);
      setError(null);
      // Disparamos el arreglo directamente hacia el RPC blindado
      const { data: certificateId, error: rpcError } = await supabase.rpc('fn_generate_execution_certificate', {
          p_assignment_ids: selectedShiftIds,
          p_client_erp_id: 'XERO-HBC-001' // Placeholder dinámico futuro
      });

      if (rpcError) {
          // Renderizar el mensaje de Violación Financiera exacto que escupe Postgres
          throw new Error(rpcError.message);
      }
      
      // Purgar la selección y recargar la consulta para que los turnos desaparezcan instantáneamente de la bandeja
      setSelectedShiftIds([]);
      await fetchCompletedShifts();
      
      alert(`Certificado generado exitosamente: ${certificateId}`);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setGenerating(false);
    }
  };

  return (
    <ExecutionCertificateManager 
      shifts={shifts}
      loading={loading}
      error={error}
      selectedShiftIds={selectedShiftIds}
      onToggleShift={handleToggleShift}
      onGenerate={handleGenerateCertificate}
      generating={generating}
    />
  );
};

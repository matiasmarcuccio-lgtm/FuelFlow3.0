import React, { useState } from 'react';
import { useQuery, useMutation } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';
import { CommandCenterPresenter } from './CommandCenterPresenter';
import { DispatchModalPresenter } from './DispatchModalPresenter';
import { HumanResourcesContainer } from './HumanResourcesContainer';
import type { Operator } from './DispatchModalPresenter';
import { useCommandCenterRealtime } from './useCommandCenterRealtime';

interface CommandCenterContainerProps {
  fleetId: string;
}

export const CommandCenterContainer: React.FC<CommandCenterContainerProps> = ({ fleetId }) => {
  // 1. Acoplar el motor de invalidación WebSocket (construido en la fase anterior)
  useCommandCenterRealtime(fleetId);

  // Estados locales para el manejo del Modal y Tabs
  const [activeTab, setActiveTab] = useState<'tactical' | 'hr' | 'assets'>('tactical');
  const [selectedAssetId, setSelectedAssetId] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // 2. Consulta de Activos (La caché será destruida automáticamente por Realtime)
  const { data: assets = [], isLoading: isLoadingAssets } = useQuery({
    queryKey: ['assets', fleetId],
    queryFn: async () => {
      let query = supabase
        .from('assets')
        .select(`
          id, internal_code, status,
          asset_assignments!left ( id, driver_id, status )
        `)
        .in('asset_assignments.status', ['pending_prestart', 'in_progress']);
        
      if (fleetId && fleetId !== 'default-fleet') {
        query = query.eq('fleet_id', fleetId);
      }
      
      const { data, error } = await query;
        
      if (error) throw new Error(error.message);
      
      // Mapeo al formato del Presentador
      return data.map(asset => ({
        ...asset,
        current_shift: asset.asset_assignments?.[0] ? {
          id: asset.asset_assignments[0].id,
          driver_name: 'Driver Data', // En producción, cruzar con perfiles de usuario
          status: asset.asset_assignments[0].status,
        } : undefined
      }));
    }
  });

  // 3. Consulta de Operadores Disponibles y su Fatiga
  const { data: operators = [] } = useQuery({
    queryKey: ['operators', fleetId],
    queryFn: async () => {
      // Fallback a perfiles ya que el RPC no está disponible en la topología básica
      const { data, error } = await supabase
        .from('profiles')
        .select('id, full_name')
        .in('role', ['operator', 'driver', 'DRIVER']);
        
      if (error) throw new Error(error.message);
      return data.map(d => ({
        id: d.id,
        full_name: d.full_name || 'Operador',
        hours_worked_today: 0 // Mock de fatiga para pruebas de arquitectura
      })) as Operator[];
    }
  });

  // 4. La Mutación Pesimista (Despacho Logístico)
  const dispatchMutation = useMutation({
    mutationFn: async ({ assetId, operatorId, overrideReason }: { assetId: string, operatorId: string, overrideReason?: string }) => {
      const { error } = await supabase
        .from('asset_assignments')
        .insert({
          asset_id: assetId,
          driver_id: operatorId,
          status: 'pending_prestart',
          fatigue_override_reason: overrideReason
        });

      if (error) {
        // Traducción de Errores Duros de PostgreSQL
        if (error.code === '23P01') throw new Error('EXCLUSION_VIOLATION: El operador o la máquina ya están ocupados en este bloque de tiempo.');
        if (error.message.includes('WHS_FATIGUE_LIMIT')) throw new Error('FATIGUE_LIMIT: Justificación insuficiente para saltar el umbral WHS.');
        throw new Error(error.message);
      }
    },
    onSuccess: () => {
      // Éxito: Cerramos el modal. La UI principal se actualizará asíncronamente vía WebSocket.
      setSelectedAssetId(null);
      setErrorMessage(null);
    },
    onError: (error: Error) => {
      setErrorMessage(error.message);
    }
  });

  // 5. Mutación de Revocación (Válvula de Escape)
  const revokeMutation = useMutation({
    mutationFn: async (shiftId: string) => {
      const { error } = await supabase.rpc('revoke_pending_shift', { p_assignment_id: shiftId, p_reason: 'Revocado desde Command Center' });
      if (error) throw error;
    }
  });

  if (isLoadingAssets) return <div className="text-white p-6 font-mono text-xl">SINCRONIZANDO TELEMETRÍA...</div>;

  return (
    <div className="min-h-screen bg-slate-950 flex flex-col font-sans select-none text-foreground">
      {/* Tab Navigation */}
      <div className="bg-slate-900 border-b border-slate-800 p-4 flex gap-4">
        <button
          onClick={() => setActiveTab('tactical')}
          className={`px-4 py-2 rounded-lg font-bold text-sm uppercase tracking-wider transition-colors ${
            activeTab === 'tactical' ? 'bg-blue-600 text-white' : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
          }`}
        >
          Tactical Dispatch
        </button>
        <button
          onClick={() => setActiveTab('hr')}
          className={`px-4 py-2 rounded-lg font-bold text-sm uppercase tracking-wider transition-colors ${
            activeTab === 'hr' ? 'bg-blue-600 text-white' : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
          }`}
        >
          Human Resources
        </button>
        <button
          onClick={() => setActiveTab('assets')}
          className={`px-4 py-2 rounded-lg font-bold text-sm uppercase tracking-wider transition-colors ${
            activeTab === 'assets' ? 'bg-blue-600 text-white' : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
          }`}
        >
          Asset Management
        </button>
      </div>

      <div className="flex-1 p-6">
        {errorMessage && (
          <div className="bg-red-900 text-white p-4 text-center font-bold font-mono border-b border-red-700 mb-6 rounded-lg">
            ERROR TRANSACCIONAL: {errorMessage}
          </div>
        )}

        {activeTab === 'tactical' && (
          <CommandCenterPresenter 
            assets={assets}
            isMutating={dispatchMutation.isPending || revokeMutation.isPending}
            onInitiateDispatch={(assetId) => setSelectedAssetId(assetId)}
            onRevokeDispatch={(shiftId) => revokeMutation.mutate(shiftId)}
          />
        )}

        {activeTab === 'hr' && (
          <HumanResourcesContainer fleetId={fleetId} />
        )}

        {activeTab === 'assets' && (
          <div className="text-slate-400 text-center mt-20">Asset Management Module under construction...</div>
        )}

        {selectedAssetId && activeTab === 'tactical' && (
          <DispatchModalPresenter 
            assetCode={assets.find(a => a.id === selectedAssetId)?.internal_code || 'DESC'}
            operators={operators}
            isSubmitting={dispatchMutation.isPending}
            fatigueThreshold={10}
            hardLimit={12}
            onConfirm={(operatorId, overrideReason) => 
              dispatchMutation.mutate({ assetId: selectedAssetId, operatorId, overrideReason })
            }
            onCancel={() => {
              setSelectedAssetId(null);
              setErrorMessage(null);
            }}
          />
        )}
      </div>
    </div>
  );
};

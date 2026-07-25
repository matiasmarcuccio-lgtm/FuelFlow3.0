import React, { useState, useEffect, useCallback } from 'react';
import { supabase } from '../../lib/supabase';
import { enqueueRpcPayload } from '../../lib/offlineVault';
import { useSyncEngine } from '../../hooks/useSyncEngine';

interface DispatchKioskProps {
  assetId: string;
  assetName: string;
}

export const DispatchKiosk: React.FC<DispatchKioskProps> = ({ assetId, assetName }) => {
  const [cycleState, setCycleState] = useState<'IDLE' | 'LOADING' | 'HAULING' | 'RETURNING'>('IDLE');

  // Extraemos la telemetría de red y sincronización
  const { isOnline, syncing, pendingCount, flushOutbox } = useSyncEngine();

  const [dailyTonnage, setDailyTonnage] = useState(0);
  const [cycleCount, setCycleCount] = useState(0);

  const [selectedRoute, setSelectedRoute] = useState('a1b2c3d4-0000-0000-0000-000000000001');
  const [selectedMaterial, setSelectedMaterial] = useState('e5f6a7b8-0000-0000-0000-000000000001');

  // Inicialización (Intentamos consultar el servidor, si falla por red, nos quedamos con el estado actual en memoria)
  const checkCurrentCycle = useCallback(async () => {
    if (!isOnline) return;
    try {
      const { data, error } = await supabase
        .from('haul_cycles')
        .select('state, tonnage_moved')
        .eq('asset_id', assetId)
        .not('state', 'in', '("COMPLETED","ABORTED")')
        .maybeSingle();

      if (!error && data) setCycleState(data.state as any);
    } catch (err) {
      console.warn('Lectura fallida. Manteniendo estado local.');
    }
  }, [assetId, isOnline]);

  useEffect(() => { checkCurrentCycle(); }, [checkCurrentCycle]);

  // DISPARADOR OPTIMISTA E INYECCIÓN EN CAJA NEGRA (INDEXEDDB)
  const executeOptimisticTransition = async (action: 'START_LOADING' | 'FINISH_LOADING' | 'CONFIRM_DUMP' | 'COMPLETE_CYCLE' | 'ABORT') => {
    // 1. Mutación Optimista del DOM: Respuesta inmediata (1ms) al conductor, tenga internet o no.
    if (action === 'START_LOADING') setCycleState('LOADING');
    if (action === 'FINISH_LOADING') setCycleState('HAULING');
    if (action === 'CONFIRM_DUMP') setCycleState('RETURNING');
    if (action === 'COMPLETE_CYCLE') {
      setCycleState('IDLE');
      setDailyTonnage(prev => prev + 32.4); // Estimado optimista local
      setCycleCount(prev => prev + 1);
    }
    if (action === 'ABORT') setCycleState('IDLE');

    // 2. Acopio Local (Store)
    const payload = {
      p_asset_id: assetId,
      p_action: action,
      p_route_id: action === 'START_LOADING' ? selectedRoute : undefined,
      p_material_id: action === 'START_LOADING' ? selectedMaterial : undefined,
      // La marca de tiempo se inyecta dentro de enqueueRpcPayload automáticamente
    };

    await enqueueRpcPayload('fn_execute_haul_transition', payload);

    // 3. Intento de Reenvío inmediato si hay señal (Forward)
    if (isOnline) flushOutbox();
  };

  return (
    <div className="flex flex-col h-full w-full max-w-2xl mx-auto p-4 md:p-6 text-white select-none">
      {/* Cabecera de Telemetría + HUD De Señal 4G */}
      <header className="flex justify-between items-center border-b border-slate-800 pb-4">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className={`w-3 h-3 rounded-full ${isOnline ? 'bg-emerald-500 animate-ping' : 'bg-red-500'}`}></span>
            <span className={`font-mono text-[10px] font-black uppercase rounded px-2 py-0.5 ${
              isOnline ? 'bg-emerald-950/50 text-emerald-400' : 'bg-red-950/50 text-red-400 border border-red-800'
            }`}>
              {isOnline ? 'EN LÍNEA (4G)' : 'OFFLINE • MODO FOSA'}
            </span>
          </div>
          <h3 className="text-xl font-black uppercase text-white mt-1">
            {assetName}
          </h3>
        </div>

        <div className="text-right font-mono">
          <p className="text-[10px] text-slate-500 uppercase font-bold">Producción (Local)</p>
          <p className="text-2xl font-black text-emerald-400">{dailyTonnage.toFixed(1)} t</p>
          {pendingCount > 0 && (
            <p className="text-[9px] text-amber-400 font-bold bg-amber-950/30 px-2 py-0.5 rounded animate-pulse uppercase">
              {pendingCount} PAQUETES RETENIDOS
            </p>
          )}
        </div>
      </header>

      {/* CUERPO CENTRAL (LA MÁQUINA DE ESTADO RESPONDE INCLUSO SIN WIFI) */}
      <main className="my-auto py-4 flex flex-col items-center justify-center">
        {cycleState === 'IDLE' && (
          <div className="w-full text-center">
            <p className="font-mono text-xs text-slate-400 uppercase mb-4">Seleccione material en rampa:</p>
            <div className="grid grid-cols-2 gap-3 mb-6 font-mono text-xs">
              <button
                onClick={() => setSelectedMaterial('e5f6a7b8-0000-0000-0000-000000000001')}
                className={`py-4 rounded-xl font-bold border-2 transition-all ${selectedMaterial === 'e5f6a7b8-0000-0000-0000-000000000001' ? 'bg-blue-600 border-blue-400 text-white' : 'bg-slate-900 border-slate-800 text-slate-400'}`}
              >🪨 GRAVA</button>
              <button
                onClick={() => setSelectedMaterial('e5f6a7b8-0000-0000-0000-000000000002')}
                className={`py-4 rounded-xl font-bold border-2 transition-all ${selectedMaterial === 'e5f6a7b8-0000-0000-0000-000000000002' ? 'bg-amber-600 border-amber-400 text-black' : 'bg-slate-900 border-slate-800 text-slate-400'}`}
              >⚠️ ESTÉRIL</button>
            </div>
            <button
              onClick={() => executeOptimisticTransition('START_LOADING')}
              className="w-full h-36 bg-blue-600 active:scale-95 text-white rounded-3xl font-black text-2xl uppercase shadow-2xl flex flex-col items-center justify-center gap-2 border-4 border-blue-400"
            >
              <span className="text-4xl">🏗️</span><span>ENTRAR A COLA</span>
            </button>
          </div>
        )}

        {cycleState === 'LOADING' && (
          <button
            onClick={() => executeOptimisticTransition('FINISH_LOADING')}
            className="w-full h-56 bg-amber-500 active:scale-95 text-black rounded-3xl font-black text-3xl uppercase shadow-2xl flex flex-col items-center justify-center gap-3 border-4 border-amber-300 animate-pulse"
          >
            <span className="text-6xl">🚛</span><span>✅ TOLVA LLENA</span>
          </button>
        )}

        {cycleState === 'HAULING' && (
          <button
            onClick={() => executeOptimisticTransition('CONFIRM_DUMP')}
            className="w-full h-56 bg-purple-600 active:scale-95 text-white rounded-3xl font-black text-3xl uppercase shadow-2xl flex flex-col items-center justify-center gap-3 border-4 border-purple-400"
          >
            <span className="text-6xl">🛑</span><span>VACIAR MATERIAL</span>
          </button>
        )}

        {cycleState === 'RETURNING' && (
          <button
            onClick={() => executeOptimisticTransition('COMPLETE_CYCLE')}
            className="w-full h-56 bg-emerald-600 active:scale-95 text-black rounded-3xl font-black text-3xl uppercase shadow-2xl flex flex-col items-center justify-center gap-3 border-4 border-emerald-400"
          >
            <span className="text-6xl">🔄</span><span>CERRAR CICLO</span>
          </button>
        )}
      </main>

      <footer className="border-t border-slate-800 pt-3 flex justify-between items-center font-mono text-[10px] text-slate-500 uppercase">
        <span>Estado: <strong className="text-white">{cycleState}</strong></span>
        {syncing && <span className="text-blue-400 animate-pulse">Sincronizando caja negra...</span>}
      </footer>
    </div>
  );
};

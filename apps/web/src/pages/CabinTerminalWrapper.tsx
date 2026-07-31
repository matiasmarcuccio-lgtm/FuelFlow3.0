import React, { useState, useEffect, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { OperatorJoinScreen } from './OperatorJoinScreen';
import { PreStartPinScreen } from './PreStartPinScreen';
import { PreStartKiosk } from './PreStartKiosk';
import { CabinShiftHUD } from '../features/compliance/CabinShiftHUD';
import { DispatchKiosk } from '../features/dispatch/DispatchKiosk';
import { FuelFlowModal } from '../features/fuelflow/FuelFlowModal';

type TerminalMode = 
  | 'INITIALIZING' 
  | 'ENROLLMENT_REQUIRED' 
  | 'PIN_REQUIRED' 
  | 'WAITING_DISPATCH'
  | 'PRESTART_REQUIRED' 
  | 'OPERATIONS_ACTIVE' 
  | 'SYSTEM_ERROR';


interface AssetData {
  id: string;
  internal_code: string;
  status: string;
  current_engine_hours: number;
}

const VAULT_KEY = 'jitsite_device_vault_uid';
const ASSET_VAULT_KEY = 'jitsite_device_asset_id';

export const CabinTerminalWrapper: React.FC = () => {
  const [mode, setMode] = useState<TerminalMode>('INITIALIZING');
  const [operatorName, setOperatorName] = useState<string>('OPERARIO');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [assignedAsset, setAssignedAsset] = useState<AssetData | null>(null);
  const [assignmentId, setAssignmentId] = useState<string | null>(null);

  // ESTADO RAÍZ PARA EL MODAL DE REPOSTAJE (ACCESIBLE EN CUALQUIER MODO OPERATIVO)
  const [isFuelModalOpen, setIsFuelModalOpen] = useState<boolean>(false);

  const evaluateTerminalState = useCallback(async () => {
    setMode('INITIALIZING');
    setErrorMessage(null);

    try {
      const { data: { session }, error: sessionError } = await supabase.auth.getSession();
      if (sessionError) throw new Error(`Fallo criptográfico local: ${sessionError.message}`);

      if (!session) {
        const vaultedUid = localStorage.getItem(VAULT_KEY);
        if (!vaultedUid) {
          setMode('ENROLLMENT_REQUIRED');
          return;
        }
        setMode('ENROLLMENT_REQUIRED');
        return;
      }

      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('id, full_name, fleet_id, role')
        .eq('id', session.user.id)
        .maybeSingle();

      if (profileError) throw new Error(`Error de lectura en Capa 0: ${profileError.message}`);
      if (!profile || !profile.fleet_id) {
        setMode('ENROLLMENT_REQUIRED');
        return;
      }

      localStorage.setItem(VAULT_KEY, profile.id);
      const fullName = (profile.full_name || 'Operario').trim();
      setOperatorName(fullName.toUpperCase());

      // NO MÁS BÓVEDAS LOCALES. La asignación depende de la orden transaccional del despachador.
      const { data: assignmentData, error: assignmentErr } = await supabase
        .from('asset_assignments')
        .select(`
          id, 
          status, 
          asset_id,
          assets ( id, internal_code, status, current_engine_hours )
        `)
        .eq('driver_id', profile.id)
        .in('status', ['DISPATCHED', 'IN_PROGRESS'])
        .maybeSingle();
      
      if (assignmentErr) throw new Error(`Error leyendo la matriz de despacho: ${assignmentErr.message}`);

      if (assignmentData && assignmentData.assets) {
        // Ignoramos el error de tipo de Supabase para assets.
        const assetObj: any = assignmentData.assets;
        setAssignedAsset({
          id: assetObj.id,
          internal_code: assetObj.internal_code,
          status: assetObj.status,
          current_engine_hours: Number(assetObj.current_engine_hours || 0)
        });
        setAssignmentId(assignmentData.id);
      } else {
        setAssignedAsset(null);
        setAssignmentId(null);
      }

      setMode('PIN_REQUIRED');

    } catch (err: any) {
      console.error('🛑 FRACTURA EN EL ENRUTADOR DE CABINA:', err);
      setErrorMessage(err.message || 'Error de sincronización con el Command Center.');
      setMode('SYSTEM_ERROR');
    }
  }, []);

  useEffect(() => {
    evaluateTerminalState();
  }, [evaluateTerminalState]);

  // MANEJADORES DE TRANSICIÓN INDUSTRIAL
  const handleEnrollmentComplete = () => evaluateTerminalState();
  const handlePinAuthorized = () => {
    // Post-PIN, verificamos si tenemos turno y en qué estado.
    if (!assignedAsset || !assignmentId) {
      setMode('WAITING_DISPATCH');
      return;
    }
    // Si tenemos asignación, miramos su estado (que leímos en evaluateTerminalState)
    // Nota: Como no tenemos el estado de la asignación suelto, lo inferiremos o lo guardaremos.
    // Pequeño workaround: Si llegamos aquí y es DISPATCHED, vamos a PRESTART. 
    // Para simplificar, siempre vamos a PRESTART si tenemos asset (el Kiosko decidirá).
    // Mejor aún, agreguemos el chequeo explícito aquí.
    supabase
        .from('asset_assignments')
        .select('status')
        .eq('id', assignmentId)
        .single()
        .then(({ data }) => {
            if (data?.status === 'DISPATCHED') setMode('PRESTART_REQUIRED');
            else if (data?.status === 'IN_PROGRESS') setMode('OPERATIONS_ACTIVE');
            else setMode('WAITING_DISPATCH');
        });
  };
  
  const handlePreStartCompleted = (passed: boolean) => {
    if (passed) {
      setMode('OPERATIONS_ACTIVE');
    } else {
      setErrorMessage('MAQUINARIA ENCLAVADA (LOTO APLICADO). La máquina ha sido inhabilitada por defecto crítico en terreno.');
      setMode('SYSTEM_ERROR');
    }
  };

  const handleShiftTerminated = () => setMode('PIN_REQUIRED');

  // MANEJADOR DE ACTUALIZACIÓN POST-REPOSTAJE (SINCRONIZACIÓN EN MEMORIA)
  const handleFuelLoggedSuccess = (payload: any) => {
    console.debug('⚡ Repostaje sellado en WORM. Actualizando horómetro en memoria:', payload);
    if (assignedAsset && payload.hours_elapsed !== undefined) {
      // El horómetro avanza al nuevo valor firmado por el operario
      setAssignedAsset((prev) => prev ? {
        ...prev,
        current_engine_hours: prev.current_engine_hours + Number(payload.hours_elapsed)
      } : null);
    }
  };

  if (mode === 'INITIALIZING') {
    return (
      <div className="min-h-screen bg-black flex flex-col items-center justify-center p-6 select-none font-mono text-white">
        <div className="w-16 h-16 border-4 border-blue-600 border-t-transparent rounded-full animate-spin mb-6"></div>
        <p className="text-sm font-bold tracking-widest uppercase text-slate-400">
          SINCRONIZANDO TERMINAL CON CAPA 0...
        </p>
        <p className="text-[10px] text-slate-600 mt-2 uppercase">JITSite Zero-Trust Architecture</p>
      </div>
    );
  }

  if (mode === 'SYSTEM_ERROR') {
    return (
      <div className="min-h-screen bg-black flex flex-col items-center justify-center p-6 select-none font-sans text-white text-center">
        <div className="bg-red-950/40 border-4 border-red-600 p-8 rounded-3xl max-w-md w-full shadow-2xl">
          <div className="text-5xl mb-4">🛑</div>
          <h2 className="text-2xl font-black uppercase tracking-tight mb-2">Fallo de Aduana</h2>
          <p className="font-mono text-xs text-red-400 uppercase mb-6 break-words">{errorMessage}</p>
          <button
            onClick={evaluateTerminalState}
            className="w-full bg-slate-800 hover:bg-slate-700 text-white font-black py-4 rounded-xl uppercase tracking-widest text-xs transition-colors border border-slate-600 shadow-lg"
          >
            🔄 REINTENTAR CONEXIÓN SATELITAL
          </button>
        </div>
      </div>
    );
  }

  if (mode === 'ENROLLMENT_REQUIRED') {
    return <OperatorJoinScreen onEnrollmentComplete={handleEnrollmentComplete} />;
  }

  if (mode === 'PIN_REQUIRED') {
    return <PreStartPinScreen operatorName={operatorName} onAuthorized={handlePinAuthorized} />;
  }

  if (mode === 'WAITING_DISPATCH') {
    return (
      <div className="min-h-screen bg-slate-950 flex flex-col items-center justify-center p-6 text-center font-mono">
        <div className="w-16 h-16 border-4 border-slate-700 border-t-amber-500 rounded-full animate-spin mb-8"></div>
        <h2 className="text-2xl font-bold text-amber-500 tracking-widest uppercase mb-4">Aguardando Órdenes</h2>
        <p className="text-slate-400 text-sm max-w-md">No posee ningún despacho activo. Por favor aguarde la orden de la Romana o Despacho central. La terminal se activará automáticamente.</p>
        
        <button onClick={() => window.location.reload()} className="mt-12 text-[10px] text-slate-600 hover:text-slate-400 border border-slate-800 px-4 py-2 uppercase">
          Forzar Sincronización Manual
        </button>
      </div>
    );
  }

  if (mode === 'PRESTART_REQUIRED' && assignedAsset && assignmentId) {
    return (
      <PreStartKiosk
        operatorName={operatorName}
        assignmentId={assignmentId}
        assetId={assignedAsset.id}
        assetName={assignedAsset.internal_code}
        onPreStartCompleted={handlePreStartCompleted}
      />
    );
  }

  // GRILLA OPERATIVA DEFINITIVA (CONDUCTO 1 + CONDUCTO 2 + CONDUCTO 3)
  return (
    <div className="min-h-screen bg-black text-white p-4 md:p-6 font-sans select-none flex flex-col justify-between overflow-x-hidden relative">
      
      {/* MÓDULO SUPERIOR: RELOJ BIOLÓGICO Y FATIGA WHS (CONDUCTO 1) */}
      <section className="w-full max-w-5xl mx-auto">
        {assignedAsset && assignmentId && (
          <CabinShiftHUD 
            assetId={assignedAsset.id} 
            assignmentId={assignmentId}
            onShiftTerminated={handleShiftTerminated} 
          />
        )}
      </section>

      {/* MÓDULO INFERIOR: KIOSCO LOGÍSTICO DE DESPACHO Y ACARREO (CONDUCTO 2) */}
      <main className="w-full max-w-5xl mx-auto flex-1 flex flex-col justify-center my-2">
        {assignedAsset ? (
          <DispatchKiosk 
            assetId={assignedAsset.id} 
            assetName={assignedAsset.internal_code} 
          />
        ) : (
          <div className="p-12 text-center font-mono text-red-500 bg-red-950/20 border-2 border-red-800 rounded-3xl">
            ⚠️ ERROR INTERNO: TERMINAL SIN ASSET ASIGNADO EN LA BÓVEDA LOCAL.
          </div>
        )}
      </main>

      {/* BARRA DE ACCIÓN UNIVERSAL Y PIE OPERATIVO (CONDUCTO 3) */}
      <footer className="w-full max-w-5xl mx-auto border-t-2 border-slate-800 pt-4 mt-2 flex flex-col md:flex-row justify-between items-center gap-4 font-mono">
        
        {/* Indicador de hardware e identidad */}
        <div className="flex items-center gap-3 text-xs text-slate-400 uppercase">
          <span>🚜 HORÓMETRO: <strong className="text-emerald-400">{assignedAsset?.current_engine_hours.toFixed(1)} h</strong></span>
          <span>•</span>
          <span>TERMINAL: {localStorage.getItem(VAULT_KEY)?.slice(0, 8)}</span>
        </div>

        {/* BOTONERA TÁCTIL DE ACCIÓN INTER-CONDUCTOS */}
        <div className="flex items-center gap-3 w-full md:w-auto">
          <button
            type="button"
            onClick={() => setIsFuelModalOpen(true)}
            className="flex-1 md:flex-initial bg-blue-600 hover:bg-blue-500 text-white font-black px-6 py-3.5 rounded-xl uppercase tracking-widest text-xs shadow-lg shadow-blue-600/30 transition-all flex items-center justify-center gap-2 border border-blue-400 active:scale-95 animate-pulse"
          >
            <span>⛽ REPOSTAR COMBUSTIBLE</span>
          </button>

          <button
            type="button"
            onClick={() => setMode('PIN_REQUIRED')}
            className="bg-slate-900 hover:bg-slate-800 text-amber-500 hover:text-amber-400 font-bold px-4 py-3.5 rounded-xl uppercase text-xs border border-slate-700 transition-all"
          >
            🔒 BLOQUEAR
          </button>
        </div>
      </footer>

      {/* INYECCIÓN DEL MODAL DE COMBUSTIBLE EN EL NIVEL RAÍZ */}
      {assignedAsset && (
        <FuelFlowModal
          isOpen={isFuelModalOpen}
          onClose={() => setIsFuelModalOpen(false)}
          assetId={assignedAsset.id}
          assetName={assignedAsset.name}
          currentEngineHours={assignedAsset.current_engine_hours}
          onFuelLogged={handleFuelLoggedSuccess}
        />
      )}
    </div>
  );
};

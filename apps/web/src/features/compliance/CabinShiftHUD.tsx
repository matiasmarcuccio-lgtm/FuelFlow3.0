import React, { useState, useEffect, useCallback } from 'react';
import { supabase } from '../../lib/supabase';

interface CabinShiftHUDProps {
  assetId: string;
  onShiftTerminated: () => void;
}

interface ShiftStatusPayload {
  success: boolean;
  status: 'ACTIVE' | 'ON_BREAK' | 'COMPLETED' | 'FATIGUE_LOCKOUT' | 'NO_ACTIVE_SHIFT';
  shift_id?: string;
  continuous_work_seconds?: number;
  accumulated_work_seconds?: number;
  seconds_until_break_required?: number;
  seconds_until_shift_end?: number;
  current_break_duration?: number;
  min_legal_break_seconds?: number;
  msg?: string;
}

export const CabinShiftHUD: React.FC<CabinShiftHUDProps> = ({ assetId, onShiftTerminated }) => {
  const [shiftState, setShiftState] = useState<ShiftStatusPayload | null>(null);
  const [isExecuting, setIsExecuting] = useState<boolean>(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  // 1. SINCRONIZACIÓN SATELITAL CON CAPA 0 (POLLING FORENSE)
  const syncShiftWithLayerZero = useCallback(async () => {
    try {
      const { data, error } = await supabase.rpc('fn_execute_shift_action', {
        p_action: 'CHECK_STATUS',
        p_asset_id: assetId,
      });

      if (error) throw new Error(error.message);
      const payload = data as ShiftStatusPayload;
      
      setShiftState(payload);
      setErrorMsg(null);
    } catch (err: any) {
      console.error('🛑 FRACTURA DE TELEMETRÍA BIOLÓGICA:', err);
      setErrorMsg(err.message || 'Error de sincronización con el reloj WHS.');
    }
  }, [assetId]);

  useEffect(() => {
    syncShiftWithLayerZero();
    // Interrogar al servidor cada 15 segundos para evitar evasión por reloj local
    const interval = setInterval(syncShiftWithLayerZero, 15000);
    return () => clearInterval(interval);
  }, [syncShiftWithLayerZero]);

  // 2. DISPARO DE ACCIONES BIOLÓGICAS
  const executeAction = async (action: 'START_SHIFT' | 'START_BREAK' | 'END_BREAK' | 'END_SHIFT') => {
    if (isExecuting) return;
    setIsExecuting(true);
    setErrorMsg(null);

    try {
      const { data, error } = await supabase.rpc('fn_execute_shift_action', {
        p_action: action,
        p_asset_id: assetId,
      });

      if (error) throw new Error(error.message);
      const payload = data as ShiftStatusPayload;

      if (action === 'END_SHIFT' || payload.status === 'COMPLETED') {
        onShiftTerminated();
        return;
      }

      await syncShiftWithLayerZero();
    } catch (err: any) {
      setErrorMsg(`RECHAZO DE ADUANA: ${err.message}`);
    } finally {
      setIsExecuting(false);
    }
  };

  // Formateador de tiempo militar (HH:MM:SS)
  const formatTime = (totalSeconds?: number) => {
    if (totalSeconds === undefined || totalSeconds < 0) return '00:00:00';
    const hrs = Math.floor(totalSeconds / 3600).toString().padStart(2, '0');
    const mins = Math.floor((totalSeconds % 3600) / 60).toString().padStart(2, '0');
    const secs = (totalSeconds % 60).toString().padStart(2, '0');
    return `${hrs}:${mins}:${secs}`;
  };

  if (!shiftState || shiftState.status === 'NO_ACTIVE_SHIFT') {
    return (
      <div className="bg-slate-900 border-2 border-blue-600 p-6 rounded-3xl text-center shadow-2xl mb-6 select-none">
        <div className="flex items-center justify-center gap-3 mb-4">
          <span className="text-3xl">⏱️</span>
          <h2 className="text-xl font-black uppercase tracking-tight text-white font-mono">
            Reloj Biológico WHS Desconectado
          </h2>
        </div>
        <p className="text-xs font-mono text-slate-400 uppercase mb-6">
          La legislación minera prohíbe el movimiento de tierra sin un registro de fatiga activo.
        </p>
        <button
          onClick={() => executeAction('START_SHIFT')}
          disabled={isExecuting}
          className="w-full md:w-auto px-8 py-5 bg-blue-600 hover:bg-blue-500 text-white font-black rounded-2xl uppercase tracking-widest text-sm shadow-xl transition-all"
        >
          {isExecuting ? 'SELLERANDO LIBRO MAYOR...' : '▶️ INICIAR JORNADA LABORAL WHS'}
        </button>
      </div>
    );
  }

  // GUILLOTINA DE BLOQUEO POR FATIGA (PANTALLA INFRANQUEABLE)
  if (shiftState.status === 'FATIGUE_LOCKOUT') {
    return (
      <div className="fixed inset-0 z-50 bg-red-950/95 backdrop-blur-xl flex flex-col items-center justify-center p-6 text-center select-none border-8 border-red-600 animate-pulse">
        <div className="text-8xl mb-6">🛑</div>
        <h1 className="text-4xl md:text-6xl font-black uppercase tracking-tight text-white mb-4">
          Bloqueo Legal por Fatiga
        </h1>
        <p className="text-lg md:text-xl font-mono font-bold text-red-300 max-w-2xl bg-black/60 p-6 rounded-2xl border border-red-600 mb-8">
          HA EXCEDIDO EL LÍMITE DE CONDUCCIÓN CONTINUA BAJO LA NORMATIVA DE WORKSAFE TASMANIA. SU MAQUINARIA HA CAMBIADO A ESTADO <span className="underline text-white">OUT_OF_SERVICE</span>.
        </p>
        <p className="font-mono text-xs text-slate-400 uppercase mb-8">
          TIEMPO AL VOLANTE REGISTRADO: <strong className="text-white text-base">{formatTime(shiftState.continuous_work_seconds)}</strong>
        </p>
        <button
          onClick={() => executeAction('END_SHIFT')}
          disabled={isExecuting}
          className="bg-black hover:bg-slate-900 text-red-500 border-2 border-red-600 font-black px-8 py-6 rounded-2xl uppercase tracking-widest text-sm shadow-2xl transition-all"
        >
          ⏹️ FIRMAR CIERRE DE JORNADA Y APAGAR TERMINAL
        </button>
      </div>
    );
  }

  // ESCLUSA DE DESCANSO WHS (BLOQUEO TEMPORAL HASTA CUMPLIR 30 MIN)
  if (shiftState.status === 'ON_BREAK') {
    const breakDur = shiftState.current_break_duration || 0;
    const minBreak = shiftState.min_legal_break_seconds || 1800;
    const canResume = breakDur >= minBreak;
    const remainingBreak = Math.max(0, minBreak - breakDur);

    return (
      <div className="bg-emerald-950/40 border-4 border-emerald-500 p-6 md:p-8 rounded-3xl text-center shadow-2xl mb-6 select-none animate-fade-in">
        <div className="flex items-center justify-center gap-3 mb-2">
          <span className="text-4xl animate-bounce">☕</span>
          <span className="bg-emerald-500 text-black font-mono text-xs font-black px-3 py-1 uppercase rounded tracking-widest">
            DESCANSO OBLIGATORIO EN CURSO
          </span>
        </div>
        <h2 className="text-3xl font-black uppercase tracking-tight text-white mt-2 mb-4">
          Pausa de Recuperación Biológica
        </h2>
        
        <div className="bg-black/60 border border-emerald-500/30 p-6 rounded-2xl max-w-md mx-auto mb-6">
          <p className="font-mono text-xs text-slate-400 uppercase mb-1">Tiempo de Descanso Transcurrido:</p>
          <p className="font-mono text-4xl font-black text-emerald-400">{formatTime(breakDur)}</p>
          
          {!canResume && (
            <p className="font-mono text-[11px] text-amber-400 font-bold mt-3 uppercase border-t border-slate-800 pt-3 animate-pulse">
              ⚠️ REINICIO DE RELOJ LEGAL EN: {formatTime(remainingBreak)}
              <br />
              <span className="text-[9px] text-slate-500">Si retoma antes, el reloj de 5 horas continuas no se reiniciará.</span>
            </p>
          )}
        </div>

        <div className="flex justify-center gap-4">
          <button
            onClick={() => executeAction('END_BREAK')}
            disabled={isExecuting}
            className={`px-8 py-5 rounded-2xl font-black uppercase tracking-widest text-sm shadow-xl transition-all ${
              canResume
                ? 'bg-emerald-500 hover:bg-emerald-400 text-black animate-bounce'
                : 'bg-slate-800 text-slate-300 hover:bg-slate-700 border border-slate-600'
            }`}
          >
            {canResume ? '▶️ RETOMAR TURNO OPERATIVO (RELOJ REINICIADO)' : '▶️ FORZAR RETORNO PREMATURO AL VOLANTE'}
          </button>
        </div>
      </div>
    );
  }

  // HUD PRINCIPAL DE CABINA (JORNADA ACTIVA)
  const isNearFatigue = (shiftState.seconds_until_break_required || 0) < 1800; // Alerta 30 min antes

  return (
    <div className={`bg-slate-950 border-2 ${isNearFatigue ? 'border-amber-500 bg-amber-950/10' : 'border-slate-800'} p-5 rounded-3xl shadow-2xl mb-6 select-none transition-colors`}>
      
      {/* Barra de Título y Alarmas */}
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-3 border-b border-slate-800 pb-4 mb-4">
        <div className="flex items-center gap-2">
          <span className="w-3 h-3 bg-emerald-500 rounded-full animate-ping"></span>
          <span className="font-mono text-xs font-black uppercase tracking-widest text-white">
            TURNO ACTIVO • TELEMETRÍA WHS TASMANIA
          </span>
        </div>

        {isNearFatigue && (
          <span className="bg-amber-500 text-black font-mono text-[10px] font-black px-3 py-1 rounded uppercase tracking-wider animate-pulse">
            ⚠️ APROXIMACIÓN A LÍMITE DE CONDUCCIÓN — SOLICITE RELEVO
          </span>
        )}
      </div>

      {/* Relojes Biológicos Gemelos */}
      <div className="grid grid-cols-2 gap-4 mb-6 text-center font-mono">
        <div className="bg-slate-900 border border-slate-800 p-4 rounded-2xl">
          <p className="text-[10px] text-slate-500 uppercase font-bold mb-1">Conducción Continua (Máx 5h)</p>
          <p className={`text-2xl md:text-3xl font-black ${isNearFatigue ? 'text-amber-400 animate-pulse' : 'text-blue-400'}`}>
            {formatTime(shiftState.continuous_work_seconds)}
          </p>
          <p className="text-[9px] text-slate-600 mt-1 uppercase">
            Restante: {formatTime(shiftState.seconds_until_break_required)}
          </p>
        </div>

        <div className="bg-slate-900 border border-slate-800 p-4 rounded-2xl">
          <p className="text-[10px] text-slate-500 uppercase font-bold mb-1">Jornada Acumulada (Máx 12h)</p>
          <p className="text-2xl md:text-3xl font-black text-white">
            {formatTime(shiftState.accumulated_work_seconds)}
          </p>
          <p className="text-[9px] text-slate-600 mt-1 uppercase">
            Restante: {formatTime(shiftState.seconds_until_shift_end)}
          </p>
        </div>
      </div>

      {/* Botonera Táctil de Mando */}
      <div className="grid grid-cols-2 gap-3">
        <button
          onClick={() => executeAction('START_BREAK')}
          disabled={isExecuting}
          className="bg-amber-600 hover:bg-amber-500 text-black font-black py-4 rounded-xl uppercase tracking-widest text-xs shadow-lg transition-all flex items-center justify-center gap-2"
        >
          <span>☕ INICIAR DESCANSO WHS</span>
        </button>

        <button
          onClick={() => {
            if (window.confirm('¿Confirma el cierre definitivo de su jornada laboral de hoy?')) {
              executeAction('END_SHIFT');
            }
          }}
          disabled={isExecuting}
          className="bg-slate-900 hover:bg-red-950/50 text-slate-400 hover:text-red-400 border border-slate-800 hover:border-red-800 font-bold py-4 rounded-xl uppercase tracking-widest text-xs transition-all"
        >
          ⏹️ FINALIZAR JORNADA
        </button>
      </div>

      {errorMsg && (
        <p className="mt-3 text-[10px] font-mono text-red-400 uppercase text-center bg-red-950/40 py-1.5 rounded border border-red-900">
          ⚠️ {errorMsg}
        </p>
      )}
    </div>
  );
};

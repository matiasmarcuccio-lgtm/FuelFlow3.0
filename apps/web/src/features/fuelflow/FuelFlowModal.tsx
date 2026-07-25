import React, { useState } from 'react';
import { supabase } from '../../lib/supabase';

interface FuelFlowModalProps {
  isOpen: boolean;
  onClose: () => void;
  assetId: string;
  assetName: string;
  currentEngineHours: number;
  onFuelLogged: (payload: any) => void;
}

interface FuelRpcResponse {
  success: boolean;
  status: 'VERIFIED' | 'ANOMALY_HIGH_BURN' | 'ANOMALY_IDLE_BURN' | 'THEFT_SUSPECTED';
  liters_filled: number;
  total_cost: number;
  burn_rate_lph: number;
  hours_elapsed: number;
  tonnage_cross_ref: number;
  timestamp: string;
}

export const FuelFlowModal: React.FC<FuelFlowModalProps> = ({
  isOpen,
  onClose,
  assetId,
  assetName,
  currentEngineHours,
  onFuelLogged,
}) => {
  const [activeField, setActiveField] = useState<'HOURS' | 'LITERS'>('HOURS');
  const [hoursInput, setHoursInput] = useState<string>(currentEngineHours.toString());
  const [litersInput, setLitersInput] = useState<string>('');
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  
  // Estado para el resultado algorítmico post-envío
  const [resultPayload, setResultPayload] = useState<FuelRpcResponse | null>(null);

  if (!isOpen) return null;

  const handlePadPress = (val: string) => {
    if (isSubmitting || resultPayload) return;
    setErrorMessage(null);

    const currentVal = activeField === 'HOURS' ? hoursInput : litersInput;
    const setVal = activeField === 'HOURS' ? setHoursInput : setLitersInput;

    if (val === 'CLEAR') {
      setVal('');
      return;
    }
    if (val === 'BACK') {
      setVal(currentVal.slice(0, -1));
      return;
    }
    if (val === '.') {
      if (!currentVal.includes('.')) setVal(currentVal + '.');
      return;
    }
    // Evitar cadenas infinitas
    if (currentVal.length < 7) {
      setVal(currentVal + val);
    }
  };

  const submitFuelToLayerZero = async () => {
    const numHours = parseFloat(hoursInput);
    const numLiters = parseFloat(litersInput);

    if (isNaN(numHours) || numHours < currentEngineHours) {
      setErrorMessage(`ERROR DE HORÓMETRO: El valor debe ser mayor o igual al registro actual (${currentEngineHours}).`);
      return;
    }
    if (isNaN(numLiters) || numLiters <= 0) {
      setErrorMessage('ERROR DE VOLUMEN: Ingrese una cantidad válida de litros cargados.');
      return;
    }

    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      const { data, error } = await supabase.rpc('fn_submit_fuel_log', {
        p_asset_id: assetId,
        p_liters_filled: numLiters,
        p_engine_hours: numHours,
        p_cost_per_liter: 1.85, // Tasa base minera Hobart
      });

      if (error) throw new Error(error.message);

      const response = data as FuelRpcResponse;
      setIsSubmitting(false);
      setResultPayload(response);

      // Si todo fue verificado limpio, cerramos en 2.5s. Si hay anomalía, dejamos que el conductor lea la alerta.
      if (response.status === 'VERIFIED') {
        setTimeout(() => {
          onFuelLogged(response);
          onClose();
          setResultPayload(null);
        }, 2500);
      }
    } catch (err: any) {
      setIsSubmitting(false);
      setErrorMessage(`RECHAZO FORENSE: ${err.message}`);
    }
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'VERIFIED':
        return { bg: 'bg-emerald-500/20 text-emerald-400 border-emerald-500/40', text: '🟢 CONSUMO VERIFICADO • ÓPTIMO', icon: '✓' };
      case 'ANOMALY_HIGH_BURN':
        return { bg: 'bg-amber-500/20 text-amber-400 border-amber-500/40 animate-pulse', text: '⚠️ ANOMALÍA: CONSUMO EXCESIVO DE COMBUSTIBLE', icon: '⚡' };
      case 'ANOMALY_IDLE_BURN':
        return { bg: 'bg-purple-500/20 text-purple-400 border-purple-500/40 animate-pulse', text: '⚠️ ANOMALÍA: RALENTÍ ABUSIVO SIN PRODUCCIÓN', icon: '🛑' };
      case 'THEFT_SUSPECTED':
        return { bg: 'bg-red-600 text-white border-white animate-bounce', text: '🚨 ALERTA CRÍTICA: SOSPECHA DE ROBO O SIFÓN', icon: '🚨' };
      default:
        return { bg: 'bg-slate-800 text-white', text: status, icon: 'ℹ️' };
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/90 backdrop-blur-md flex items-center justify-center p-4 select-none font-sans overflow-y-auto">
      <div className="w-full max-w-xl bg-slate-950 border-4 border-blue-600 rounded-3xl shadow-2xl overflow-hidden flex flex-col my-auto animate-fade-in">
        
        {/* Cabecera Industrial */}
        <header className="bg-blue-600 text-black px-6 py-4 flex justify-between items-center font-mono">
          <div className="flex items-center gap-2 font-black text-sm uppercase tracking-widest">
            <span>⛽ FUELFLOW TELEMETRY • REPOSTAJE</span>
          </div>
          <span className="bg-black/20 text-white text-xs font-bold px-2.5 py-1 rounded">
            {assetName}
          </span>
        </header>

        <main className="p-6">
          {resultPayload ? (
            /* PANTALLA DE RESULTADO ALGORÍTMICO */
            <div className="text-center py-6 font-mono">
              <div className="text-6xl mb-4">{getStatusBadge(resultPayload.status).icon}</div>
              
              <div className={`p-4 rounded-2xl border-2 font-black text-xs md:text-sm uppercase mb-6 ${getStatusBadge(resultPayload.status).bg}`}>
                {getStatusBadge(resultPayload.status).text}
              </div>

              <div className="bg-slate-900 border border-slate-800 p-6 rounded-2xl text-left text-xs space-y-3 mb-6">
                <div className="flex justify-between border-b border-slate-800 pb-2">
                  <span className="text-slate-400">Litros Inyectados:</span>
                  <span className="text-white font-black text-base">{resultPayload.liters_filled} L</span>
                </div>
                <div className="flex justify-between border-b border-slate-800 pb-2">
                  <span className="text-slate-400">Costo Total (AUD):</span>
                  <span className="text-emerald-400 font-black">${resultPayload.total_cost.toFixed(2)}</span>
                </div>
                <div className="flex justify-between border-b border-slate-800 pb-2">
                  <span className="text-slate-400">Tasa de Consumo Calculada:</span>
                  <span className="text-blue-400 font-black">{resultPayload.burn_rate_lph} L/Hora</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-400">Trabajo Previo Cruzado:</span>
                  <span className="text-white font-bold">{resultPayload.tonnage_cross_ref} t movidas</span>
                </div>
              </div>

              {resultPayload.status !== 'VERIFIED' && (
                <p className="text-[11px] text-amber-400 uppercase font-bold bg-amber-950/40 p-3 rounded-xl border border-amber-800 mb-6">
                  ⚠️ Esta discrepancia ha sido enviada al libro mayor de auditoría y al radio del Fleet Manager en Hobart.
                </p>
              )}

              <button
                type="button"
                onClick={() => {
                  onFuelLogged(resultPayload);
                  onClose();
                  setResultPayload(null);
                }}
                className="w-full bg-blue-600 hover:bg-blue-500 text-white font-black py-4 rounded-xl uppercase tracking-widest text-xs shadow-xl"
              >
                CERRAR Y REGRESAR AL DESPACHO ➔
              </button>
            </div>
          ) : (
            /* FORMULARIO DE INTERFAZ TÁCTIL */
            <div>
              {/* Selector de Campo Activo (Horómetro vs Litros) */}
              <div className="grid grid-cols-2 gap-3 mb-6 font-mono">
                <button
                  type="button"
                  onClick={() => setActiveField('HOURS')}
                  className={`p-4 rounded-2xl border-2 text-left transition-all ${
                    activeField === 'HOURS'
                      ? 'bg-blue-950/40 border-blue-500 text-white scale-105 shadow-lg shadow-blue-500/10'
                      : 'bg-slate-900 border-slate-800 text-slate-500'
                  }`}
                >
                  <span className="text-[10px] block font-bold uppercase tracking-wider mb-1">
                    1. Horómetro Actual (Horas)
                  </span>
                  <span className="text-2xl md:text-3xl font-black block">
                    {hoursInput || '0.0'} <span className="text-xs font-normal">h</span>
                  </span>
                  <span className="text-[9px] text-slate-400 block mt-1">
                    Anterior: {currentEngineHours} h
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => setActiveField('LITERS')}
                  className={`p-4 rounded-2xl border-2 text-left transition-all ${
                    activeField === 'LITERS'
                      ? 'bg-emerald-950/40 border-emerald-500 text-white scale-105 shadow-lg shadow-emerald-500/10'
                      : 'bg-slate-900 border-slate-800 text-slate-500'
                  }`}
                >
                  <span className="text-[10px] block font-bold uppercase tracking-wider mb-1">
                    2. Litros Cargados
                  </span>
                  <span className="text-2xl md:text-3xl font-black block text-emerald-400">
                    {litersInput || '0.0'} <span className="text-xs font-normal text-white">L</span>
                  </span>
                  <span className="text-[9px] text-slate-400 block mt-1">
                    Tasa: $1.85 / Litro
                  </span>
                </button>
              </div>

              {errorMessage && (
                <div className="bg-red-950/80 border border-red-600 p-3 rounded-xl mb-4 font-mono text-xs text-red-300 font-bold uppercase text-center animate-shake">
                  ⚠️ {errorMessage}
                </div>
              )}

              {/* Teclado Matricial Industrial Integrado */}
              <div className="grid grid-cols-3 gap-2 mb-6">
                {['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', 'BACK'].map((key) => {
                  const isSpecial = key === 'BACK';
                  return (
                    <button
                      key={key}
                      type="button"
                      disabled={isSubmitting}
                      onClick={() => handlePadPress(key)}
                      className={`h-16 rounded-xl font-mono font-black text-xl uppercase transition-all active:scale-95 disabled:opacity-20 flex items-center justify-center shadow-md ${
                        isSpecial
                          ? 'bg-slate-900 border border-slate-800 text-red-400 hover:bg-slate-800'
                          : 'bg-slate-900 hover:bg-slate-800 text-white border border-slate-700'
                      }`}
                    >
                      {key === 'BACK' ? '⌫ BORRAR' : key}
                    </button>
                  );
                })}
              </div>

              {/* Botonera de Envío */}
              <div className="flex gap-3 pt-2 border-t border-slate-800 font-mono">
                <button
                  type="button"
                  disabled={isSubmitting}
                  onClick={onClose}
                  className="w-1/3 bg-slate-900 hover:bg-slate-800 text-slate-400 font-bold py-4 rounded-xl uppercase tracking-wider text-xs border border-slate-800"
                >
                  Cancelar
                </button>
                <button
                  type="button"
                  disabled={isSubmitting || !litersInput || !hoursInput}
                  onClick={submitFuelToLayerZero}
                  className="w-2/3 bg-emerald-500 hover:bg-emerald-400 disabled:opacity-20 text-black font-black py-4 rounded-xl uppercase tracking-widest text-xs shadow-xl transition-all flex items-center justify-center gap-2"
                >
                  {isSubmitting ? 'ANALIZANDO TELEMETRÍA...' : '⚡ FIRMAR REPOSTAJE WORM ➔'}
                </button>
              </div>
            </div>
          )}
        </main>

        <footer className="bg-black/60 px-6 py-3 border-t border-slate-900 text-center font-mono text-[9px] text-slate-500 uppercase">
          Triangulación Activa • Los intentos de falsificación de horómetro son reportados automáticamente bajo norma WHS.
        </footer>
      </div>
    </div>
  );
};

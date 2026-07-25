import React, { useState, useEffect } from 'react';

export interface AssignedShift {
  id: string;
  asset_code: string;
  asset_id: string;
}

interface PreStartKioskProps {
  shift: AssignedShift | null;
  onCertifyShift: (shiftId: string) => void;
  onReportDefect: (assetId: string, shiftId: string, reason: string) => void;
  isSubmitting: boolean;
}

export const PreStartKiosk: React.FC<PreStartKioskProps> = ({
  shift,
  onCertifyShift,
  onReportDefect,
  isSubmitting
}) => {
  // Estado de Fricción Forense (60 Segundos)
  const [secondsRemaining, setSecondsRemaining] = useState(60);
  const [isDefectMode, setIsDefectMode] = useState(false);
  const [defectReason, setDefectReason] = useState('');

  useEffect(() => {
    if (!shift || isDefectMode || secondsRemaining <= 0) return;
    
    const timer = setInterval(() => {
      setSecondsRemaining(prev => prev - 1);
    }, 1000);
    
    return () => clearInterval(timer);
  }, [shift, isDefectMode, secondsRemaining]);

  if (!shift) {
    return (
      <div className="min-h-screen bg-slate-950 flex flex-col items-center justify-center p-6 text-center select-none">
        <div className="w-24 h-24 mb-6 rounded-full bg-slate-900 border border-slate-800 flex items-center justify-center animate-pulse">
          <span className="text-3xl">📡</span>
        </div>
        <h1 className="text-2xl font-black text-white uppercase tracking-tight">Capa 0 Sincronizada</h1>
        <p className="text-slate-500 font-mono mt-2 uppercase text-sm">Ningún turno asignado. Esperando despacho...</p>
      </div>
    );
  }

  // Flujo de Aborto y Defecto
  if (isDefectMode) {
    return (
      <div className="min-h-screen bg-red-950 flex flex-col p-6 select-none">
        <header className="mb-6">
          <h1 className="text-3xl font-black text-red-500 uppercase tracking-tight">REPORTE DE AVERÍA</h1>
          <p className="text-red-200 font-mono text-sm mt-1">Activo: {shift.asset_code}</p>
        </header>

        <div className="flex-1 flex flex-col gap-4">
          <p className="text-white font-bold">Describa la falla crítica encontrada en la inspección visual:</p>
          <textarea
            value={defectReason}
            onChange={(e) => setDefectReason(e.target.value)}
            placeholder="Ej: Fuga de aceite hidráulico en el cilindro frontal..."
            className="w-full flex-1 bg-red-900/50 border-2 border-red-700 rounded-xl p-4 text-white placeholder-red-400 focus:outline-none focus:border-red-500 font-mono text-lg transition-colors"
          />
        </div>

        <div className="mt-6 flex flex-col gap-4">
          <button
            onClick={() => onReportDefect(shift.asset_id, shift.id, defectReason)}
            disabled={defectReason.trim().length < 10 || isSubmitting}
            className="w-full bg-red-600 hover:bg-red-500 text-white font-black text-xl py-6 rounded-xl uppercase tracking-widest disabled:opacity-50 transition-colors shadow-2xl"
          >
            {isSubmitting ? 'SECUESTRANDO...' : 'SECUESTRAR MÁQUINA'}
          </button>
          <button
            onClick={() => setIsDefectMode(false)}
            disabled={isSubmitting}
            className="w-full bg-transparent border-2 border-red-800 text-red-400 font-bold text-lg py-4 rounded-xl uppercase transition-colors"
          >
            Cancelar Reporte
          </button>
        </div>
      </div>
    );
  }

  // Flujo Táctico Normal (El Túnel del Pre-Start)
  return (
    <div className="min-h-screen bg-slate-950 flex flex-col p-6 select-none">
      <header className="mb-8 border-b border-slate-800 pb-4">
        <h1 className="text-4xl font-black text-white uppercase tracking-tight">{shift.asset_code}</h1>
        <div className="flex items-center justify-between mt-2">
          <span className="text-amber-500 font-mono text-sm font-bold uppercase">Pre-Start Requerido</span>
          <span className="bg-slate-800 text-slate-300 px-3 py-1 rounded text-xs font-bold font-mono">
            {secondsRemaining > 0 ? `T-${secondsRemaining}s` : 'DESBLOQUEADO'}
          </span>
        </div>
      </header>

      <div className="flex-1 space-y-6">
        <div className="bg-slate-900 border border-slate-800 p-6 rounded-xl">
          <h2 className="text-slate-400 font-black uppercase text-sm mb-4">Obligaciones WHS</h2>
          <ul className="space-y-4 text-white font-bold text-lg">
            <li className="flex items-center gap-3">
              <span className="w-2 h-2 bg-blue-500 rounded-full"></span> Inspección de Neumáticos y Llantas
            </li>
            <li className="flex items-center gap-3">
              <span className="w-2 h-2 bg-blue-500 rounded-full"></span> Niveles de Aceite y Refrigerante
            </li>
            <li className="flex items-center gap-3">
              <span className="w-2 h-2 bg-blue-500 rounded-full"></span> Prueba de Frenos Estática
            </li>
            <li className="flex items-center gap-3">
              <span className="w-2 h-2 bg-blue-500 rounded-full"></span> Estructura y Cilindros (Sin Fugas)
            </li>
          </ul>
        </div>
      </div>

      <div className="mt-8 flex flex-col gap-4">
        <button
          onClick={() => setIsDefectMode(true)}
          disabled={isSubmitting}
          className="w-full bg-slate-900 border-2 border-red-900/50 hover:bg-red-950 text-red-500 font-black text-lg py-5 rounded-xl uppercase transition-colors"
        >
          ❌ REPORTAR DEFECTO
        </button>

        <button
          onClick={() => onCertifyShift(shift.id)}
          disabled={secondsRemaining > 0 || isSubmitting}
          className={`w-full font-black text-xl py-6 rounded-xl uppercase tracking-widest transition-all duration-300 shadow-2xl
            ${secondsRemaining > 0 
              ? 'bg-slate-800 text-slate-500 border border-slate-700 cursor-not-allowed' 
              : 'bg-green-600 hover:bg-green-500 text-white'
            }
          `}
        >
          {secondsRemaining > 0 ? `ESPERE ${secondsRemaining}s...` : 'CERTIFICAR FIRMA'}
        </button>
      </div>
    </div>
  );
};

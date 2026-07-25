import React, { useState, useEffect } from 'react';
import { ExpenseCameraPresenter } from './ExpenseCameraPresenter';

interface ActiveShiftProps {
  assetCode: string;
  startTime: string;
  onEndShift: () => void;
  onCaptureExpense: (base64: string, category: string) => void;
  isSubmitting: boolean;
  isUploadingExpense: boolean;
}

export const ActiveShiftPresenter: React.FC<ActiveShiftProps> = ({
  assetCode,
  startTime,
  onEndShift,
  onCaptureExpense,
  isSubmitting,
  isUploadingExpense
}) => {
  const [elapsed, setElapsed] = useState<string>('00:00:00');
  const [showConfirm, setShowConfirm] = useState(false);

  // Cronómetro visual (no afecta la facturación, solo es UX)
  useEffect(() => {
    const timer = setInterval(() => {
      const ms = new Date().getTime() - new Date(startTime).getTime();
      const hours = Math.floor(ms / 3600000).toString().padStart(2, '0');
      const mins = Math.floor((ms % 3600000) / 60000).toString().padStart(2, '0');
      const secs = Math.floor((ms % 60000) / 1000).toString().padStart(2, '0');
      setElapsed(`${hours}:${mins}:${secs}`);
    }, 1000);
    return () => clearInterval(timer);
  }, [startTime]);

  return (
    <div className="min-h-screen bg-slate-950 flex flex-col p-6 select-none justify-center">
      <div className="bg-slate-900 border border-slate-800 p-8 rounded-2xl text-center shadow-2xl">
        <h2 className="text-slate-500 font-mono text-sm uppercase tracking-widest mb-2">Operación en Curso</h2>
        <h1 className="text-5xl font-black text-white uppercase tracking-tight mb-6">{assetCode}</h1>
        
        <div className="bg-slate-950 border-2 border-blue-900/50 rounded-xl p-6 mb-8 inline-block">
          <span className="text-4xl font-mono font-bold text-blue-400">{elapsed}</span>
          <p className="text-slate-500 text-xs mt-2 uppercase">Tiempo de Turno</p>
        </div>

        <ExpenseCameraPresenter 
          onCapture={onCaptureExpense}
          isSubmitting={isUploadingExpense}
        />

        <div className="mt-8">
          {!showConfirm ? (
          <button
            onClick={() => setShowConfirm(true)}
            className="w-full bg-slate-800 hover:bg-slate-700 text-white font-black text-xl py-6 rounded-xl uppercase tracking-widest transition-colors border border-slate-700"
          >
            FINALIZAR TURNO
          </button>
        ) : (
          <div className="animate-fade-in">
            <p className="text-amber-500 font-bold mb-4">¿Confirmas el cierre del equipo y cese de operaciones?</p>
            <div className="flex gap-4">
              <button
                onClick={() => setShowConfirm(false)}
                disabled={isSubmitting}
                className="flex-1 bg-slate-800 text-white font-bold py-4 rounded-xl uppercase"
              >
                Cancelar
              </button>
              <button
                onClick={onEndShift}
                disabled={isSubmitting}
                className="flex-1 bg-amber-600 hover:bg-amber-500 text-white font-black py-4 rounded-xl uppercase transition-colors"
              >
                {isSubmitting ? 'CERRANDO...' : 'SÍ, FINALIZAR'}
              </button>
            </div>
          </div>
        )}
        </div>
      </div>
    </div>
  );
};

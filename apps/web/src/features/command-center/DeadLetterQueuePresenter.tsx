import React, { useState } from 'react';

export interface DeadLetter {
  id: string;
  certificate_id: string;
  payload: any;
  last_error: string;
  updated_at: string;
}

interface DeadLetterQueueProps {
  deadLetters: DeadLetter[];
  onResurrect: (id: string) => void;
  isSubmitting: boolean;
}

export const DeadLetterQueuePresenter: React.FC<DeadLetterQueueProps> = ({
  deadLetters,
  onResurrect,
  isSubmitting
}) => {
  const [selectedId, setSelectedId] = useState<string | null>(null);

  if (deadLetters.length === 0) return null; // Si no hay sangre, la UI no estorba

  const totalAtascado = deadLetters.reduce((sum, letter) => sum + (letter.payload.total_billable || 0), 0);

  return (
    <div className="bg-red-950/20 border-2 border-red-900 rounded-2xl p-6 mt-8 select-none font-sans">
      <header className="mb-6 flex justify-between items-center border-b border-red-900/50 pb-4">
        <div>
          <h2 className="text-2xl font-black text-red-500 uppercase tracking-tight flex items-center gap-3">
            <span className="animate-pulse">⚠️</span> ALERTA DE HEMORRAGIA FINANCIERA
          </h2>
          <p className="text-red-400 font-mono text-sm mt-1">Facturas decapitadas por el orquestador externo</p>
        </div>
        <div className="text-right">
          <p className="text-red-500 font-bold text-xs uppercase mb-1">Capital Secuestrado</p>
          <span className="text-3xl font-black text-red-400">${totalAtascado.toFixed(2)} AUD</span>
        </div>
      </header>

      <div className="space-y-4">
        {deadLetters.map((letter) => {
          const isSelected = selectedId === letter.id;
          return (
            <div key={letter.id} className="bg-slate-900 border border-red-900 rounded-xl overflow-hidden transition-all">
              <div 
                className="p-4 flex justify-between items-center cursor-pointer hover:bg-slate-800"
                onClick={() => setSelectedId(isSelected ? null : letter.id)}
              >
                <div>
                  <p className="text-white font-bold font-mono text-sm">CERT: {letter.certificate_id.substring(0, 13)}...</p>
                  <p className="text-slate-500 text-xs">Caída a las: {new Date(letter.updated_at).toLocaleString()}</p>
                </div>
                <div className="text-right">
                  <span className="text-red-400 font-black text-lg">${letter.payload.total_billable?.toFixed(2)}</span>
                </div>
              </div>

              {isSelected && (
                <div className="p-6 bg-red-950/30 border-t border-red-900/50">
                  <p className="text-red-300 font-bold text-xs uppercase mb-2">Diagnóstico de la API Externa:</p>
                  <div className="bg-black/50 p-4 rounded text-red-400 font-mono text-sm mb-6 border border-red-900 break-words">
                    {letter.last_error || "Timeout de red desconocido"}
                  </div>
                  
                  <button
                    onClick={() => onResurrect(letter.id)}
                    disabled={isSubmitting}
                    className="w-full bg-red-800 hover:bg-red-700 text-white font-black py-4 rounded uppercase tracking-widest transition-colors disabled:opacity-50"
                  >
                    {isSubmitting ? 'FORZANDO RESURRECCIÓN...' : 'INYECTAR EN COLA DE SALIDA'}
                  </button>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
};

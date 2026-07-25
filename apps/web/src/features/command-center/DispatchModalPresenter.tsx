import React, { useState } from 'react';

// Contrato de datos inyectado por el Container (pre-calculado o desde SQL)
export interface Operator {
  id: string;
  full_name: string;
  hours_worked_today: number;
}

interface DispatchModalProps {
  assetCode: string;
  operators: Operator[];
  onConfirm: (operatorId: string, overrideReason?: string) => void;
  onCancel: () => void;
  isSubmitting: boolean;
  fatigueThreshold: number; // Ej: 10 horas
  hardLimit: number; // Ej: 12 horas (Ilegal absoluto)
}

export const DispatchModalPresenter: React.FC<DispatchModalProps> = ({
  assetCode,
  operators,
  onConfirm,
  onCancel,
  isSubmitting,
  fatigueThreshold,
  hardLimit
}) => {
  const [selectedOperatorId, setSelectedOperatorId] = useState<string>('');
  const [overrideReason, setOverrideReason] = useState<string>('');

  const selectedOperator = operators.find(op => op.id === selectedOperatorId);
  const isWarning = selectedOperator ? selectedOperator.hours_worked_today >= fatigueThreshold : false;
  const isBlocked = selectedOperator ? selectedOperator.hours_worked_today >= hardLimit : false;

  const handleConfirm = () => {
    if (!selectedOperatorId || isBlocked) return;
    if (isWarning && overrideReason.trim().length < 10) return;
    
    onConfirm(selectedOperatorId, isWarning ? overrideReason : undefined);
  };

  return (
    <div className="fixed inset-0 bg-black/80 flex items-center justify-center z-50 p-4 select-none">
      <div className="bg-slate-900 border border-slate-700 rounded-xl w-full max-w-lg overflow-hidden shadow-2xl">
        
        <div className="bg-slate-950 p-6 border-b border-slate-800">
          <h2 className="text-2xl font-black text-white uppercase tracking-tight">ASSIGN SHIFT</h2>
          <p className="text-slate-400 font-mono mt-1">Target Asset: <span className="text-blue-400 font-bold">{assetCode}</span></p>
        </div>

        {/* Cuerpo del Modal */}
        <div className="p-6 space-y-6">
          
          {/* Selector de Operador con Semaforización */}
          <div>
            <label className="block text-slate-300 font-bold mb-2 uppercase text-sm">Available Operator</label>
            <div className="space-y-2 max-h-48 overflow-y-auto pr-2 custom-scrollbar">
              {operators.map(op => {
                const opIsBlocked = op.hours_worked_today >= hardLimit;
                const opIsWarning = op.hours_worked_today >= fatigueThreshold && !opIsBlocked;
                
                return (
                  <button
                    key={op.id}
                    onClick={() => setSelectedOperatorId(op.id)}
                    disabled={opIsBlocked}
                    className={`w-full text-left p-3 rounded-lg border flex justify-between items-center transition-colors
                      ${selectedOperatorId === op.id ? 'bg-blue-900/40 border-blue-500 ring-1 ring-blue-500' : ''}
                      ${!selectedOperatorId || selectedOperatorId !== op.id ? 
                        (opIsBlocked ? 'bg-red-950/30 border-red-900/50 opacity-50 cursor-not-allowed' : 
                        opIsWarning ? 'bg-amber-950/30 border-amber-800/50 hover:bg-amber-900/40' : 
                        'bg-slate-800 border-slate-700 hover:bg-slate-700') : ''}
                    `}
                  >
                    <span className="font-bold text-white">{op.full_name}</span>
                    <span className={`text-xs font-mono font-bold px-2 py-1 rounded
                      ${opIsBlocked ? 'bg-red-900 text-red-200' : 
                        opIsWarning ? 'bg-amber-700 text-amber-100' : 
                        'bg-slate-700 text-slate-300'}
                    `}>
                      {op.hours_worked_today} HR
                    </span>
                  </button>
                );
              })}
              {operators.length === 0 && (
                <div className="bg-red-950/50 border border-red-900/50 p-4 rounded-lg flex items-center justify-center text-center">
                  <p className="text-red-400 font-mono text-xs font-bold uppercase tracking-widest">
                    CRITICAL ERROR: No available operators found in the workforce roster.
                  </p>
                </div>
              )}
            </div>
          </div>

          {/* Renderizado Condicional del Cortafuegos Legal */}
          {selectedOperator && isWarning && !isBlocked && (
            <div className="bg-amber-950 border border-amber-800 p-4 rounded-lg animate-fade-in">
                <h3 className="text-amber-500 font-black uppercase text-sm mb-2 flex items-center gap-2">
                ⚠️ WHS ALERT: FATIGUE THRESHOLD EXCEEDED
              </h3>
              <p className="text-amber-200/80 text-sm mb-4">
                Operator {selectedOperator.full_name} has exceeded {fatigueThreshold} hours. Provide logistic justification to sign the override.
              </p>
              <textarea
                value={overrideReason}
                onChange={(e) => setOverrideReason(e.target.value)}
                placeholder="Ex: Emergency relief due to equipment breakdown..."
                className="w-full bg-black/50 border border-amber-700/50 rounded p-3 text-white placeholder-amber-700 focus:outline-none focus:border-amber-500 transition-colors"
                rows={3}
              />
            </div>
          )}

          {selectedOperator && isBlocked && (
            <div className="bg-red-950 border border-red-800 p-4 rounded-lg">
               <h3 className="text-red-500 font-black uppercase text-sm">⛔ ABSOLUTE LEGAL BLOCK</h3>
               <p className="text-red-200/80 text-sm mt-1">This operator has reached the absolute limit of {hardLimit} hours. Assignment forbidden by Layer 0.</p>
            </div>
          )}
        </div>

        {/* Controles de Acción */}
        <div className="bg-slate-950 p-6 border-t border-slate-800 flex gap-4">
          <button
            onClick={onCancel}
            disabled={isSubmitting}
            className="flex-1 py-3 bg-slate-800 hover:bg-slate-700 text-white font-bold rounded uppercase transition-colors"
          >
            ABORT
          </button>
          <button
            onClick={handleConfirm}
            disabled={!selectedOperatorId || isBlocked || (isWarning && overrideReason.trim().length < 10) || isSubmitting}
            className={`flex-1 py-3 font-black rounded uppercase transition-colors
              ${isWarning ? 'bg-amber-600 hover:bg-amber-500 text-white' : 'bg-blue-600 hover:bg-blue-500 text-white'}
              disabled:opacity-50 disabled:cursor-not-allowed
            `}
          >
            {isSubmitting ? 'PROCESSING...' : isWarning ? 'SIGN OVERRIDE' : 'DISPATCH ASSET'}
          </button>
        </div>

      </div>
    </div>
  );
};

import React, { useState, useEffect } from 'react';

export interface QuarantinedExpense {
  id: string;
  shift_id: string;
  raw_image_url: string;
  extracted_amount: number;
  extracted_vendor: string;
  expense_category: string;
  ocr_confidence: number;
  created_at: string;
}

interface ExpenseQuarantineProps {
  expenses: QuarantinedExpense[];
  onProcessExpense: (id: string, status: 'approved' | 'rejected', correctedAmount: number, notes: string) => void;
  isSubmitting: boolean;
}

export const ExpenseQuarantinePresenter: React.FC<ExpenseQuarantineProps> = ({
  expenses,
  onProcessExpense,
  isSubmitting
}) => {
  const [activeIndex, setActiveIndex] = useState(0);
  const [correctedAmount, setCorrectedAmount] = useState<number | ''>('');
  const [notes, setNotes] = useState('');

  const activeExpense = expenses[activeIndex];

  // Pre-llenar el formulario con la suposición de la IA cuando cambia el recibo
  useEffect(() => {
    if (activeExpense) {
      setCorrectedAmount(activeExpense.extracted_amount || '');
      setNotes('');
    }
  }, [activeExpense]);

  if (expenses.length === 0) {
    return null; // La cuarentena está vacía. Silencio visual.
  }

  const isLowConfidence = activeExpense.ocr_confidence < 80;

  return (
    <div className="bg-slate-950 border-2 border-slate-800 rounded-2xl p-6 mt-8 select-none font-sans shadow-2xl">
      <header className="mb-6 flex justify-between items-end border-b border-slate-800 pb-4">
        <div>
          <h2 className="text-2xl font-black text-white uppercase tracking-tight flex items-center gap-3">
            ⚖️ CUARENTENA DE GASTOS
          </h2>
          <p className="text-slate-400 font-mono text-sm mt-1">
            {expenses.length} recibo(s) esperando auditoría humana.
          </p>
        </div>
        <div className="flex gap-2">
          <button 
            onClick={() => setActiveIndex(Math.max(0, activeIndex - 1))}
            disabled={activeIndex === 0}
            className="px-4 py-2 bg-slate-900 text-slate-400 rounded disabled:opacity-30 font-bold"
          >
            ◀ ANTERIOR
          </button>
          <button 
            onClick={() => setActiveIndex(Math.min(expenses.length - 1, activeIndex + 1))}
            disabled={activeIndex === expenses.length - 1}
            className="px-4 py-2 bg-slate-900 text-slate-400 rounded disabled:opacity-30 font-bold"
          >
            SIGUIENTE ▶
          </button>
        </div>
      </header>

      <div className="flex flex-col lg:flex-row gap-8 h-[600px]">
        {/* PANEL IZQUIERDO: La Verdad Física (WORM) */}
        <div className="w-full lg:w-1/2 bg-black rounded-xl overflow-hidden border border-slate-800 flex items-center justify-center relative group">
          <div className="absolute top-4 left-4 bg-black/80 px-3 py-1 rounded border border-slate-700 text-xs text-slate-400 font-mono z-10 uppercase">
            ORIGINAL INMUTABLE
          </div>
          <img 
            src={activeExpense.raw_image_url} 
            alt="Recibo analógico" 
            className="max-h-full max-w-full object-contain cursor-crosshair transition-transform duration-300 group-hover:scale-110"
          />
        </div>

        {/* PANEL DERECHO: El Bisturí de Auditoría */}
        <div className="w-full lg:w-1/2 flex flex-col justify-between bg-slate-900 p-6 rounded-xl border border-slate-800">
          <div>
            <div className={`mb-6 p-4 rounded-lg border-l-4 ${isLowConfidence ? 'bg-amber-950/30 border-amber-500' : 'bg-blue-950/30 border-blue-500'}`}>
              <p className="text-slate-400 text-xs font-mono uppercase mb-1">Extracción de Inteligencia Artificial</p>
              <div className="flex justify-between items-center">
                <span className="text-xl font-bold text-white uppercase">{activeExpense.extracted_vendor || 'PROVEEDOR DESCONOCIDO'}</span>
                <span className={`font-mono font-bold ${isLowConfidence ? 'text-amber-500' : 'text-blue-400'}`}>
                  {activeExpense.ocr_confidence.toFixed(1)}% Certeza
                </span>
              </div>
            </div>

            <label className="block text-slate-400 font-bold mb-2 uppercase text-sm">Valor Auditado (AUD)</label>
            <input 
              type="number"
              step="0.01"
              value={correctedAmount}
              onChange={(e) => setCorrectedAmount(parseFloat(e.target.value))}
              className="w-full bg-slate-950 border-2 border-slate-700 rounded-xl p-4 text-3xl text-white font-black font-mono focus:outline-none focus:border-blue-500 mb-6"
            />

            <label className="block text-slate-400 font-bold mb-2 uppercase text-sm">Notas del Auditor (Justificación)</label>
            <textarea 
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="Ej. La IA confundió un 7 con un 1. Corregido."
              className="w-full bg-slate-950 border-2 border-slate-700 rounded-xl p-4 text-white font-mono h-24 focus:outline-none focus:border-blue-500 mb-6 resize-none"
            />
          </div>

          <div className="flex gap-4">
            <button
              onClick={() => onProcessExpense(activeExpense.id, 'rejected', 0, notes)}
              disabled={isSubmitting || notes.trim().length < 5}
              className="flex-1 border-2 border-red-900 text-red-500 hover:bg-red-950 font-black py-4 rounded-xl uppercase transition-colors disabled:opacity-30 text-sm tracking-widest"
            >
              RECHAZAR FRAUDE
            </button>
            <button
              onClick={() => onProcessExpense(activeExpense.id, 'approved', Number(correctedAmount), notes)}
              disabled={isSubmitting || !correctedAmount || correctedAmount <= 0}
              className="flex-1 bg-blue-600 hover:bg-blue-500 text-white font-black py-4 rounded-xl uppercase transition-colors disabled:opacity-30 text-sm tracking-widest shadow-xl"
            >
              CERTIFICAR Y LIQUIDAR
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

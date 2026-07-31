import React, { useState } from 'react';
import { X, Truck, Save, Loader2 } from 'lucide-react';

interface CreateAssetModalProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirm: (payload: { name: string; category: string }) => void;
  isSubmitting: boolean;
}

export const CreateAssetModal: React.FC<CreateAssetModalProps> = ({
  isOpen,
  onClose,
  onConfirm,
  isSubmitting
}) => {
  const [name, setName] = useState('');
  const [category, setCategory] = useState('dump_truck');

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    onConfirm({ name: name.trim(), category });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm p-4">
      <div className="bg-slate-950 border border-slate-800 rounded-3xl w-full max-w-md shadow-2xl overflow-hidden">
        
        <header className="px-6 py-4 border-b border-slate-800 flex justify-between items-center bg-slate-900/50">
          <div className="flex items-center gap-3">
            <div className="bg-emerald-500/20 p-2 rounded-lg">
              <Truck className="w-5 h-5 text-emerald-400" />
            </div>
            <h3 className="font-mono text-lg font-bold text-white uppercase tracking-tight">Matricular Maquinaria</h3>
          </div>
          <button onClick={onClose} className="text-slate-500 hover:text-white transition-colors">
            <X className="w-6 h-6" />
          </button>
        </header>

        <form onSubmit={handleSubmit} className="p-6">
          <div className="space-y-5">
            
            <div className="space-y-2">
              <label className="text-xs font-mono font-bold text-slate-400 uppercase tracking-widest block">
                Identificador (Internal Code)
              </label>
              <input 
                type="text" 
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Ej: DT-104"
                className="w-full bg-slate-900 border border-slate-700 rounded-xl px-4 py-3 text-white font-mono uppercase focus:outline-none focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500 transition-all"
                required
                maxLength={20}
              />
            </div>

            <div className="space-y-2">
              <label className="text-xs font-mono font-bold text-slate-400 uppercase tracking-widest block">
                Categoría (Tipo)
              </label>
              <select 
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                className="w-full bg-slate-900 border border-slate-700 rounded-xl px-4 py-3 text-white font-mono uppercase focus:outline-none focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500 transition-all"
              >
                <option value="dump_truck">Dump Truck (Volquete)</option>
                <option value="excavator">Excavator (Excavadora)</option>
                <option value="loader">Loader (Cargador Frontal)</option>
                <option value="dozer">Dozer (Bulldozer)</option>
                <option value="water_cart">Water Cart (Aljibe)</option>
                <option value="weighbridge">Weighbridge (Romana)</option>
              </select>
            </div>
          </div>

          <div className="mt-8 pt-6 border-t border-slate-800 flex justify-end gap-3">
            <button
              type="button"
              onClick={onClose}
              disabled={isSubmitting}
              className="px-5 py-2.5 rounded-xl text-slate-400 font-bold uppercase tracking-wider text-xs hover:text-white transition-colors"
            >
              Cancelar
            </button>
            <button
              type="submit"
              disabled={isSubmitting || !name.trim()}
              className="bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 text-white px-6 py-2.5 rounded-xl font-bold uppercase tracking-wider text-xs shadow-[0_0_15px_rgba(16,185,129,0.3)] hover:shadow-[0_0_25px_rgba(16,185,129,0.5)] transition-all flex items-center gap-2"
            >
              {isSubmitting ? (
                <><Loader2 className="w-4 h-4 animate-spin" /> Procesando...</>
              ) : (
                <><Save className="w-4 h-4" /> Registrar Activo</>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

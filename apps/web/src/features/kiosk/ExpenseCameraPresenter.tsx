import React, { useRef, useState } from 'react';

interface ExpenseCameraProps {
  onCapture: (compressedBase64: string, category: string) => void;
  isSubmitting: boolean;
}

export const ExpenseCameraPresenter: React.FC<ExpenseCameraProps> = ({ onCapture, isSubmitting }) => {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [category, setCategory] = useState<string>('fuel');

  // Compresión Forense en el Navegador
  const processImage = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (e) => {
      const img = new Image();
      img.onload = () => {
        const canvas = document.createElement('canvas');
        const MAX_WIDTH = 1200;
        const scaleSize = MAX_WIDTH / img.width;
        
        canvas.width = MAX_WIDTH;
        canvas.height = img.height * scaleSize;
        
        const ctx = canvas.getContext('2d');
        ctx?.drawImage(img, 0, 0, canvas.width, canvas.height);
        
        // Aplastar a JPEG con calidad 70% (Perfecto para OCR, pesa <400kb)
        const compressedData = canvas.toDataURL('image/jpeg', 0.7);
        onCapture(compressedData, category);
      };
      img.src = e.target?.result as string;
    };
    reader.readAsDataURL(file);
  };

  return (
    <div className="bg-slate-900 border border-slate-800 p-6 rounded-2xl flex flex-col gap-4 mt-6">
      <h2 className="text-slate-400 font-black uppercase text-sm tracking-widest border-b border-slate-800 pb-2">
        Cargar Gasto Analógico
      </h2>
      
      <select 
        value={category}
        onChange={(e) => setCategory(e.target.value)}
        disabled={isSubmitting}
        className="w-full bg-slate-950 border border-slate-700 rounded-xl p-4 text-white font-mono uppercase"
      >
        <option value="fuel">Gasoil / Combustible</option>
        <option value="toll">Peaje / Permiso</option>
        <option value="maintenance_parts">Repuesto de Emergencia</option>
      </select>

      <input
        type="file"
        accept="image/*"
        capture="environment"
        ref={fileInputRef}
        onChange={processImage}
        className="hidden"
      />

      <button
        onClick={() => fileInputRef.current?.click()}
        disabled={isSubmitting}
        className="w-full bg-blue-600 hover:bg-blue-500 text-white font-black text-xl py-6 rounded-xl uppercase tracking-widest transition-colors shadow-2xl flex items-center justify-center gap-3 disabled:opacity-50"
      >
        {isSubmitting ? 'ENCRIPTANDO...' : '📸 ESCANEAR RECIBO'}
      </button>
    </div>
  );
};

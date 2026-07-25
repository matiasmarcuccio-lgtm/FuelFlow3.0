import React, { useState } from 'react';
import { supabase } from '../../lib/supabase';

interface TokenGeneratorModalProps {
  isOpen: boolean;
  onClose: () => void;
  fleetId: string;
}

export const TokenGeneratorModal: React.FC<TokenGeneratorModalProps> = ({ isOpen, onClose, fleetId }) => {
  const [isGenerating, setIsGenerating] = useState(false);
  const [generatedToken, setGeneratedToken] = useState<string | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  if (!isOpen) return null;

  const handleGenerate = async () => {
    setIsGenerating(true);
    setErrorMsg(null);
    setGeneratedToken(null);

    try {
      const { data, error } = await supabase.rpc('fn_generate_fleet_invite', {
        p_fleet_id: fleetId
      });

      if (error) throw new Error(error.message);
      
      setGeneratedToken(data);
    } catch (err: any) {
      setErrorMsg(`Fallo criptográfico: ${err.message}`);
    } finally {
      setIsGenerating(false);
    }
  };

  const handleCopy = () => {
    if (generatedToken) {
      navigator.clipboard.writeText(generatedToken);
      alert('¡Token copiado al portapapeles!');
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm p-4 select-none font-sans text-white">
      <div className="bg-slate-950 border-2 border-slate-800 rounded-3xl max-w-md w-full p-8 shadow-2xl relative animate-fade-in flex flex-col items-center text-center">
        
        <div className="w-16 h-16 bg-blue-500/10 border border-blue-500/20 rounded-2xl flex items-center justify-center mb-6 text-3xl">
          📲
        </div>
        
        <h2 className="text-2xl font-black uppercase tracking-tight mb-2">
          Provisionar Nueva Terminal
        </h2>
        
        <p className="font-mono text-xs text-slate-400 uppercase mb-8">
          Genere un token efímero de 6 caracteres. Un operario lo usará para vincular una tablet física a la flota en el foso.
        </p>

        {errorMsg && (
          <div className="w-full bg-red-950/60 border border-red-800 p-4 rounded-xl mb-6 font-mono text-xs text-red-300 uppercase">
            ⚠️ {errorMsg}
          </div>
        )}

        {generatedToken ? (
          <div className="w-full mb-8 animate-fade-in">
            <p className="font-mono text-[10px] text-emerald-500 font-bold uppercase mb-2">
              ✅ TOKEN GENERADO CON ÉXITO
            </p>
            <div 
              onClick={handleCopy}
              className="w-full h-24 bg-slate-900 border-2 border-emerald-500/50 hover:border-emerald-400 rounded-xl flex items-center justify-center cursor-pointer transition-all hover:scale-105 active:scale-95 group"
              title="Copiar al portapapeles"
            >
              <span className="font-mono text-5xl font-black text-white tracking-widest group-hover:text-emerald-400 transition-colors">
                {generatedToken}
              </span>
            </div>
            <p className="font-mono text-[10px] text-slate-500 uppercase mt-3">
              Toque el código para copiar. Expira en 24 horas.
            </p>
          </div>
        ) : (
          <button
            onClick={handleGenerate}
            disabled={isGenerating}
            className="w-full bg-blue-600 hover:bg-blue-500 disabled:opacity-50 disabled:scale-100 text-white font-black py-5 rounded-2xl uppercase tracking-widest text-sm shadow-xl transition-all flex items-center justify-center gap-3 active:scale-95 mb-4 border border-blue-400"
          >
            {isGenerating ? 'FIRMANDO...' : 'GENERAR TOKEN DE FLOTA ➔'}
          </button>
        )}

        <button
          onClick={onClose}
          className="text-[10px] font-mono text-slate-500 hover:text-slate-300 underline uppercase mt-4 transition-colors"
        >
          [CERRAR PANEL]
        </button>

      </div>
    </div>
  );
};

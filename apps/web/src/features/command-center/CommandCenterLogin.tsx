import React, { useState } from 'react';
import { supabase } from '../../lib/supabase';

interface CommandCenterLoginProps {
  onBackToSelector: () => void;
}

export const CommandCenterLogin: React.FC<CommandCenterLoginProps> = ({ onBackToSelector }) => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);
    setErrorMsg(null);

    try {
      const { error } = await supabase.auth.signInWithPassword({
        email,
        password,
      });

      if (error) {
        throw new Error(error.message);
      }
      
      // La suscripción en App.tsx capturará el evento onAuthStateChange y recargará el perfil
    } catch (err: any) {
      setErrorMsg(`Fallo de Autenticación: ${err.message}`);
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-black text-white flex flex-col items-center justify-center p-6 font-sans select-none">
      <div className="max-w-md w-full bg-slate-950 border-2 border-slate-800 rounded-3xl p-8 shadow-2xl animate-fade-in relative">
        <div className="text-center mb-8">
          <div className="w-16 h-16 bg-blue-500/10 border border-blue-500/20 rounded-2xl flex items-center justify-center mx-auto mb-4 text-3xl">
            🔐
          </div>
          <h2 className="text-2xl font-black uppercase tracking-tight mb-2">
            Aduana de Mando
          </h2>
          <p className="font-mono text-xs text-slate-400 uppercase">
            Autenticación WHS Corporativa • Hobart
          </p>
        </div>

        {errorMsg && (
          <div className="bg-red-950/60 border border-red-800 p-4 rounded-xl mb-6 font-mono text-xs text-red-300 uppercase text-center">
            ⚠️ {errorMsg}
          </div>
        )}

        <form onSubmit={handleLogin} className="space-y-4">
          <div>
            <label className="block font-mono text-[10px] uppercase text-slate-500 mb-2 font-bold tracking-widest">
              Identificador (Email Corporativo)
            </label>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              disabled={isLoading}
              className="w-full bg-slate-900 border border-slate-700 focus:border-blue-500 rounded-xl px-4 py-4 text-white font-mono text-sm outline-none transition-colors"
              placeholder="manager@hobartquarry.com"
            />
          </div>

          <div>
            <label className="block font-mono text-[10px] uppercase text-slate-500 mb-2 font-bold tracking-widest">
              Contraseña Encriptada
            </label>
            <input
              type="password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              disabled={isLoading}
              className="w-full bg-slate-900 border border-slate-700 focus:border-blue-500 rounded-xl px-4 py-4 text-white font-mono text-sm outline-none transition-colors"
              placeholder="••••••••"
            />
          </div>

          <button
            type="submit"
            disabled={isLoading || !email || !password}
            className="w-full bg-blue-600 hover:bg-blue-500 disabled:opacity-50 text-white font-black py-4 mt-4 rounded-xl uppercase tracking-widest text-xs shadow-xl transition-all flex justify-center items-center gap-2 border border-blue-400"
          >
            {isLoading ? 'VERIFICANDO EN CAPA 0...' : 'INICIAR SESIÓN ➔'}
          </button>
        </form>

        <button
          onClick={onBackToSelector}
          className="mt-8 text-[10px] font-mono text-slate-600 hover:text-slate-400 underline uppercase block w-full text-center transition-colors"
        >
          [ CAMBIAR PROPÓSITO DE ESTE DISPOSITIVO ]
        </button>
      </div>
    </div>
  );
};

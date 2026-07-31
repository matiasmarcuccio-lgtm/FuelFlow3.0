import React, { useState } from 'react';
import { supabase } from '../../lib/supabase';

interface InviteRegistrationProps {
  inviteToken: string;
}

export const InviteRegistration: React.FC<InviteRegistrationProps> = ({ inviteToken }) => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [fullName, setFullName] = useState('');
  const [pin, setPin] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubmitting(true);
    setError(null);

    try {
      // 1. Crear identidad en GoTrue (Trigger handle_new_user lo deja en pending_onboarding)
      const { error: signUpError } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: {
            full_name: fullName
          }
        }
      });

      if (signUpError) throw signUpError;
      
      // Esperar 1 segundo para asegurar que GoTrue haya replicado la sesión
      await new Promise(resolve => setTimeout(resolve, 1000));

      // 2. Consumir la invitación (Asigna fleet_id y el rol verdadero)
      const { error: consumeError } = await supabase.rpc('fn_consume_fleet_invite', {
        p_token: inviteToken
      });
      if (consumeError) throw new Error(`Fallo al vincular flota: ${consumeError.message}`);

      // 3. Sellar el PIN Militar
      const { error: pinError } = await supabase.rpc('fn_set_operator_pin', {
        p_pin: pin
      });
      if (pinError) throw new Error(`Fallo al establecer PIN: ${pinError.message}`);

      setSuccess(true);
    } catch (err: unknown) {
      console.error('Error in registration:', err);
      const e = err as Error;
      setError(e.message || 'Registration failed. Please contact the Fleet Manager.');
    } finally {
      setIsSubmitting(false);
    }
  };

  if (success) {
    return (
      <div className="min-h-screen bg-slate-950 flex flex-col items-center justify-center p-6 font-sans select-none text-white">
        <div className="max-w-md w-full bg-emerald-950/30 border-2 border-emerald-800 rounded-3xl p-8 text-center shadow-2xl">
          <div className="text-5xl mb-4">✅</div>
          <h1 className="text-2xl font-black uppercase tracking-tight mb-2 text-emerald-400">
            Identidad Criptográfica Creada
          </h1>
          <p className="text-slate-400 font-mono text-xs mb-8">
            El sistema ha verificado su token y sellado su jurisdicción.
          </p>
          <button
            onClick={() => window.location.href = '/'}
            className="w-full bg-emerald-600 hover:bg-emerald-500 text-black font-black py-4 rounded-xl uppercase tracking-widest transition-colors shadow-lg shadow-emerald-600/20"
          >
            INGRESAR A TERMINAL
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-slate-950 flex flex-col items-center justify-center p-6 font-sans select-none text-white">
      <div className="max-w-md w-full bg-slate-900 border-2 border-slate-800 rounded-3xl p-8 shadow-2xl relative overflow-hidden">
        {/* Decoración de alta seguridad */}
        <div className="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-blue-600 to-indigo-600"></div>
        <div className="absolute top-8 right-8 w-2 h-2 rounded-full bg-amber-500 animate-pulse"></div>

        <span className="bg-blue-900/50 text-blue-400 font-mono font-black text-[10px] px-3 py-1 uppercase rounded tracking-widest border border-blue-800/50">
          WHS TASMANIA • ONBOARDING
        </span>
        
        <h1 className="text-3xl font-black uppercase tracking-tight mt-4 mb-2">
          Registro Operativo
        </h1>
        <p className="text-slate-400 font-mono text-xs mb-8">
          Bienvenido. El Command Center le ha asignado el Token <strong className="text-white">[{inviteToken.substring(0, 6)}...]</strong>. 
          Complete sus datos para reclamar su jurisdicción en la flota.
        </p>

        {error && (
          <div className="bg-red-950/50 border border-red-800 text-red-400 p-4 rounded-lg mb-6 font-mono text-xs uppercase text-center">
            ⚠️ {error}
          </div>
        )}

        <form onSubmit={handleRegister} className="flex flex-col gap-4">
          <div>
            <label className="block text-[10px] font-mono text-slate-500 uppercase mb-1">Nombre Completo Legítimo</label>
            <input
              type="text"
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-3 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 transition-colors outline-none placeholder-slate-700 font-medium"
              placeholder="Ej: John Doe"
              required
            />
          </div>

          <div>
            <label className="block text-[10px] font-mono text-slate-500 uppercase mb-1">Correo Electrónico WHS</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-3 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 transition-colors outline-none placeholder-slate-700 font-medium"
              placeholder="operario@jitsite.com"
              required
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-[10px] font-mono text-slate-500 uppercase mb-1">Credencial WHS (Contraseña)</label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-3 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 transition-colors outline-none placeholder-slate-700 font-medium"
                placeholder="Mínimo 6 caracteres"
                required
                minLength={6}
              />
            </div>
            <div>
              <label className="block text-[10px] font-mono text-slate-500 uppercase mb-1">PIN Operativo Kiosco (4 Dígitos)</label>
              <input
                type="password"
                value={pin}
                onChange={(e) => setPin(e.target.value.replace(/\D/g, '').slice(0, 4))}
                className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-3 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 transition-colors outline-none placeholder-slate-700 font-mono tracking-widest text-center"
                placeholder="****"
                required
                maxLength={4}
                minLength={4}
                pattern="\d{4}"
              />
            </div>
          </div>

          <button
            type="submit"
            disabled={isSubmitting}
            className="w-full bg-blue-600 hover:bg-blue-500 disabled:bg-slate-800 disabled:text-slate-500 text-white font-black py-4 rounded-xl uppercase tracking-widest transition-all mt-4 shadow-lg shadow-blue-600/20"
          >
            {isSubmitting ? 'VERIFICANDO ADUANA...' : 'ESTABLECER IDENTIDAD'}
          </button>
        </form>

        <p className="text-center text-[9px] text-slate-600 font-mono mt-6 uppercase">
          La creación de esta cuenta sella su responsabilidad legal sobre la maquinaria despachada por JITSite.
        </p>
      </div>
    </div>
  );
};

import React, { useState, useRef, useEffect } from 'react';
import { supabase } from '../lib/supabase';

interface OperatorJoinProps {
  onEnrollmentComplete: () => void;
}

export const OperatorJoinScreen: React.FC<OperatorJoinProps> = ({ onEnrollmentComplete }) => {
  // Estado de la esclusa: Paso 1 (Token SMS 6 letras) -> Paso 2 (PIN 4 dígitos)
  const [step, setStep] = useState<'TOKEN' | 'PIN_SETUP'>('TOKEN');
  
  // Estado para el Token de 6 caracteres (ej. 74BEAF)
  const [token, setToken] = useState<string[]>(Array(6).fill(''));
  const tokenRefs = useRef<(HTMLInputElement | null)[]>([]);

  // Estado para el PIN militar de 4 dígitos (ej. 0426)
  const [pin, setPin] = useState<string[]>(Array(4).fill(''));
  const pinRefs = useRef<(HTMLInputElement | null)[]>([]);

  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [isProcessing, setIsProcessing] = useState<boolean>(false);

  // Auto-enfoque inicial
  useEffect(() => {
    if (step === 'TOKEN') {
      tokenRefs.current[0]?.focus();
    } else {
      pinRefs.current[0]?.focus();
    }
  }, [step]);

  // MANEJADOR FÍSICO PARA TOKEN DE 6 CASILLAS (Alfanumérico Mayúsculas)
  const handleTokenChange = (index: number, value: string) => {
    const cleanValue = value.toUpperCase().replace(/[^A-Z0-9]/g, '');
    if (!cleanValue) return;

    const newToken = [...token];
    newToken[index] = cleanValue[0]; // Solo tomar el primer carácter digitado
    setToken(newToken);
    setErrorMsg(null);

    // Salto óptico automático a la siguiente casilla en milisegundos
    if (index < 5 && cleanValue[0]) {
      tokenRefs.current[index + 1]?.focus();
    }
  };

  const handleTokenKeyDown = (index: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Backspace') {
      if (!token[index] && index > 0) {
        // Si la casilla actual está vacía, retroceder y borrar la anterior
        tokenRefs.current[index - 1]?.focus();
        const newToken = [...token];
        newToken[index - 1] = '';
        setToken(newToken);
      } else {
        const newToken = [...token];
        newToken[index] = '';
        setToken(newToken);
      }
    }
  };

  // Interceptor para cuando pegan el texto completo "74BEAF" de golpe
  const handleTokenPaste = (e: React.ClipboardEvent<HTMLInputElement>) => {
    e.preventDefault();
    const pastedData = e.clipboardData.getData('text').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 6);
    if (!pastedData) return;

    const newToken = [...token];
    pastedData.split('').forEach((char, i) => {
      if (i < 6) newToken[i] = char;
    });
    setToken(newToken);
    
    // Enfocar la última casilla llena o la siguiente disponible
    const nextFocusIndex = Math.min(pastedData.length, 5);
    tokenRefs.current[nextFocusIndex]?.focus();
  };

  // MANEJADOR FÍSICO PARA PIN DE 4 DÍGITOS (Solo Números)
  const handlePinChange = (index: number, value: string) => {
    const cleanValue = value.replace(/[^0-9]/g, '');
    if (!cleanValue) return;

    const newPin = [...pin];
    newPin[index] = cleanValue[0];
    setPin(newPin);
    setErrorMsg(null);

    if (index < 3 && cleanValue[0]) {
      pinRefs.current[index + 1]?.focus();
    }
  };

  const handlePinKeyDown = (index: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Backspace') {
      if (!pin[index] && index > 0) {
        pinRefs.current[index - 1]?.focus();
        const newPin = [...pin];
        newPin[index - 1] = '';
        setPin(newPin);
      } else {
        const newPin = [...pin];
        newPin[index] = '';
        setPin(newPin);
      }
    }
  };

  // VERIFICACIÓN DEL TOKEN EN CAPA 0
  const verifyToken = async () => {
    const fullToken = token.join('');
    if (fullToken.length !== 6) {
      setErrorMsg('INCOMPLETE_TOKEN: Digite los 6 caracteres recibidos por SMS.');
      return;
    }

    setIsProcessing(true);
    setErrorMsg(null);

    try {
      // 1. Establecer Identidad Anónima de Hardware si la tablet es "virgen"
      const { data: sessionData } = await supabase.auth.getSession();
      if (!sessionData.session) {
        const { error: anonError } = await supabase.auth.signInAnonymously();
        if (anonError) throw new Error('El backend rechazó la conexión anónima. Habilite "Anonymous Sign-ins" en Supabase.');
        
        // Mitigación de Desfase de Reloj (Clock Drift): GoTrue puede emitir el JWT 
        // unos milisegundos en el "futuro" relativo al reloj de PostgREST.
        await new Promise(resolve => setTimeout(resolve, 2500));
      }

      // 2. Llamada al RPC de PostgreSQL que valida el token y vincula la tablet
      const { error } = await supabase.rpc('fn_consume_fleet_invite', {
        p_token: fullToken
      });

      if (error) throw new Error(error.message);

      // Si el token es legítimo, avanzamos al Paso 2: Creación de PIN
      setIsProcessing(false);
      setStep('PIN_SETUP');
    } catch (err: any) {
      setIsProcessing(false);
      setErrorMsg(`TOKEN_INVALIDO: ${err.message || 'El código expiró o no existe en la flota.'}`);
    }
  };

  // GUARDADO DEL PIN MILITAR Y ENTRADA AL PRE-START
  const finalizeEnrollment = async () => {
    const fullPin = pin.join('');
    if (fullPin.length !== 4) {
      setErrorMsg('PIN_INCOMPLETO: Configure un PIN numérico de 4 dígitos.');
      return;
    }

    setIsProcessing(true);
    try {
      // Guardar el hash del PIN en el perfil del conductor (Capa 0)
      const { error } = await supabase.rpc('fn_set_operator_pin', {
        p_pin: fullPin
      });

      if (error) throw new Error(error.message);

      // Enrolamiento finalizado, expulsamos al operador hacia el Kiosco
      onEnrollmentComplete();
    } catch (err: any) {
      setIsProcessing(false);
      setErrorMsg(`FALLO_DE_REGISTRO: ${err.message}`);
    }
  };

  return (
    <div className="min-h-screen bg-black text-white flex flex-col justify-between p-6 md:p-12 font-sans select-none">
      {/* Cabecera Industrial */}
      <header className="border-b-2 border-slate-800 pb-6">
        <div className="flex justify-between items-center">
          <span className="bg-blue-600 font-mono text-xs font-black px-3 py-1 uppercase tracking-widest text-black">
            JITSITE HOBART • ONBOARDING
          </span>
          <span className="text-slate-500 font-mono text-xs uppercase">
            {step === 'TOKEN' ? 'PASO 1 DE 2: VINCULACIÓN' : 'PASO 2 DE 2: SEGURIDAD'}
          </span>
        </div>
      </header>

      {/* Contenedor Principal */}
      <main className="max-w-2xl mx-auto w-full my-auto py-8">
        {step === 'TOKEN' ? (
          <div className="bg-slate-950 border-2 border-slate-800 p-8 md:p-12 rounded-3xl shadow-2xl animate-fade-in">
            <div className="w-16 h-16 bg-blue-500/10 border border-blue-500/20 rounded-2xl flex items-center justify-center mb-6 text-3xl">
              📲
            </div>
            <h1 className="text-3xl md:text-4xl font-black uppercase tracking-tight mb-2">
              Ingrese Código de Flota
            </h1>
            <p className="text-slate-400 font-mono text-sm mb-8 leading-relaxed">
              Digite el token alfanumérico de 6 caracteres enviado por SMS a su teléfono de bolsillo. Este paso se ejecuta <span className="text-amber-400 font-bold">una sola vez</span> para registrar esta tablet.
            </p>

            {/* Matriz táctil gigante para guantes (6 casillas) */}
            <div className="grid grid-cols-6 gap-2 md:gap-4 mb-8">
              {token.map((char, i) => (
                <input
                  key={i}
                  ref={(el) => { tokenRefs.current[i] = el; }}
                  type="text"
                  inputMode="text"
                  autoCapitalize="characters"
                  autoCorrect="off"
                  autoComplete="off"
                  maxLength={1}
                  value={char}
                  onChange={(e) => handleTokenChange(i, e.target.value)}
                  onKeyDown={(e) => handleTokenKeyDown(i, e)}
                  onPaste={handleTokenPaste}
                  disabled={isProcessing}
                  className="w-full h-16 md:h-20 bg-slate-900 border-2 border-slate-700 focus:border-blue-500 rounded-xl text-center font-mono text-2xl md:text-3xl font-black text-white outline-none transition-all focus:scale-105 disabled:opacity-50"
                />
              ))}
            </div>

            {errorMsg && (
              <div className="bg-red-950/60 border border-red-800 p-4 rounded-xl mb-6 font-mono text-xs text-red-300 uppercase">
                ⚠️ {errorMsg}
              </div>
            )}

            <button
              onClick={verifyToken}
              disabled={isProcessing || token.join('').length < 6}
              className="w-full bg-blue-600 hover:bg-blue-500 disabled:opacity-30 text-white font-black py-6 rounded-2xl uppercase tracking-widest text-sm shadow-xl transition-all flex justify-center items-center gap-3"
            >
              {isProcessing ? 'VERIFICANDO EN CAPA 0...' : 'VINCULAR TABLET CON LA FLOTA ➔'}
            </button>
          </div>
        ) : (
          <div className="bg-slate-950 border-2 border-emerald-500/50 p-8 md:p-12 rounded-3xl shadow-2xl animate-fade-in">
            <div className="w-16 h-16 bg-emerald-500/10 border border-emerald-500/20 rounded-2xl flex items-center justify-center mb-6 text-3xl">
              🔒
            </div>
            <h1 className="text-3xl md:text-4xl font-black uppercase tracking-tight mb-2 text-emerald-400">
              Cree su PIN Rápido
            </h1>
            <p className="text-slate-400 font-mono text-sm mb-8 leading-relaxed">
              La tablet ha sido vinculada. Ahora defina un PIN de 4 dígitos. A partir de mañana, usará exclusivamente este PIN para iniciar su jornada de trabajo en menos de 2 segundos.
            </p>

            {/* Matriz táctil para PIN militar (4 casillas) */}
            <div className="grid grid-cols-4 gap-4 max-w-xs mx-auto mb-8">
              {pin.map((digit, i) => (
                <input
                  key={i}
                  ref={(el) => { pinRefs.current[i] = el; }}
                  type="text"
                  inputMode="numeric"
                  pattern="[0-9]*"
                  maxLength={1}
                  value={digit}
                  onChange={(e) => handlePinChange(i, e.target.value)}
                  onKeyDown={(e) => handlePinKeyDown(i, e)}
                  disabled={isProcessing}
                  className="w-full h-20 bg-slate-900 border-2 border-slate-700 focus:border-emerald-500 rounded-xl text-center font-mono text-3xl font-black text-emerald-400 outline-none transition-all focus:scale-105 disabled:opacity-50"
                />
              ))}
            </div>

            {errorMsg && (
              <div className="bg-red-950/60 border border-red-800 p-4 rounded-xl mb-6 font-mono text-xs text-red-300 uppercase">
                ⚠️ {errorMsg}
              </div>
            )}

            <button
              onClick={finalizeEnrollment}
              disabled={isProcessing || pin.join('').length < 4}
              className="w-full bg-emerald-600 hover:bg-emerald-500 disabled:opacity-30 text-black font-black py-6 rounded-2xl uppercase tracking-widest text-sm shadow-xl transition-all flex justify-center items-center gap-3"
            >
              {isProcessing ? 'SELLANDO IDENTIDAD...' : 'GUARDAR PIN Y ENTRAR AL PRE-START ➔'}
            </button>
          </div>
        )}
      </main>

      {/* Pie de página con instrucciones WHS */}
      <footer className="border-t border-slate-900 pt-4 text-center font-mono text-xs text-slate-600 uppercase">
        Si no recibió su SMS de 6 caracteres, solicite al Fleet Manager la re-emisión del token en el Command Center.
        <br />
        Sistema protegido contra fuerza bruta • JITSite Zero-Trust Architecture
      </footer>
    </div>
  );
};

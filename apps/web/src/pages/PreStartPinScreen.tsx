import React, { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';

interface PreStartPinProps {
  operatorName: string;
  onAuthorized: () => void;
}

interface PinRpcResponse {
  success: boolean;
  status: 'AUTHORIZED' | 'INVALID_PIN' | 'LOCKED_OUT' | 'PIN_NOT_SET';
  attempts_left?: number;
  seconds_remaining?: number;
  locked_until?: string;
  msg?: string;
}

export const PreStartPinScreen: React.FC<PreStartPinProps> = ({ operatorName, onAuthorized }) => {
  const [pin, setPin] = useState<string>('');
  const [isVerifying, setIsVerifying] = useState<boolean>(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [shake, setShake] = useState<boolean>(false);
  
  // Estados para el Escudo de Retroceso Geométrico
  const [isLockedOut, setIsLockedOut] = useState<boolean>(false);
  const [countdown, setCountdown] = useState<number>(0);

  // Manejador del temporizador satelital de exclusión
  useEffect(() => {
    let timer: ReturnType<typeof setInterval>;
    if (isLockedOut && countdown > 0) {
      timer = setInterval(() => {
        setCountdown((prev) => {
          if (prev <= 1) {
            setIsLockedOut(false);
            setErrorMessage(null);
            return 0;
          }
          return prev - 1;
        });
      }, 1000);
    }
    return () => clearInterval(timer);
  }, [isLockedOut, countdown]);

  // Disparo de animación de temblor visual (Shake)
  const triggerShake = () => {
    setShake(true);
    setTimeout(() => setShake(false), 500);
  };

  // Verificación contra el motor PostgreSQL en Capa 0
  const verifyPinInLayerZero = async (pinToTest: string) => {
    setIsVerifying(true);
    setErrorMessage(null);

    try {
      const { data, error } = await supabase.rpc('fn_verify_operator_pin', {
        p_pin: pinToTest,
      });

      if (error) throw new Error(error.message);

      const response = data as PinRpcResponse;

      if (response.success && response.status === 'AUTHORIZED') {
        setIsVerifying(false);
        onAuthorized(); // Catapultar al Kiosco Pre-Start
        return;
      }

      // Análisis forense de fallos devueltos por el motor SQL
      setIsVerifying(false);
      setPin(''); // Limpiar casillas al instante
      triggerShake();

      if (response.status === 'LOCKED_OUT') {
        setIsLockedOut(true);
        setCountdown(response.seconds_remaining || 60);
        setErrorMessage(response.msg || 'Terminal temporalmente congelada.');
      } else if (response.status === 'INVALID_PIN') {
        setErrorMessage(response.msg || `PIN incorrecto. Quedan ${response.attempts_left} intentos.`);
      } else {
        setErrorMessage('ERROR_ESTRUCTURAL: No se pudo verificar la identidad en el servidor.');
      }
    } catch (err: any) {
      setIsVerifying(false);
      setPin('');
      triggerShake();
      setErrorMessage(`FRACTURA DE RED: ${err.message || 'Sin conexión al Command Center.'}`);
    }
  };

  // Entrada de dígitos desde el teclado matricial industrial
  const handlePadPress = (digit: string) => {
    if (isVerifying || isLockedOut) return;

    if (digit === 'CLEAR') {
      setPin('');
      setErrorMessage(null);
      return;
    }

    if (digit === 'BACK') {
      setPin((prev) => prev.slice(0, -1));
      return;
    }

    if (pin.length < 4) {
      const nextPin = pin + digit;
      setPin(nextPin);
      setErrorMessage(null);

      // Auto-envío en el milisegundo en que se digita el 4to número
      if (nextPin.length === 4) {
        verifyPinInLayerZero(nextPin);
      }
    }
  };

  // Formateador visual para el reloj de cuenta regresiva (MM:SS)
  const formatCountdown = (secs: number) => {
    const m = Math.floor(secs / 60).toString().padStart(2, '0');
    const s = (secs % 60).toString().padStart(2, '0');
    return `${m}:${s}`;
  };

  return (
    <div className="min-h-screen bg-black text-white flex flex-col justify-between p-6 select-none font-sans overflow-hidden">
      {/* Estilos inyectados para la animación de temblor háptico */}
      <style>{`
        @keyframes industrialShake {
          0%, 100% { transform: translateX(0); }
          20%, 60% { transform: translateX(-12px); }
          40%, 80% { transform: translateX(12px); }
        }
        .animate-shake { animation: industrialShake 0.4s cubic-bezier(.36,.07,.19,.97) both; }
      `}</style>

      {/* Cabecera de Identificación de Cabina */}
      <header className="border-b-2 border-slate-800 pb-4 flex justify-between items-center">
        <div className="flex items-center gap-3">
          <span className="w-3 h-3 bg-emerald-500 rounded-full animate-ping"></span>
          <span className="font-mono text-xs uppercase tracking-widest text-slate-400">
            TERMINAL DE CABINA • PRE-START WHS
          </span>
        </div>
        <div className="font-mono text-xs text-slate-500 uppercase">
          OPERARIO ASIGNADO: <span className="text-white font-bold">{operatorName}</span>
        </div>
      </header>

      {/* Cuerpo Principal: Esclusa Visual y Teclado Matricial */}
      <main className="max-w-md mx-auto w-full my-auto py-6 flex flex-col items-center">
        
        {/* Pantalla Visual de 4 Dígitos (Sin etiqueta <input> para evadir el teclado del OS) */}
        <div className={`w-full bg-slate-950 border-4 ${isLockedOut ? 'border-red-600 bg-red-950/20' : errorMessage ? 'border-amber-500' : 'border-slate-800'} rounded-3xl p-6 mb-8 text-center transition-colors shadow-2xl ${shake ? 'animate-shake' : ''}`}>
          
          <p className="font-mono text-xs text-slate-500 uppercase tracking-widest mb-3">
            {isLockedOut ? '🛑 SISTEMA EN RETROCESO GEOMÉTRICO' : 'DIGITE SU PIN MILITAR DE 4 DÍGITOS'}
          </p>

          {isLockedOut ? (
            <div className="py-2 animate-pulse">
              <span className="font-mono text-5xl font-black text-red-500 tracking-tight block mb-1">
                {formatCountdown(countdown)}
              </span>
              <span className="text-[10px] font-mono text-red-400 uppercase tracking-wider block">
                Bloqueo activo por seguridad. Solicite indulto por radio VHF si es una emergencia.
              </span>
            </div>
          ) : (
            <div className="flex justify-center gap-4 py-2">
              {[0, 1, 2, 3].map((index) => {
                const isFilled = index < pin.length;
                return (
                  <div
                    key={index}
                    className={`w-14 h-16 md:w-16 md:h-20 rounded-2xl flex items-center justify-center font-mono text-3xl font-black transition-all ${
                      isFilled
                        ? 'bg-blue-600 text-white shadow-lg shadow-blue-600/30 scale-105'
                        : 'bg-slate-900 border-2 border-slate-800 text-transparent'
                    }`}
                  >
                    {isFilled ? '•' : ''}
                  </div>
                );
              })}
            </div>
          )}

          {/* Banner de Mensajes de Error y Estado */}
          {errorMessage && !isLockedOut && (
            <p className="mt-4 text-xs font-mono font-bold text-amber-400 uppercase tracking-wide bg-amber-950/40 border border-amber-800/60 py-2 px-3 rounded-xl">
              ⚠️ {errorMessage}
            </p>
          )}

          {isVerifying && (
            <p className="mt-4 text-xs font-mono font-bold text-blue-400 uppercase tracking-widest animate-pulse">
              ⚡ COMPROBANDO HASH BCRYPT EN CAPA 0...
            </p>
          )}
        </div>

        {/* Teclado Matricial Industrial (Botones masivos para guantes mecánicos) */}
        <div className="w-full grid grid-cols-3 gap-3 md:gap-4">
          {['1', '2', '3', '4', '5', '6', '7', '8', '9', 'CLEAR', '0', 'BACK'].map((key) => {
            const isSpecial = key === 'CLEAR' || key === 'BACK';
            return (
              <button
                key={key}
                type="button"
                disabled={isVerifying || isLockedOut}
                onClick={() => handlePadPress(key)}
                className={`h-20 md:h-24 rounded-2xl font-mono font-black text-2xl md:text-3xl uppercase tracking-wider transition-all active:scale-95 disabled:opacity-20 flex items-center justify-center shadow-xl ${
                  isSpecial
                    ? 'bg-slate-900 border-2 border-slate-800 text-slate-400 hover:text-white hover:bg-slate-800 text-sm md:text-base'
                    : 'bg-slate-900 hover:bg-slate-800 text-white border border-slate-700 hover:border-slate-500'
                }`}
              >
                {key === 'BACK' ? '⌫' : key === 'CLEAR' ? 'C' : key}
              </button>
            );
          })}
        </div>
      </main>

      {/* Pie de página con directiva legal */}
      <footer className="border-t border-slate-900 pt-3 text-center font-mono text-[10px] text-slate-600 uppercase">
        El intento de suplantación de identidad en este terminal constituye un delito bajo las leyes WHS de Tasmania.
        <br />
        Criptografía de Grado Servidor • JITSite Zero-Trust Engine
      </footer>
    </div>
  );
};

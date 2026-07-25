import { useState, useEffect } from 'react';
import { ShieldAlert, Signal, SignalZero, CheckCircle2, PowerOff } from 'lucide-react';

interface HandoverPresenterProps {
  onVerify: (pin: string, operatorId: string) => Promise<void>;
  onGracefulShutdown?: (pin: string, operatorId: string) => Promise<void>;
  isPending: boolean;
  isLocked: boolean;
  lockoutTimeRemaining: number;
  roster: { user_id: string; full_name: string }[];
  isGeolocked: boolean;
  geoMessage: string;
  mode?: 'handover' | 'shutdown';
}

export const HandoverPresenter: React.FC<HandoverPresenterProps> = ({
  onVerify,
  onGracefulShutdown,
  isPending,
  isLocked,
  lockoutTimeRemaining,
  roster,
  isGeolocked,
  geoMessage,
  mode = 'handover',
}) => {
  const [pin, setPin] = useState('');
  const [operatorId, setOperatorId] = useState('');
  const [isOffline, setIsOffline] = useState(!navigator.onLine);

  useEffect(() => {
    const handleOnline = () => setIsOffline(false);
    const handleOffline = () => setIsOffline(true);
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  const handlePinChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    // Phase 2: Motor Háptico Nativo
    if (navigator.vibrate) navigator.vibrate(50); // Golpe seco de 50ms
    
    // Solo permitir números y hasta 4 dígitos
    const val = e.target.value.replace(/\D/g, '').slice(0, 4);
    setPin(val);
  };

  const unlockAudioContext = () => {
    if ('speechSynthesis' in window) {
      const silentUtterance = new SpeechSynthesisUtterance('');
      silentUtterance.volume = 0;
      window.speechSynthesis.speak(silentUtterance);
    }
  };

  const handleVerify = async () => {
    if (pin.length === 4 && operatorId) {
      if (navigator.vibrate) navigator.vibrate([100, 50, 100]); // Patrón de éxito/intento
      unlockAudioContext(); // 1. Inyección de la llave acústica
      try {
        await onVerify(pin, operatorId);
        setPin(''); // Clear si es exitoso (o si el container lo maneja)
      } catch (e) {
        setPin(''); // Clear el pin al fallar para el próximo intento
      }
    }
  };

  const handleShutdown = async () => {
    if (pin.length === 4 && operatorId && onGracefulShutdown) {
      if (navigator.vibrate) navigator.vibrate([200, 100, 200]);
      unlockAudioContext(); // 1. Inyección de la llave acústica
      try {
        await onGracefulShutdown(pin, operatorId);
        setPin('');
      } catch (e) {
        setPin('');
      }
    }
  };

  if (isLocked) {
    return (
      <div className="flex flex-col items-center justify-center min-h-screen bg-red-950 p-6">
        <ShieldAlert className="w-32 h-32 text-red-500 mb-8 animate-pulse" />
        <h1 className="text-4xl font-bold text-red-500 mb-4 text-center">BLOQUEO DE SEGURIDAD</h1>
        <p className="text-2xl text-red-200 text-center mb-8">Demasiados intentos fallidos. Sistema bloqueado preventivamente.</p>
        <div className="text-8xl font-black text-foreground">{lockoutTimeRemaining}s</div>
      </div>
    );
  }

  return (
    <div className="flex flex-col min-h-screen bg-background text-foreground font-sans">
      {/* Barra de Estado Táctica */}
      <div className={`p-4 flex items-center justify-center gap-3 font-bold text-lg uppercase tracking-widest ${isOffline ? 'bg-amber-500 text-slate-900' : 'bg-emerald-600 text-white'}`}>
        {isOffline ? <SignalZero size={24} /> : <Signal size={24} />}
        {isOffline ? 'MODO OFFLINE: FIRMA LOCAL ACTIVA' : 'SISTEMA EN LÍNEA'}
      </div>

      <div className="flex-1 flex flex-col p-6 max-w-2xl mx-auto w-full">
        <h2 className="text-3xl font-black text-foreground mb-8 text-center uppercase tracking-tight">Traspaso de Equipo</h2>
        
        {/* Selector de Operario Gigante */}
        <div className="mb-8">
          <label className="block text-xl font-bold text-on-surface-variant mb-4 uppercase">Operario Entrante / Saliente</label>
          <div className="grid grid-cols-1 gap-4">
            {roster?.map((operator) => (
              <button
                key={operator.user_id}
                type="button"
                onClick={() => {
                  if (navigator.vibrate) navigator.vibrate(20);
                  setOperatorId(operator.user_id);
                }}
                className={`py-6 px-4 rounded-xl text-2xl font-bold transition-all border-4 ${
                  operatorId === operator.user_id 
                    ? 'bg-primary text-on-primary border-blue-400 text-white shadow-[0_0_20px_rgba(37,99,235,0.5)]' 
                    : 'bg-surface border border-outline-variant shadow-sm border-outline-variant text-on-surface hover:bg-surface-variant'
                }`}
              >
                {operator.full_name}
              </button>
            ))}
          </div>
        </div>

        {/* Phase 2: Input Semántico Central y Bloqueo Geofísico */}
        <div className="mb-8">
          <label className="block text-xl font-bold text-on-surface-variant mb-4 uppercase text-center">Firma (PIN de 4 dígitos)</label>
          
          {isGeolocked ? (
            <div className="w-full bg-red-900/50 text-red-200 text-2xl text-center p-8 rounded-2xl border-4 border-red-500 font-bold shadow-[0_0_30px_rgba(239,68,68,0.4)]">
              {geoMessage}
            </div>
          ) : (
            <input 
              type="password" 
              inputMode="numeric" 
              pattern="[0-9]*" 
              autoComplete="off" 
              value={pin}
              onChange={handlePinChange}
              className="w-full bg-surface border border-outline-variant shadow-sm text-foreground text-6xl text-center py-8 rounded-2xl border-4 border-outline-variant focus:border-blue-500 focus:outline-none tracking-[0.5em] font-black shadow-inner"
              placeholder="••••"
            />
          )}
        </div>

        {/* Botones de Acción */}
        <div className="mt-auto flex flex-col gap-4">
          {mode === 'handover' && (
            <button
              onClick={handleVerify}
              disabled={pin.length !== 4 || !operatorId || isPending || isGeolocked}
              className="bg-primary text-on-primary disabled:bg-surface border border-outline-variant shadow-sm disabled:text-outline-variant disabled:border-outline-variant active:scale-95 transition-all text-white flex justify-center items-center py-6 rounded-2xl shadow-[0_0_20px_rgba(37,99,235,0.4)] disabled:shadow-none border border-blue-400"
            >
              {isPending ? (
                <div className="w-8 h-8 border-4 border-white border-t-transparent rounded-full animate-spin"></div>
              ) : (
                <span className="text-2xl font-black uppercase flex items-center gap-4"><CheckCircle2 size={32} /> INICIAR TURNO</span>
              )}
            </button>
          )}

          {mode === 'shutdown' && (
            <button
              onClick={handleShutdown}
              disabled={pin.length !== 4 || !operatorId || isPending}
              className="bg-surface border border-outline-variant shadow-sm hover:bg-surface-variant disabled:opacity-50 active:scale-95 transition-all text-amber-500 flex justify-center items-center py-6 rounded-2xl border border-amber-500/50"
            >
              {isPending ? (
                <div className="w-8 h-8 border-4 border-amber-500 border-t-transparent rounded-full animate-spin"></div>
              ) : (
                <span className="text-xl font-black uppercase flex items-center gap-4"><PowerOff size={28} /> FINALIZAR OPERACIÓN</span>
              )}
            </button>
          )}
        </div>
      </div>
    </div>
  );
};

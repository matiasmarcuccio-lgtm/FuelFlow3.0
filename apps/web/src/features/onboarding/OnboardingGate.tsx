import React, { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { PaymentSetupForm } from './PaymentSetupForm';
import { Elements } from '@stripe/react-stripe-js';
import { loadStripe } from '@stripe/stripe-js';

const stripePromise = loadStripe(import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY || '');

export const OnboardingGate: React.FC<{ userEmail: string; userId: string }> = ({ userEmail, userId }) => {
  const [clientSecret, setClientSecret] = useState<string | null>(null);
  const [fleetName, setFleetName] = useState<string>('');
  const [step, setStep] = useState<'NAME' | 'CARD' | 'PROCESING'>('NAME');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // 1. Suscripción Realtime a cambios en nuestra propia fila de perfiles
    const profileSubscription = supabase
      .channel(`profile_onboarding_${userId}`)
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'profiles', filter: `id=eq.${userId}` },
        (payload) => {
          if (payload.new && payload.new.role === 'account_owner') {
            window.location.reload(); // Ascenso detectado: recargar para liberar el Command Center
          }
        }
      )
      .subscribe();

    // 2. Respaldo de Polling activo cada 4s si el usuario ya envió su tarjeta
    let pollingInterval: NodeJS.Timeout;
    if (step === 'PROCESING') {
      pollingInterval = setInterval(async () => {
        const { data } = await supabase.from('profiles').select('role').eq('id', userId).single();
        if (data?.role === 'account_owner') {
          window.location.reload();
        }
      }, 4000);
    }

    return () => {
      supabase.removeChannel(profileSubscription);
      if (pollingInterval) clearInterval(pollingInterval);
    };
  }, [userId, step]);

  const handleCreateIntent = async (e: React.FormEvent) => {
    e.preventDefault();
    if (fleetName.trim().length < 3) return setError('El nombre de la mina debe tener al menos 3 caracteres.');
    
    setError(null);
    try {
      const { data, error: fnError } = await supabase.functions.invoke('create-setup-intent', {
        body: { fleetName }
      });
      
      // Supabase-js a veces oculta el cuerpo del error real dentro de fnError.context
      if (fnError) {
        if (fnError.context && typeof fnError.context.json === 'function') {
           const errBody = await fnError.context.json().catch(() => ({}));
           throw new Error(errBody.error || fnError.message);
        }
        // Alternativamente, a veces viene como fnError.message
        throw new Error(fnError.message || 'Error al conectar con la pasarela.');
      }
      
      setClientSecret(data.client_secret);
      setStep('CARD');
    } catch (err: any) {
      setError(err.message || 'Error al conectar con la pasarela bancaria.');
    }
  };

  return (
    <div className="min-h-screen bg-slate-950 text-white flex flex-col items-center justify-center p-6">
      <div className="max-w-md w-full bg-slate-900 border border-slate-800 rounded-xl p-8 shadow-2xl">
        <div className="text-center mb-6">
          <span className="text-3xl">🏗️</span>
          <h1 className="text-xl font-bold mt-2">Configuración de Jurisdicción Minera</h1>
          <p className="text-xs text-slate-400 font-mono mt-1">{userEmail}</p>
        </div>

        {error && <div className="p-3 mb-4 bg-rose-950 border border-rose-800 rounded text-rose-300 text-xs">⚠️ {error}</div>}

        {step === 'NAME' && (
          <form onSubmit={handleCreateIntent} className="space-y-4">
            <div>
              <label className="block text-xs font-semibold uppercase text-slate-400 mb-2">Nombre Legal de la Flota / Mina</label>
              <input
                type="text"
                value={fleetName}
                onChange={(e) => setFleetName(e.target.value)}
                placeholder="Ej. Hazell Bros Excavaciones"
                required
                className="w-full bg-slate-950 border border-slate-800 rounded-lg p-3 text-sm text-white focus:border-emerald-500 outline-none font-medium"
              />
            </div>
            <button type="submit" className="w-full py-3 bg-emerald-600 hover:bg-emerald-500 font-bold rounded-lg text-sm shadow-lg transition-all">
              Continuar a Garantía de Pago ($0 AUD) ➔
            </button>
          </form>
        )}

        {step === 'CARD' && clientSecret && (
          <Elements stripe={stripePromise} options={{ clientSecret, appearance: { theme: 'night' } }}>
            <PaymentSetupForm onProcessing={() => setStep('PROCESING')} onError={(msg) => setError(msg)} />
          </Elements>
        )}

        {step === 'PROCESING' && (
          <div className="text-center py-8 space-y-4">
            <div className="w-8 h-8 border-4 border-emerald-500 border-t-transparent rounded-full animate-spin mx-auto"></div>
            <div className="font-semibold text-sm">Validando tarjeta con el banco...</div>
            <p className="text-xs text-slate-400 leading-relaxed">
              Stripe está autorizando su método de cobro metrado y generando su bóveda minera en Hobart. No cierre esta ventana.
            </p>
          </div>
        )}
      </div>
    </div>
  );
};

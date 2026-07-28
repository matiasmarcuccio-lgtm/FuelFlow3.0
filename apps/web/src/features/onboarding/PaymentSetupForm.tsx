import React, { useState } from 'react';
import { useStripe, useElements, PaymentElement } from '@stripe/react-stripe-js';

export const PaymentSetupForm: React.FC<{ onProcessing: () => void; onError: (msg: string) => void }> = ({ onProcessing, onError }) => {
  const stripe = useStripe();
  const elements = useElements();
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!stripe || !elements) return;

    setLoading(true);
    const { error } = await stripe.confirmSetup({
      elements,
      confirmParams: {
        return_url: window.location.href, // Redirección de respaldo si el banco exige 3D Secure (3DS)
      },
      redirect: 'if_required',
    });

    if (error) {
      onError(error.message || 'La tarjeta fue rechazada por la entidad bancaria.');
      setLoading(false);
    } else {
      // SetupIntent aprobado: notificamos al contenedor para que inicie el polling mientras el webhook hace el resto
      onProcessing();
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      <div className="p-4 bg-slate-950 rounded-lg border border-slate-800">
        <PaymentElement />
      </div>
      <button
        type="submit"
        disabled={!stripe || loading}
        className="w-full py-3 bg-emerald-600 hover:bg-emerald-500 disabled:bg-slate-800 text-white font-bold rounded-lg text-sm shadow-lg transition-all"
      >
        {loading ? 'Firma Criptográfica en Proceso...' : '🛡️ Autorizar y Fundar Mina Minera'}
      </button>
    </form>
  );
};

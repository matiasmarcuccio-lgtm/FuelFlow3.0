import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { B2BCheckoutPresenter } from '../features/billing/B2BCheckoutPresenter';
import { useCurrentProfile } from '../hooks/useCurrentProfile';

export default function PaymentFrozenScreen({ fleetId = '' }: { fleetId?: string }) {
  const { data: currentProfile } = useCurrentProfile();
  const [showCheckout, setShowCheckout] = useState(false);
  const [isSuccess, setIsSuccess] = useState(false);
  const navigate = useNavigate();

  const activeFleetId = fleetId || currentProfile?.fleet_id || '';

  const handlePaymentSuccess = async () => {
    setIsSuccess(true);
    
    setTimeout(() => {
      // Usar href para forzar una recarga completa y refrescar el AuthContext
      window.location.href = '/dispatch';
    }, 1200);
  };

  if (isSuccess) {
    return (
      <div className="min-h-screen bg-slate-950 flex items-center justify-center p-6">
        <div className="bg-emerald-950/40 border-2 border-emerald-500 rounded-2xl p-8 max-w-md text-center animate-in fade-in">
          <div className="text-5xl mb-4">🔓</div>
          <h2 className="text-2xl font-black text-white uppercase tracking-tight">Fleet Unlocked</h2>
          <p className="text-emerald-400 font-mono text-sm mt-2">
            The ledger has recorded the immutable transaction. Redirecting to Command Center...
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-slate-950 flex items-center justify-center p-6 relative overflow-hidden">
      {/* HUD de Peligro Ambiental */}
      <div 
        className="absolute inset-0 pointer-events-none opacity-20" 
        style={{ backgroundImage: 'radial-gradient(rgb(239, 68, 68) 1.5px, transparent 1.5px)', backgroundSize: '32px 32px' }}
      ></div>

      {!showCheckout ? (
        <div className="z-10 max-w-md w-full bg-slate-900 border border-slate-800 p-8 rounded-2xl text-center shadow-2xl">
          <div className="w-16 h-16 bg-red-500/10 border border-red-500/20 rounded-full flex items-center justify-center mx-auto mb-6 shadow-[0_0_30px_rgba(220,38,38,0.5)] animate-pulse">
            <span className="text-2xl">🛑</span>
          </div>
          <h1 className="text-2xl font-black text-white uppercase mb-2">Restricted Access</h1>
          <p className="text-slate-400 text-sm mb-6 font-mono">
            Your fleet's operating license is currently <span className="text-red-400 font-bold">PAST_DUE</span>. Machinery assignments and dispatch are temporarily suspended.
          </p>
          {currentProfile?.role === 'fleet_manager' ? (
            <button
              onClick={() => setShowCheckout(true)}
              className="w-full bg-blue-600 hover:bg-blue-500 text-white font-black py-4 rounded-xl uppercase tracking-widest text-sm transition-colors shadow-[0_0_20px_rgba(37,99,235,0.4)]"
            >
              UPDATE PAYMENT METHOD
            </button>
          ) : (
            <div className="bg-amber-950/30 border border-amber-500/50 p-4 rounded-xl">
              <p className="text-amber-500 font-mono text-xs uppercase font-bold mb-1">Authorization Required</p>
              <p className="text-slate-300 text-sm">Please contact your Fleet Manager. The B2B Billing Portal is restricted to authorized administrative personnel.</p>
            </div>
          )}
        </div>
      ) : (
        <div className="z-10 w-full max-w-xl animate-in fade-in">
          <button 
            onClick={() => setShowCheckout(false)}
            className="text-slate-500 hover:text-white font-mono text-xs uppercase mb-4 flex items-center gap-2 transition-colors"
          >
            ◀ Back to restriction summary
          </button>
          <B2BCheckoutPresenter
            fleetId={activeFleetId}
            amountDueAud={1450.00}
            onPaymentSuccess={handlePaymentSuccess}
          />
        </div>
      )}
    </div>
  );
}

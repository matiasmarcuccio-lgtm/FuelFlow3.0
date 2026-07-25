import React, { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';

interface B2BCheckoutProps {
  fleetId: string | undefined | null;
  amountDueAud: number;
  onPaymentSuccess: () => Promise<void>;
}

// Strict validation of UUID v4 syntax (Visual Friction Layer)
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export const B2BCheckoutPresenter: React.FC<B2BCheckoutProps> = ({
  fleetId,
  amountDueAud,
  onPaymentSuccess,
}) => {
  const queryClient = useQueryClient();

  // 1. IDENTITY SOVEREIGNTY EVALUATION
  const isFleetIdValid = Boolean(fleetId && UUID_REGEX.test(fleetId));

  const [cardNumber, setCardNumber] = useState('');
  const [expiry, setExpiry] = useState('');
  const [cvc, setCvc] = useState('');
  const [cardholderName, setCardholderName] = useState('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isProcessingBank, setIsProcessingBank] = useState(false);

  // If the router or AuthContext passed us a null or corrupt UUID,
  // we block the rendering of the financial form completely.
  if (!isFleetIdValid) {
    return (
      <div className="bg-red-950/40 border-4 border-red-600 rounded-2xl p-8 max-w-xl mx-auto shadow-2xl font-sans select-none animate-fade-in text-center">
        <div className="w-16 h-16 bg-red-600/20 border-2 border-red-600 rounded-full flex items-center justify-center mx-auto mb-6">
          <span className="text-3xl">🛑</span>
        </div>
        <h2 className="text-2xl font-black text-white uppercase tracking-tight mb-2">
          B2B Routing Fracture
        </h2>
        <p className="text-red-400 font-mono text-xs uppercase tracking-widest mb-4 font-bold">
          [PREVENTIVE 400 ERROR: MISSING OR INVALID FLEET UUID]
        </p>
        <div className="bg-black/60 border border-red-900/50 p-4 rounded-xl text-left font-mono text-xs text-slate-300 mb-6 space-y-2">
          <p><strong className="text-white">DIAGNOSIS:</strong> The interface did not receive the unique identifier for your fleet from the authentication server.</p>
          <p><strong className="text-white">RECEIVED ID:</strong> <span className="text-amber-400 font-bold">"{String(fleetId)}"</span></p>
          <p><strong className="text-white">IMPACT:</strong> Payment has been disabled to prevent orphan charges without allocation in the accounting ledger.</p>
        </div>
        <button
          onClick={() => {
            // Force clear idb-keyval caches since we persist query state
            localStorage.clear();
            sessionStorage.clear();
            window.location.reload();
          }}
          className="w-full bg-slate-800 hover:bg-slate-700 text-white font-black py-4 rounded-xl uppercase tracking-widest text-xs transition-colors border border-slate-600 shadow-lg"
        >
          🔄 RELOAD SESSION AND RESTORE IDENTITY
        </button>
      </div>
    );
  }

  const handleCardChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const raw = e.target.value.replace(/\D/g, '').slice(0, 16);
    const formatted = raw.match(/.{1,4}/g)?.join(' ') || raw;
    setCardNumber(formatted);
    if (errorMessage) setErrorMessage(null);
  };

  const handleExpiryChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const raw = e.target.value.replace(/\D/g, '').slice(0, 4);
    if (raw.length >= 3) {
      setExpiry(`${raw.slice(0, 2)}/${raw.slice(2)}`);
    } else {
      setExpiry(raw);
    }
  };

  const handleCvcChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setCvc(e.target.value.replace(/\D/g, '').slice(0, 4));
  };

  const checkoutMutation = useMutation({
    mutationFn: async () => {
      setIsProcessingBank(true);
      await new Promise((resolve) => setTimeout(resolve, 1500));

      const cleanCard = cardNumber.replace(/\s/g, '');
      if (cleanCard !== '4242424242424242') {
        throw new Error('ERR_INSUFFICIENT_FUNDS: Card rejected by issuing entity. Use a valid corporate test card.');
      }

      if (expiry.length !== 5 || cvc.length < 3 || !cardholderName.trim()) {
        throw new Error('INVALID_INPUT: Complete all cryptographic fields of the card.');
      }

      // TypeScript and the upper shield guarantee that fleetId here is a legitimate UUID string
      const { data, error } = await supabase.rpc('fn_simulate_payment_success', {
        p_fleet_id: fleetId!,
        p_amount_due: amountDueAud,
      });

      if (error) {
        if (error.message.includes('UNAUTHORIZED_ROLE')) {
          throw new Error('JURISDICTION DENIED: Your JWT lacks Fleet Manager permissions to settle debts.');
        }
        throw new Error(error.message);
      }

      return data;
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['fleet_status', fleetId] });
      await queryClient.invalidateQueries({ queryKey: ['profile'] });
      await onPaymentSuccess();
    },
    onError: (err: Error) => {
      setIsProcessingBank(false);
      setErrorMessage(err.message);
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);
    checkoutMutation.mutate();
  };

  const isBusy = isProcessingBank || checkoutMutation.isPending;

  return (
    <div className="bg-slate-950 border-2 border-slate-800 rounded-2xl p-8 max-w-xl mx-auto shadow-2xl font-sans select-none">
      <header className="border-b border-slate-800 pb-6 mb-6">
        <div className="flex justify-between items-center mb-2">
          <span className="bg-red-500/10 text-red-500 border border-red-500/30 text-xs font-mono font-bold px-3 py-1 rounded uppercase tracking-widest">
            Fleet Restricted by Non-Payment
          </span>
          <span className="text-slate-400 font-mono text-xs uppercase">UUID: {fleetId.slice(0, 8)}... (AAL2)</span>
        </div>
        <h2 className="text-3xl font-black text-white uppercase tracking-tight">B2B Settlement</h2>
        <p className="text-slate-400 text-sm mt-1">
          Enter an authorized credit card to settle the balance and instantly restore logistics dispatch.
        </p>
      </header>

      <div className="bg-slate-900/50 border border-slate-800 p-6 rounded-xl mb-6 flex justify-between items-center">
        <div>
          <p className="text-xs font-mono uppercase text-slate-500">Operating Balance Due</p>
          <p className="text-3xl font-black text-white font-mono mt-1">${amountDueAud.toFixed(2)} AUD</p>
        </div>
        <div className="text-right">
          <span className="text-xs font-bold text-amber-500 uppercase bg-amber-500/10 px-2 py-1 rounded border border-amber-500/20">
            Overdue Invoice
          </span>
          <p className="text-[10px] text-slate-500 font-mono mt-2">Includes 10% Australian GST</p>
        </div>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="block text-xs font-bold uppercase tracking-wider text-slate-400 mb-2">
            Cardholder Name (Company / Manager)
          </label>
          <input
            type="text"
            disabled={isBusy}
            value={cardholderName}
            onChange={(e) => setCardholderName(e.target.value)}
            placeholder="EX. HOBART EXCAVATIONS PTY LTD"
            className="w-full bg-slate-900 border border-slate-700 rounded-xl p-4 text-white font-mono text-sm uppercase focus:outline-none focus:border-blue-500 transition-colors disabled:opacity-50"
            required
          />
        </div>

        <div>
          <label className="block text-xs font-bold uppercase tracking-wider text-slate-400 mb-2">
            Corporate Card Number
          </label>
          <div className="relative">
            <input
              type="text"
              disabled={isBusy}
              value={cardNumber}
              onChange={handleCardChange}
              placeholder="4242 4242 4242 4242"
              maxLength={19}
              className="w-full bg-slate-900 border border-slate-700 rounded-xl p-4 text-white font-mono text-lg tracking-widest focus:outline-none focus:border-blue-500 transition-colors disabled:opacity-50"
              required
            />
            <span className="absolute right-4 top-4 text-xs font-mono text-slate-600 uppercase">
              Stripe Test
            </span>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-xs font-bold uppercase tracking-wider text-slate-400 mb-2">
              Expiration
            </label>
            <input
              type="text"
              disabled={isBusy}
              value={expiry}
              onChange={handleExpiryChange}
              placeholder="MM/YY"
              maxLength={5}
              className="w-full bg-slate-900 border border-slate-700 rounded-xl p-4 text-white font-mono text-center focus:outline-none focus:border-blue-500 transition-colors disabled:opacity-50"
              required
            />
          </div>
          <div>
            <label className="block text-xs font-bold uppercase tracking-wider text-slate-400 mb-2">
              CVC Code
            </label>
            <input
              type="password"
              disabled={isBusy}
              value={cvc}
              onChange={handleCvcChange}
              placeholder="•••"
              maxLength={4}
              className="w-full bg-slate-900 border border-slate-700 rounded-xl p-4 text-white font-mono text-center tracking-widest focus:outline-none focus:border-blue-500 transition-colors disabled:opacity-50"
              required
            />
          </div>
        </div>

        {errorMessage && (
          <div className="bg-red-950/50 border-2 border-red-800 rounded-xl p-4 animate-fade-in">
            <p className="text-xs font-bold text-red-400 uppercase tracking-wide font-mono flex items-center gap-2">
              <span>⚠️ TRANSACTIONAL ERROR:</span>
            </p>
            <p className="text-sm text-red-300 font-mono mt-1 break-words">{errorMessage}</p>
            <p className="text-[10px] text-red-500 font-mono mt-2 uppercase">
              Dev Tip: Use card 4242 4242 4242 4242 to clear customs.
            </p>
          </div>
        )}

        <button
          type="submit"
          disabled={isBusy || !cardNumber || !expiry || !cvc || !isFleetIdValid}
          className="w-full mt-6 bg-blue-600 hover:bg-blue-500 text-white font-black py-5 rounded-xl uppercase tracking-widest transition-all shadow-xl hover:shadow-blue-600/20 disabled:opacity-30 disabled:hover:bg-blue-600 flex items-center justify-center gap-3 text-sm"
        >
          {isBusy ? (
            <>
              <span className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin"></span>
              <span>AUTHORIZING WITH ISSUING BANK...</span>
            </>
          ) : (
            <span>🔒 SETTLE ${amountDueAud.toFixed(2)} AUD AND UNLOCK</span>
          )}
        </button>
      </form>
    </div>
  );
};

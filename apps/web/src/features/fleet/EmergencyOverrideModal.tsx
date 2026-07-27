import React, { useState } from 'react';
import { supabase } from '../../lib/supabase';
import type { OverrideReason, BreakGlassResponse } from '../../types/whs.types';

interface EmergencyOverrideModalProps {
  isOpen: boolean;
  onClose: () => void;
  assetId: string;
  assetCode: string;
  onSuccess: (data: BreakGlassResponse) => void;
}

export const EmergencyOverrideModal: React.FC<EmergencyOverrideModalProps> = ({
  isOpen,
  onClose,
  assetId,
  assetCode,
  onSuccess
}) => {
  const [reason, setReason] = useState<OverrideReason | ''>('');
  const [pin, setPin] = useState<string>('');
  const [affidavitChecked, setAffidavitChecked] = useState<boolean>(false);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  if (!isOpen) return null;

  const handleExecuteBreakGlass = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!affidavitChecked || !reason || pin.length < 4) {
      setError('Debe completar la declaración jurada, el motivo legal y proporcionar su PIN de 4 dígitos.');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const { data, error: rpcError } = await supabase.rpc('fn_emergency_override_lockout', {
        p_asset_id: assetId,
        p_override_reason: reason as OverrideReason,
        p_manager_pin: pin
      });

      if (rpcError) throw rpcError;

      // Éxito: el servidor limpió el activo e inyectó la traza forense
      onSuccess(data as BreakGlassResponse);
      onClose();
    } catch (err: any) {
      const errorMessage = err?.message || (err instanceof Error ? err.message : 'Error al ejecutar la ruptura de candado WHS');
      setError(errorMessage);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="bg-slate-900 border-2 border-rose-600 rounded-xl max-w-lg w-full p-6 shadow-2xl text-slate-100">
        <div className="flex items-center gap-3 border-b border-slate-800 pb-4 mb-6">
          <div className="w-10 h-10 rounded-full bg-rose-600/20 text-rose-500 flex items-center justify-center text-xl font-bold">
            ⚠️
          </div>
          <div>
            <h2 className="text-lg font-bold text-white uppercase tracking-wider">Ruptura de Candado WHS (Break-Glass)</h2>
            <p className="text-xs text-rose-400 font-mono">Activo Inmovilizado: {assetCode} | ID: {assetId.slice(0, 8)}</p>
          </div>
        </div>

        <form onSubmit={handleExecuteBreakGlass} className="space-y-5">
          {error && (
            <div className="p-3 bg-rose-950 border border-rose-700 rounded text-rose-300 text-xs">
              ⛔ {error}
            </div>
          )}

          <div>
            <label className="block text-xs font-semibold uppercase text-slate-400 mb-2">
              1. Motivo Normativo de Excepción (WorkSafe)
            </label>
            <select
              value={reason}
              onChange={(e) => setReason(e.target.value as OverrideReason)}
              required
              className="w-full bg-slate-950 border border-slate-800 rounded-lg p-3 text-sm text-white focus:outline-none focus:border-rose-500 font-medium"
            >
              <option value="">-- Seleccione una causa legal --</option>
              <option value="OPERARIO AUSENTE">OPERARIO AUSENTE (Fin de turno / Abandono de sitio)</option>
              <option value="EMERGENCIA OPERATIVA">EMERGENCIA OPERATIVA (Riesgo inminente de seguridad / Rescate)</option>
              <option value="FALLO DE TERMINAL">FALLO DE TERMINAL (Destrucción o pérdida de hardware Kiosco)</option>
            </select>
          </div>

          <div>
            <label className="block text-xs font-semibold uppercase text-slate-400 mb-2">
              2. Declaración Jurada y Inspección Física
            </label>
            <label className="flex items-start gap-3 p-3 bg-slate-950/80 border border-slate-800/80 rounded-lg cursor-pointer hover:border-slate-700 transition-colors">
              <input
                type="checkbox"
                checked={affidavitChecked}
                onChange={(e) => setAffidavitChecked(e.target.checked)}
                className="mt-1 w-4 h-4 accent-rose-600 rounded cursor-pointer"
              />
              <span className="text-xs text-slate-300 leading-relaxed">
                <strong>Certifico bajo pena de perjurio normativo WHS</strong> que he realizado una inspección física y visual en terreno sobre el activo <strong>{assetCode}</strong>, confirmando que es seguro operar y que el operario responsable original no se encuentra dentro o alrededor de la zona de peligro.
              </span>
            </label>
          </div>

          <div>
            <label className="block text-xs font-semibold uppercase text-slate-400 mb-2">
              3. Firma Criptográfica (PIN Gerencial de 4 Dígitos)
            </label>
            <input
              type="password"
              maxLength={10}
              value={pin}
              onChange={(e) => setPin(e.target.value)}
              placeholder="••••"
              required
              className="w-full bg-slate-950 border border-slate-800 rounded-lg p-3 text-center tracking-widest text-lg text-white font-mono focus:outline-none focus:border-rose-500"
            />
            <p className="text-[10px] text-slate-500 mt-1">
              * Esta acción quedará grabada de forma permanente e imborrable en la tabla system_audit_logs para inspección federal de la ATO y WorkSafe.
            </p>
          </div>

          <div className="flex items-center justify-end gap-3 pt-4 border-t border-slate-800">
            <button
              type="button"
              onClick={onClose}
              disabled={loading}
              className="px-4 py-2 bg-slate-800 hover:bg-slate-700 text-slate-300 text-sm font-medium rounded-lg transition-colors"
            >
              Cancelar
            </button>
            <button
              type="submit"
              disabled={loading || !affidavitChecked || !reason || pin.length < 4}
              className="px-6 py-2 bg-rose-600 hover:bg-rose-500 disabled:bg-slate-800 disabled:text-slate-600 text-white font-bold text-sm rounded-lg shadow-lg shadow-rose-600/30 transition-all flex items-center gap-2"
            >
              {loading ? 'Firmando Indulto...' : '⚠️ Confirmar Ruptura Legal'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

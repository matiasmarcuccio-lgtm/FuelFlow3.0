import React, { useState } from 'react';
import { supabase } from '../../lib/supabase';

interface FitterReleaseModalProps {
  isOpen: boolean;
  onClose: () => void;
  assetId: string;
  assetName: string;
  lockoutReason: string;
  onReleasedSuccess: (releaseData: any) => void;
}

interface ReleaseRpcResponse {
  success: boolean;
  action: string;
  asset_id: string;
  lockout_id: string;
  released_by_uid: string;
  fitter_name: string;
  resolution: string;
  timestamp: string;
}

export const FitterReleaseModal: React.FC<FitterReleaseModalProps> = ({
  isOpen,
  onClose,
  assetId,
  assetName,
  lockoutReason,
  onReleasedSuccess,
}) => {
  const [resolutionNotes, setResolutionNotes] = useState<string>('');
  const [fitterPin, setFitterPin] = useState<string>('');
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  
  // Estado para la transición de éxito verde industrial
  const [successPayload, setSuccessPayload] = useState<ReleaseRpcResponse | null>(null);

  if (!isOpen) return null;

  const charCount = resolutionNotes.trim().length;
  const isNoteValid = charCount >= 10;
  const isPinValid = fitterPin.length === 4;

  // Manejador del Teclado Matricial del Mecánico
  const handlePadPress = (digit: string) => {
    if (isSubmitting || successPayload) return;

    if (digit === 'CLEAR') {
      setFitterPin('');
      setErrorMessage(null);
      return;
    }

    if (digit === 'BACK') {
      setFitterPin((prev) => prev.slice(0, -1));
      return;
    }

    if (fitterPin.length < 4) {
      setFitterPin((prev) => prev + digit);
      setErrorMessage(null);
    }
  };

  // Disparo transaccional hacia la Capa 0 (fn_release_asset_lockout)
  const executeIndultoInLayerZero = async () => {
    if (!isNoteValid) {
      setErrorMessage('NOTE_TOO_SHORT: Normativa WHS exige un mínimo de 10 caracteres técnicos.');
      return;
    }

    if (!isPinValid) {
      setErrorMessage('PIN_INCOMPLETO: Digite los 4 dígitos de su firma criptográfica.');
      return;
    }

    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      const { data, error } = await supabase.rpc('fn_release_asset_lockout', {
        p_asset_id: assetId,
        p_resolution_notes: resolutionNotes,
        p_fitter_pin: fitterPin,
      });

      if (error) {
        if (error.message.includes('PIN_INVALIDO')) {
          throw new Error('FIRMA RECHAZADA: El PIN introducido no coincide con los registros biométricos del técnico.');
        }
        if (error.message.includes('JURISDICCIÓN DENEGADA')) {
          throw new Error('SIN LICENCIA: Su usuario no posee rol de Fitter o Fleet Manager.');
        }
        throw new Error(error.message);
      }

      // Transición visual atómica al estado verde esmeralda
      const response = data as ReleaseRpcResponse;
      setIsSubmitting(false);
      setSuccessPayload(response);

      // Catapultar el evento de actualización a la tabla de activos tras 2.5 segundos
      setTimeout(() => {
        onReleasedSuccess(response);
        onClose();
        // Reset de estados internos
        setSuccessPayload(null);
        setResolutionNotes('');
        setFitterPin('');
      }, 2500);

    } catch (err: any) {
      setIsSubmitting(false);
      setFitterPin(''); // Limpieza inmediata por seguridad
      setErrorMessage(`FALLO DE LIBERACIÓN: ${err.message}`);
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/85 backdrop-blur-md flex items-center justify-center p-4 md:p-6 select-none font-sans overflow-y-auto">
      
      {/* Contenedor del Modal: Borde Rojo en Bloqueo -> Borde Verde en Éxito */}
      <div className={`w-full max-w-2xl bg-slate-950 border-4 ${
        successPayload ? 'border-emerald-500 bg-emerald-950/20' : 'border-red-600'
      } rounded-3xl shadow-2xl overflow-hidden transition-all duration-500 flex flex-col my-auto`}>
        
        {/* Cabecera Jurisdiccional */}
        <header className={`px-6 py-4 border-b-2 flex justify-between items-center ${
          successPayload ? 'bg-emerald-600 text-black border-emerald-400' : 'bg-red-600 text-black border-red-800'
        }`}>
          <div className="flex items-center gap-2">
            <span className="text-xl font-black">{successPayload ? '🔓' : '🔐'}</span>
            <span className="font-mono text-xs font-black uppercase tracking-widest">
              {successPayload ? 'INDULTO CONCEDIDO • WHS RELEASED' : 'PROTOCOLO DE INDULTO INDUSTRIAL WHS'}
            </span>
          </div>
          <span className="font-mono text-xs font-bold uppercase tracking-tight bg-black/20 px-2 py-1 rounded">
            ASSET: {assetName} ({assetId.slice(0, 8)})
          </span>
        </header>

        {/* CUERPO DEL MODAL */}
        <main className="p-6 md:p-8 flex-1">
          
          {successPayload ? (
            /* PANTALLA VERDE DE TRANSICIÓN CRIPTOGRÁFICA */
            <div className="text-center py-8 animate-fade-in">
              <div className="w-20 h-20 bg-emerald-500/20 border-2 border-emerald-500 text-emerald-400 rounded-full flex items-center justify-center mx-auto mb-6 text-4xl animate-bounce">
                ✓
              </div>
              <h2 className="text-3xl md:text-4xl font-black text-white uppercase tracking-tight mb-2">
                Maquinaria Liberada
              </h2>
              <p className="font-mono text-sm text-emerald-400 font-bold uppercase mb-6">
                ESTADO ACTUALIZADO A: [ AVAILABLE / OPERATIVA ]
              </p>
              
              <div className="bg-black/60 border border-emerald-500/30 p-4 rounded-xl text-left font-mono text-xs text-slate-300 space-y-2 max-w-md mx-auto">
                <p><strong className="text-white">MECÁNICO FIRMANTE:</strong> {successPayload.fitter_name}</p>
                <p><strong className="text-white">LOCKOUT PURGADO:</strong> #{successPayload.lockout_id.slice(0, 8)}</p>
                <p><strong className="text-white">TRABAJO REGISTRADO:</strong> <span className="text-emerald-300">"{successPayload.resolution}"</span></p>
              </div>
              
              <p className="font-mono text-[10px] text-slate-500 uppercase mt-8 animate-pulse">
                Sincronizando con Command Center en Hobart... Cerrando esclusa.
              </p>
            </div>
          ) : (
            /* FORMULARIO DE INDULTO Y FIRMA */
            <div className="space-y-6">
              
              {/* Bloque de Alerta Roja: El porqué está bloqueado */}
              <div className="bg-red-950/40 border-l-4 border-red-600 p-4 rounded-r-xl">
                <p className="text-[10px] font-mono text-red-400 font-bold uppercase tracking-wider mb-1">
                  MOTIVO DEL ENCLAVAMIENTO (DANGER TAG ACTIVA):
                </p>
                <p className="text-sm font-bold text-slate-200 uppercase font-mono break-words">
                  "{lockoutReason}"
                </p>
              </div>

              {/* ZONA 1: Redacción Técnica Asistida */}
              <div>
                <div className="flex justify-between items-center mb-2">
                  <label className="text-xs font-mono font-bold uppercase tracking-wider text-slate-300">
                    1. Reporte de Resolución Técnica (Mecánico / Fitter)
                  </label>
                  <span className={`font-mono text-xs font-bold px-2 py-0.5 rounded ${
                    isNoteValid ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30' : 'bg-amber-500/20 text-amber-400 border border-amber-500/30'
                  }`}>
                    {charCount} / 10 CARACTERES MÍN.
                  </span>
                </div>
                <textarea
                  rows={3}
                  disabled={isSubmitting}
                  value={resolutionNotes}
                  onChange={(e) => {
                    setResolutionNotes(e.target.value);
                    if (errorMessage) setErrorMessage(null);
                  }}
                  placeholder="EJ: SUSTITUCIÓN DE MANGUERA HIDRÁULICA EN BRAZO PRINCIPAL Y PURGA DE FLUIDO. PRUEBAS DE PRESIÓN OK..."
                  className="w-full bg-slate-900 border-2 border-slate-700 rounded-xl p-4 text-white font-mono text-xs uppercase focus:outline-none focus:border-blue-500 transition-colors disabled:opacity-50"
                  required
                />
              </div>

              {/* ZONA 2: Firma Criptográfica por Teclado Matricial */}
              <div className="border-t border-slate-800 pt-6">
                <label className="block text-xs font-mono font-bold uppercase tracking-wider text-slate-300 mb-3 text-center">
                  2. Firma Criptográfica de Indulto (PIN de 4 Dígitos del Técnico)
                </label>

                {/* Visor de PIN Aislado */}
                <div className="flex justify-center gap-3 mb-4">
                  {[0, 1, 2, 3].map((idx) => {
                    const filled = idx < fitterPin.length;
                    return (
                      <div
                        key={idx}
                        className={`w-12 h-14 rounded-xl flex items-center justify-center font-mono text-2xl font-black transition-all ${
                          filled
                            ? 'bg-blue-600 text-white shadow-lg shadow-blue-600/30 scale-105'
                            : 'bg-slate-900 border-2 border-slate-800 text-transparent'
                        }`}
                      >
                        {filled ? '•' : ''}
                      </div>
                    );
                  })}
                </div>

                {/* Teclado Matricial Integrado */}
                <div className="grid grid-cols-3 gap-2 max-w-xs mx-auto">
                  {['1', '2', '3', '4', '5', '6', '7', '8', '9', 'CLEAR', '0', 'BACK'].map((key) => {
                    const special = key === 'CLEAR' || key === 'BACK';
                    return (
                      <button
                        key={key}
                        type="button"
                        disabled={isSubmitting}
                        onClick={() => handlePadPress(key)}
                        className={`h-14 rounded-xl font-mono font-black text-lg uppercase tracking-wider transition-all active:scale-95 disabled:opacity-20 flex items-center justify-center shadow-md ${
                          special
                            ? 'bg-slate-900 border border-slate-800 text-slate-400 hover:text-white hover:bg-slate-800 text-xs'
                            : 'bg-slate-900 hover:bg-slate-800 text-white border border-slate-700'
                        }`}
                      >
                        {key === 'BACK' ? '⌫' : key === 'CLEAR' ? 'C' : key}
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* Alertas Transaccionales */}
              {errorMessage && (
                <div className="bg-red-950/80 border-2 border-red-600 p-3 rounded-xl font-mono text-xs text-red-300 uppercase font-bold text-center animate-shake">
                  ⚠️ {errorMessage}
                </div>
              )}

              {/* Botonera de Acción Militar */}
              <div className="flex gap-4 pt-4 border-t border-slate-800">
                <button
                  type="button"
                  disabled={isSubmitting}
                  onClick={onClose}
                  className="w-1/3 bg-slate-900 hover:bg-slate-800 text-slate-400 hover:text-white font-mono text-xs font-bold py-4 rounded-xl uppercase tracking-wider transition-colors border border-slate-800"
                >
                  Cancelar
                </button>
                <button
                  type="button"
                  disabled={isSubmitting || !isNoteValid || !isPinValid}
                  onClick={executeIndultoInLayerZero}
                  className="w-2/3 bg-red-600 hover:bg-red-500 disabled:opacity-30 disabled:hover:bg-red-600 text-black font-black py-4 rounded-xl uppercase tracking-widest text-xs shadow-xl transition-all flex justify-center items-center gap-2"
                >
                  {isSubmitting ? (
                    <>
                      <span className="w-4 h-4 border-2 border-black border-t-transparent rounded-full animate-spin"></span>
                      <span>AUTORIZANDO CON CAPA 0...</span>
                    </>
                  ) : (
                    <span>🔧 FIRMAR INDULTO Y LIBERAR AL DEPOSITO ➔</span>
                  )}
                </button>
              </div>
            </div>
          )}
        </main>

        {/* Pie de Página Legal */}
        <footer className="px-6 py-3 bg-black/60 border-t border-slate-900 text-center font-mono text-[9px] text-slate-500 uppercase">
          La liberación indebida de un activo inhabilitado acarrea responsabilidad civil y penal bajo las leyes de WorkSafe Tasmania.
        </footer>
      </div>
    </div>
  );
};

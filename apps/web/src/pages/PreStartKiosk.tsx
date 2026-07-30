import React, { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';

interface PreStartKioskProps {
  operatorName: string;
  assetId: string;
  assetName: string;
  onPreStartCompleted: (passed: boolean) => void;
}

// Clasificación estricta bajo normas WHS de Tasmania
interface InspectionItem {
  id: string;
  category: 'CRITICAL' | 'GENERAL' | 'ENVIRONMENTAL';
  title: string;
  instruction: string;
  icon: string;
}

const TASMANIA_WHS_CHECKLIST: InspectionItem[] = [
  {
    id: 'oil_hydraulics',
    category: 'CRITICAL',
    title: 'Niveles de Aceite e Hidráulico',
    instruction: 'Descienda de la cabina. Verifique varilla de aceite del motor y mirilla de fluido hidráulico. Cero fugas activas en mangueras.',
    icon: '🛢️',
  },
  {
    id: 'brakes_interlock',
    category: 'CRITICAL',
    title: 'Frenos de Servicio y Parqueo',
    instruction: 'Prueba de carga estática: Enganche freno de parqueo y aplique aceleración leve. El vehículo no debe presentar desplazamiento.',
    icon: '🛑',
  },
  {
    id: 'estop_ground',
    category: 'CRITICAL',
    title: 'Parada de Emergencia (E-Stop)',
    instruction: 'Accione el botón de parada de emergencia externo e interno. Verifique el corte inmediato de ignición y bomba de combustible.',
    icon: '⚠️',
  },
  {
    id: 'wheels_lugs',
    category: 'CRITICAL',
    title: 'Neumáticos y Tuercas de Rueda',
    instruction: 'Inspección visual 360°. Verifique ausencia de grietas profundas en banda de rodadura y torque visual en tuercas de sujeción.',
    icon: '⚙️',
  },
  {
    id: 'comms_vhf',
    category: 'GENERAL',
    title: 'Radio VHF y Baliza de Señalización',
    instruction: 'Encienda baliza ámbar (beacon light). Realice prueba de transmisión en Canal 4 VHF con garita de control.',
    icon: '📡',
  },
];

type ItemResult = 'PASS' | 'FAIL' | 'UNTESTED';

export const PreStartKiosk: React.FC<PreStartKioskProps> = ({
  operatorName,
  assetId,
  assetName,
  onPreStartCompleted,
}) => {
  // Estado de navegación por tarjetas individuales (Anti-Pencil-Whipping)
  const [currentIndex, setCurrentIndex] = useState<number>(0);
  const [results, setResults] = useState<Record<string, ItemResult>>({});
  const [defectNotes, setDefectNotes] = useState<Record<string, string>>({});
  
  // Retardo háptico para evitar clics rápidos involuntarios
  const [canConfirm, setCanConfirm] = useState<boolean>(false);
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false);
  const [fatalDefectTriggered, setFatalDefectTriggered] = useState<boolean>(false);

  const currentItem = TASMANIA_WHS_CHECKLIST[currentIndex];
  const totalItems = TASMANIA_WHS_CHECKLIST.length;

  // Al cambiar de tarjeta, bloqueamos los botones durante 1.5 segundos
  // para obligar al operario a leer la directiva técnica.
  useEffect(() => {
    setCanConfirm(false);
    const timer = setTimeout(() => setCanConfirm(true), 1500);
    return () => clearTimeout(timer);
  }, [currentIndex]);

  const handleSetResult = (status: ItemResult) => {
    if (!canConfirm || isSubmitting) return;

    // Si marca FAIL en un ítem CRÍTICO, activamos la alerta de enclavamiento
    if (status === 'FAIL' && currentItem.category === 'CRITICAL') {
      setFatalDefectTriggered(true);
    }

    setResults((prev) => ({ ...prev, [currentItem.id]: status }));

    // Si no es el último ítem y no hay fallo fatal, avanzamos automáticamente tras 300ms
    if (currentIndex < totalItems - 1 && !(status === 'FAIL' && currentItem.category === 'CRITICAL')) {
      setTimeout(() => setCurrentIndex((prev) => prev + 1), 300);
    }
  };

  const handleNoteChange = (text: string) => {
    setDefectNotes((prev) => ({ ...prev, [currentItem.id]: text }));
  };

  // Liquidación del Pre-Start hacia PostgreSQL (Capa 0)
  const submitPreStartToLayerZero = async () => {
    setIsSubmitting(true);
    
    // Evaluar si existe al menos un fallo crítico en todo el arreglo
    const hasCriticalFail = TASMANIA_WHS_CHECKLIST.some(
      (item) => item.category === 'CRITICAL' && results[item.id] === 'FAIL'
    );

    const payload = {
      p_asset_id: assetId,
      p_checklist_data: results,
      p_defect_notes: defectNotes,
      p_passed: !hasCriticalFail,
      p_client_timestamp: new Date().toISOString(),
    };

    try {
      // Invocación al procedimiento atómico de registro WHS
      const { error } = await supabase.rpc('fn_submit_whs_prestart', payload);

      if (error) throw new Error(error.message);

      setIsSubmitting(false);
      onPreStartCompleted(!hasCriticalFail);
    } catch (err: any) {
      setIsSubmitting(false);
      if (err.message.includes('42501') || err.message.includes('BILLING_LOCKDOWN')) {
        setIsAdministrativeLock(true);
      } else {
        alert(`ERR_LEDGER_SYNC: No se pudo firmar la bitácora WHS. ${err.message}`);
      }
    }
  };

  if (isAdministrativeLock) {
    return <AdministrativeLockdown />;
  }

  // GUILLOTINA DE DEFECTO VITAL: Si falló un ítem crítico, bloqueamos la máquina in situ
  if (fatalDefectTriggered) {
    return (
      <div className="min-h-screen bg-black text-white p-6 md:p-12 flex flex-col justify-between font-sans select-none border-8 border-red-600 animate-pulse">
        <header className="flex justify-between items-center border-b-2 border-red-800 pb-4">
          <span className="bg-red-600 text-black font-mono font-black text-xs px-3 py-1 uppercase tracking-widest">
            PARADA DE EMERGENCIA WHS • ENCLAVAMIENTO ACTIVO
          </span>
          <span className="font-mono text-xs text-red-400 font-bold uppercase">MAQUINARIA INHABILITADA</span>
        </header>

        <main className="max-w-2xl mx-auto my-auto text-center py-8">
          <div className="text-7xl mb-6">🛑</div>
          <h1 className="text-4xl md:text-5xl font-black uppercase tracking-tight text-red-500 mb-4">
            Defecto Crítico Detectado
          </h1>
          <p className="text-xl font-bold text-white mb-6 bg-red-950/80 p-6 rounded-2xl border border-red-800">
            Fallo reportado en: <span className="underline">{currentItem.title}</span>
          </p>
          <p className="text-slate-300 font-mono text-sm leading-relaxed mb-8">
            Bajo las normativas de WorkSafe Tasmania, esta maquinaria ha cambiado automáticamente a estado <span className="text-red-400 font-bold">OUT_OF_SERVICE</span> en el servidor. La ignición queda prohibida.
          </p>

          <div className="text-left bg-slate-900 p-6 rounded-2xl border border-slate-800 mb-8 font-mono">
            <label className="block text-xs text-slate-400 uppercase mb-2">
              Ingrese detalles obligatorios para el mecánico (Fitter):
            </label>
            <textarea
              rows={3}
              value={defectNotes[currentItem.id] || ''}
              onChange={(e) => handleNoteChange(e.target.value)}
              placeholder="EJ: MANGUERA HIDRÁULICA PRINCIPAL CON FUGA A GOTEO RÁPIDO..."
              className="w-full bg-black border border-red-800 rounded-xl p-4 text-white text-sm focus:outline-none focus:border-red-500 uppercase"
            />
          </div>

          <button
            onClick={submitPreStartToLayerZero}
            disabled={isSubmitting || !defectNotes[currentItem.id]}
            className="w-full bg-red-600 hover:bg-red-500 disabled:opacity-30 text-black font-black py-6 rounded-2xl uppercase tracking-widest text-base shadow-2xl transition-all"
          >
            {isSubmitting ? 'SELLANDO LIBRO MAYOR...' : 'FIRMAR BLOQUEO Y DESPACHAR AL TALLER ➔'}
          </button>
        </main>

        <footer className="text-center font-mono text-xs text-red-600 uppercase border-t border-red-950 pt-4">
          Retire las llaves de la cabina y coloque la etiqueta de peligro (Danger Tag) en el volante.
        </footer>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-slate-950 text-white flex flex-col justify-between p-6 md:p-12 font-sans select-none overflow-hidden">
      {/* Cabecera del Kiosco WHS */}
      <header className="border-b-2 border-slate-800 pb-6">
        <div className="flex justify-between items-center mb-4">
          <div className="flex items-center gap-3">
            <span className="bg-blue-600 font-mono font-black text-xs px-3 py-1 uppercase text-black">
              PRE-START OBLIGATORIO
            </span>
            <span className="font-mono text-xs text-slate-400 uppercase">
              ACTIVO: <strong className="text-white">{assetName} ({assetId})</strong>
            </span>
          </div>
          <span className="font-mono text-xs text-emerald-400 uppercase font-bold">
            OPERARIO: {operatorName}
          </span>
        </div>

        {/* Barra de Progreso Secuencial */}
        <div className="w-full bg-slate-900 h-3 rounded-full overflow-hidden flex gap-1 p-0.5 border border-slate-800">
          {TASMANIA_WHS_CHECKLIST.map((item, idx) => {
            const res = results[item.id];
            let bgColor = 'bg-slate-800';
            if (res === 'PASS') bgColor = 'bg-emerald-500';
            if (res === 'FAIL') bgColor = 'bg-red-600';
            if (idx === currentIndex && !res) bgColor = 'bg-blue-500 animate-pulse';
            return <div key={item.id} className={`flex-1 h-full rounded-sm transition-all ${bgColor}`} />;
          })}
        </div>
      </header>

      {/* Tarjeta de Inspección Activa (Aislamiento Óptico) */}
      <main className="max-w-2xl mx-auto w-full my-auto py-8">
        <div className="bg-slate-900 border-2 border-slate-800 p-8 md:p-12 rounded-3xl shadow-2xl relative">
          
          <div className="flex justify-between items-start mb-6">
            <span className="text-5xl md:text-6xl p-4 bg-black/50 border border-slate-800 rounded-2xl">
              {currentItem.icon}
            </span>
            <span className={`font-mono text-xs font-black px-3 py-1 rounded uppercase ${
              currentItem.category === 'CRITICAL' 
                ? 'bg-red-500/10 text-red-500 border border-red-500/30' 
                : 'bg-blue-500/10 text-blue-400 border border-blue-500/30'
            }`}>
              {currentItem.category === 'CRITICAL' ? '⚠️ ÍTEM CRÍTICO DE SEGURIDAD' : 'ℹ️ GENERAL'}
            </span>
          </div>

          <div className="font-mono text-xs text-slate-500 uppercase mb-1">
            PASO {currentIndex + 1} DE {totalItems}
          </div>
          <h2 className="text-3xl md:text-4xl font-black uppercase tracking-tight text-white mb-6">
            {currentItem.title}
          </h2>

          {/* Bloque de Directiva Legal con Alto Contraste */}
          <div className="bg-black/80 border-l-4 border-blue-500 p-6 rounded-r-2xl mb-8">
            <p className="text-xs font-mono uppercase text-blue-400 mb-1">Mandato de Inspección Físico:</p>
            <p className="text-lg md:text-xl font-bold text-slate-200 leading-relaxed">
              {currentItem.instruction}
            </p>
          </div>

          {/* Temporizador Óptico Anti-Pencil-Whipping */}
          {!canConfirm && (
            <div className="w-full bg-blue-950/40 border border-blue-800/60 p-4 rounded-xl mb-6 text-center animate-pulse">
              <span className="font-mono text-xs text-blue-400 font-bold uppercase tracking-widest">
                ⏱️ LEA LA DIRECTIVA — DESBLOQUEANDO BOTONES EN 1.5s...
              </span>
            </div>
          )}

          {/* Matriz de Botones Masivos para Guantes Industriales */}
          <div className="grid grid-cols-2 gap-4">
            <button
              type="button"
              disabled={!canConfirm || isSubmitting}
              onClick={() => handleSetResult('FAIL')}
              className={`py-8 rounded-2xl font-black text-xl uppercase tracking-wider transition-all border-2 flex flex-col items-center justify-center gap-2 shadow-xl ${
                results[currentItem.id] === 'FAIL'
                  ? 'bg-red-600 text-black border-red-400 scale-95'
                  : 'bg-slate-950 hover:bg-red-950/50 text-red-500 border-red-900/50 hover:border-red-600 disabled:opacity-20'
              }`}
            >
              <span className="text-3xl">✕</span>
              <span>FALLO / DEFECTO</span>
            </button>

            <button
              type="button"
              disabled={!canConfirm || isSubmitting}
              onClick={() => handleSetResult('PASS')}
              className={`py-8 rounded-2xl font-black text-xl uppercase tracking-wider transition-all border-2 flex flex-col items-center justify-center gap-2 shadow-xl ${
                results[currentItem.id] === 'PASS'
                  ? 'bg-emerald-500 text-black border-emerald-300 scale-95'
                  : 'bg-slate-950 hover:bg-emerald-950/50 text-emerald-400 border-emerald-900/50 hover:border-emerald-500 disabled:opacity-20'
              }`}
            >
              <span className="text-3xl">✓</span>
              <span>APROBADO (OK)</span>
            </button>
          </div>

          {/* Controles de Navegación Inferior */}
          <div className="flex justify-between items-center mt-8 pt-6 border-t border-slate-800 font-mono text-xs">
            <button
              type="button"
              disabled={currentIndex === 0 || isSubmitting}
              onClick={() => setCurrentIndex((prev) => Math.max(0, prev - 1))}
              className="text-slate-500 hover:text-white disabled:opacity-20 uppercase font-bold py-2 px-4 rounded bg-slate-950 border border-slate-800"
            >
              🡠 Ítem Anterior
            </button>

            {currentIndex === totalItems - 1 && results[currentItem.id] && (
              <button
                type="button"
                disabled={isSubmitting || Object.keys(results).length < totalItems}
                onClick={submitPreStartToLayerZero}
                className="bg-blue-600 hover:bg-blue-500 text-black font-black px-6 py-4 rounded-xl uppercase tracking-widest transition-all shadow-xl animate-bounce"
              >
                {isSubmitting ? 'FIRMANDO...' : 'FIRMAR Y ENCENDER MOTOR ➔'}
              </button>
            )}
          </div>
        </div>
      </main>

      {/* Pie de página WHS */}
      <footer className="border-t border-slate-900 pt-4 text-center font-mono text-[10px] text-slate-600 uppercase">
        Falsificar un reporte de seguridad Pre-Start es causal de despido sumario bajo legislación minera australiana.
        <br />
        JITSite Telemetry Engine • Cryptographic Time-stamping Active
      </footer>
    </div>
  );
};

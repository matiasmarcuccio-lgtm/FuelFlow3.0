import React, { useState, useEffect } from 'react';
import { useBiometricFriction, StepStatus } from './useBiometricFriction';

interface PrestartKioskProps {
  assetCode: string;
  onCertify: () => void;
  onReportDefect: (notes: string) => void;
  isPending: boolean;
}

export const PrestartKioskPresenter: React.FC<PrestartKioskProps> = ({
  assetCode,
  onCertify,
  onReportDefect,
  isPending
}) => {
  const [defectNotes, setDefectNotes] = useState('');
  const [isReportingDefect, setIsReportingDefect] = useState(false);
  
  const { steps, isAllCompleted, handlePointerDown, handlePointerUp } = useBiometricFriction();

  const renderStepButton = (id: string, label: string) => {
    const step = steps[id];
    const isLocked = step.status === 'locked' || step.status === 'completed' || step.status === 'cooldown';

    return (
      <div key={id} className="mb-6 bg-slate-900 border border-slate-700 p-4 rounded-xl">
        <div className="flex justify-between items-center mb-4">
          <h3 className="text-xl font-bold text-white uppercase">{label}</h3>
          {step.status === 'completed' && <span className="text-green-500 font-bold">✓ VERIFICADO</span>}
          {step.status === 'cooldown' && (
            <span className="text-amber-500 font-mono">
              PAUSA FORZADA: CAMINA AL SIGUIENTE PUNTO ({step.cooldownRemaining}s)
            </span>
          )}
          {step.status === 'locked' && <span className="text-slate-500">BLOQUEADO</span>}
        </div>

        <button
          className={`w-full h-24 rounded-lg text-2xl font-black uppercase transition-all select-none
            ${step.status === 'ready' ? 'bg-slate-700 text-white active:scale-95' : ''}
            ${step.status === 'pressing' ? 'bg-blue-600 text-white' : ''}
            ${isLocked ? 'bg-slate-800 text-slate-600 cursor-not-allowed' : ''}
          `}
          onPointerDown={(e) => {
             // Captura el evento táctil sin disparar scroll en la tablet
             e.currentTarget.releasePointerCapture(e.pointerId);
             handlePointerDown(id);
          }}
          onPointerUp={() => handlePointerUp(id)}
          onPointerLeave={() => handlePointerUp(id)}
          disabled={isLocked || isPending}
        >
          {step.status === 'ready' && 'MANTENER PRESIONADO (3s)'}
          {step.status === 'pressing' && 'INSPECCIONANDO...'}
          {step.status === 'cooldown' && 'ESPERANDO...'}
          {step.status === 'completed' && 'COMPLETADO'}
          {step.status === 'locked' && 'REQUIERE PASO PREVIO'}
        </button>

        {/* Barra de Fricción Visual */}
        <div className="w-full bg-slate-800 h-2 mt-2 rounded overflow-hidden">
          <div 
            className="bg-blue-500 h-full transition-all duration-100 ease-linear"
            style={{ width: `${step.pressProgress}%` }}
          />
        </div>
      </div>
    );
  };

  if (isReportingDefect) {
    return (
      <div className="p-8 max-w-2xl mx-auto bg-black min-h-screen">
        <h2 className="text-3xl font-black text-red-500 mb-6 uppercase">SECUESTRO DE MAQUINARIA</h2>
        <p className="text-white mb-4">Describa la falla crítica. Esta acción abortará su turno y bloqueará la máquina {assetCode}.</p>
        <textarea 
          className="w-full h-48 p-4 bg-slate-900 text-white border border-red-500 rounded mb-6 text-xl"
          placeholder="Ej: Fuga masiva de aceite en el eje trasero..."
          value={defectNotes}
          onChange={(e) => setDefectNotes(e.target.value)}
        />
        <div className="flex gap-4">
          <button 
            className="flex-1 bg-slate-700 text-white py-6 rounded text-xl font-bold uppercase"
            onClick={() => setIsReportingDefect(false)}
            disabled={isPending}
          >
            Cancelar
          </button>
          <button 
            className="flex-1 bg-red-600 text-white py-6 rounded text-xl font-black uppercase"
            onClick={() => onReportDefect(defectNotes)}
            disabled={defectNotes.length < 10 || isPending}
          >
            CONFIRMAR FALLA
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="p-8 max-w-3xl mx-auto bg-black min-h-screen select-none">
      <header className="mb-8 border-b border-slate-800 pb-4">
        <h1 className="text-4xl font-black text-white uppercase">PRE-START CHECK</h1>
        <h2 className="text-2xl font-bold text-slate-400 mt-2">ACTIVO: {assetCode}</h2>
      </header>

      <div className="mb-12">
        {renderStepButton('brakes', '1. Sistemas de Freno e Hidráulica')}
        {renderStepButton('fluids', '2. Niveles de Fluidos y Fugas')}
        {renderStepButton('structural', '3. Ejes, Neumáticos y Estructura')}
      </div>

      <div className="flex gap-4 border-t border-slate-800 pt-8">
        <button 
          className="flex-1 bg-red-900 text-red-100 py-8 rounded-xl text-2xl font-black uppercase"
          onClick={() => setIsReportingDefect(true)}
          disabled={isPending}
        >
          REPORTAR FALLA
        </button>
        
        <button 
          className={`flex-1 py-8 rounded-xl text-2xl font-black uppercase transition-all
            ${isAllCompleted ? 'bg-green-600 text-white' : 'bg-slate-800 text-slate-600 cursor-not-allowed'}
          `}
          onClick={() => onCertify()}
          disabled={!isAllCompleted || isPending}
        >
          CERTIFICAR OPERATIVIDAD
        </button>
      </div>
    </div>
  );
};

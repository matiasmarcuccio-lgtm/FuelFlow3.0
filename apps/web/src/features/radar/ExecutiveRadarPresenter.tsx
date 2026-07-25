import React from 'react';

export interface FrictionMetrics {
  fleet_readiness_percent: number;
  active_maintenance_locks: number;
  daily_idle_cash_burn_aud: number;
  critical_fatigue_operators: number;
  timestamp: string;
}

interface ExecutiveRadarProps {
  metrics: FrictionMetrics | null;
  isLoading: boolean;
  error: string | null;
}

export const ExecutiveRadarPresenter: React.FC<ExecutiveRadarProps> = ({ metrics, isLoading, error }) => {
  if (error) {
    return (
      <div className="bg-red-950 p-6 border-l-4 border-red-500 m-6 font-mono text-red-200">
        FRACTURA ANALÍTICA: {error}
      </div>
    );
  }

  if (isLoading || !metrics) {
    return (
      <div className="min-h-screen bg-slate-950 flex flex-col items-center justify-center font-mono">
        <div className="text-blue-500 text-xl font-bold animate-pulse">CALCULANDO FRICCIÓN OPERATIVA...</div>
      </div>
    );
  }

  // Lógica Termodinámica Visual
  const isBurnCritical = metrics.daily_idle_cash_burn_aud > 500;
  const isReadinessCritical = metrics.fleet_readiness_percent < 80;

  return (
    <div className="min-h-screen bg-slate-950 p-8 font-sans select-none">
      <header className="mb-10 border-b border-slate-800 pb-6 flex justify-between items-end">
        <div>
          <h1 className="text-4xl font-black text-white uppercase tracking-tight">Capa de Inteligencia</h1>
          <p className="text-slate-500 font-mono mt-2 text-sm uppercase tracking-widest">Radar de Fricción Operativa</p>
        </div>
        <div className="text-right">
          <p className="text-blue-400 font-mono font-bold text-xs">ACTUALIZACIÓN EN TIEMPO REAL</p>
          <p className="text-slate-600 font-mono text-xs mt-1">Último bloque: {new Date(metrics.timestamp).toLocaleTimeString()}</p>
        </div>
      </header>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        
        {/* 1. Cash Burn (El sangrado financiero) */}
        <div className={`p-6 rounded-2xl border-2 transition-colors flex flex-col justify-between h-48
          ${isBurnCritical ? 'bg-red-950/30 border-red-900/50' : 'bg-slate-900 border-slate-800'}
        `}>
          <h2 className={`font-black uppercase text-sm tracking-widest mb-2 ${isBurnCritical ? 'text-red-500' : 'text-slate-400'}`}>
            Quema de Efectivo (Idle)
          </h2>
          <div className="flex items-baseline gap-2">
            <span className={`text-5xl font-black ${isBurnCritical ? 'text-red-400' : 'text-white'}`}>
              ${metrics.daily_idle_cash_burn_aud.toFixed(2)}
            </span>
            <span className="text-slate-500 font-bold">AUD</span>
          </div>
          <p className="text-slate-500 font-mono text-xs mt-4">
            Costo de maquinaria estancada hoy
          </p>
        </div>

        {/* 2. Fleet Readiness (Disponibilidad de Flota) */}
        <div className={`p-6 rounded-2xl border-2 flex flex-col justify-between h-48
          ${isReadinessCritical ? 'bg-amber-950/30 border-amber-900/50' : 'bg-slate-900 border-slate-800'}
        `}>
          <h2 className={`font-black uppercase text-sm tracking-widest mb-2 ${isReadinessCritical ? 'text-amber-500' : 'text-slate-400'}`}>
            Disponibilidad Mecánica
          </h2>
          <div className="flex items-baseline gap-1">
            <span className={`text-5xl font-black ${isReadinessCritical ? 'text-amber-400' : 'text-green-400'}`}>
              {metrics.fleet_readiness_percent}%
            </span>
          </div>
          <div className="w-full bg-slate-950 h-2 mt-4 rounded-full overflow-hidden">
            <div 
              className={`h-full ${isReadinessCritical ? 'bg-amber-500' : 'bg-green-500'}`} 
              style={{ width: `${metrics.fleet_readiness_percent}%` }}
            ></div>
          </div>
        </div>

        {/* 3. Triage Activo (Máquinas Secuestradas) */}
        <div className="p-6 rounded-2xl border-2 border-slate-800 bg-slate-900 flex flex-col justify-between h-48">
          <h2 className="font-black uppercase text-sm tracking-widest mb-2 text-slate-400">
            Bloqueos de Taller
          </h2>
          <span className="text-5xl font-black text-white">
            {metrics.active_maintenance_locks}
          </span>
          <p className="text-slate-500 font-mono text-xs mt-4">
            Activos en reparación o alerta térmica
          </p>
        </div>

        {/* 4. Riesgo WHS (Fatiga) */}
        <div className={`p-6 rounded-2xl border-2 flex flex-col justify-between h-48
          ${metrics.critical_fatigue_operators > 0 ? 'bg-purple-950/30 border-purple-900/50' : 'bg-slate-900 border-slate-800'}
        `}>
          <h2 className={`font-black uppercase text-sm tracking-widest mb-2 ${metrics.critical_fatigue_operators > 0 ? 'text-purple-500' : 'text-slate-400'}`}>
            Alerta Fatiga WHS
          </h2>
          <span className={`text-5xl font-black ${metrics.critical_fatigue_operators > 0 ? 'text-purple-400' : 'text-white'}`}>
            {metrics.critical_fatigue_operators}
          </span>
          <p className="text-slate-500 font-mono text-xs mt-4">
            Operadores superando las 10h hoy
          </p>
        </div>

      </div>
    </div>
  );
};

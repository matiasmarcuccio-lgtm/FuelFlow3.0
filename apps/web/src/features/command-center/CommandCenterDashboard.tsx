import React from 'react';
import { TelemetryMap } from './TelemetryMap';
import { AnomalyStream } from './AnomalyStream';

export const CommandCenterDashboard = () => {
  return (
    <div className="flex h-screen bg-slate-900 text-slate-100 overflow-hidden">
      {/* Left Column: Anomaly Stream */}
      <div className="w-1/3 min-w-[400px] border-r border-slate-700 flex flex-col">
        <div className="p-4 bg-slate-800 border-b border-slate-700 flex items-center justify-between">
          <h1 className="text-xl font-bold tracking-tight text-white flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse"></span>
            Exception Stream
          </h1>
          <span className="text-xs font-mono text-slate-400">COMMAND CENTER</span>
        </div>
        <AnomalyStream />
      </div>

      {/* Right Column: Telemetry Map */}
      <div className="flex-1 flex flex-col">
        <div className="p-4 bg-slate-800 border-b border-slate-700">
          <h2 className="text-lg font-semibold text-slate-200">Live Telemetry Map (Nodal)</h2>
        </div>
        <div className="flex-1 relative bg-slate-950">
          <TelemetryMap />
        </div>
      </div>
    </div>
  );
};

import React from 'react';
import { TelemetryMap } from '../features/command-center/TelemetryMap';
import { AnomalyStream } from '../features/command-center/AnomalyStream';

export const LiveOps = () => {
  return (
    <div className="flex h-full w-full bg-slate-900">
      <div className="flex-1 relative border-r border-slate-700">
        <TelemetryMap />
        <div className="absolute top-4 left-4 z-[400] bg-slate-900/80 backdrop-blur-md p-3 rounded-md border border-slate-700 shadow-lg pointer-events-none">
          <h2 className="text-white font-bold tracking-wider mb-1 flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></span>
            LIVE TELEMETRY
          </h2>
          <p className="text-xs text-slate-300 font-mono">EPSG:4326 WGS84</p>
        </div>
      </div>
      <div className="w-[450px] flex flex-col bg-slate-900">
        <div className="p-4 border-b border-slate-700 bg-slate-900 z-10 flex-shrink-0">
          <h2 className="text-lg font-bold text-slate-200">Exception Stream</h2>
          <p className="text-xs text-slate-400">Real-time Anomaly Detection</p>
        </div>
        <AnomalyStream />
      </div>
    </div>
  );
};

import React from 'react';
import { TelemetryMap } from '../features/command-center/TelemetryMap';
import { AnomalyStream } from '../features/command-center/AnomalyStream';

export const LiveOps = () => {
  return (
    <div className="flex h-full w-full bg-background">
      <div className="flex-1 relative border-r border-outline-variant">
        <TelemetryMap />
        <div className="absolute top-4 left-4 z-[400] bg-background/80 backdrop-blur-md p-3 rounded-md border border-outline-variant shadow-lg pointer-events-none">
          <h2 className="text-foreground font-bold tracking-wider mb-1 flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></span>
            LIVE TELEMETRY
          </h2>
          <p className="text-xs text-on-surface font-mono">EPSG:4326 WGS84</p>
        </div>
      </div>
      <div className="w-[450px] flex flex-col bg-background">
        <div className="p-4 border-b border-outline-variant bg-background z-10 flex-shrink-0">
          <h2 className="text-lg font-bold text-foreground">Exception Stream</h2>
          <p className="text-xs text-on-surface-variant">Real-time Anomaly Detection</p>
        </div>
        <AnomalyStream />
      </div>
    </div>
  );
};

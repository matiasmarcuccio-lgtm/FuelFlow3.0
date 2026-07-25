
import { TelemetryMap } from './TelemetryMap';
import { AnomalyStream } from './AnomalyStream';
import { DeadLetterQueueContainer } from './DeadLetterQueueContainer';
import { ExpenseQuarantineContainer } from './ExpenseQuarantineContainer';

export const CommandCenterDashboard = () => {
  return (
    <div className="flex h-screen bg-background text-foreground overflow-hidden">
      {/* Left Column: Anomaly Stream & Dead Letters */}
      <div className="w-1/3 min-w-[400px] border-r border-outline-variant flex flex-col">
        <div className="p-4 bg-surface border border-outline-variant shadow-sm border-b border-outline-variant flex items-center justify-between">
          <h1 className="text-xl font-bold tracking-tight text-foreground flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse"></span>
            Exception Stream
          </h1>
          <span className="text-xs font-mono text-on-surface-variant">COMMAND CENTER</span>
        </div>
        <div className="flex-1 flex flex-col overflow-y-auto">
          <DeadLetterQueueContainer />
          <AnomalyStream />
        </div>
      </div>

      {/* Right Column: Telemetry Map & OCR Quarantine */}
      <div className="flex-1 flex flex-col overflow-y-auto">
        <ExpenseQuarantineContainer />
        <div className="p-4 bg-surface border border-outline-variant shadow-sm border-b border-outline-variant mt-4">
          <h2 className="text-lg font-semibold text-foreground">Live Telemetry Map (Nodal)</h2>
        </div>
        <div className="flex-1 relative bg-slate-950 min-h-[500px]">
          <TelemetryMap />
        </div>
      </div>
    </div>
  );
};

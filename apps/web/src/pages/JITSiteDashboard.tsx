import { useParams } from 'react-router-dom';
import { DashboardTacticalMap } from '../features/dashboard/DashboardTacticalMap';
import { JITQueueSidebar } from '../features/dashboard/JITQueueSidebar';
import { AcousticDispatchMonitor } from '../features/dashboard/AcousticDispatchMonitor';
import { Map } from 'lucide-react';

export function JITSiteDashboard() {
  const { projectId } = useParams<{ projectId: string }>();
  const targetProject = projectId || 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  return (
    <div className="h-full w-full bg-background text-foreground flex flex-col lg:flex-row font-sans overflow-hidden">
      <AcousticDispatchMonitor projectId={targetProject} />
      
      {/* 
        Bucle Táctico (High-Frequency Map) 
      */}
      <div className="flex-1 flex flex-col lg:block border-b lg:border-b-0 lg:border-r border-border order-1 relative">
        <div className="relative h-[45vh] lg:h-full lg:absolute lg:inset-0 shrink-0 z-0">
          <DashboardTacticalMap projectId={targetProject} />
          {/* Map filter overlay */}
          <div className="absolute inset-0 bg-background/20 pointer-events-none hidden lg:block"></div>
        </div>
        
        {/* OVERLAYS ESTÁTICOS DE TELEMETRÍA */}
        <div className="lg:absolute lg:top-4 lg:left-4 p-4 lg:p-0 flex flex-col gap-4 z-20 pointer-events-auto lg:pointer-events-none bg-background lg:bg-transparent shadow-md lg:shadow-none relative">
          <div className="drop-shadow-md hidden lg:block">
            <h1 className="text-2xl font-bold flex items-center gap-2 text-foreground">
              <Map className="text-primary" />
              Telemetry map
            </h1>
            <p className="text-sm text-on-surface-variant font-sans mt-1">Live tracking and geospatial logistics.</p>
          </div>
          <div className="flex flex-col sm:flex-row gap-3">
          <div className="bg-card/90 backdrop-blur-md p-4 shadow-lg rounded-lg flex flex-col min-w-[200px]">
            <span className="font-mono text-[10px] text-muted-foreground block mb-2 uppercase tracking-widest font-bold">Fleet Telemetry</span>
            <div className="flex items-center gap-3">
              <span className="font-mono text-3xl font-bold tracking-tight text-foreground uppercase">Live</span>
              <span className="w-2.5 h-2.5 rounded-full bg-primary shadow-[0_0_10px_rgba(34,197,94,1)] animate-pulse"></span>
            </div>
            <span className="font-mono text-[10px] text-primary font-bold tracking-widest uppercase mt-1">42 Active Units Synced</span>
          </div>

          <div className="bg-card/90 backdrop-blur-md p-4 shadow-lg rounded-lg flex flex-col min-w-[200px] justify-between">
            <span className="font-mono text-[10px] text-muted-foreground block mb-2 uppercase tracking-widest font-bold">Network Metrics</span>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <div className="font-mono text-xl font-bold text-foreground">18ms</div>
                <div className="font-mono text-[9px] text-muted-foreground uppercase font-bold tracking-widest">Latency</div>
              </div>
              <div>
                <div className="font-mono text-xl font-bold text-primary">99.9%</div>
                <div className="font-mono text-[9px] text-muted-foreground uppercase font-bold tracking-widest">Uptime</div>
              </div>
            </div>
          </div>
          </div>
        </div>
      </div>

      {/* 
        Bucle de Interfaz (Low-Frequency React DOM) 
      */}
      <div className="w-full lg:w-[400px] shrink-0 h-[50vh] lg:h-full order-2 bg-card/50">
        <JITQueueSidebar projectId={targetProject} />
      </div>
    </div>
  );
}

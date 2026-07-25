
import { NavLink } from 'react-router-dom';
import { Activity, Map, Settings, FileText, HardHat, Truck, Search, Users } from 'lucide-react';

export const Sidebar = () => {
  return (
    <div className="w-full h-full glass-card text-foreground flex flex-col overflow-y-auto shadow-2xl ring-1 ring-white/5 bg-card/40 transition-all duration-300 custom-scrollbar">
      <div className="p-6 border-b border-border/50 bg-background/20 backdrop-blur-md sticky top-0 z-10">
        <h1 className="text-xl font-bold font-mono text-foreground flex items-center gap-2">
          <Activity className="text-primary drop-shadow-[0_0_8px_rgba(34,197,94,0.5)]" />
          JITSite
        </h1>
        <p className="text-[10px] text-muted-foreground mt-1.5 uppercase tracking-widest font-bold">Command Center</p>
      </div>

      <nav className="flex-1 p-4 space-y-1">
        <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider mb-2 mt-4 px-2">
          Live Ops (Shared)
        </p>
        
        <NavLink 
          to="/" 
          end
          className={({ isActive }) => `flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all duration-200 ${isActive ? 'bg-primary/15 text-primary font-medium' : 'hover:bg-accent text-foreground hover:text-accent-foreground'}`}
        >
          <Map className="w-5 h-5" />
          Telemetry Map
        </NavLink>

        <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider mb-2 mt-6 px-2">
          Builder
        </p>
        
        <NavLink 
          to="/builder" 
          className={({ isActive }) => `flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all duration-200 ${isActive ? 'bg-emerald-500/15 text-emerald-500 font-medium' : 'hover:bg-accent text-foreground hover:text-accent-foreground'}`}
        >
          <HardHat className="w-5 h-5" />
          Project Progress
        </NavLink>
        
        <NavLink 
          to="/analytics" 
          className={({ isActive }) => `flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all duration-200 ${isActive ? 'bg-emerald-500/15 text-emerald-500 font-medium' : 'hover:bg-accent text-foreground hover:text-accent-foreground'}`}
        >
          <Activity className="w-5 h-5" />
          Financial Intelligence
        </NavLink>
        
        <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider mb-2 mt-6 px-2">
          Fleet
        </p>

        <NavLink 
          to="/fleet" 
          className={({ isActive }) => `flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all duration-200 ${isActive ? 'bg-orange-500/15 text-orange-500 font-medium' : 'hover:bg-accent text-foreground hover:text-accent-foreground'}`}
        >
          <Truck className="w-5 h-5" />
          Resource Matrix
        </NavLink>

        <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider mb-2 mt-6 px-2">
          Governance
        </p>
        
        <NavLink 
          to="/compliance" 
          className={({ isActive }) => `flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all duration-200 ${isActive ? 'bg-purple-500/15 text-purple-500 font-medium' : 'hover:bg-accent text-foreground hover:text-accent-foreground'}`}
        >
          <FileText className="w-5 h-5" />
          CoR Weekly Summary
        </NavLink>

        <NavLink 
          to="/forensic" 
          className={({ isActive }) => `flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all duration-200 ${isActive ? 'bg-primary/15 text-primary font-medium' : 'hover:bg-accent text-foreground hover:text-accent-foreground'}`}
        >
          <Search className="w-5 h-5" />
          Forensic Engine
        </NavLink>
        
        <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider mb-2 mt-6 px-2">
          Administration
        </p>

        <NavLink 
          to="/users" 
          className={({ isActive }) => `flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all duration-200 ${isActive ? 'bg-primary/15 text-primary font-medium' : 'hover:bg-accent text-foreground hover:text-accent-foreground'}`}
        >
          <Users className="w-5 h-5" />
          Human Resources
        </NavLink>

        <NavLink 
          to="/settings" 
          className={({ isActive }) => `flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all duration-200 ${isActive ? 'bg-primary/15 text-primary font-medium' : 'hover:bg-accent text-foreground hover:text-accent-foreground'}`}
        >
          <Settings className="w-5 h-5" />
          System Settings
        </NavLink>
      </nav>

      <div className="p-4 border-t border-border text-xs text-muted-foreground">
        <p>Chain of Command Architecture</p>
        <p className="mt-1 font-mono">v3.1.0-RC</p>
      </div>
    </div>
  );
};


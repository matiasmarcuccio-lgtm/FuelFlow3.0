import React from 'react';
import { NavLink } from 'react-router-dom';
import { Activity, ShieldCheck, Map, Settings, FileText, HardHat, Truck, Search, Users } from 'lucide-react';

export const Sidebar = () => {
  return (
    <div className="w-64 bg-slate-900 border-r border-slate-800 text-slate-300 flex flex-col h-full overflow-y-auto">
      <div className="p-6 border-b border-slate-800">
        <h1 className="text-xl font-bold text-white flex items-center gap-2">
          <Activity className="text-blue-500" />
          FuelFlow
        </h1>
        <p className="text-xs text-slate-500 mt-1 uppercase tracking-wider">Command Center</p>
      </div>

      <nav className="flex-1 p-4 space-y-2">
        <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-4 mt-2 px-2">Live Ops (Shared)</p>
        
        <NavLink 
          to="/" 
          end
          className={({ isActive }) => `flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${isActive ? 'bg-blue-600/20 text-blue-400 font-medium' : 'hover:bg-slate-800 hover:text-white'}`}
        >
          <Map className="w-5 h-5" />
          Telemetry Map
        </NavLink>

        <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-4 mt-8 px-2">Builder</p>
        
        <NavLink 
          to="/builder" 
          className={({ isActive }) => `flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${isActive ? 'bg-emerald-600/20 text-emerald-400 font-medium' : 'hover:bg-slate-800 hover:text-white'}`}
        >
          <HardHat className="w-5 h-5" />
          Project Progress
        </NavLink>
        
        <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-4 mt-8 px-2">Fleet</p>

        <NavLink 
          to="/fleet" 
          className={({ isActive }) => `flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${isActive ? 'bg-orange-600/20 text-orange-400 font-medium' : 'hover:bg-slate-800 hover:text-white'}`}
        >
          <Truck className="w-5 h-5" />
          Resource Matrix
        </NavLink>

        <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-4 mt-8 px-2">Governance</p>
        
        <NavLink 
          to="/compliance" 
          className={({ isActive }) => `flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${isActive ? 'bg-purple-600/20 text-purple-400 font-medium' : 'hover:bg-slate-800 hover:text-white'}`}
        >
          <FileText className="w-5 h-5" />
          CoR Weekly Summary
        </NavLink>

        <NavLink 
          to="/forensic" 
          className={({ isActive }) => `flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${isActive ? 'bg-slate-700/50 text-white font-medium' : 'hover:bg-slate-800 hover:text-white'}`}
        >
          <Search className="w-5 h-5 text-slate-400" />
          Forensic Engine
        </NavLink>
        <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-4 mt-8 px-2">Administration</p>

        <NavLink 
          to="/users" 
          className={({ isActive }) => `flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${isActive ? 'bg-blue-600/20 text-blue-400 font-medium' : 'hover:bg-slate-800 hover:text-white'}`}
        >
          <Users className="w-5 h-5" />
          Human Resources
        </NavLink>

        <NavLink 
          to="/settings" 
          className={({ isActive }) => `flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${isActive ? 'bg-slate-700/50 text-white font-medium' : 'hover:bg-slate-800 hover:text-white'}`}
        >
          <Settings className="w-5 h-5 text-slate-400" />
          System Settings
        </NavLink>
      </nav>

      <div className="p-4 border-t border-slate-800 text-xs text-slate-600">
        <p>Chain of Command Architecture</p>
        <p className="mt-1">v3.1.0-RC</p>
      </div>
    </div>
  );
};

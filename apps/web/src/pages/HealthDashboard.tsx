import React from 'react';
import { Activity } from 'lucide-react';

export const HealthDashboard = () => {
  return (
    <div className="flex-1 p-8 bg-slate-900 text-slate-200">
      <h1 className="text-2xl font-bold mb-6 flex items-center gap-2">
        <Activity className="text-emerald-500" />
        Health Dashboard
      </h1>
      <p className="text-slate-400">Monitor system latency, stale sync events, and database triggers here.</p>
    </div>
  );
};

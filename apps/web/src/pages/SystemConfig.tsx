import React, { useEffect, useState } from 'react';
import { Settings, Save } from 'lucide-react';
import { supabase } from '../lib/supabase';

export const SystemConfig = () => {
  const [configs, setConfigs] = useState<{ key: string, value: string }[]>([]);

  useEffect(() => {
    fetchConfigs();
  }, []);

  const fetchConfigs = async () => {
    const { data, error } = await supabase.from('system_config').select('*');
    if (!error && data) {
      setConfigs(data);
    }
  };

  return (
    <div className="flex-1 p-8 bg-slate-900 text-slate-200">
      <h1 className="text-2xl font-bold mb-6 flex items-center gap-2">
        <Settings className="text-emerald-500" />
        System Configuration
      </h1>
      <p className="text-slate-400 mb-8">Manage global thresholds and tolerances without deploying code.</p>

      <div className="space-y-4 max-w-2xl">
        {configs.map(config => (
          <div key={config.key} className="bg-slate-800 p-4 rounded-lg flex items-center justify-between border border-slate-700">
            <div>
              <p className="font-mono text-sm text-blue-400">{config.key}</p>
            </div>
            <div className="flex items-center gap-2">
              <input 
                type="text" 
                defaultValue={String(config.value)} 
                className="bg-slate-900 border border-slate-600 rounded px-3 py-1 w-24 text-center font-mono text-white"
              />
              <button className="bg-blue-600 hover:bg-blue-700 p-1.5 rounded">
                <Save className="w-4 h-4 text-white" />
              </button>
            </div>
          </div>
        ))}
        {configs.length === 0 && <p className="text-slate-500">Loading configurations...</p>}
      </div>
    </div>
  );
};

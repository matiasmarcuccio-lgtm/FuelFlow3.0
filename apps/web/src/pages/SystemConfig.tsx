import { useEffect, useState } from 'react';
import { Settings, Save } from 'lucide-react';
import { supabase } from '../lib/supabase';

export const SystemConfig = () => {
  const [configs, setConfigs] = useState<{ key: string, value: string }[]>([]);

  useEffect(() => {
    fetchConfigs();
  }, []);

  async function fetchConfigs() {
    const { data, error } = await supabase.from('system_config').select('*');
    if (!error && data) {
      setConfigs(data.map(d => ({ key: d.key, value: String(d.value) })));
    }
  };

  return (
    <div className="flex-1 p-8 bg-background text-foreground">
      <h1 className="text-2xl font-bold mb-6 flex items-center gap-2">
        <Settings className="text-emerald-500" />
        System Configuration
      </h1>
      <p className="text-on-surface-variant mb-8">Manage global thresholds and tolerances without deploying code.</p>

      <div className="space-y-4 max-w-2xl">
        {configs.map(config => (
          <div key={config.key} className="bg-surface border border-outline-variant shadow-sm p-4 rounded-lg flex items-center justify-between border border-outline-variant">
            <div>
              <p className="font-mono text-sm text-primary">{config.key}</p>
            </div>
            <div className="flex items-center gap-2">
              <input 
                type="text" 
                defaultValue={String(config.value)} 
                className="bg-background border border-outline rounded px-3 py-1 w-24 text-center font-mono text-foreground"
              />
              <button className="bg-primary text-on-primary hover:bg-primary-container text-on-primary-container p-1.5 rounded">
                <Save className="w-4 h-4 text-foreground" />
              </button>
            </div>
          </div>
        ))}
        {configs.length === 0 && <p className="text-outline">Loading configurations...</p>}
      </div>
    </div>
  );
};

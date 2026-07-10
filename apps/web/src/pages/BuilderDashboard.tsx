import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { BarChart, Activity, AlertTriangle, Plus, HardHat, HelpCircle } from 'lucide-react';

export const BuilderDashboard = () => {
  const [progress, setProgress] = useState<any[]>([]);
  const [bottlenecks, setBottlenecks] = useState<any[]>([]);
  const [masterOrders, setMasterOrders] = useState<any[]>([]);
  const [isDeploying, setIsDeploying] = useState(false);
  const [formData, setFormData] = useState({
    material_type: 'SUB_BASE',
    target_tonnage: 5000,
    requires_4x4: false
  });

  const [isHudActive, setIsHudActive] = useState(false);

  useEffect(() => {
    fetchData();

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === '?' && e.shiftKey) {
        setIsHudActive(prev => !prev);
      }
      if (e.key === 'Escape') {
        setIsHudActive(false);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);

  const fetchData = async () => {
    const { data: progressData } = await supabase.from('view_project_progress').select('*');
    if (progressData) setProgress(progressData);

    const { data: bottleneckData } = await supabase.from('view_site_bottlenecks').select('*');
    if (bottleneckData) setBottlenecks(bottleneckData);

    const { data: ordersData } = await supabase.from('master_orders').select('*').order('created_at', { ascending: false });
    if (ordersData) setMasterOrders(ordersData);
  };

  const handleDeployPipeline = async () => {
    const { error } = await supabase.from('master_orders').insert({
      material_type: formData.material_type,
      target_tonnage: formData.target_tonnage,
      requires_4x4_traction: formData.requires_4x4,
      origin_geofence: { lat: -42.8821, lng: 147.3272, radius: 50 },
      destination_geofence: { lat: -42.8850, lng: 147.3300, radius: 50 }
    });
    if (!error) {
      setIsDeploying(false);
      fetchData();
    }
  };

  return (
    <div className="flex-1 p-8 bg-background text-foreground h-full overflow-y-auto relative">
      
      {/* TACTICAL HUD OVERLAY */}
      {isHudActive && (
        <div 
          className="absolute inset-0 bg-slate-950/80 backdrop-blur-sm z-40 flex items-center justify-center cursor-pointer transition-opacity duration-200"
          onClick={() => setIsHudActive(false)}
        >
          <div className="text-center pointer-events-none mt-32">
            <h2 className="text-primary font-bold text-2xl uppercase tracking-widest mb-4 animate-pulse">Tactical HUD Active</h2>
            <div className="bg-background/80 border border-blue-500/50 p-6 rounded-lg text-left inline-block shadow-[0_0_30px_rgba(59,130,246,0.3)]">
              <h3 className="text-foreground font-bold mb-4 uppercase text-sm border-b border-blue-900 pb-2">Deploy Protocol Sequence</h3>
              <ol className="text-on-surface space-y-3">
                <li className="flex items-center gap-3"><span className="flex items-center justify-center w-6 h-6 rounded-full bg-primary text-on-primary text-white font-bold text-xs">1</span> Click <strong className="text-foreground">Deploy Pipeline</strong> (Highlighted Top Right).</li>
                <li className="flex items-center gap-3"><span className="flex items-center justify-center w-6 h-6 rounded-full bg-primary text-on-primary text-white font-bold text-xs">2</span> Input exact tonnage from Civil 3D.</li>
                <li className="flex items-center gap-3"><span className="flex items-center justify-center w-6 h-6 rounded-full bg-primary text-on-primary text-white font-bold text-xs">3</span> Execute Order to open volumetric channel.</li>
              </ol>
            </div>
            <p className="text-outline mt-6 text-sm uppercase tracking-widest">Press ESC or click anywhere to dismiss</p>
          </div>
        </div>
      )}

      <div className="flex justify-between items-center mb-6">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <BarChart className="text-primary" />
            Constructor Command Panel
          </h1>
          <p className="text-sm text-on-surface-variant mt-1">Macro-level volume tracking and pipeline deployment. No truck-level micromanagement.</p>
        </div>
        <div className={isHudActive ? "relative z-50 ring-4 ring-blue-500/50 rounded shadow-[0_0_20px_rgba(59,130,246,0.8)]" : ""}>
          <button 
            onClick={() => {
              if (isHudActive) setIsHudActive(false);
              setIsDeploying(true);
            }}
            className="bg-primary text-on-primary hover:bg-primary text-on-primary text-white font-bold py-2 px-4 rounded flex items-center gap-2 shadow-lg transition-colors"
          >
            <Plus className="w-5 h-5" />
            Deploy Pipeline
          </button>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-8">
        {/* Active Pipelines */}
        <div>
          <h2 className="text-lg font-bold mb-4 flex items-center gap-2 border-b border-outline-variant pb-2">
            <HardHat className="text-emerald-500 w-5 h-5" />
            Active Master Orders (Pipelines)
            <div className="relative group ml-auto">
              <button className="text-outline hover:text-primary transition-colors p-1 rounded-full hover:bg-surface border border-outline-variant shadow-sm">
                <HelpCircle className="w-5 h-5" />
              </button>
              <div className="absolute right-0 top-full mt-2 w-64 bg-surface border border-outline-variant shadow-sm border border-outline-variant shadow-2xl rounded-lg p-4 hidden group-hover:block z-50">
                <h4 className="text-primary font-bold mb-2 text-xs uppercase tracking-wider">Deploy Protocol</h4>
                <ol className="text-left text-xs text-on-surface space-y-2">
                  <li className="flex gap-2"><span className="text-primary font-bold">1.</span> Click "Deploy Pipeline" (Top Right).</li>
                  <li className="flex gap-2"><span className="text-primary font-bold">2.</span> Input target tonnage from Civil 3D.</li>
                  <li className="flex gap-2"><span className="text-primary font-bold">3.</span> Execute Order to open channel.</li>
                </ol>
              </div>
            </div>
          </h2>
          <div className="space-y-4">
            {masterOrders.map((order, i) => {
              const p = progress.find(pr => pr.material_type === order.material_type);
              const delivered = p ? p.total_mass_delivered_kg : 0;
              const percent = Math.min(100, (delivered / order.target_tonnage) * 100);
              const isFulfilled = order.status === 'FULFILLED';
              
              return (
                <div key={i} className={`p-4 rounded-lg border ${isFulfilled ? 'bg-background border-outline-variant opacity-50' : 'bg-surface border border-outline-variant shadow-sm border-blue-900'}`}>
                  <div className="flex justify-between items-center mb-2">
                    <span className="font-bold text-foreground">{order.material_type}</span>
                    <span className="text-primary font-mono font-bold">{delivered} / {order.target_tonnage} kg</span>
                  </div>
                  <div className="w-full bg-background rounded-full h-2">
                    <div className={`h-2 rounded-full ${isFulfilled ? 'bg-slate-500' : 'bg-primary text-on-primary'}`} style={{ width: `${percent}%` }}></div>
                  </div>
                  <div className="flex justify-between mt-2">
                    <span className="text-[10px] text-outline font-mono uppercase">ID: {order.id.substring(0,8)}</span>
                    <span className={`text-xs font-bold uppercase ${isFulfilled ? 'text-outline' : 'text-emerald-500 animate-pulse'}`}>{order.status}</span>
                  </div>
                </div>
              );
            })}
            {masterOrders.length === 0 && (
              <div className="p-6 bg-blue-900/10 border border-blue-900/30 rounded-lg text-center">
                <HardHat className="w-12 h-12 text-primary/50 mx-auto mb-3" />
                <h3 className="text-primary font-bold mb-2 uppercase tracking-wider text-sm">System Standing By</h3>
                <p className="text-on-surface-variant text-sm mb-4">No active pipelines detected. To initiate JIT operations:</p>
                <ol className="text-left text-xs text-outline space-y-2 max-w-xs mx-auto mb-4 bg-background/50 p-4 rounded border border-outline-variant">
                  <li className="flex gap-2"><span className="text-primary font-bold">1.</span> Click "Deploy Pipeline" (Top Right).</li>
                  <li className="flex gap-2"><span className="text-primary font-bold">2.</span> Input target tonnage from Civil 3D.</li>
                  <li className="flex gap-2"><span className="text-primary font-bold">3.</span> Execute Order to open the volumetric channel.</li>
                </ol>
                <p className="text-xs text-outline italic">Fleet Dispatchers cannot assign trucks until a pipeline is deployed.</p>
              </div>
            )}
          </div>
        </div>

        {/* Bottlenecks */}
        <div>
          <h2 className="text-lg font-bold mb-4 flex items-center gap-2 border-b border-outline-variant pb-2">
            <AlertTriangle className="text-orange-500 w-5 h-5" />
            Access Point Bottlenecks
          </h2>
          <div className="space-y-4">
            {bottlenecks.map((b, i) => {
              const isCongested = b.avg_cycle_time_mins > 15;
              return (
                <div key={i} className={`p-4 rounded-lg border ${isCongested ? 'bg-orange-900/20 border-orange-700' : 'bg-surface border border-outline-variant shadow-sm border-outline-variant'}`}>
                  <div className="flex justify-between items-center mb-2">
                    <span className="font-bold text-foreground">{b.geofence_zone || 'MAIN_GATE'}</span>
                    <span className={`font-mono font-bold ${isCongested ? 'text-orange-400' : 'text-on-surface'}`}>
                      {Number(b.avg_cycle_time_mins).toFixed(1)} mins avg
                    </span>
                  </div>
                  <p className="text-xs text-on-surface-variant">{b.active_trucks} Active Trucks in Zone</p>
                  {isCongested && <p className="text-xs text-orange-400 mt-2 font-bold uppercase animate-pulse">Congestion Detected</p>}
                </div>
              )
            })}
            {bottlenecks.length === 0 && <p className="text-outline italic">No active bottlenecks.</p>}
          </div>
        </div>
      </div>

      {/* Deploy Pipeline Modal */}
      {isDeploying && (
        <div className="absolute inset-0 bg-black/60 flex items-center justify-center z-50 backdrop-blur-sm">
          <div className="bg-surface border border-outline-variant shadow-sm border border-outline rounded-lg p-6 w-96 shadow-2xl">
            <h3 className="text-xl font-bold mb-4 text-foreground border-b border-outline-variant pb-2">Deploy New Pipeline</h3>
            
            <div className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-on-surface-variant uppercase mb-1">Material Type</label>
                <select 
                  className="w-full bg-background border border-outline-variant rounded p-2 text-foreground"
                  value={formData.material_type}
                  onChange={e => setFormData({...formData, material_type: e.target.value})}
                >
                  <option value="SUB_BASE">Sub-Base (Class 1)</option>
                  <option value="ASPHALT">Asphalt</option>
                  <option value="SPOIL">Spoil (Waste)</option>
                </select>
              </div>

              <div>
                <label className="block text-xs font-bold text-on-surface-variant uppercase mb-1">Target Tonnage (kg)</label>
                <input 
                  type="number"
                  className="w-full bg-background border border-outline-variant rounded p-2 text-foreground font-mono"
                  value={formData.target_tonnage}
                  onChange={e => setFormData({...formData, target_tonnage: parseInt(e.target.value)})}
                />
              </div>

              <div className="flex items-center gap-2 mt-4">
                <input 
                  type="checkbox" 
                  id="req4x4"
                  checked={formData.requires_4x4}
                  onChange={e => setFormData({...formData, requires_4x4: e.target.checked})}
                />
                <label htmlFor="req4x4" className="text-sm text-on-surface">Requires 4x4 Traction</label>
              </div>
            </div>

            <div className="flex justify-end gap-3 mt-8">
              <button 
                onClick={() => setIsDeploying(false)}
                className="px-4 py-2 text-on-surface-variant hover:text-foreground transition-colors"
              >
                Cancel
              </button>
              <button 
                onClick={handleDeployPipeline}
                className="bg-primary text-on-primary hover:bg-primary text-on-primary text-white font-bold py-2 px-4 rounded transition-colors"
              >
                Execute Order
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

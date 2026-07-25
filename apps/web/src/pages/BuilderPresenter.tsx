import { BarChart, AlertTriangle, Plus, HardHat, HelpCircle, X, Rocket, Settings, Info } from 'lucide-react';

interface BuilderPresenterProps {
  progress: any[];
  bottlenecks: any[];
  masterOrders: any[];
  isDeploying: boolean;
  setIsDeploying: (v: boolean) => void;
  formData: any;
  setFormData: (v: any) => void;
  isHudActive: boolean;
  setIsHudActive: (v: boolean) => void;
  handleDeployPipeline: () => void;
  isLoading?: boolean;
}

export const BuilderPresenter: React.FC<BuilderPresenterProps> = ({
  progress, bottlenecks, masterOrders,
  isDeploying, setIsDeploying,
  formData, setFormData,
  isHudActive, setIsHudActive,
  handleDeployPipeline,
  isLoading
}) => {
  return (
    <div className="flex-1 p-4 md:p-8 bg-background text-foreground h-full overflow-y-auto relative font-sans">
      
      {/* TACTICAL HUD OVERLAY */}
      {isHudActive && (
        <div 
          className="absolute inset-0 bg-background/80 backdrop-blur-sm z-40 flex items-center justify-center cursor-pointer transition-opacity duration-200"
          onClick={() => setIsHudActive(false)}
        >
          <div className="text-center pointer-events-none mt-32 max-w-lg">
            <div className="flex items-center justify-center gap-2 mb-4 animate-pulse">
              <Settings className="text-primary w-6 h-6 animate-spin" style={{ animationDuration: '3s' }} />
              <h2 className="text-primary font-mono font-bold text-2xl uppercase tracking-widest">Deploy Protocol Active</h2>
            </div>
            <div className="bg-card border border-primary p-6 shadow-[0_0_30px_rgba(34,197,94,0.15)] relative overflow-hidden">
              <div className="absolute inset-0 bg-primary/5 pointer-events-none" />
              <h3 className="text-foreground font-mono font-bold mb-4 uppercase text-sm border-b border-border pb-2 relative z-10">Sequence Initialization</h3>
              <ol className="text-muted-foreground font-mono space-y-4 relative z-10 text-left">
                <li className="flex items-start gap-3">
                  <span className="flex items-center justify-center w-5 h-5 bg-primary text-primary-foreground font-bold text-[10px] mt-0.5">01</span> 
                  <span className="text-sm">Click <strong className="text-foreground">NEW PIPELINE</strong> (Highlighted Top Right).</span>
                </li>
                <li className="flex items-start gap-3">
                  <span className="flex items-center justify-center w-5 h-5 bg-primary text-primary-foreground font-bold text-[10px] mt-0.5">02</span> 
                  <span className="text-sm">Input exact tonnage calculated from Civil 3D volumetric analysis.</span>
                </li>
                <li className="flex items-start gap-3">
                  <span className="flex items-center justify-center w-5 h-5 bg-primary text-primary-foreground font-bold text-[10px] mt-0.5">03</span> 
                  <span className="text-sm">Execute Order to open volumetric channel and authorize fleet.</span>
                </li>
              </ol>
            </div>
            <p className="text-muted-foreground mt-6 text-xs font-mono uppercase tracking-widest animate-pulse">Press ESC or click anywhere to dismiss</p>
          </div>
        </div>
      )}

      {/* HEADER */}
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-8 gap-4">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-3 text-foreground">
            <BarChart className="text-primary w-6 h-6" />
            Project progress
          </h1>
          <p className="text-sm font-sans text-muted-foreground mt-1">Macro-level volume tracking and pipeline deployment. No truck-level micromanagement.</p>
        </div>
        <div className={isHudActive ? "relative z-50 ring-4 ring-primary/50 shadow-[0_0_20px_rgba(34,197,94,0.4)]" : ""}>
          <button 
            onClick={() => {
              if (isHudActive) setIsHudActive(false);
              setIsDeploying(true);
            }}
            className="bg-primary text-primary-foreground hover:bg-primary/90 font-bold py-2.5 px-5 flex items-center gap-2 transition-colors font-mono tracking-widest text-xs uppercase"
          >
            <Plus className="w-4 h-4" />
            New Pipeline
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-12 gap-8">
        
        {/* Active Pipelines */}
        <div className="xl:col-span-8 space-y-4">
          <div className="flex items-center justify-between mb-4 border-b border-border pb-2">
            <h2 className="text-lg font-mono font-bold flex items-center gap-2 text-foreground uppercase tracking-wider">
              <HardHat className="text-primary w-5 h-5" />
              Active Master Orders
            </h2>
            <div className="relative group">
              <button className="text-muted-foreground hover:text-primary transition-colors p-1.5 hover:bg-muted border border-border shadow-sm">
                <HelpCircle className="w-4 h-4" />
              </button>
              <div className="absolute right-0 top-full mt-2 w-72 bg-card border border-border shadow-2xl p-5 hidden group-hover:block z-50">
                <h4 className="text-primary font-mono font-bold mb-3 text-xs uppercase tracking-wider">Deploy Protocol</h4>
                <ol className="text-left font-mono text-xs text-muted-foreground space-y-3">
                  <li className="flex gap-2"><span className="text-primary font-bold">1.</span> Click "New Pipeline".</li>
                  <li className="flex gap-2"><span className="text-primary font-bold">2.</span> Input target tonnage from Civil 3D.</li>
                  <li className="flex gap-2"><span className="text-primary font-bold">3.</span> Execute Order to open channel.</li>
                </ol>
              </div>
            </div>
          </div>
          
          <div className="space-y-4">
            {isLoading ? (
              <div className="space-y-4">
                {[1,2,3].map(i => (
                  <div key={i} className="bg-card/50 animate-pulse border border-border h-32" />
                ))}
              </div>
            ) : masterOrders.map((order) => {
              const p = progress.find(pr => pr.material_type === order.material_type);
              const delivered = p ? p.total_mass_delivered_kg : 0;
              const percent = Math.min(100, (delivered / order.target_tonnage) * 100);
              const isFulfilled = order.status === 'FULFILLED';
              const remaining = Math.max(0, order.target_tonnage - delivered);
              
              return (
                <div key={order.id} className={`bg-card shadow-lg rounded-lg p-5 relative group transition-colors ${isFulfilled ? 'opacity-60 grayscale' : 'hover:shadow-[0_0_15px_rgba(34,197,94,0.15)]'}`}>
                  <div className="flex justify-between items-start mb-4">
                    <div>
                      <div className="flex items-center gap-3 mb-2">
                        <span className={`px-2 py-0.5 text-[10px] font-mono font-bold uppercase tracking-widest border ${isFulfilled ? 'bg-secondary text-secondary-foreground border-border' : 'bg-primary/10 text-primary border-primary/20'}`}>
                          {order.material_type}
                        </span>
                        <span className="font-mono text-xs text-muted-foreground">ORD-{String(order.id).substring(0,6).toUpperCase()}</span>
                      </div>
                      <h4 className={`font-mono font-bold text-lg tracking-tight uppercase ${isFulfilled ? 'text-muted-foreground' : 'text-foreground'}`}>
                        {order.material_type} Pipeline
                      </h4>
                    </div>
                    <div className="text-right">
                      <span className={`font-mono text-2xl font-bold ${isFulfilled ? 'text-muted-foreground' : 'text-primary'}`}>
                        {percent.toFixed(1)}%
                      </span>
                      <p className="font-mono text-[9px] text-muted-foreground uppercase tracking-widest">Delivery Progress</p>
                    </div>
                  </div>
                  
                  <div className="space-y-4">
                    <div className="w-full h-2 bg-background border border-border overflow-hidden">
                      <div className={`h-full transition-all duration-1000 ${isFulfilled ? 'bg-muted-foreground' : 'bg-primary shadow-[0_0_10px_rgba(34,197,94,0.5)]'}`} style={{ width: `${percent}%` }}></div>
                    </div>
                    
                    <div className="grid grid-cols-3 gap-3">
                      <div className="p-3 bg-background border border-border flex flex-col justify-center">
                        <span className="font-mono text-[9px] font-bold text-muted-foreground uppercase block mb-1 tracking-widest">Target</span>
                        <span className="font-mono text-sm font-medium">{(order.target_tonnage / 1000).toFixed(1)} t</span>
                      </div>
                      <div className="p-3 bg-background border border-border flex flex-col justify-center">
                        <span className="font-mono text-[9px] font-bold text-muted-foreground uppercase block mb-1 tracking-widest">Remaining</span>
                        <span className="font-mono text-sm font-medium">{(remaining / 1000).toFixed(1)} t</span>
                      </div>
                      <div className="p-3 bg-background border border-border flex flex-col justify-center">
                        <span className="font-mono text-[9px] font-bold text-muted-foreground uppercase block mb-1 tracking-widest">Class</span>
                        <span className={`font-mono text-[10px] font-bold ${order.requires_4x4_traction ? 'text-primary' : 'text-muted-foreground'}`}>
                          {order.requires_4x4_traction ? '4X4_REQUIRED' : 'STANDARD'}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              );
            })}
            
            {!isLoading && masterOrders.length === 0 && (
              <div className="p-10 bg-background border border-dashed border-border text-center">
                <HardHat className="w-10 h-10 text-muted-foreground mx-auto mb-4 opacity-50" />
                <h3 className="text-foreground font-mono font-bold mb-2 uppercase tracking-wider text-sm">System Standing By</h3>
                <p className="font-sans text-muted-foreground text-sm mb-6 max-w-sm mx-auto">No active pipelines detected. To initiate JIT operations, deploy a new pipeline protocol.</p>
                <div className="text-left font-mono text-xs text-muted-foreground space-y-3 max-w-xs mx-auto mb-4 bg-card p-5 border border-border">
                  <div className="flex gap-2"><span className="text-primary font-bold">1.</span> Click "New Pipeline".</div>
                  <div className="flex gap-2"><span className="text-primary font-bold">2.</span> Input target tonnage.</div>
                  <div className="flex gap-2"><span className="text-primary font-bold">3.</span> Execute Order.</div>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Bottlenecks */}
        <div className="xl:col-span-4 space-y-4">
          <div className="mb-4 border-b border-border pb-2">
            <h3 className="text-lg font-mono font-bold flex items-center gap-2 text-foreground uppercase tracking-wider">
              <AlertTriangle className="text-destructive w-5 h-5" />
              Access Point Bottlenecks
            </h3>
          </div>
          
          <div className="bg-card shadow-lg rounded-lg overflow-hidden divide-y divide-border">
            {isLoading ? (
              <div className="p-4 bg-card/50 animate-pulse h-24" />
            ) : bottlenecks.length > 0 ? bottlenecks.map((b, i) => {
              const isCongested = b.avg_cycle_time_mins > 15;
              const severityColor = isCongested ? 'text-destructive border-l-destructive bg-destructive/10' : 'text-amber-500 border-l-amber-500 bg-amber-500/5';
              
              return (
                <div key={b.geofence_zone || i} className={`p-5 border-l-4 ${severityColor}`}>
                  <div className="flex justify-between items-center mb-2">
                    <span className={`font-mono text-[10px] font-bold px-2 py-0.5 border ${isCongested ? 'border-destructive text-destructive' : 'border-amber-500 text-amber-500'}`}>
                      {isCongested ? 'CRITICAL' : 'WARNING'}
                    </span>
                    <span className="font-mono text-[10px] text-muted-foreground">LOC: {b.geofence_zone || 'MAIN_GATE'}</span>
                  </div>
                  <h5 className="font-mono font-bold text-sm mb-1 text-foreground uppercase">
                    {isCongested ? 'Severe Congestion' : 'Elevated Cycle Time'}
                  </h5>
                  <p className="font-sans text-xs text-muted-foreground mb-4">
                    {b.active_trucks} active trucks in zone. Average cycle time: {Number(b.avg_cycle_time_mins).toFixed(1)} mins.
                  </p>
                  {isCongested && (
                    <div className="flex gap-2">
                      <button className="flex-1 py-2 px-2 bg-destructive/10 text-destructive font-mono text-[10px] font-bold hover:bg-destructive/20 transition-colors uppercase border border-destructive/30 tracking-widest">Acknowledge</button>
                    </div>
                  )}
                </div>
              )
            }) : (
              <div className="p-8 text-center bg-background border-b border-border">
                <Info className="w-8 h-8 text-muted-foreground mx-auto mb-3 opacity-50" />
                <p className="font-mono text-muted-foreground text-xs uppercase tracking-widest">No bottlenecks detected</p>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Deploy Pipeline Modal */}
      {isDeploying && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center bg-background/90 backdrop-blur-sm p-4">
          <div className="bg-card border-2 border-primary w-full max-w-md shadow-2xl">
            <div className="p-4 bg-secondary border-b border-border flex justify-between items-center">
              <div className="flex items-center gap-2">
                <Rocket className="text-primary w-5 h-5" />
                <h3 className="font-mono font-bold text-primary tracking-wider uppercase">DEPLOY NEW PIPELINE</h3>
              </div>
              <button 
                className="text-muted-foreground hover:text-foreground transition-colors"
                onClick={() => setIsDeploying(false)}
              >
                <X className="w-5 h-5" />
              </button>
            </div>
            
            <div className="p-6">
              <form className="space-y-5" onSubmit={(e) => { e.preventDefault(); handleDeployPipeline(); }}>
                <div className="space-y-2">
                  <label className="font-mono font-bold text-[10px] text-muted-foreground block uppercase tracking-widest">Material Type</label>
                  <select 
                    className="w-full bg-background border border-input text-foreground p-3 focus:border-primary focus:ring-1 focus:ring-primary transition-colors outline-none font-mono text-sm"
                    value={formData.material_type}
                    onChange={e => setFormData({...formData, material_type: e.target.value})}
                  >
                    <option value="SUB_BASE">Sub-Base (Class 1)</option>
                    <option value="ASPHALT">Asphalt</option>
                    <option value="SPOIL">Spoil (Waste)</option>
                  </select>
                </div>
                
                <div className="space-y-2">
                  <label className="font-mono font-bold text-[10px] text-muted-foreground block uppercase tracking-widest">Target Tonnage (kg)</label>
                  <div className="relative">
                    <input 
                      type="number"
                      className="w-full bg-background border border-input text-foreground p-3 focus:border-primary focus:ring-1 focus:ring-primary transition-colors font-mono outline-none text-sm"
                      value={formData.target_tonnage}
                      onChange={e => setFormData({...formData, target_tonnage: parseInt(e.target.value) || 0})}
                    />
                    <span className="absolute right-4 top-1/2 -translate-y-1/2 font-mono font-bold text-[10px] text-muted-foreground">KG</span>
                  </div>
                </div>
                
                <div className="flex items-center justify-between p-4 bg-background border border-border">
                  <div className="flex flex-col">
                    <span className="font-mono font-bold text-xs text-foreground uppercase tracking-wider">Requires 4x4 Transport</span>
                    <span className="font-sans text-[10px] text-muted-foreground mt-1">Check if access point is unpaved</span>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input 
                      type="checkbox" 
                      className="sr-only peer"
                      checked={formData.requires_4x4}
                      onChange={e => setFormData({...formData, requires_4x4: e.target.checked})}
                    />
                    <div className="w-11 h-6 bg-secondary peer-focus:outline-none rounded-none peer peer-checked:after:translate-x-full after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-muted-foreground peer-checked:after:bg-background after:border after:border-transparent after:h-5 after:w-5 after:transition-all peer-checked:bg-primary"></div>
                  </label>
                </div>
                
                <div className="pt-6 flex gap-3">
                  <button 
                    type="button"
                    onClick={() => setIsDeploying(false)}
                    className="flex-1 py-3 border border-border text-muted-foreground hover:text-foreground font-mono text-xs hover:bg-muted transition-colors tracking-widest uppercase"
                  >
                    Cancel
                  </button>
                  <button 
                    type="submit"
                    className="flex-1 py-3 bg-primary text-primary-foreground font-bold font-mono text-xs hover:brightness-110 transition-all shadow-[0_0_15px_rgba(34,197,94,0.2)] tracking-widest uppercase"
                  >
                    Execute_Order
                  </button>
                </div>
              </form>
            </div>
            <div className="px-6 py-2 bg-primary/10 border-t border-primary/20">
              <p className="font-mono text-[9px] text-primary text-center tracking-widest uppercase">SYSTEM_PENDING_AUTHORIZATION: LEVEL_3_CLEARANCE</p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

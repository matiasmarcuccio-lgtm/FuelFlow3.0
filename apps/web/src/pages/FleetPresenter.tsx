import { Truck, FileText, X, CheckCircle, UploadCloud, Activity, RefreshCw, AlertTriangle, Link } from 'lucide-react';

interface FleetPresenterProps {
  masterOrders: any[];
  driverFatigue: any[];
  fleetMatrix: any[];
  shiftAssignments: any[];
  activeLoads: any[];
  bottlenecks: any[];
  fleetDrivers: any[];
  
  selectedOrder: string; setSelectedOrder: (v: string) => void;
  selectedDriver: string; setSelectedDriver: (v: string) => void;
  selectedAsset: string; setSelectedAsset: (v: string) => void;
  handleDispatchShift: () => void;
  dispatchError: string;
  
  isVaultOpen: boolean; setIsVaultOpen: (v: boolean) => void;
  vaultOrder: string; setVaultOrder: (v: string) => void;
  vaultDriver: string; setVaultDriver: (v: string) => void;
  vaultTonnage: string; setVaultTonnage: (v: string) => void;
  vaultDocketRef: string; setVaultDocketRef: (v: string) => void;
  vaultImageFile: File | null; setVaultImageFile: (v: File | null) => void;
  vaultIsSubmitting: boolean;
  vaultError: string;
  handleVaultSubmit: () => void;
  fileInputRef: React.RefObject<HTMLInputElement | null>;
  
  isSwapModalOpen: boolean; setIsSwapModalOpen: (v: boolean) => void;
  swapReserveDriver: string; setSwapReserveDriver: (v: string) => void;
  openSwapModal: (id: string) => void;
  handleSwapDriver: () => void;
  fleetCommand: any;
  
  getFatigueStatus: (id: string) => any;
  isLoading?: boolean;
  onOpenComplianceModal?: () => void;
}

export const FleetPresenter: React.FC<FleetPresenterProps> = ({
  masterOrders, driverFatigue, fleetMatrix, shiftAssignments, activeLoads, bottlenecks, fleetDrivers,
  selectedOrder, setSelectedOrder, selectedDriver, setSelectedDriver, selectedAsset, setSelectedAsset,
  handleDispatchShift, dispatchError,
  isVaultOpen, setIsVaultOpen, vaultOrder, setVaultOrder, vaultDriver, setVaultDriver,
  vaultTonnage, setVaultTonnage, vaultDocketRef, setVaultDocketRef, vaultImageFile, setVaultImageFile,
  vaultIsSubmitting, vaultError, handleVaultSubmit, fileInputRef,
  isSwapModalOpen, setIsSwapModalOpen, swapReserveDriver, setSwapReserveDriver,
  openSwapModal, handleSwapDriver, fleetCommand, getFatigueStatus, isLoading, onOpenComplianceModal
}) => {
  return (
    <div className="flex-1 p-4 md:p-8 bg-background text-foreground h-full flex flex-col relative font-sans overflow-y-auto md:overflow-hidden">
      
      {/* EVIDENCE VAULT MODAL */}
      {isVaultOpen && (
        <div className="absolute inset-0 bg-background/90 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-card border-2 border-border shadow-2xl w-full max-w-2xl overflow-hidden flex flex-col max-h-full">
            <div className="bg-secondary p-4 border-b border-border flex justify-between items-center">
              <h2 className="text-xl font-mono font-bold flex items-center gap-2 text-foreground tracking-tight uppercase">
                <FileText className="text-primary w-5 h-5" />
                Evidence Vault (Bypass)
              </h2>
              <button onClick={() => setIsVaultOpen(false)} className="text-muted-foreground hover:text-foreground transition-colors">
                <X className="w-5 h-5" />
              </button>
            </div>
            
            <div className="p-6 overflow-y-auto space-y-6">
              <div className="bg-destructive/10 border-l-4 border-destructive p-4 text-sm text-destructive-foreground font-mono">
                <strong>LEGAL WARNING:</strong> Manual override for a "dark" vehicle. You assume full liability for accuracy under Chain of Responsibility laws. Evidence is strictly required.
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="block text-xs font-bold text-muted-foreground uppercase mb-2 font-mono">1. Target Pipeline</label>
                  <select 
                    className="w-full bg-background border border-input p-2.5 text-foreground text-sm focus:ring-1 focus:ring-primary focus:border-primary outline-none font-mono"
                    value={vaultOrder}
                    onChange={e => setVaultOrder(e.target.value)}
                    disabled={vaultIsSubmitting}
                  >
                    <option value="">Select Pipeline...</option>
                    {masterOrders.map(mo => (
                      <option key={mo.id} value={mo.id}>{mo.material_type} - {mo.target_tonnage}kg</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block text-xs font-bold text-muted-foreground uppercase mb-2 font-mono">2. Affected Driver</label>
                  <select 
                    className="w-full bg-background border border-input p-2.5 text-foreground text-sm font-mono focus:ring-1 focus:ring-primary focus:border-primary outline-none"
                    value={vaultDriver}
                    onChange={e => setVaultDriver(e.target.value)}
                    disabled={vaultIsSubmitting}
                  >
                    <option value="">Select Driver...</option>
                    {driverFatigue.map(d => (
                      <option key={d.driver_id} value={d.driver_id}>
                        {d.driver_id.substring(0,8)}... ({d.hours_active}h)
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-muted-foreground uppercase mb-2 font-mono">3. Physical Evidence</label>
                <div 
                  className={`border-2 border-dashed p-8 text-center cursor-pointer transition-colors ${vaultImageFile ? 'border-primary bg-primary/10' : 'border-border hover:border-primary/50 bg-background'}`}
                  onClick={() => fileInputRef.current?.click()}
                >
                  <input 
                    type="file" 
                    accept="image/*" 
                    className="hidden" 
                    ref={fileInputRef}
                    onChange={e => setVaultImageFile(e.target.files?.[0] || null)}
                    disabled={vaultIsSubmitting}
                  />
                  {vaultImageFile ? (
                    <div className="flex flex-col items-center">
                      <CheckCircle className="w-10 h-10 text-primary mb-2" />
                      <p className="text-primary font-bold font-mono text-sm">{vaultImageFile.name}</p>
                    </div>
                  ) : (
                    <div className="flex flex-col items-center">
                      <UploadCloud className="w-10 h-10 text-muted-foreground mb-2" />
                      <p className="text-muted-foreground font-mono text-sm uppercase">Upload Weighbridge Docket</p>
                    </div>
                  )}
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="block text-xs font-bold text-muted-foreground uppercase mb-2 font-mono">4. Paper Reference</label>
                  <input 
                    type="text" 
                    className="w-full bg-background border border-input p-2.5 text-foreground text-sm font-mono focus:ring-1 focus:ring-primary focus:border-primary outline-none"
                    placeholder="DOC-12345"
                    value={vaultDocketRef}
                    onChange={e => setVaultDocketRef(e.target.value)}
                    disabled={vaultIsSubmitting}
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold text-muted-foreground uppercase mb-2 font-mono">5. Exact Mass (kg)</label>
                  <input 
                    type="number" 
                    className="w-full bg-background border border-input p-2.5 text-foreground text-sm font-mono focus:ring-1 focus:ring-primary focus:border-primary outline-none"
                    placeholder="4000"
                    value={vaultTonnage}
                    onChange={e => setVaultTonnage(e.target.value)}
                    disabled={vaultIsSubmitting}
                  />
                </div>
              </div>

              {vaultError && (
                <div className="p-3 bg-destructive/10 border border-destructive/20 text-xs text-destructive font-mono font-bold text-center">
                  {vaultError}
                </div>
              )}
            </div>
            
            <div className="p-4 border-t border-border bg-secondary flex justify-end gap-4">
              <button 
                onClick={() => setIsVaultOpen(false)}
                className="px-6 py-2 font-mono font-bold text-muted-foreground hover:text-foreground text-sm uppercase"
                disabled={vaultIsSubmitting}
              >
                CANCEL
              </button>
              <button 
                onClick={handleVaultSubmit}
                disabled={vaultIsSubmitting || !vaultImageFile}
                className="bg-primary text-primary-foreground hover:bg-primary/90 disabled:opacity-50 text-sm font-mono font-bold py-2 px-8 flex items-center gap-2 uppercase tracking-widest"
              >
                {vaultIsSubmitting ? <Activity className="w-4 h-4 animate-spin" /> : 'SEAL BYPASS'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* SWAP MODAL */}
      {isSwapModalOpen && (
        <div className="absolute inset-0 bg-background/90 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-card border-2 border-border max-w-md w-full shadow-2xl">
            <div className="p-4 border-b border-border flex justify-between items-center bg-secondary">
              <h2 className="text-xl font-mono font-bold text-primary flex items-center gap-2 uppercase">
                <RefreshCw className="w-5 h-5" /> TACTICAL OVERRIDE
              </h2>
              <button onClick={() => setIsSwapModalOpen(false)} className="text-muted-foreground hover:text-foreground">
                <X className="w-5 h-5" />
              </button>
            </div>
            
            <div className="p-6 space-y-4">
              <div className="bg-muted p-4 text-sm text-foreground border-l-4 border-muted-foreground font-mono">
                Forcefully detaching driver from active Auto-Loop and assigning physical truck to reserve driver.
              </div>

              {fleetCommand.error && (
                <div className="bg-destructive/10 border-l-4 border-destructive p-4">
                  <h4 className="text-destructive font-bold font-mono">{fleetCommand.error.code}</h4>
                  <p className="text-destructive-foreground font-mono text-xs mt-1">{fleetCommand.error.message}</p>
                </div>
              )}

              <div>
                <label className="block text-xs font-bold text-muted-foreground uppercase mb-2 font-mono">Select Reserve Driver</label>
                <select 
                  className="w-full bg-background border border-input p-2.5 text-foreground text-sm font-mono focus:ring-1 focus:ring-primary focus:border-primary outline-none"
                  value={swapReserveDriver}
                  onChange={e => setSwapReserveDriver(e.target.value)}
                >
                  <option value="">Choose operator...</option>
                  {fleetDrivers
                    .filter(d => !shiftAssignments.some(s => s.driver_id === d.id))
                    .map(d => (
                    <option key={d.id} value={d.id}>{d.full_name || d.id.substring(0,8)}</option>
                  ))}
                </select>
              </div>
              
              <button 
                onClick={handleSwapDriver}
                disabled={fleetCommand.isLoading || !swapReserveDriver}
                className="w-full bg-primary hover:bg-primary/90 disabled:opacity-50 text-primary-foreground font-mono font-bold py-3 mt-4 uppercase tracking-widest"
              >
                {fleetCommand.isLoading ? 'OVERRIDING...' : 'EXECUTE OVERRIDE'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* HEADER TITLE */}
      <h1 className="text-2xl font-bold mb-2 flex items-center gap-3 text-foreground">
        <Truck className="text-primary w-6 h-6" />
        Resource matrix
      </h1>
      <p className="text-sm font-sans text-muted-foreground mb-8">Manage active pipelines, triage fleet health, and dispatch JIT shifts.</p>

      <div className="flex flex-col gap-6 flex-1 min-h-0 overflow-hidden">
        
        {/* TOP ROW: IGNITION MATRIX */}
        <div className="w-full shrink-0 bg-card border border-border flex flex-col shadow-lg overflow-visible">
          <div className="p-4 border-b border-border bg-secondary/80">
            <h2 className="text-sm font-mono font-bold flex items-center gap-2 text-foreground uppercase tracking-widest">
              <Link className="text-primary w-4 h-4" />
              DISPATCH IGNITION
            </h2>
          </div>
          <div className="p-5 flex flex-col xl:flex-row gap-5 items-end">
            <div className="w-full xl:flex-1">
              <label className="block text-[10px] font-mono font-bold text-muted-foreground uppercase mb-2 tracking-widest">1. Couple Pipeline</label>
              <select 
                className="w-full bg-background border border-input p-2.5 text-foreground text-sm font-mono focus:border-primary outline-none transition-colors"
                value={selectedOrder}
                onChange={e => setSelectedOrder(e.target.value)}
              >
                <option value="">Select Pipeline...</option>
                {masterOrders.map(mo => (
                  <option key={mo.id} value={mo.id}>{mo.material_type} [{mo.target_tonnage}kg]</option>
                ))}
              </select>
            </div>

            <div className="w-full xl:flex-1">
              <label className="block text-[10px] font-mono font-bold text-muted-foreground uppercase mb-2 tracking-widest">2. Select Driver</label>
              <select 
                className="w-full bg-background border border-input p-2.5 text-foreground text-sm font-mono focus:border-primary outline-none transition-colors"
                value={selectedDriver}
                onChange={e => setSelectedDriver(e.target.value)}
              >
                <option value="">Select Driver...</option>
                {fleetDrivers.map(d => {
                  const status = getFatigueStatus(d.id);
                  return (
                    <option key={d.id} value={d.id} disabled={status.isCritical}>
                      {d.full_name || d.id.substring(0,8)} - {status.hours.toFixed(1)}h
                    </option>
                  )
                })}
              </select>
            </div>

            <div className="w-full xl:flex-1">
              <label className="block text-[10px] font-mono font-bold text-muted-foreground uppercase mb-2 tracking-widest">3. Assign Asset</label>
              <select 
                className="w-full bg-background border border-input p-2.5 text-foreground text-sm font-mono focus:border-primary outline-none transition-colors"
                value={selectedAsset}
                onChange={e => setSelectedAsset(e.target.value)}
              >
                <option value="">Select Vehicle...</option>
                {fleetMatrix.map(v => (
                  <option key={v.vehicle_id} value={v.vehicle_id}>
                    {v.registration_number}
                  </option>
                ))}
              </select>
            </div>

            <div className="w-full xl:w-auto flex flex-col">
              {dispatchError && (
                <div className="mb-2 p-2 bg-destructive/10 border border-destructive/20 flex flex-col gap-2 text-xs text-destructive font-mono font-bold text-center">
                  <span>{dispatchError}</span>
                  {dispatchError.toLowerCase().includes('póliza') && onOpenComplianceModal && (
                    <button 
                      onClick={onOpenComplianceModal}
                      className="mt-1 bg-red-600 hover:bg-red-700 text-white py-1 px-3 rounded text-[10px] uppercase tracking-widest shadow-sm mx-auto"
                    >
                      Regularizar Conductor
                    </button>
                  )}
                </div>
              )}

              <button 
                onClick={handleDispatchShift}
                className="w-full xl:w-48 bg-primary hover:bg-primary/90 text-primary-foreground font-mono font-bold py-2.5 active:scale-[0.98] transition-all flex items-center justify-center gap-2 text-xs tracking-widest uppercase shadow-[0_0_15px_rgba(34,197,94,0.15)]"
              >
                <Activity className="w-4 h-4" /> DISPATCH
              </button>
            </div>
          </div>
        </div>

        {/* COL 2: FLEET GRID (Main) */}
        <div className="flex-1 flex flex-col min-h-0">
          <div className="flex items-center justify-between mb-4 border-b border-border pb-3">
            <div>
              <h2 className="text-lg font-mono font-bold text-foreground tracking-tight uppercase">Active Fleet Matrix</h2>
              <p className="text-xs font-sans text-muted-foreground mt-1">Real-time status monitoring of all active logistics deployments.</p>
            </div>
            <button 
              onClick={() => setIsVaultOpen(true)}
              className="text-[10px] font-mono bg-card text-muted-foreground hover:text-foreground border border-border px-4 py-2 uppercase font-bold tracking-widest hover:bg-muted transition-colors flex items-center gap-2"
            >
              <FileText className="w-3 h-3" />
              OPEN VAULT
            </button>
          </div>
          
          <div className="flex-1 overflow-y-auto pr-2 custom-scrollbar">
            {isLoading ? (
              <div className="grid grid-grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-4">
                {[1,2,3].map((_, index) => (
                  <div key={index} className="bg-card/30 animate-pulse border border-border h-40"></div>
                ))}
              </div>
            ) : (
              <div className="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-4">
                {shiftAssignments.map((shift) => {
                  const activeLoad = activeLoads.find(l => l.driver_id === shift.driver_id);
                  const latencyMinutes = activeLoad ? (Date.now() - new Date(activeLoad.updated_at).getTime()) / 60000 : 0;
                  
                  const zoneBottleneck = activeLoad ? bottlenecks.find(b => b.geofence_zone === activeLoad.staging_area) : null;
                  const avgCycleTime = zoneBottleneck?.avg_cycle_time_mins ? Number(zoneBottleneck.avg_cycle_time_mins) : 45;
                  const threshold = avgCycleTime * 1.25; 
                  
                  const isMIA = activeLoad && latencyMinutes > threshold;
                  const isDetaching = shift.intent_to_detach === true;
                  
                  // Visual Triage Variables
                  let badgeText = 'OPERATIONAL';
                  let badgeColor = 'bg-primary/10 text-primary border-primary/20';
                  let cardBorder = 'border-border';
                  let statusGlow = 'shadow-none';
                  
                  if (isMIA) {
                    badgeText = 'SIGNAL LOST';
                    badgeColor = 'bg-amber-500/10 text-amber-500 border-amber-500/20';
                    cardBorder = 'border-amber-500/50';
                  } else if (isDetaching) {
                    badgeText = 'CRITICAL FAILURE';
                    badgeColor = 'bg-destructive/10 text-destructive border-destructive/20 animate-pulse';
                    cardBorder = 'border-destructive/80';
                    statusGlow = 'shadow-[inset_4px_0_0_rgba(239,68,68,1)]';
                  } else {
                    statusGlow = 'shadow-[inset_4px_0_0_rgba(34,197,94,1)]';
                  }

                  return (
                    <div key={shift.id} className={`bg-card p-5 border ${cardBorder} flex flex-col gap-4 relative overflow-hidden group hover:bg-secondary/40 transition-all ${statusGlow}`}>
                      
                      <div className="flex justify-between items-start">
                        <div>
                          <div className="flex items-center gap-2 mb-2">
                            <span className="font-mono text-[10px] font-bold px-2 py-0.5 bg-background text-foreground border border-border">LOOP-{String(shift.id).substring(0,4).toUpperCase()}</span>
                            <span className={`font-mono text-[9px] px-2 py-0.5 border font-bold tracking-widest ${badgeColor}`}>
                              {badgeText}
                            </span>
                          </div>
                          <span className="font-bold text-sm font-mono text-foreground uppercase tracking-wider">OP: {String(shift.driver_id).substring(0,8)}</span>
                        </div>
                      </div>
                      
                      <div className="grid grid-cols-2 gap-3 mt-1">
                        <div className="bg-background border border-border p-3 flex flex-col justify-center">
                          <p className="text-[9px] font-mono font-bold text-muted-foreground uppercase tracking-widest mb-1">Vehicle</p>
                          <p className="font-mono text-xs text-foreground">{shift.vehicle_id ? String(shift.vehicle_id).substring(0,8) : 'UNK'}</p>
                        </div>
                        <div className="bg-background border border-border p-3 flex flex-col justify-center">
                          <p className="text-[9px] font-mono font-bold text-muted-foreground uppercase tracking-widest mb-1">Payload</p>
                          <p className="font-mono text-xs text-foreground">{shift.master_order_id ? String(shift.master_order_id).substring(0,8) : 'N/A'}</p>
                        </div>
                      </div>

                      <div className="mt-auto pt-2">
                        <button 
                          onClick={() => openSwapModal(shift.driver_id)}
                          className="w-full py-2 bg-transparent hover:bg-secondary text-[10px] font-mono font-bold tracking-widest text-muted-foreground hover:text-foreground border border-border transition-all uppercase"
                        >
                          SWAP OPERATOR
                        </button>
                      </div>
                    </div>
                  );
                })}

                {!isLoading && shiftAssignments.length === 0 && (
                  <div className="col-span-full p-16 flex flex-col items-center justify-center text-muted-foreground bg-background border border-dashed border-border">
                    <AlertTriangle className="w-10 h-10 mb-4 opacity-50" />
                    <p className="font-mono tracking-widest text-xs uppercase font-bold">NO ACTIVE FLEET LOOPS</p>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>

      </div>
    </div>
  );
};

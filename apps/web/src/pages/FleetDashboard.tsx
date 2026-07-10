import React, { useEffect, useState, useRef } from 'react';
import { supabase } from '../lib/supabase';
import { useCurrentProfile } from '../hooks/useCurrentProfile';
import { useFleetCommand } from '../hooks/useFleetCommand';
import { Truck, ShieldAlert, CheckCircle, Link, Activity, HelpCircle, UploadCloud, X, FileText, RefreshCw } from 'lucide-react';

export const FleetDashboard = () => {
  const { data: currentProfile } = useCurrentProfile();
  const fleetCommand = useFleetCommand();
  const [fleetMatrix, setFleetMatrix] = useState<any[]>([]);
  const [driverFatigue, setDriverFatigue] = useState<any[]>([]);
  const [masterOrders, setMasterOrders] = useState<any[]>([]);
  const [shiftAssignments, setShiftAssignments] = useState<any[]>([]);
  const [activeLoads, setActiveLoads] = useState<any[]>([]);
  const [bottlenecks, setBottlenecks] = useState<any[]>([]);
  const [fleetDrivers, setFleetDrivers] = useState<any[]>([]);  
  const [selectedOrder, setSelectedOrder] = useState<string>('');
  const [selectedDriver, setSelectedDriver] = useState<string>('');
  const [selectedAsset, setSelectedAsset] = useState<string>('');
  const [dispatchError, setDispatchError] = useState<string>('');

  const [isHudActive, setIsHudActive] = useState(false);
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 60000);
    return () => clearInterval(timer);
  }, []);

  // Evidence Vault State
  const [isVaultOpen, setIsVaultOpen] = useState(false);
  const [vaultOrder, setVaultOrder] = useState<string>('');
  const [vaultDriver, setVaultDriver] = useState<string>('');
  const [vaultTonnage, setVaultTonnage] = useState<string>('');
  const [vaultDocketRef, setVaultDocketRef] = useState<string>('');
  const [vaultImageFile, setVaultImageFile] = useState<File | null>(null);
  const [vaultIsSubmitting, setVaultIsSubmitting] = useState(false);
  const [vaultError, setVaultError] = useState<string>('');
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Swap Driver State
  const [isSwapModalOpen, setIsSwapModalOpen] = useState(false);
  const [swapAbsentDriver, setSwapAbsentDriver] = useState<string>('');
  const [swapReserveDriver, setSwapReserveDriver] = useState<string>('');

  useEffect(() => {
    fetchData();

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === '?' && e.shiftKey) {
        setIsHudActive(prev => !prev);
      }
      if (e.key === 'Escape') {
        setIsHudActive(false);
        setIsVaultOpen(false);
        setIsSwapModalOpen(false);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [currentProfile]);

  async function fetchData() {
    const { data: fleetData } = await supabase.from('view_fleet_matrix').select('*');
    if (fleetData) setFleetMatrix(fleetData);

    const { data: fatigueData } = await supabase.from('view_driver_fatigue').select('*');
    if (fatigueData) setDriverFatigue(fatigueData);

    const { data: ordersData } = await supabase.from('master_orders').select('*').eq('status', 'OPEN');
    if (ordersData) setMasterOrders(ordersData);

    const { data: shiftsData } = await supabase.from('shift_assignments').select('*').eq('status', 'ACTIVE');
    if (shiftsData) setShiftAssignments(shiftsData);

    const { data: loadsData } = await supabase.from('load_offers').select('*').in('status', ['PENDING', 'LOADING', 'IN_TRANSIT', 'AT_WEIGHBRIDGE']);
    if (loadsData) setActiveLoads(loadsData);

    const { data: bottleneckData } = await supabase.from('view_site_bottlenecks').select('*');
    if (bottleneckData) setBottlenecks(bottleneckData);

    if (currentProfile?.fleet_id) {
      const { data: driversData } = await supabase
        .from('profiles')
        .select('*')
        .eq('fleet_id', currentProfile.fleet_id)
        .eq('role', 'DRIVER')
        .eq('status', 'ACTIVE');
      if (driversData) setFleetDrivers(driversData);
    }
  };

  const getFatigueStatus = (driverId: string) => {
    const record = driverFatigue.find(d => d.driver_id === driverId);
    if (!record) return { hours: 0, color: 'text-emerald-400', isCritical: false, label: 'SAFE' };
    
    const hours = Number(record.hours_active);
    if (hours >= 11) return { hours, color: 'text-red-500', isCritical: true, label: 'LIMIT EXCEEDED' };
    if (hours >= 10) return { hours, color: 'text-orange-500', isCritical: true, label: 'APPROACHING LIMIT' };
    return { hours, color: 'text-emerald-400', isCritical: false, label: 'SAFE' };
  };

  const handleDispatchShift = async () => {
    setDispatchError('');
    if (!selectedOrder || !selectedDriver || !selectedAsset) {
      setDispatchError('Select Pipeline, Driver, and Asset to dispatch.');
      return;
    }

    const { error } = await supabase.rpc('fn_dispatch_shift', {
      p_master_order_id: selectedOrder,
      p_driver_id: selectedDriver,
      p_asset_id: selectedAsset
    });

    if (error) {
      setDispatchError(error.message);
    } else {
      setSelectedDriver('');
      setSelectedAsset('');
      fetchData();
    }
  };

  const handleSwapDriver = async () => {
    if (!swapAbsentDriver || !swapReserveDriver) return;
    const success = await fleetCommand.overrideShift(swapAbsentDriver, swapReserveDriver);
    if (success) {
      setIsSwapModalOpen(false);
      setSwapAbsentDriver('');
      setSwapReserveDriver('');
      fetchData();
    }
  };

  const openSwapModal = (absentDriverId: string) => {
    fleetCommand.resetState();
    setSwapAbsentDriver(absentDriverId);
    setSwapReserveDriver('');
    setIsSwapModalOpen(true);
  };

  const handleVaultSubmit = async () => {
    setVaultError('');
    if (!vaultOrder || !vaultDriver || !vaultTonnage || !vaultDocketRef || !vaultImageFile) {
      setVaultError('All fields and physical evidence are mandatory.');
      return;
    }

    setVaultIsSubmitting(true);
    try {
      // 1. Upload Evidence
      const fileExt = vaultImageFile.name.split('.').pop();
      const fileName = `${Math.random().toString(36).substring(2, 15)}_${Date.now()}.${fileExt}`;
      const filePath = `retroactive/${fileName}`;

      const { error: uploadError } = await supabase.storage
        .from('docket_evidence')
        .upload(filePath, vaultImageFile);

      if (uploadError) throw uploadError;

      // 2. Call RPC
      const { error: rpcError } = await supabase.rpc('fn_inject_retroactive_docket', {
        p_master_order_id: vaultOrder,
        p_driver_id: vaultDriver,
        p_loaded_gross_mass: Number(vaultTonnage),
        p_paper_docket_ref: vaultDocketRef,
        p_docket_image_path: filePath
      });

      if (rpcError) throw rpcError;

      // Success
      setIsVaultOpen(false);
      setVaultOrder('');
      setVaultDriver('');
      setVaultTonnage('');
      setVaultDocketRef('');
      setVaultImageFile(null);
      fetchData();

    } catch (err: any) {
      setVaultError(err.message || 'Unknown error during vault submission');
    } finally {
      setVaultIsSubmitting(false);
    }
  };

  return (
    <div className="flex-1 p-8 bg-background text-foreground h-full flex flex-col relative">
      
      {/* EVIDENCE VAULT MODAL */}
      {isVaultOpen && (
        <div className="absolute inset-0 bg-slate-950/90 backdrop-blur-md z-50 flex items-center justify-center p-4">
          <div className="bg-background border border-outline-variant rounded-lg shadow-2xl w-full max-w-2xl overflow-hidden flex flex-col max-h-full">
            <div className="bg-surface border border-outline-variant shadow-sm p-4 border-b border-outline-variant flex justify-between items-center">
              <h2 className="text-xl font-bold flex items-center gap-2 text-foreground">
                <FileText className="text-primary w-6 h-6" />
                Evidence Vault (Retroactive Docket Injection)
              </h2>
              <button onClick={() => setIsVaultOpen(false)} className="text-on-surface-variant hover:text-foreground transition-colors">
                <X className="w-6 h-6" />
              </button>
            </div>
            
            <div className="p-6 overflow-y-auto space-y-6">
              <div className="bg-blue-900/20 border border-blue-900/50 p-4 rounded text-sm text-blue-200">
                <strong>Legal Warning:</strong> You are submitting a manual override for a "dark" vehicle. You assume full legal liability for the accuracy of this data under Chain of Responsibility (CoR) laws. Photographic evidence is strictly required.
              </div>

              <div className="grid grid-cols-2 gap-6">
                <div>
                  <label className="block text-xs font-bold text-on-surface-variant uppercase mb-2">1. Target Pipeline</label>
                  <select 
                    className="w-full bg-slate-950 border border-outline-variant rounded p-3 text-foreground text-sm"
                    value={vaultOrder}
                    onChange={e => setVaultOrder(e.target.value)}
                    disabled={vaultIsSubmitting}
                  >
                    <option value="">Select an Open Pipeline...</option>
                    {masterOrders.map(mo => (
                      <option key={mo.id} value={mo.id}>{mo.material_type} - {mo.target_tonnage}kg</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block text-xs font-bold text-on-surface-variant uppercase mb-2">2. Affected Driver</label>
                  <select 
                    className="w-full bg-slate-950 border border-outline-variant rounded p-3 text-foreground text-sm font-mono"
                    value={vaultDriver}
                    onChange={e => setVaultDriver(e.target.value)}
                    disabled={vaultIsSubmitting}
                  >
                    <option value="">Select a Driver...</option>
                    {driverFatigue.map(d => (
                      <option key={d.driver_id} value={d.driver_id}>
                        {d.driver_id.substring(0,8)}... (Active: {d.hours_active}h)
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-on-surface-variant uppercase mb-2">3. Physical Evidence Upload</label>
                <div 
                  className={`border-2 border-dashed rounded-lg p-8 text-center cursor-pointer transition-colors ${vaultImageFile ? 'border-emerald-500 bg-emerald-900/10' : 'border-outline-variant hover:border-outline bg-slate-950'}`}
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
                      <CheckCircle className="w-10 h-10 text-emerald-500 mb-2" />
                      <p className="text-emerald-400 font-bold">{vaultImageFile.name}</p>
                      <p className="text-xs text-outline mt-1">Click to replace</p>
                    </div>
                  ) : (
                    <div className="flex flex-col items-center">
                      <UploadCloud className="w-10 h-10 text-outline mb-2" />
                      <p className="text-on-surface-variant font-medium">Click to upload weighbridge or docket photo</p>
                      <p className="text-xs text-outline mt-1">Required to seal bypass</p>
                    </div>
                  )}
                </div>
              </div>

              <div className="grid grid-cols-2 gap-6">
                <div>
                  <label className="block text-xs font-bold text-on-surface-variant uppercase mb-2">4. Paper Reference Number</label>
                  <input 
                    type="text" 
                    className="w-full bg-slate-950 border border-outline-variant rounded p-3 text-foreground text-sm"
                    placeholder="e.g. DOC-12345"
                    value={vaultDocketRef}
                    onChange={e => setVaultDocketRef(e.target.value)}
                    disabled={vaultIsSubmitting}
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold text-on-surface-variant uppercase mb-2">5. Exact Mass (kg)</label>
                  <input 
                    type="number" 
                    className="w-full bg-slate-950 border border-outline-variant rounded p-3 text-foreground text-sm font-mono"
                    placeholder="e.g. 4000"
                    value={vaultTonnage}
                    onChange={e => setVaultTonnage(e.target.value)}
                    disabled={vaultIsSubmitting}
                  />
                </div>
              </div>

              {vaultError && (
                <div className="p-3 bg-red-900/50 border border-red-700 rounded text-xs text-red-200">
                  <span className="font-bold uppercase block mb-1">Vault Rejection</span>
                  {vaultError}
                </div>
              )}
            </div>
            
            <div className="p-4 border-t border-outline-variant bg-surface border border-outline-variant shadow-sm flex justify-end gap-4">
              <button 
                onClick={() => setIsVaultOpen(false)}
                className="px-6 py-2 rounded font-bold text-on-surface-variant hover:text-foreground transition-colors"
                disabled={vaultIsSubmitting}
              >
                Cancel
              </button>
              <button 
                onClick={handleVaultSubmit}
                disabled={vaultIsSubmitting || !vaultImageFile}
                className="bg-primary text-on-primary hover:bg-primary text-on-primary disabled:opacity-50 disabled:cursor-not-allowed text-white font-bold py-2 px-8 rounded shadow-lg transition-colors flex items-center gap-2"
              >
                {vaultIsSubmitting ? (
                  <>
                    <Activity className="w-4 h-4 animate-spin" />
                    Sealing...
                  </>
                ) : (
                  'Seal Bypass'
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* TACTICAL HUD OVERLAY */}
      {isHudActive && (
        <div 
          className="absolute inset-0 bg-slate-950/80 backdrop-blur-sm z-40 flex items-center justify-center cursor-pointer transition-opacity duration-200"
          onClick={() => setIsHudActive(false)}
        >
          <div className="text-center pointer-events-none mt-32">
            <h2 className="text-orange-400 font-bold text-2xl uppercase tracking-widest mb-4 animate-pulse">Tactical HUD Active</h2>
            <div className="bg-background/80 border border-orange-500/50 p-6 rounded-lg text-left inline-block shadow-[0_0_30px_rgba(249,115,22,0.3)]">
              <h3 className="text-foreground font-bold mb-4 uppercase text-sm border-b border-orange-900 pb-2">JIT Ignition Sequence</h3>
              <ol className="text-on-surface space-y-3">
                <li className="flex items-center gap-3"><span className="flex items-center justify-center w-6 h-6 rounded-full bg-orange-600 text-white font-bold text-xs">1</span> <strong className="text-foreground">Select Open Pipeline</strong> from active orders.</li>
                <li className="flex items-center gap-3"><span className="flex items-center justify-center w-6 h-6 rounded-full bg-orange-600 text-white font-bold text-xs">2</span> <strong className="text-foreground">Assign Rested Driver</strong> (Check fatigue column).</li>
                <li className="flex items-center gap-3"><span className="flex items-center justify-center w-6 h-6 rounded-full bg-orange-600 text-white font-bold text-xs">3</span> <strong className="text-foreground">Assign Asset</strong> with necessary capabilities.</li>
                <li className="flex items-center gap-3"><span className="flex items-center justify-center w-6 h-6 rounded-full bg-orange-600 text-white font-bold text-xs">4</span> Click <strong className="text-foreground">Couple & Ignite Auto-Loop</strong> (Highlighted Left).</li>
              </ol>
            </div>
            <p className="text-outline mt-6 text-sm uppercase tracking-widest">Press ESC or click anywhere to dismiss</p>
          </div>
        </div>
      )}

      <h1 className="text-2xl font-bold mb-2 flex items-center gap-2">
        <Truck className="text-orange-500" />
        Fleet Shift Matrix
      </h1>
      <p className="text-sm text-on-surface-variant mb-8">Connect assets to active pipelines. Auto-Loop JIT will take over after assignment.</p>

      <div className="grid grid-cols-3 gap-6 flex-1 min-h-0">
        
        {/* Column 1: Dispatch Control (The Shift Matrix) */}
        <div className={`bg-surface border border-outline-variant shadow-sm rounded-lg border border-outline-variant flex flex-col overflow-visible ${isHudActive ? 'relative z-50 ring-4 ring-orange-500/50 shadow-[0_0_20px_rgba(249,115,22,0.8)]' : ''}`}>
          <div className="p-4 border-b border-outline-variant">
            <h2 className="text-lg font-bold flex items-center gap-2">
              <Link className="text-primary w-5 h-5" />
              Dispatch Shift
              <div className="relative group ml-auto">
                <button className="text-outline hover:text-orange-400 transition-colors p-1 rounded-full hover:bg-background">
                  <HelpCircle className="w-4 h-4" />
                </button>
                <div className="absolute left-0 top-full mt-2 w-64 bg-background border border-outline-variant shadow-2xl rounded-lg p-4 hidden group-hover:block z-50">
                  <h4 className="text-orange-400 font-bold mb-2 text-xs uppercase tracking-wider">JIT Ignition Sequence</h4>
                  <ol className="text-left text-xs text-on-surface space-y-2">
                    <li className="flex gap-2"><span className="text-orange-500 font-bold">1.</span> Select open pipeline.</li>
                    <li className="flex gap-2"><span className="text-orange-500 font-bold">2.</span> Assign rested driver.</li>
                    <li className="flex gap-2"><span className="text-orange-500 font-bold">3.</span> Assign capable asset.</li>
                  </ol>
                </div>
              </div>
            </h2>
          </div>
          <div className="p-4 flex-1 overflow-y-auto space-y-4">
            
            <div>
              <label className="block text-xs font-bold text-on-surface-variant uppercase mb-1">1. Active Pipeline</label>
              <select 
                className="w-full bg-background border border-outline-variant rounded p-2 text-foreground text-sm"
                value={selectedOrder}
                onChange={e => setSelectedOrder(e.target.value)}
              >
                <option value="">Select an Open Pipeline...</option>
                {masterOrders.map(mo => (
                  <option key={mo.id} value={mo.id}>{mo.material_type} - {mo.target_tonnage}kg (Req 4x4: {mo.requires_4x4_traction ? 'YES' : 'NO'})</option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs font-bold text-on-surface-variant uppercase mb-1">2. Assign Driver</label>
              <select 
                className="w-full bg-background border border-outline-variant rounded p-2 text-foreground text-sm font-mono"
                value={selectedDriver}
                onChange={e => setSelectedDriver(e.target.value)}
              >
                <option value="">Select a Driver...</option>
                {driverFatigue.map(d => {
                  const status = getFatigueStatus(d.driver_id);
                  return (
                    <option key={d.driver_id} value={d.driver_id} disabled={status.isCritical}>
                      {d.driver_id.substring(0,8)} - {status.hours.toFixed(1)}h ({status.label})
                    </option>
                  )
                })}
              </select>
            </div>

            <div>
              <label className="block text-xs font-bold text-on-surface-variant uppercase mb-1">3. Assign Asset</label>
              <select 
                className="w-full bg-background border border-outline-variant rounded p-2 text-foreground text-sm"
                value={selectedAsset}
                onChange={e => setSelectedAsset(e.target.value)}
              >
                <option value="">Select a Vehicle...</option>
                {fleetMatrix.map(v => (
                  <option key={v.vehicle_id} value={v.vehicle_id}>
                    {v.registration_number} (4x4: {v.has_4x4_traction ? 'YES' : 'NO'})
                  </option>
                ))}
              </select>
            </div>

            {dispatchError && (
              <div className="p-3 bg-red-900/50 border border-red-700 rounded text-xs text-red-200">
                <span className="font-bold uppercase block mb-1">Assignment Rejected</span>
                {dispatchError}
              </div>
            )}

            <button 
              onClick={handleDispatchShift}
              className="w-full bg-orange-600 hover:bg-orange-500 text-white font-bold py-3 rounded mt-4 transition-colors shadow-lg"
            >
              Couple & Ignite Auto-Loop
            </button>
          </div>
        </div>

        {/* Column 2: Active Shift Assignments */}
        <div className="bg-surface border border-outline-variant shadow-sm rounded-lg border border-outline-variant flex flex-col overflow-visible">
          <div className="p-4 border-b border-outline-variant flex justify-between items-center">
            <h2 className="text-lg font-bold flex items-center gap-2">
              <Activity className="text-emerald-500 w-5 h-5" />
              Active Auto-Loops
            </h2>
            <button 
              onClick={() => setIsVaultOpen(true)}
              className="text-xs bg-blue-900/50 hover:bg-primary text-on-primary text-blue-200 font-bold px-3 py-1 rounded transition-colors border border-blue-800"
            >
              + Inject Docket
            </button>
          </div>
          <div className="p-4 flex-1 overflow-y-auto space-y-2">
            {shiftAssignments.map((shift, i) => {
              const activeLoad = activeLoads.find(l => l.driver_id === shift.driver_id);
              const latencyMinutes = activeLoad ? (Date.now() - new Date(activeLoad.updated_at).getTime()) / 60000 : 0;
              
              const zoneBottleneck = activeLoad ? bottlenecks.find(b => b.geofence_zone === activeLoad.staging_area) : null;
              const avgCycleTime = zoneBottleneck?.avg_cycle_time_mins ? Number(zoneBottleneck.avg_cycle_time_mins) : 45;
              const threshold = avgCycleTime * 1.25; // 25% tolerance
              
              const isMIA = activeLoad && latencyMinutes > threshold;
              const isDetaching = shift.intent_to_detach === true;
              
              return (
                <div key={i} className={`p-3 rounded border ${isMIA ? 'bg-red-950/40 border-red-500 animate-pulse' : isDetaching ? 'bg-orange-900/20 border-orange-700' : 'bg-background border-emerald-900/50'}`}>
                  <div className="flex justify-between">
                    <span className={`text-xs font-bold uppercase tracking-wider ${isMIA ? 'text-red-500' : isDetaching ? 'text-orange-500 animate-pulse' : 'text-emerald-500'}`}>
                      {isMIA ? 'SIGNAL LOST / M.I.A' : isDetaching ? 'DETACH PENDING' : 'LOOP ACTIVE'}
                    </span>
                    <span className="text-[10px] text-outline font-mono">{shift.id?.substring(0,8) || 'N/A'}</span>
                  </div>
                  <div className="mt-2 text-xs text-on-surface font-mono space-y-1">
                    <p>DRV: {shift.driver_id?.substring(0,8) || 'N/A'}...</p>
                    <p>AST: {shift.vehicle_id?.substring(0,8) || 'N/A'}...</p>
                    <p>PLN: {shift.master_order_id?.substring(0,8) || 'N/A'}...</p>
                  </div>
                  {isMIA && (
                    <div className="mt-2 p-2 bg-red-950 rounded border border-red-900">
                      <p className="text-[10px] text-red-400 font-bold uppercase tracking-wider mb-1">CRITICAL LATENCY ALARM</p>
                      <p className="text-xs text-red-200">No telemetry in {Math.round(latencyMinutes)}m (Threshold: {Math.round(threshold)}m). Check radio.</p>
                    </div>
                  )}
                  {!isMIA && isDetaching && (
                    <div className="mt-2 p-2 bg-orange-950/50 rounded border border-orange-900">
                      <p className="text-[10px] text-orange-400 font-bold uppercase tracking-wider mb-1">Reason for Break</p>
                      <p className="text-xs text-orange-200">{shift.detach_reason?.replace(/_/g, ' ') || 'DRIVER REQUEST'}</p>
                    </div>
                  )}
                  
                  <div className="mt-3 pt-3 border-t border-outline-variant/50">
                    <button 
                      onClick={() => openSwapModal(shift.driver_id)}
                      className="w-full bg-orange-900/40 hover:bg-orange-600 text-orange-400 hover:text-white font-bold py-1.5 rounded text-xs transition-colors border border-orange-800 flex items-center justify-center gap-2"
                    >
                      <RefreshCw className="w-3 h-3" />
                      Swap Driver
                    </button>
                  </div>
                </div>
              );
            })}
            {shiftAssignments.length === 0 && (
              <div className="p-4 bg-orange-900/10 border border-orange-900/30 rounded-lg text-center mt-4">
                <Truck className="w-10 h-10 text-orange-500/50 mx-auto mb-2" />
                <h3 className="text-orange-400 font-bold mb-2 uppercase tracking-wider text-xs">No Active Fleet Loops</h3>
                <ol className="text-left text-[11px] text-outline space-y-1 bg-background/50 p-3 rounded border border-outline-variant">
                  <li className="flex gap-2"><span className="text-orange-500 font-bold">1.</span> Select an open pipeline.</li>
                  <li className="flex gap-2"><span className="text-orange-500 font-bold">2.</span> Assign a rested driver.</li>
                  <li className="flex gap-2"><span className="text-orange-500 font-bold">3.</span> Assign a capable asset.</li>
                  <li className="flex gap-2"><span className="text-orange-500 font-bold">4.</span> Couple to ignite JIT loop.</li>
                </ol>
              </div>
            )}
          </div>
        </div>

        {/* Column 3: Telemetry Matrix */}
        <div className="bg-surface border border-outline-variant shadow-sm rounded-lg border border-outline-variant flex flex-col">
          <div className="p-4 border-b border-outline-variant">
            <h2 className="text-lg font-bold flex items-center gap-2">
              <ShieldAlert className="text-red-500 w-5 h-5" />
              Driver Fatigue State
            </h2>
          </div>
          <div className="p-4 flex-1 overflow-y-auto space-y-2">
            {driverFatigue.map((d, i) => {
              const status = getFatigueStatus(d.driver_id);
              return (
                <div key={i} className={`p-3 rounded flex justify-between items-center border ${status.isCritical ? 'bg-red-900/20 border-red-800' : 'bg-background border-outline-variant'}`}>
                  <div>
                    <p className="font-mono text-xs text-on-surface-variant mb-1">UUID: {d.driver_id.substring(0,8)}...</p>
                    <p className={`text-[10px] font-bold ${status.color}`}>{status.label}</p>
                  </div>
                  <div className="text-right">
                    <p className={`text-lg font-bold font-mono ${status.color}`}>{status.hours.toFixed(1)}h</p>
                  </div>
                </div>
              )
            })}
            {driverFatigue.length === 0 && <p className="text-outline italic text-sm">No drivers logged today.</p>}
          </div>
        </div>

      </div>
      {/* Swap Driver Modal */}
      {isSwapModalOpen && (
        <div className="fixed inset-0 bg-black/80 flex items-center justify-center z-50 p-4">
          <div className="bg-background border-2 border-orange-600 rounded-lg max-w-lg w-full max-h-[90vh] overflow-y-auto">
            <div className="p-4 border-b border-orange-900/50 flex justify-between items-center bg-orange-950/20">
              <h2 className="text-xl font-bold text-orange-500 flex items-center gap-2">
                <RefreshCw className="w-5 h-5" /> Tactical Shift Override
              </h2>
              <button onClick={() => setIsSwapModalOpen(false)} className="text-on-surface-variant hover:text-foreground">
                <X className="w-6 h-6" />
              </button>
            </div>
            
            <div className="p-6 space-y-4">
              <div className="bg-orange-950/30 p-4 rounded text-sm text-orange-200 border border-orange-900/50">
                You are about to forcefully detach a driver from an active Auto-Loop and assign the physical truck to a reserve driver. 
                The current active cycle will be gracefully shut down.
              </div>

              {fleetCommand.error && (
                <div className="bg-red-950/50 border border-red-700 p-4 rounded">
                  <h4 className="text-red-400 font-bold">{fleetCommand.error.code}</h4>
                  <p className="text-red-200 text-sm mt-1">{fleetCommand.error.message}</p>
                  {fleetCommand.error.actionRequired && (
                    <p className="text-red-300 text-xs mt-2">{fleetCommand.error.actionRequired}</p>
                  )}
                </div>
              )}

              <div>
                <label className="block text-xs font-bold text-on-surface-variant uppercase mb-1">Select Reserve Driver</label>
                <select 
                  className="w-full bg-slate-950 border border-outline-variant rounded p-3 text-foreground text-sm"
                  value={swapReserveDriver}
                  onChange={e => setSwapReserveDriver(e.target.value)}
                >
                  <option value="">Choose an available operator...</option>
                  {fleetDrivers
                    .filter(d => !shiftAssignments.some(s => s.driver_id === d.id)) // Filter out drivers already in a shift
                    .map(d => (
                    <option key={d.id} value={d.id}>{d.full_name || d.id.substring(0,8)}</option>
                  ))}
                </select>
              </div>
              
              <button 
                onClick={handleSwapDriver}
                disabled={fleetCommand.isLoading || !swapReserveDriver}
                className="w-full bg-orange-600 hover:bg-orange-500 disabled:bg-orange-900 text-white font-bold py-3 rounded mt-4 transition-colors"
              >
                {fleetCommand.isLoading ? 'Overriding Shift...' : 'Execute Shift Override'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};


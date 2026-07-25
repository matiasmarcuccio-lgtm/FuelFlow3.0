import { useEffect, useState, useRef } from 'react';
import { supabase } from '../lib/supabase';
import { useCurrentProfile } from '../hooks/useCurrentProfile';
import { useFleetCommand } from '../hooks/useFleetCommand';
import { FleetPresenter } from './FleetPresenter';
import { ComplianceUploadModal } from '../features/compliance/components/ComplianceUploadModal';

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
  const [isLoading, setIsLoading] = useState<boolean>(true);

  const [isComplianceModalOpen, setIsComplianceModalOpen] = useState(false);
  const [complianceDriverId, setComplianceDriverId] = useState('');
  const [complianceDriverName, setComplianceDriverName] = useState('');

  const [, setIsHudActive] = useState(false);
  useEffect(() => {
    const timer = setInterval(() => {}, 60000);
    return () => clearInterval(timer);
  }, []);

  const [isVaultOpen, setIsVaultOpen] = useState(false);
  const [vaultOrder, setVaultOrder] = useState<string>('');
  const [vaultDriver, setVaultDriver] = useState<string>('');
  const [vaultTonnage, setVaultTonnage] = useState<string>('');
  const [vaultDocketRef, setVaultDocketRef] = useState<string>('');
  const [vaultImageFile, setVaultImageFile] = useState<File | null>(null);
  const [vaultIsSubmitting, setVaultIsSubmitting] = useState(false);
  const [vaultError, setVaultError] = useState<string>('');
  const fileInputRef = useRef<HTMLInputElement>(null);

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
    setIsLoading(true);
    const { data: fleetData, error: fErr } = await supabase.from('view_fleet_matrix' as any).select('*');
    if (fErr) {
      // Fallback a assets para que la UI no colapse
      const { data } = await supabase.from('assets').select('*');
      setFleetMatrix((data || []).map(a => ({ vehicle_id: a.id, registration_number: a.internal_code })));
    } else if (fleetData) {
      setFleetMatrix(fleetData);
    }

    const { data: fatigueData, error: fatErr } = await supabase.from('view_driver_fatigue' as any).select('*');
    if (fatErr) {
      const { data } = await supabase.from('profiles').select('id');
      setDriverFatigue((data || []).map(p => ({ driver_id: p.id, hours_active: 0 })));
    } else if (fatigueData) {
      setDriverFatigue(fatigueData);
    }

    const { data: ordersData } = await supabase.from('master_orders').select('*').eq('status', 'OPEN');
    if (ordersData) setMasterOrders(ordersData);

    const { data: shiftsData } = await supabase.from('shift_assignments').select('*').eq('status', 'ACTIVE');
    if (shiftsData) setShiftAssignments(shiftsData);

    const { data: loadsData } = await supabase.from('load_offers').select('*').in('status', ['PENDING', 'LOADING', 'IN_TRANSIT', 'AT_WEIGHBRIDGE']);
    if (loadsData) setActiveLoads(loadsData);

    const { data: bottleneckData, error: bErr } = await supabase.from('view_site_bottlenecks').select('*');
    if (bErr) {
      setBottlenecks([]);
    } else if (bottleneckData) {
      setBottlenecks(bottleneckData);
    }

    let driversQuery = supabase.from('profiles').select('*').in('role', ['DRIVER', 'operator']).eq('status', 'ACTIVE');
    if (currentProfile?.role === 'fleet_manager' && currentProfile?.fleet_id) {
      driversQuery = driversQuery.eq('fleet_id', currentProfile.fleet_id);
    }
    const { data: driversData } = await driversQuery;
    if (driversData) setFleetDrivers(driversData);
    setIsLoading(false);
  }

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
      if (error.message.includes('Póliza expirada')) {
         setDispatchError('Operación bloqueada: Póliza expirada. Requiere sello WHS.');
         setComplianceDriverId(selectedDriver);
         const dName = fleetDrivers.find(d => d.id === selectedDriver)?.full_name || 'Conductor';
         setComplianceDriverName(dName);
         setIsComplianceModalOpen(true);
      } else {
         setDispatchError(error.message);
      }
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
      const fileExt = vaultImageFile.name.split('.').pop();
      const fileName = `${Math.random().toString(36).substring(2, 15)}_${Date.now()}.${fileExt}`;
      const filePath = `retroactive/${fileName}`;

      const { error: uploadError } = await supabase.storage
        .from('docket_evidence')
        .upload(filePath, vaultImageFile);

      if (uploadError) throw uploadError;

      const { error: rpcError } = await supabase.rpc('fn_inject_retroactive_docket', {
        p_master_order_id: vaultOrder,
        p_driver_id: vaultDriver,
        p_loaded_gross_mass: Number(vaultTonnage),
        p_paper_docket_ref: vaultDocketRef,
        p_docket_image_path: filePath
      });

      if (rpcError) throw rpcError;

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
    <>
      {isComplianceModalOpen && (
        <ComplianceUploadModal 
          driverId={complianceDriverId}
          driverName={complianceDriverName}
          onSuccess={() => { setIsComplianceModalOpen(false); setDispatchError(''); handleDispatchShift(); }}
          onCancel={() => setIsComplianceModalOpen(false)}
        />
      )}
      <FleetPresenter 
        masterOrders={masterOrders}
        driverFatigue={driverFatigue}
        fleetMatrix={fleetMatrix}
        shiftAssignments={shiftAssignments}
        activeLoads={activeLoads}
        bottlenecks={bottlenecks}
        fleetDrivers={fleetDrivers}
        selectedOrder={selectedOrder}
        setSelectedOrder={setSelectedOrder}
        selectedDriver={selectedDriver}
        setSelectedDriver={setSelectedDriver}
        selectedAsset={selectedAsset}
        setSelectedAsset={setSelectedAsset}
        handleDispatchShift={handleDispatchShift}
        dispatchError={dispatchError}
        isVaultOpen={isVaultOpen}
        setIsVaultOpen={setIsVaultOpen}
        vaultOrder={vaultOrder}
        setVaultOrder={setVaultOrder}
        vaultDriver={vaultDriver}
        setVaultDriver={setVaultDriver}
        vaultTonnage={vaultTonnage}
        setVaultTonnage={setVaultTonnage}
        vaultDocketRef={vaultDocketRef}
        setVaultDocketRef={setVaultDocketRef}
        vaultImageFile={vaultImageFile}
        setVaultImageFile={setVaultImageFile}
        vaultIsSubmitting={vaultIsSubmitting}
        vaultError={vaultError}
        handleVaultSubmit={handleVaultSubmit}
        fileInputRef={fileInputRef}
        isSwapModalOpen={isSwapModalOpen}
        setIsSwapModalOpen={setIsSwapModalOpen}
        swapReserveDriver={swapReserveDriver}
        setSwapReserveDriver={setSwapReserveDriver}
        openSwapModal={openSwapModal}
        handleSwapDriver={handleSwapDriver}
        fleetCommand={fleetCommand}
        getFatigueStatus={getFatigueStatus}
        isLoading={isLoading}
        onOpenComplianceModal={() => setIsComplianceModalOpen(true)}
      />
    </>
  );
};

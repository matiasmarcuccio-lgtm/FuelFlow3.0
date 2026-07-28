import React, { useState, useEffect, useCallback } from 'react';
import { supabase } from './lib/supabase';
import { CabinTerminalWrapper } from './pages/CabinTerminalWrapper';
import { FleetAssetRoster } from './features/fleet/FleetAssetRoster';
import { RegulatoryAuditDashboard } from './features/command-center/RegulatoryAuditDashboard';
import { CommandCenterLogin } from './features/command-center/CommandCenterLogin';
import { BillingPortal } from './features/billing/BillingPortal';
import { OnboardingGate } from './features/onboarding/OnboardingGate';

// Tipos de Propósito de Hardware y Perfil
type DevicePurpose = 'UNSET' | 'CABIN_KIOSK' | 'COMMAND_CENTER';
type CommandTab = 'ROSTER' | 'AUDIT_LEDGER' | 'SYSTEM_CONFIG';

interface UserProfile {
  id: string;
  full_name: string;
  role: 'super_admin' | 'fleet_manager' | 'fitter' | 'dispatcher' | 'driver' | 'account_owner' | 'pending_onboarding';
  fleet_id: string;
  email?: string;
}

const DEVICE_PURPOSE_KEY = 'jitsite_device_purpose_latch';

export const App: React.FC = () => {
  const [devicePurpose, setDevicePurpose] = useState<DevicePurpose>('UNSET');
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [authError, setAuthError] = useState<string | null>(null);
  
  // Estado de navegación para el Command Center
  const [activeCommandTab, setActiveCommandTab] = useState<CommandTab>('ROSTER');

  // 1. AUDITORÍA DE IDENTIDAD Y CERROJO DE HARDWARE
  const evaluateMasterState = useCallback(async () => {
    setIsLoading(true);
    setAuthError(null);

    try {
      // Paso A: Consultar el Cerrojo de Propósito de Hardware en memoria inmutable
      const latchedPurpose = localStorage.getItem(DEVICE_PURPOSE_KEY) as DevicePurpose;
      if (latchedPurpose === 'CABIN_KIOSK') {
        // El hardware está sellado para cabina de camión. Omitimos carga de gerencia.
        setDevicePurpose('CABIN_KIOSK');
        setIsLoading(false);
        return;
      }

      if (latchedPurpose === 'COMMAND_CENTER') {
        setDevicePurpose('COMMAND_CENTER');
      }

      // Paso B: Consultar sesión criptográfica de Supabase
      const { data: { session }, error: sessionError } = await supabase.auth.getSession();
      if (sessionError) throw new Error(sessionError.message);

      if (!session || !session.user) {
        setProfile(null);
        setAuthError('AUTH_REQUIRED');
        setIsLoading(false);
        return;
      }

      // Paso C: Verificar jurisdicción y rol en la Capa 0
      const { data: userProfile, error: profileError } = await supabase
        .from('profiles')
        .select('id, full_name, role, fleet_id')
        .eq('id', session.user.id)
        .single();

      if (profileError || !userProfile) {
        console.error("🛑 FRACTURA EN EL ENRUTADOR:", profileError?.message);
        setAuthError('AUTH_REQUIRED');
        setIsLoading(false);
        return;
      }

      // Si un conductor de campo (driver) intenta entrar al Command Center, lo expulsamos a Cabina
      if (userProfile.role === 'driver' && devicePurpose !== 'CABIN_KIOSK') {
        console.warn('⚠️ Intento de acceso administrativo por un operario de campo. Redirigiendo a Kiosco.');
        localStorage.setItem(DEVICE_PURPOSE_KEY, 'CABIN_KIOSK');
        setDevicePurpose('CABIN_KIOSK');
        setIsLoading(false);
        return;
      }

      setProfile({
        ...userProfile,
        email: session.user.email
      } as UserProfile);
      setIsLoading(false);

    } catch (err: any) {
      console.error('🛑 FRACTURA EN EL ENRUTADOR MAESTRO:', err);
      setAuthError(err.message || 'Error fatal de alineación criptográfica.');
      setIsLoading(false);
    }
  }, [devicePurpose]);

  useEffect(() => {
    evaluateMasterState();

    // Escuchar cambios de sesión GoTrue en vivo (guillotina de revocación instantánea)
    const { data: { subscription } } = supabase.auth.onAuthStateChange(() => {
      evaluateMasterState();
    });

    return () => subscription.unsubscribe();
  }, [evaluateMasterState]);

  // SELLO DE PROPÓSITO DEL DISPOSITIVO (SETUP INICIAL)
  const latchDevicePurpose = (purpose: 'CABIN_KIOSK' | 'COMMAND_CENTER') => {
    localStorage.setItem(DEVICE_PURPOSE_KEY, purpose);
    setDevicePurpose(purpose);
  };

  // PURGA LEGAL DEL DISPOSITIVO (SOLO ADMINISTRADORES)
  const executeDevicePurge = () => {
    if (window.confirm('🚨 ¿CONFIRMA LA PURGA DEL CERROJO DE HARDWARE? El dispositivo olvidará su asignación operativa.')) {
      localStorage.removeItem(DEVICE_PURPOSE_KEY);
      localStorage.removeItem('jitsite_device_vault_uid');
      localStorage.removeItem('jitsite_device_asset_id');
      window.location.reload();
    }
  };

  // 2. ESCLUSAS DE CARGA Y ERROR
  if (isLoading) {
    return (
      <div className="min-h-screen bg-black flex flex-col items-center justify-center p-6 select-none font-mono text-white">
        <div className="w-16 h-16 border-4 border-emerald-500 border-t-transparent rounded-full animate-spin mb-6"></div>
        <p className="text-xs font-black tracking-widest uppercase text-slate-400">
          ALINEANDO ADUANAS DE JURISDICCIÓN • CAPA 0...
        </p>
        <p className="text-[10px] text-slate-600 mt-2 uppercase">Hobart Quarry • Zero-Trust Router</p>
      </div>
    );
  }

  // 3. ESCLUSA DE CONFIGURACIÓN INICIAL (DISPOSITIVO VIRGEN / SIN SELLAR)
  if (devicePurpose === 'UNSET') {
    return (
      <div className="min-h-screen bg-slate-950 text-white flex flex-col items-center justify-center p-6 font-sans select-none">
        <div className="max-w-xl w-full bg-slate-900 border-2 border-slate-800 rounded-3xl p-8 shadow-2xl text-center">
          <span className="bg-blue-600 text-black font-mono font-black text-[10px] px-3 py-1 uppercase rounded tracking-widest">
            INICIALIZACIÓN DE HARDWARE • WHS TASMANIA
          </span>
          <h1 className="text-3xl font-black uppercase tracking-tight mt-4 mb-2">
            Seleccione Propósito Operativo
          </h1>
          <p className="text-slate-400 font-mono text-xs mb-8">
            Este dispositivo no tiene un cerrojo de propósito registrado en su memoria inmutable. Defina la función física de este hardware en la mina:
          </p>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <button
              onClick={() => latchDevicePurpose('CABIN_KIOSK')}
              className="bg-slate-950 hover:bg-emerald-950/40 border-2 border-slate-800 hover:border-emerald-500 p-6 rounded-2xl flex flex-col items-center gap-3 transition-all group"
            >
              <span className="text-5xl group-hover:scale-110 transition-transform">🚜</span>
              <span className="font-black text-lg uppercase text-white">Terminal de Cabina</span>
              <span className="text-[10px] font-mono text-slate-500 uppercase text-center">
                Montaje en camión/excavadora. Pre-Start WHS, PIN rápido, FuelFlow y telemetría en terreno.
              </span>
            </button>

            <button
              onClick={() => latchDevicePurpose('COMMAND_CENTER')}
              className="bg-slate-950 hover:bg-blue-950/40 border-2 border-slate-800 hover:border-blue-500 p-6 rounded-2xl flex flex-col items-center gap-3 transition-all group"
            >
              <span className="text-5xl group-hover:scale-110 transition-transform">🖥️</span>
              <span className="font-black text-lg uppercase text-white">Command Center</span>
              <span className="text-[10px] font-mono text-slate-500 uppercase text-center">
                Oficina / Taller Hobart. Roster de flotas, indultos de mantenimiento y reportes legales ATO.
              </span>
            </button>
          </div>
        </div>
      </div>
    );
  }

  // 4. BIFURCACIÓN DE HARDWARE 1: TERMINAL DE CABINA (ENCLAVAMIENTO ABSOLUTO)
  if (devicePurpose === 'CABIN_KIOSK') {
    return (
      <div className="relative min-h-screen bg-black">
        <CabinTerminalWrapper />
        
        {/* Escotilla de Purga Oculta para Mecánicos y Administradores en Terreno */}
        <button
          onClick={executeDevicePurge}
          className="absolute bottom-2 left-2 opacity-10 hover:opacity-100 bg-red-950 text-red-500 font-mono text-[8px] p-2 rounded border border-red-800 transition-opacity z-50"
          title="PURGA DE HARDWARE (SOLO PERSONAL TECNICO)"
        >
          🔧 PURGAR CERROJO
        </button>
      </div>
    );
  }

  // 5. BIFURCACIÓN DE HARDWARE 2: COMMAND CENTER (ENCLAVAMIENTO RBAC)
  if (!profile) {
    // Si no hay sesión en el Command Center, forzamos login satelital a través del componente real
    return <CommandCenterLogin onBackToSelector={executeDevicePurge} />;
  }

  // 🛑 BARRERA ZERO-TRUST DE ONBOARDING
  if (profile && profile.role === 'pending_onboarding') {
    return <OnboardingGate userEmail={profile.email || ''} userId={profile.id} />;
  }

  // 🛑 COMPUERTA DE AISLAMIENTO FINANCIERO (ZERO-TRUST)
  if (profile && profile.role === 'account_owner') {
    return <BillingPortal userEmail={profile.email || ''} />;
  }

  // ENCLAVAMIENTO DE ROLES: Verificar quién tiene permiso para ver qué tablero
  const canAccessRoster = ['super_admin', 'fleet_manager', 'fitter', 'dispatcher'].includes(profile.role);
  const canAccessAudit = ['super_admin', 'fleet_manager'].includes(profile.role);

  return (
    <div className="min-h-screen bg-slate-950 text-white flex flex-col font-sans select-none overflow-x-hidden">
      
      {/* Barra de Mando Superior (Command Center HUD) */}
      <header className="bg-black/80 border-b border-slate-800 px-6 py-4 flex flex-col md:flex-row justify-between items-start md:items-center gap-4 sticky top-0 z-40 backdrop-blur-md">
        <div className="flex items-center gap-3">
          <span className="bg-emerald-500 text-black font-mono font-black text-xs px-3 py-1 rounded uppercase tracking-widest">
            JITSITE COMMAND CENTER
          </span>
          <span className="font-mono text-xs text-slate-400 uppercase hidden md:inline">
            JURISDICCIÓN: #{profile.fleet_id.slice(0, 8)} • HOBART AEST
          </span>
        </div>

        {/* Botonera de Navegación de Pestañas */}
        <nav className="flex items-center gap-2 w-full md:w-auto font-mono text-xs">
          {canAccessRoster && (
            <button
              onClick={() => setActiveCommandTab('ROSTER')}
              className={`flex-1 md:flex-initial px-4 py-2.5 rounded-xl font-bold uppercase tracking-wider transition-all border ${
                activeCommandTab === 'ROSTER'
                  ? 'bg-blue-600 text-white border-blue-400 shadow-lg shadow-blue-600/20'
                  : 'bg-slate-900 text-slate-400 border-slate-800 hover:text-white'
              }`}
            >
              🚜 Roster de Flota
            </button>
          )}

          {canAccessAudit && (
            <button
              onClick={() => setActiveCommandTab('AUDIT_LEDGER')}
              className={`flex-1 md:flex-initial px-4 py-2.5 rounded-xl font-bold uppercase tracking-wider transition-all border ${
                activeCommandTab === 'AUDIT_LEDGER'
                  ? 'bg-emerald-600 text-black border-emerald-400 shadow-lg shadow-emerald-600/20'
                  : 'bg-slate-900 text-slate-400 border-slate-800 hover:text-white'
              }`}
            >
              ⚖️ Auditoría ATO/WHS
            </button>
          )}
        </nav>

        {/* Perfil y Cierre de Sesión */}
        <div className="flex items-center gap-4 text-right w-full md:w-auto justify-end border-t md:border-t-0 pt-3 md:pt-0 border-slate-900 font-mono">
          <div>
            <p className="text-xs font-bold text-white uppercase">{profile.full_name}</p>
            <p className="text-[10px] text-blue-400 uppercase font-black">{profile.role}</p>
          </div>
          <button
            onClick={() => supabase.auth.signOut()}
            className="bg-slate-900 hover:bg-red-950/50 text-slate-400 hover:text-red-400 border border-slate-800 px-3 py-2 rounded-lg text-[10px] font-bold uppercase transition-colors"
          >
            SALIR
          </button>
        </div>
      </header>

      {/* Cuerpo Analítico Principal */}
      <main className="flex-1 p-6 md:p-8 max-w-7xl w-full mx-auto">
        {activeCommandTab === 'ROSTER' && canAccessRoster && (
          <FleetAssetRoster userRole={profile.role} fleetId={profile.fleet_id} />
        )}

        {activeCommandTab === 'AUDIT_LEDGER' && canAccessAudit && (
          <RegulatoryAuditDashboard />
        )}

        {!canAccessRoster && !canAccessAudit && (
          <div className="bg-red-950/30 border-2 border-red-800 p-12 rounded-3xl text-center font-mono text-red-400 uppercase">
            ⚠️ SU ROL ACTUAL ({profile.role}) CARECE DE ADUANAS DE LECTURA ASIGNADAS EN ESTE PANORAMA.
          </div>
        )}
      </main>

      {/* Pie de Página del Sistema */}
      <footer className="bg-black/90 border-t border-slate-900 px-6 py-4 text-center font-mono text-[10px] text-slate-600 uppercase flex justify-between items-center">
        <span>JITSite Zero-Trust Architecture • Capa 0 Blindada por RLS</span>
        <button
          onClick={executeDevicePurge}
          className="text-slate-700 hover:text-red-500 underline transition-colors"
        >
          [Reconfigurar Hardware]
        </button>
      </footer>
    </div>
  );
};

import React, { useState, useEffect, useCallback } from 'react';
import { supabase } from './lib/supabase';
import { CabinTerminalWrapper } from './pages/CabinTerminalWrapper';
import { FleetAssetRoster } from './features/fleet/FleetAssetRoster';
import { RegulatoryAuditDashboard } from './features/command-center/RegulatoryAuditDashboard';
import { CommandCenterLogin } from './features/command-center/CommandCenterLogin';
import { BillingPortal } from './features/billing/BillingPortal';
import { OnboardingGate } from './features/onboarding/OnboardingGate';
import { InviteRegistration } from './features/onboarding/InviteRegistration';
import { FleetDashboard } from './pages/FleetDashboard';
import { JITSiteDashboard } from './pages/JITSiteDashboard';
import { CommandCenterContainer } from './features/command-center/CommandCenterContainer';
import { HumanResourcesContainer } from './features/command-center/HumanResourcesContainer';
import { DeadLetterQueueContainer } from './features/command-center/DeadLetterQueueContainer';
import { FitterDashboard } from './features/fitter/FitterDashboard';
import { Map, Truck, HardHat, FileText, Users, Activity, Target, AlertTriangle } from 'lucide-react';

// Tipos de Propósito de Hardware y Perfil
type DevicePurpose = 'UNSET' | 'CABIN_KIOSK' | 'COMMAND_CENTER';
type CommandTab = 'TELEMETRY_MAP' | 'RESOURCE_MATRIX' | 'TACTICAL_DISPATCH' | 'ROSTER' | 'AUDIT_LEDGER' | 'HUMAN_RESOURCES' | 'BILLING' | 'SYSTEM_CONFIG' | 'DEAD_LETTER_QUEUE';

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
  
  // Prevent unused variable warning
  console.debug('Auth status:', authError ? 'Error' : 'OK');
  
  // Intercepting /invite URL for Employee Onboarding
  const urlParams = new URLSearchParams(window.location.search);
  const inviteToken = urlParams.get('token');
  const isInviteRoute = window.location.pathname === '/invite' && inviteToken;

  // Estado de navegación para el Command Center
  const [activeCommandTab, setActiveCommandTab] = useState<CommandTab>('TELEMETRY_MAP');

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

    } catch (err: unknown) {
      console.error('🛑 FRACTURA EN EL ENRUTADOR MAESTRO:', err);
      const e = err as Error;
      setAuthError(e.message || 'Error fatal de alineación criptográfica.');
      setIsLoading(false);
    }
  }, [devicePurpose]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
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

  // 3. RUTAS ZERO-TRUST SIN AUTENTICACIÓN
  if (isInviteRoute) {
    return <InviteRegistration inviteToken={inviteToken} />;
  }

  // 4. ESCLUSA DE CONFIGURACIÓN INICIAL (DISPOSITIVO VIRGEN / SIN SELLAR)
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

  // 🛑 BARRERA WHS DE TERRENO (PORTAL DEL MECÁNICO)
  if (profile && profile.role === 'fitter') {
    return <FitterDashboard onPurgeDevice={executeDevicePurge} />;
  }

  // ENCLAVAMIENTO DE ROLES: Verificar quién tiene permiso para ver qué tablero
  const canAccessTelemetry = ['super_admin', 'account_owner', 'fleet_manager', 'dispatcher'].includes(profile.role);
  const canAccessRoster = ['super_admin', 'account_owner', 'fleet_manager', 'fitter', 'dispatcher'].includes(profile.role);
  const canAccessAudit = ['super_admin', 'account_owner', 'fleet_manager'].includes(profile.role);
  const canAccessBilling = ['super_admin', 'account_owner'].includes(profile.role);
  const canAccessDLQ = ['super_admin', 'account_owner'].includes(profile.role);

  return (
    <div className="min-h-screen bg-background text-foreground flex flex-col font-sans select-none overflow-hidden h-screen">
      
      {/* Barra de Mando Superior (Command Center HUD) */}
      <header className="bg-card border-b border-border px-6 py-4 flex flex-col md:flex-row justify-between items-start md:items-center gap-4 z-40">
        <div className="flex items-center gap-3">
          <span className="font-mono font-bold text-lg tracking-tight uppercase text-foreground">
            JITSITE COMMAND CENTER
          </span>
          <span className="font-mono text-[10px] text-muted-foreground uppercase hidden md:inline border border-border px-2 py-0.5 ml-2">
            #{profile.fleet_id ? profile.fleet_id.slice(0, 8) : 'GLOBAL'} • HOBART AEST
          </span>
        </div>

        {/* Botonera de Navegación de Pestañas */}
        <nav className="flex items-center gap-1 w-full md:w-auto font-mono text-xs overflow-x-auto pb-2 md:pb-0">
          {canAccessTelemetry && (
            <>
              <button
                onClick={() => setActiveCommandTab('TELEMETRY_MAP')}
                className={`group flex-1 md:flex-initial px-3 py-2 font-bold uppercase tracking-widest transition-colors border flex items-center justify-center gap-2 ${
                  activeCommandTab === 'TELEMETRY_MAP'
                    ? 'bg-primary/10 text-primary border-primary'
                    : 'bg-transparent text-muted-foreground border-transparent hover:text-foreground hover:border-border'
                }`}
              >
                <Map className="w-4 h-4 shrink-0" />
                <span className="md:max-w-0 md:opacity-0 md:group-hover:max-w-xs md:group-hover:opacity-100 transition-all duration-300 ease-in-out whitespace-nowrap overflow-hidden">Telemetría</span>
              </button>

              <button
                onClick={() => setActiveCommandTab('RESOURCE_MATRIX')}
                className={`group flex-1 md:flex-initial px-3 py-2 font-bold uppercase tracking-widest transition-colors border flex items-center justify-center gap-2 ${
                  activeCommandTab === 'RESOURCE_MATRIX'
                    ? 'bg-primary/10 text-primary border-primary'
                    : 'bg-transparent text-muted-foreground border-transparent hover:text-foreground hover:border-border'
                }`}
              >
                <Truck className="w-4 h-4 shrink-0" />
                <span className="md:max-w-0 md:opacity-0 md:group-hover:max-w-xs md:group-hover:opacity-100 transition-all duration-300 ease-in-out whitespace-nowrap overflow-hidden">Recursos</span>
              </button>

              <button
                onClick={() => setActiveCommandTab('TACTICAL_DISPATCH')}
                className={`group flex-1 md:flex-initial px-3 py-2 font-bold uppercase tracking-widest transition-colors border flex items-center justify-center gap-2 ${
                  activeCommandTab === 'TACTICAL_DISPATCH'
                    ? 'bg-primary/10 text-primary border-primary'
                    : 'bg-transparent text-muted-foreground border-transparent hover:text-foreground hover:border-border'
                }`}
              >
                <Target className="w-4 h-4 shrink-0" />
                <span className="md:max-w-0 md:opacity-0 md:group-hover:max-w-xs md:group-hover:opacity-100 transition-all duration-300 ease-in-out whitespace-nowrap overflow-hidden">Despacho</span>
              </button>
            </>
          )}

          {canAccessRoster && (
            <button
              onClick={() => setActiveCommandTab('ROSTER')}
              className={`group flex-1 md:flex-initial px-3 py-2 font-bold uppercase tracking-widest transition-colors border flex items-center justify-center gap-2 ${
                activeCommandTab === 'ROSTER'
                  ? 'bg-primary/10 text-primary border-primary'
                  : 'bg-transparent text-muted-foreground border-transparent hover:text-foreground hover:border-border'
              }`}
            >
              <HardHat className="w-4 h-4 shrink-0" />
              <span className="md:max-w-0 md:opacity-0 md:group-hover:max-w-xs md:group-hover:opacity-100 transition-all duration-300 ease-in-out whitespace-nowrap overflow-hidden">Roster</span>
            </button>
          )}

          {canAccessAudit && (
            <button
              onClick={() => setActiveCommandTab('AUDIT_LEDGER')}
              className={`group flex-1 md:flex-initial px-3 py-2 font-bold uppercase tracking-widest transition-colors border flex items-center justify-center gap-2 ${
                activeCommandTab === 'AUDIT_LEDGER'
                  ? 'bg-primary/10 text-primary border-primary'
                  : 'bg-transparent text-muted-foreground border-transparent hover:text-foreground hover:border-border'
              }`}
            >
              <FileText className="w-4 h-4 shrink-0" />
              <span className="md:max-w-0 md:opacity-0 md:group-hover:max-w-xs md:group-hover:opacity-100 transition-all duration-300 ease-in-out whitespace-nowrap overflow-hidden">Auditoría</span>
            </button>
          )}

          {canAccessAudit && (
            <button
              onClick={() => setActiveCommandTab('HUMAN_RESOURCES')}
              className={`group flex-1 md:flex-initial px-3 py-2 font-bold uppercase tracking-widest transition-colors border flex items-center justify-center gap-2 ${
                activeCommandTab === 'HUMAN_RESOURCES'
                  ? 'bg-primary/10 text-primary border-primary'
                  : 'bg-transparent text-muted-foreground border-transparent hover:text-foreground hover:border-border'
              }`}
            >
              <Users className="w-4 h-4 shrink-0" />
              <span className="md:max-w-0 md:opacity-0 md:group-hover:max-w-xs md:group-hover:opacity-100 transition-all duration-300 ease-in-out whitespace-nowrap overflow-hidden">Tripulación</span>
            </button>
          )}

          {canAccessBilling && (
            <button
              onClick={() => setActiveCommandTab('BILLING')}
              className={`group flex-1 md:flex-initial px-3 py-2 font-bold uppercase tracking-widest transition-colors border flex items-center justify-center gap-2 ${
                activeCommandTab === 'BILLING'
                  ? 'bg-primary/10 text-primary border-primary'
                  : 'bg-transparent text-muted-foreground border-transparent hover:text-foreground hover:border-border'
              }`}
            >
              <Activity className="w-4 h-4 shrink-0" />
              <span className="md:max-w-0 md:opacity-0 md:group-hover:max-w-xs md:group-hover:opacity-100 transition-all duration-300 ease-in-out whitespace-nowrap overflow-hidden">Facturación</span>
            </button>
          )}

          {canAccessDLQ && (
            <button
              onClick={() => setActiveCommandTab('DEAD_LETTER_QUEUE')}
              className={`group flex-1 md:flex-initial px-3 py-2 font-bold uppercase tracking-widest transition-colors border flex items-center justify-center gap-2 ${
                activeCommandTab === 'DEAD_LETTER_QUEUE'
                  ? 'bg-red-950/50 text-red-500 border-red-500'
                  : 'bg-transparent text-muted-foreground border-transparent hover:text-red-400 hover:border-red-900'
              }`}
            >
              <AlertTriangle className="w-4 h-4 shrink-0" />
              <span className="md:max-w-0 md:opacity-0 md:group-hover:max-w-xs md:group-hover:opacity-100 transition-all duration-300 ease-in-out whitespace-nowrap overflow-hidden">Dead Letter</span>
            </button>
          )}
        </nav>

        {/* Perfil y Cierre de Sesión */}
        <div className="flex items-center gap-4 text-right w-full md:w-auto justify-end pt-3 md:pt-0 font-mono">
          <div>
            <p className="text-xs font-bold text-foreground uppercase">{profile.full_name}</p>
            <p className="text-[10px] text-primary uppercase font-black">{profile.role}</p>
          </div>
          <button
            onClick={() => supabase.auth.signOut()}
            className="bg-secondary hover:bg-destructive/10 text-muted-foreground hover:text-destructive border border-border hover:border-destructive px-3 py-2 text-[10px] font-bold uppercase transition-colors"
          >
            SALIR
          </button>
        </div>
      </header>

      {/* Cuerpo Analítico Principal */}
      <main className="flex-1 overflow-y-auto flex flex-col min-h-0 bg-background">
        {activeCommandTab === 'TELEMETRY_MAP' && canAccessTelemetry && (
          <JITSiteDashboard />
        )}

        {activeCommandTab === 'RESOURCE_MATRIX' && canAccessTelemetry && (
          <FleetDashboard />
        )}

        {activeCommandTab === 'TACTICAL_DISPATCH' && canAccessTelemetry && (
          <CommandCenterContainer fleetId={profile.fleet_id} />
        )}

        {activeCommandTab !== 'TELEMETRY_MAP' && activeCommandTab !== 'RESOURCE_MATRIX' && activeCommandTab !== 'TACTICAL_DISPATCH' && (
          <div className="p-6 md:p-8 max-w-7xl w-full mx-auto flex-1 flex flex-col min-h-0">
            {activeCommandTab === 'ROSTER' && canAccessRoster && (
              <FleetAssetRoster userRole={profile.role} fleetId={profile.fleet_id} />
            )}

            {activeCommandTab === 'AUDIT_LEDGER' && canAccessAudit && (
              <RegulatoryAuditDashboard />
            )}

            {activeCommandTab === 'HUMAN_RESOURCES' && canAccessAudit && (
              <HumanResourcesContainer fleetId={profile.fleet_id} />
            )}

            {activeCommandTab === 'BILLING' && canAccessBilling && (
              <BillingPortal userEmail={profile.email || ''} />
            )}

            {activeCommandTab === 'DEAD_LETTER_QUEUE' && canAccessDLQ && (
              <DeadLetterQueueContainer />
            )}

            {!canAccessTelemetry && !canAccessRoster && !canAccessAudit && !canAccessBilling && !canAccessDLQ && (
              <div className="bg-red-950/30 border-2 border-red-800 p-12 rounded-3xl text-center font-mono text-red-400 uppercase">
                ⚠️ SU ROL ACTUAL ({profile.role}) CARECE DE ADUANAS DE LECTURA ASIGNADAS EN ESTE PANORAMA.
              </div>
            )}
          </div>
        )}
      </main>

      {/* Pie de Página del Sistema */}
      <footer className="bg-card border-t border-border px-6 py-2 text-center font-mono text-[10px] text-muted-foreground uppercase flex justify-between items-center z-40">
        <span>JITSite Zero-Trust Architecture • Capa 0 Blindada por RLS</span>
        <button
          onClick={executeDevicePurge}
          className="hover:text-foreground transition-colors"
        >
          [Reconfigurar Hardware]
        </button>
      </footer>
    </div>
  );
};

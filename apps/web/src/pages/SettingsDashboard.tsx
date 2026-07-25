import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { useCurrentProfile } from '../hooks/useCurrentProfile';
import { Settings, LogOut, Shield, Key, CreditCard, ExternalLink } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { MFASetupModal } from '../components/auth/MFASetupModal';
import { useAuth } from '../context/AuthContext';

export const SettingsDashboard = () => {
  const { data: profile } = useCurrentProfile();
  const { userRole, fleetStatus } = useAuth();
  const navigate = useNavigate();
  const [aalLevel, setAalLevel] = useState<string>('aal1');
  const [nextLevel, setNextLevel] = useState<string>('aal1');
  const [showMfaModal, setShowMfaModal] = useState(false);

  useEffect(() => {
    checkMfaStatus();
  }, []);

  const checkMfaStatus = async () => {
    // Force a token refresh to ensure AAL claims are up to date
    await supabase.auth.refreshSession();
    
    const { data } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    if (data) {
      setAalLevel((data.currentLevel as string) || 'aal1');
      setNextLevel((data.nextLevel as string) || 'aal1');
    }
  };

  const handleLogout = async () => {
    await supabase.auth.signOut();
    navigate('/login');
  };

  return (
    <div className="flex-1 p-8 bg-background text-foreground h-full overflow-y-auto">
      <div className="flex items-center gap-3 border-b border-border pb-6 mb-8">
        <Settings className="w-8 h-8 text-primary" />
        <div>
          <h1 className="text-2xl font-bold text-foreground tracking-tight">System settings</h1>
          <p className="text-sm text-muted-foreground">Manage your account and preferences.</p>
        </div>
      </div>

      <div className="w-full lg:grid lg:grid-cols-2 lg:gap-6 space-y-6 lg:space-y-0">
        <div className="bg-card shadow-lg p-6 rounded-xl border border-border">
          <h2 className="text-lg font-bold flex items-center gap-2 mb-6 text-foreground tracking-tight uppercase">
            <Shield className="w-5 h-5 text-emerald-500" /> Account Security
          </h2>
          <div className="space-y-6">
            
            {/* MFA Status Panel */}
            <div className={`p-4 rounded-lg border ${aalLevel === 'aal2' ? 'bg-emerald-500/10 border-emerald-500/20 text-emerald-600' : 'bg-amber-500/10 border-amber-500/20 text-amber-600'}`}>
              <div className="flex items-start justify-between">
                <div>
                  <h3 className="font-bold uppercase tracking-wider text-sm mb-1">Authenticator Assurance Level</h3>
                  <p className="text-sm opacity-80">
                    {aalLevel === 'aal2' 
                      ? 'Your privileges are protected by Hardware TOTP (AAL2).'
                      : 'AAL1 level detected. You are vulnerable to session hijacking and role delegation is denied.'}
                  </p>
                </div>
                {aalLevel !== 'aal2' && (
                  <button 
                    onClick={() => setShowMfaModal(true)}
                    className={`flex-shrink-0 flex items-center gap-2 text-white font-bold py-2 px-4 rounded-md transition-colors border uppercase tracking-widest text-xs ${
                      nextLevel === 'aal2' 
                        ? 'bg-blue-500 hover:bg-blue-600 border-blue-600/50' 
                        : 'bg-amber-500 hover:bg-amber-600 border-amber-600/50'
                    }`}
                  >
                    <Key className="w-4 h-4" /> {nextLevel === 'aal2' ? 'Verify Session' : 'Activate MFA'}
                  </button>
                )}
              </div>
            </div>

            <div>
              <label className="block text-xs font-bold text-muted-foreground uppercase tracking-widest mb-2">Email</label>
              <input 
                type="text" 
                disabled 
                className="w-full bg-muted/50 border border-border rounded-md p-3 text-muted-foreground font-mono text-sm cursor-not-allowed"
                value="[Secured by Supabase Auth]" 
              />
            </div>
            <div>
              <label className="block text-xs font-bold text-muted-foreground uppercase tracking-widest mb-2">Role</label>
              <input 
                type="text" 
                disabled 
                className="w-full bg-muted/50 border border-border rounded-md p-3 text-muted-foreground font-mono text-sm cursor-not-allowed uppercase"
                value={profile?.role || 'Loading...'} 
              />
            </div>
          </div>
        </div>

        {/* Billing & Subscriptions (Tenant Admins Only) */}
        {(userRole === 'fleet_manager' || userRole === 'super_admin') && (
          <div className="bg-card shadow-lg p-6 rounded-xl border border-border lg:col-span-2">
            <h2 className="text-lg font-bold flex items-center gap-2 mb-6 text-foreground tracking-tight uppercase">
              <CreditCard className="w-5 h-5 text-primary" /> Billing & Subscriptions
            </h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6 items-center">
              <div>
                <h3 className="font-bold uppercase tracking-widest text-sm mb-1">Commercial License Status</h3>
                <div className="flex items-center gap-2 mt-2">
                  <span className={`px-3 py-1 text-xs font-bold uppercase tracking-widest rounded-full border ${
                    fleetStatus === 'active' || fleetStatus === 'trialing' ? 'bg-green-500/10 text-green-500 border-green-500/20' : 'bg-destructive/10 text-destructive border-destructive/20'
                  }`}>
                    {fleetStatus || 'Unknown'}
                  </span>
                </div>
                <p className="text-sm text-muted-foreground mt-3 leading-relaxed">
                  You are the designated Tenant Admin for your fleet. Keep your billing active to ensure all your drivers and supervisors have uninterrupted access to the FuelFlow system.
                </p>
              </div>
              <div className="flex flex-col gap-3 md:items-end justify-center">
                <button 
                  onClick={() => alert("Stripe Portal Integration coming soon")}
                  className="bg-primary hover:bg-primary/90 text-primary-foreground font-bold py-3 px-6 rounded-md transition-colors flex items-center justify-center gap-2 w-full md:w-auto uppercase tracking-widest text-sm"
                >
                  Manage Billing in Stripe <ExternalLink className="w-4 h-4" />
                </button>
              </div>
            </div>
          </div>
        )}

        <div className="bg-card shadow-lg p-6 rounded-xl border border-border lg:col-span-2">
          <h2 className="text-lg font-bold mb-4 text-destructive flex items-center gap-2 uppercase tracking-tight">
             Danger Zone
          </h2>
          <p className="text-sm text-muted-foreground mb-6 leading-relaxed">
            Logging out will terminate your current active session on this device. Any un-synchronized telemetry data might be lost if offline mode is active.
          </p>
          <button 
            onClick={handleLogout}
            className="bg-destructive/10 hover:bg-destructive text-destructive hover:text-destructive-foreground font-bold py-3 px-6 rounded-md transition-colors border border-destructive/20 flex items-center justify-center gap-2 w-full uppercase tracking-widest text-sm"
          >
            <LogOut className="w-4 h-4" /> Terminate Session
          </button>
        </div>
      </div>

      <MFASetupModal 
        isOpen={showMfaModal} 
        onClose={() => setShowMfaModal(false)}
        onSuccess={() => {
          setShowMfaModal(false);
          checkMfaStatus();
        }}
      />
    </div>
  );
};


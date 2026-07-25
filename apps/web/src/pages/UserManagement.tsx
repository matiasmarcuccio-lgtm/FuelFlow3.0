import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useCurrentProfile } from '../hooks/useCurrentProfile';
import { useFleetCommand } from '../hooks/useFleetCommand';
import { Users, UserPlus, ShieldAlert, CheckCircle, Clock, Shield, Key, AlertTriangle } from 'lucide-react';

type DashboardState = 'IDLE' | 'CHALLENGING_MFA' | 'SUBMITTING' | 'SUCCESS' | 'ERROR';

interface PendingAction {
  targetId: string;
  targetName: string;
  actionType: 'ELEVATE' | 'REVOKE';
  newRole: string;
}

export const UserManagement = () => {
  const { data: currentProfile, isLoading: isProfileLoading } = useCurrentProfile();
  const fleetCommand = useFleetCommand();
  
  const [team, setTeam] = useState<any[]>([]);
  const [inviteToken, setInviteToken] = useState<string | null>(null);
  
  // State Machine
  const [dashboardState, setDashboardState] = useState<DashboardState>('IDLE');
  const [pendingAction, setPendingAction] = useState<PendingAction | null>(null);
  const [mfaCode, setMfaCode] = useState('');
  const [errorMsg, setErrorMsg] = useState('');
  const [successMsg, setSuccessMsg] = useState('');

  useEffect(() => {
    if (currentProfile) {
      fetchTeam();
    }
  }, [currentProfile]);

  async function fetchTeam() {
    if (!currentProfile) return;
    
    // Super Admins see everyone. Fleet Managers see only their fleet.
    let query = supabase.from('profiles').select('*').order('role', { ascending: true });
    
    if (currentProfile.role !== 'super_admin') {
      if (currentProfile.fleet_id) {
         query = query.eq('fleet_id', currentProfile.fleet_id);
      } else {
         return; // Can't fetch if no fleet assigned
      }
    }
      
    const { data } = await query;
    if (data) setTeam(data);
  }

  const handleGenerateInvite = async () => {
    // 1. Verify local sovereignty before touching the network
    const { data: { session }, error: sessionError } = await supabase.auth.getSession();
    
    if (!session || sessionError) {
      alert("ERR_SESSION_STRIPPED: No active Bearer token. Please log out and log in again to renew your AAL2.");
      return;
    }

    if (!currentProfile?.fleet_id) {
      alert("ERR_MISSING_JURISDICTION: No valid fleet ID detected in component memory.");
      return;
    }

    // 2. Fire with explicit parameters
    const { data, error } = await supabase.rpc('fn_generate_fleet_invite', {
      p_fleet_id: currentProfile.fleet_id
    });

    if (error) {
      console.error("Transactional failure generating invite:", error.message);
      return;
    }

    if (data) {
      setInviteToken(data as string);
    }
  };

  const initiateAction = (targetId: string, targetName: string, actionType: 'ELEVATE' | 'REVOKE', newRole: string) => {
    setPendingAction({ targetId, targetName, actionType, newRole });
    setMfaCode('');
    setErrorMsg('');
    setDashboardState('CHALLENGING_MFA');
  };

  const executeAuthorizedAction = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pendingAction) return;

    setDashboardState('SUBMITTING');
    setErrorMsg('');

    try {
      // 1. AAL2 Verification Challenge
      const factors = await supabase.auth.mfa.listFactors();
      if (factors.error) throw factors.error;

      const totpFactor = factors.data.totp[0];
      if (!totpFactor) {
        throw new Error('No TOTP factor enrolled. Cannot authorize action.');
      }

      const challenge = await supabase.auth.mfa.challenge({ factorId: totpFactor.id });
      if (challenge.error) throw challenge.error;

      const verify = await supabase.auth.mfa.verify({
        factorId: totpFactor.id,
        challengeId: challenge.data.id,
        code: mfaCode
      });

      if (verify.error) throw verify.error;

      // 2. Ejecutar RPC transaccional
      const justification = `Authorized by ${currentProfile?.full_name} via MFA at ${new Date().toISOString()}`;
      let rpcResult;
      
      if (pendingAction.actionType === 'ELEVATE') {
        rpcResult = await supabase.rpc('fn_elevate_user_role', {
          p_target_id: pendingAction.targetId,
          p_new_role: pendingAction.newRole,
          p_justification: justification
        });
      } else {
        rpcResult = await supabase.rpc('fn_revoke_user_role', {
          p_target_id: pendingAction.targetId,
          p_new_role: pendingAction.newRole,
          p_justification: justification
        });
      }

      if (rpcResult.error) throw rpcResult.error;

      // 3. Absolute Truth Validation
      setDashboardState('SUCCESS');
      setSuccessMsg(pendingAction.actionType === 'ELEVATE' ? 'Ascenso Confirmado y Auditado.' : 'Rol Revocado y Sesión Destruida.');
      
      await fetchTeam(); // Strict refetch
      
      setTimeout(() => {
        setDashboardState('IDLE');
        setPendingAction(null);
      }, 3000);

    } catch (err: any) {
      setErrorMsg(err.message || 'Error durante la verificación MFA o ejecución RPC.');
      setDashboardState('ERROR');
    }
  };

  const cancelAction = () => {
    setDashboardState('IDLE');
    setPendingAction(null);
    setMfaCode('');
    setErrorMsg('');
  };

  if (isProfileLoading) return <div className="p-8 text-muted-foreground">Loading Headquarters...</div>;

  const isSuperAdmin = currentProfile?.role === 'super_admin';
  const canManage = isSuperAdmin || currentProfile?.role === 'fleet_manager';

  return (
    <div className="flex-1 p-8 bg-background text-foreground h-full relative overflow-y-auto">
      
      {/* ----------------- MODAL DE BLOQUEO MFA ----------------- */}
      {(dashboardState !== 'IDLE') && (
        <div className="absolute inset-0 z-50 flex items-center justify-center bg-black/90 backdrop-blur-md p-4">
          <div className="bg-card w-full max-w-md border border-border rounded-xl shadow-2xl relative overflow-hidden flex flex-col">
            
            <div className={`p-4 flex items-center justify-between border-b ${dashboardState === 'ERROR' ? 'bg-destructive/20 border-destructive' : dashboardState === 'SUCCESS' ? 'bg-emerald-500/20 border-emerald-500' : 'bg-primary/20 border-border'}`}>
              <div className="flex items-center gap-2">
                <Shield className="w-5 h-5" />
                <h2 className="font-bold uppercase tracking-widest text-sm">Validación de Autoridad Zero-Trust</h2>
              </div>
            </div>

            <div className="p-6">
              {dashboardState === 'CHALLENGING_MFA' && (
                <form onSubmit={executeAuthorizedAction} className="flex flex-col gap-4">
                  <div className="text-center mb-4">
                    <p className="text-sm text-muted-foreground mb-2">Confirma tu identidad para ejecutar la siguiente orden táctica sobre <strong>{pendingAction?.targetName}</strong>:</p>
                    <p className="text-lg font-bold text-foreground bg-muted p-2 rounded border border-border">
                      {pendingAction?.actionType === 'ELEVATE' ? 'ASCENSO A ' : 'DEGRADACIÓN A '} 
                      <span className={pendingAction?.actionType === 'ELEVATE' ? 'text-primary' : 'text-destructive'}>
                        {pendingAction?.newRole.toUpperCase()}
                      </span>
                    </p>
                  </div>
                  <div>
                    <label className="text-xs font-bold uppercase tracking-widest text-muted-foreground block mb-2 text-center">TOTP AAL2 Token</label>
                    <input
                      type="text"
                      required
                      autoFocus
                      maxLength={6}
                      value={mfaCode}
                      onChange={(e) => setMfaCode(e.target.value.replace(/\D/g, ''))}
                      placeholder="000000"
                      className="w-full px-4 py-3 bg-background border border-input rounded-md focus:outline-none focus:ring-1 focus:ring-primary text-center text-2xl tracking-[0.5em] font-mono"
                    />
                  </div>
                  <div className="flex gap-2 mt-4">
                    <button type="button" onClick={cancelAction} className="flex-1 bg-muted text-foreground py-3 rounded-md font-bold uppercase tracking-wider text-sm hover:bg-muted/80">Abortar</button>
                    <button type="submit" disabled={mfaCode.length !== 6} className="flex-1 bg-primary text-primary-foreground py-3 rounded-md font-bold uppercase tracking-wider text-sm hover:bg-primary/90 disabled:opacity-50 flex items-center justify-center gap-2">
                      <Key className="w-4 h-4" /> Firmar Orden
                    </button>
                  </div>
                </form>
              )}

              {dashboardState === 'SUBMITTING' && (
                <div className="flex flex-col items-center py-8">
                  <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary mb-4"></div>
                  <p className="text-sm font-mono text-muted-foreground uppercase tracking-widest">Inyectando Comando...</p>
                </div>
              )}

              {dashboardState === 'SUCCESS' && (
                <div className="flex flex-col items-center py-8 text-emerald-500">
                  <CheckCircle className="w-12 h-12 mb-4" />
                  <p className="text-lg font-bold uppercase tracking-wider">{successMsg}</p>
                </div>
              )}

              {dashboardState === 'ERROR' && (
                <div className="flex flex-col items-center py-6 text-destructive">
                  <AlertTriangle className="w-10 h-10 mb-4" />
                  <p className="text-sm font-bold uppercase tracking-wider mb-2">Error de Ejecución</p>
                  <p className="text-xs text-center bg-destructive/10 p-3 rounded">{errorMsg}</p>
                  <button onClick={cancelAction} className="mt-6 bg-destructive text-destructive-foreground px-6 py-2 rounded uppercase font-bold text-xs tracking-wider">Cerrar</button>
                </div>
              )}
            </div>

          </div>
        </div>
      )}
      {/* ----------------- FIN MODAL ----------------- */}

      <div className="flex justify-between items-center mb-8 border-b border-border pb-4">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2 text-foreground tracking-tight uppercase">
            <Users className="text-primary" />
            Command & Control Roster
          </h1>
          <p className="text-sm text-muted-foreground mt-1">Gestión de identidad, delegación de autoridad táctica y auditoría forense.</p>
        </div>

        {canManage && (
          <button 
            onClick={handleGenerateInvite}
            disabled={fleetCommand.isLoading}
            className="bg-primary text-primary-foreground hover:bg-primary/90 disabled:opacity-50 font-bold py-2 px-4 rounded flex items-center gap-2 transition-colors uppercase tracking-widest text-xs"
          >
            <UserPlus className="w-4 h-4" />
            {fleetCommand.isLoading ? 'Generating...' : 'Generate Fleet Token'}
          </button>
        )}
      </div>

      {inviteToken && (
        <div className="mb-8 p-6 bg-primary/10 border border-primary/30 rounded-lg text-center relative overflow-hidden">
          <div className="absolute top-0 left-0 w-full h-1 bg-primary animate-pulse"></div>
          <h3 className="text-primary font-bold uppercase tracking-widest text-sm mb-2">Secure Enrollment Token Generated</h3>
          <p className="text-4xl font-mono text-foreground font-bold tracking-[0.25em] my-4">{inviteToken}</p>
          <div className="flex justify-center items-center gap-2 text-muted-foreground text-xs uppercase tracking-wider">
            <Clock className="w-4 h-4" />
            Expires in exactly 24 hours.
          </div>
        </div>
      )}

      <div className="bg-card shadow-lg rounded-xl overflow-hidden border border-border">
        
        {/* Mobile View (Cards) */}
        <div className="md:hidden flex flex-col divide-y divide-border">
          {team.map((member) => (
            <div key={member.id} className="p-4 flex flex-col gap-3">
              <div className="flex justify-between items-start">
                <div>
                  <div className="font-bold text-foreground">{member.full_name || 'Unknown Operator'}</div>
                  <div className="text-[10px] text-muted-foreground font-mono mt-0.5">ID: {member.id.substring(0, 8)}</div>
                </div>
                {member.role !== 'suspended' ? (
                  <span className="flex items-center gap-1 text-emerald-500 text-[10px] font-bold uppercase tracking-wider bg-emerald-500/10 px-2 py-1 rounded">
                    <CheckCircle className="w-3 h-3" /> ACT
                  </span>
                ) : (
                  <span className="flex items-center gap-1 text-destructive text-[10px] font-bold uppercase tracking-wider bg-destructive/10 px-2 py-1 rounded">
                    <ShieldAlert className="w-3 h-3" /> SUSP
                  </span>
                )}
              </div>
              
              <div className="flex items-center gap-2">
                <span className="text-[10px] text-muted-foreground uppercase tracking-widest font-bold">Role:</span>
                <span className={`text-[10px] font-bold px-2 py-0.5 rounded bg-background border uppercase tracking-wider ${
                  member.role === 'super_admin' ? 'border-purple-500/50 text-purple-400 bg-purple-500/10' : 
                  member.role === 'fleet_manager' ? 'border-blue-500/50 text-blue-400 bg-blue-500/10' :
                  member.role === 'supervisor' ? 'border-amber-500/50 text-amber-500 bg-amber-500/10' :
                  'border-border text-muted-foreground'
                }`}>
                  {member.role}
                </span>
              </div>

              {/* Mobile Actions */}
              <div className="mt-2 flex flex-wrap gap-2 pt-3 border-t border-border/50">
                {isSuperAdmin && member.id !== currentProfile.id && (
                  <>
                    {member.role === 'driver' && (
                      <button 
                        onClick={() => initiateAction(member.id, member.full_name, 'ELEVATE', 'supervisor')}
                        className="flex-1 text-[10px] bg-primary/10 hover:bg-primary text-primary hover:text-primary-foreground font-bold px-3 py-2 rounded transition-colors border border-primary/30 uppercase tracking-widest text-center"
                      >
                        Make Sup
                      </button>
                    )}
                    {(member.role === 'supervisor' || member.role === 'driver') && (
                      <button 
                        onClick={() => initiateAction(member.id, member.full_name, 'ELEVATE', 'fleet_manager')}
                        className="flex-1 text-[10px] bg-blue-500/10 hover:bg-blue-600 text-blue-400 hover:text-white font-bold px-3 py-2 rounded transition-colors border border-blue-500/30 uppercase tracking-widest text-center"
                      >
                        Make Mgr
                      </button>
                    )}
                    {member.role !== 'driver' && member.role !== 'suspended' && (
                      <button 
                        onClick={() => initiateAction(member.id, member.full_name, 'REVOKE', 'driver')}
                        className="flex-1 text-[10px] bg-amber-500/10 hover:bg-amber-600 text-amber-500 hover:text-white font-bold px-3 py-2 rounded transition-colors border border-amber-500/30 uppercase tracking-widest text-center"
                      >
                        Demote
                      </button>
                    )}
                    {member.role !== 'suspended' && (
                      <button 
                        onClick={() => initiateAction(member.id, member.full_name, 'REVOKE', 'suspended')}
                        className="w-full text-[10px] bg-destructive/10 hover:bg-destructive text-destructive hover:text-destructive-foreground font-bold px-3 py-2 rounded transition-colors border border-destructive/30 uppercase tracking-widest flex items-center justify-center gap-1"
                      >
                        <ShieldAlert className="w-3 h-3" /> KILL SESSION
                      </button>
                    )}
                  </>
                )}
                {!isSuperAdmin && member.role === 'driver' && (
                    <span className="text-xs text-muted-foreground italic w-full text-center">Managed by Admin</span>
                )}
              </div>
            </div>
          ))}
          {team.length === 0 && (
            <div className="p-8 text-center text-muted-foreground text-sm">
              No personnel found.
            </div>
          )}
        </div>

        {/* Desktop View (Table) */}
        <div className="hidden md:block overflow-x-auto w-full">
          <table className="w-full text-left border-collapse min-w-[800px]">
            <thead>
              <tr className="bg-muted/30 border-b border-border text-xs uppercase tracking-widest text-muted-foreground">
                <th className="p-4 font-bold">Personnel</th>
                <th className="p-4 font-bold">Role Hierarchy</th>
                <th className="p-4 font-bold">State</th>
                <th className="p-4 font-bold text-right">Structural Actions (Requires AAL2)</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {team.map((member) => (
                <tr key={member.id} className="hover:bg-muted/10 transition-colors">
                  <td className="p-4">
                    <div className="font-bold text-foreground">{member.full_name || 'Unknown Operator'}</div>
                    <div className="text-xs text-muted-foreground font-mono mt-1">ID: {member.id.substring(0, 8)}</div>
                  </td>
                  <td className="p-4">
                    <span className={`text-xs font-bold px-2 py-1 rounded bg-background border uppercase tracking-wider ${
                      member.role === 'super_admin' ? 'border-purple-500/50 text-purple-400 bg-purple-500/10' : 
                      member.role === 'fleet_manager' ? 'border-blue-500/50 text-blue-400 bg-blue-500/10' :
                      member.role === 'supervisor' ? 'border-amber-500/50 text-amber-500 bg-amber-500/10' :
                      'border-border text-muted-foreground'
                    }`}>
                      {member.role}
                    </span>
                  </td>
                  <td className="p-4">
                    {member.role !== 'suspended' ? (
                      <span className="flex items-center gap-1 text-emerald-500 text-xs font-bold uppercase tracking-wider">
                        <CheckCircle className="w-4 h-4" /> ACTIVE
                      </span>
                    ) : (
                      <span className="flex items-center gap-1 text-destructive text-xs font-bold uppercase tracking-wider">
                        <ShieldAlert className="w-4 h-4" /> SUSPENDED
                      </span>
                    )}
                  </td>
                  <td className="p-4 text-right">
                    <div className="flex items-center justify-end gap-2">
                      {isSuperAdmin && member.id !== currentProfile.id && (
                        <>
                          {/* Botones de Promoción */}
                          {member.role === 'driver' && (
                            <button 
                              onClick={() => initiateAction(member.id, member.full_name, 'ELEVATE', 'supervisor')}
                              className="text-[10px] bg-primary/10 hover:bg-primary text-primary hover:text-primary-foreground font-bold px-3 py-1.5 rounded transition-colors border border-primary/30 uppercase tracking-widest"
                            >
                              Make Supervisor
                            </button>
                          )}
                          {(member.role === 'supervisor' || member.role === 'driver') && (
                            <button 
                              onClick={() => initiateAction(member.id, member.full_name, 'ELEVATE', 'fleet_manager')}
                              className="text-[10px] bg-blue-500/10 hover:bg-blue-600 text-blue-400 hover:text-white font-bold px-3 py-1.5 rounded transition-colors border border-blue-500/30 uppercase tracking-widest"
                            >
                              Make Fleet Mgr
                            </button>
                          )}
                          
                          {/* Botones de Revocación / Kill Switch */}
                          {member.role !== 'driver' && member.role !== 'suspended' && (
                            <button 
                              onClick={() => initiateAction(member.id, member.full_name, 'REVOKE', 'driver')}
                              className="text-[10px] bg-amber-500/10 hover:bg-amber-600 text-amber-500 hover:text-white font-bold px-3 py-1.5 rounded transition-colors border border-amber-500/30 uppercase tracking-widest"
                            >
                              Demote to Driver
                            </button>
                          )}
                          {member.role !== 'suspended' && (
                            <button 
                              onClick={() => initiateAction(member.id, member.full_name, 'REVOKE', 'suspended')}
                              className="text-[10px] bg-destructive/10 hover:bg-destructive text-destructive hover:text-destructive-foreground font-bold px-3 py-1.5 rounded transition-colors border border-destructive/30 uppercase tracking-widest flex items-center gap-1"
                            >
                              <ShieldAlert className="w-3 h-3" /> SUSPEND (KILL SESSIONS)
                            </button>
                          )}
                        </>
                      )}
                      
                      {!isSuperAdmin && member.role === 'driver' && (
                         <span className="text-xs text-muted-foreground italic">Managed by Admin</span>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
              {team.length === 0 && (
                <tr>
                  <td colSpan={4} className="p-8 text-center text-muted-foreground">
                    No personnel found.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

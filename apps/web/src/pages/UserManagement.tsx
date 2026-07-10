import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useCurrentProfile } from '../hooks/useCurrentProfile';
import { useFleetCommand } from '../hooks/useFleetCommand';
import { Users, UserPlus, ShieldAlert, CheckCircle, Clock } from 'lucide-react';

export const UserManagement = () => {
  const { data: currentProfile, isLoading: isProfileLoading } = useCurrentProfile();
  const fleetCommand = useFleetCommand();
  const [team, setTeam] = useState<any[]>([]);
  const [inviteToken, setInviteToken] = useState<string | null>(null);

  useEffect(() => {
    if (currentProfile?.fleet_id) {
      fetchTeam();
    }
  }, [currentProfile]);

  async function fetchTeam() {
    if (!currentProfile) return;
    const { data } = await supabase
      .from('profiles')
      .select('*')
      .eq('fleet_id', currentProfile.fleet_id)
      .order('role', { ascending: true });
      
    if (data) setTeam(data);
  };

  const handleGenerateInvite = async () => {
    if (!currentProfile?.fleet_id) return;
    const token = await fleetCommand.generateInvite(currentProfile.fleet_id);
    if (token) {
      setInviteToken(token as string);
    }
  };

  const handleRevokeAccess = async (driverId: string) => {
    if (window.confirm('WARNING: Are you sure you want to permanently deactivate this driver? They will lose access to the system.')) {
      const success = await fleetCommand.revokeAccess(driverId);
      if (success) {
        fetchTeam();
      }
    }
  };

  if (isProfileLoading) return <div className="p-8 text-on-surface-variant">Loading Headquarters...</div>;

  const canManage = currentProfile?.role === 'SUPER_ADMIN' || currentProfile?.role === 'FLEET_MANAGER';

  return (
    <div className="flex-1 p-8 bg-background text-foreground h-full overflow-y-auto">
      <div className="flex justify-between items-center mb-8 border-b border-outline-variant pb-4">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Users className="text-primary" />
            Human Resources (HQ)
          </h1>
          <p className="text-sm text-on-surface-variant mt-1">Manage personnel, onboard new drivers, and execute permanent structural changes.</p>
        </div>

        {canManage && (
          <button 
            onClick={handleGenerateInvite}
            disabled={fleetCommand.isLoading}
            className="bg-primary text-on-primary hover:bg-primary text-on-primary disabled:bg-blue-800 text-white font-bold py-2 px-4 rounded flex items-center gap-2 transition-colors"
          >
            <UserPlus className="w-5 h-5" />
            {fleetCommand.isLoading ? 'Generating...' : 'Generate Fleet Invite'}
          </button>
        )}
      </div>

      {fleetCommand.error && (
        <div className="mb-6 bg-red-950/50 border border-red-700 p-4 rounded-lg flex items-start gap-3">
          <ShieldAlert className="text-red-500 w-6 h-6 mt-0.5" />
          <div>
            <h3 className="text-red-400 font-bold uppercase tracking-wider">{fleetCommand.error.code}</h3>
            <p className="text-red-200 mt-1">{fleetCommand.error.message}</p>
            {fleetCommand.error.actionRequired && (
              <p className="text-red-300 text-sm mt-2 font-mono bg-red-900/30 p-2 rounded">Action Required: {fleetCommand.error.actionRequired}</p>
            )}
          </div>
        </div>
      )}

      {inviteToken && (
        <div className="mb-8 p-6 bg-blue-900/20 border border-blue-500/50 rounded-lg text-center relative overflow-hidden">
          <div className="absolute top-0 left-0 w-full h-1 bg-primary text-on-primary animate-pulse"></div>
          <h3 className="text-primary font-bold uppercase tracking-widest text-sm mb-2">Secure Enrollment Token Generated</h3>
          <p className="text-4xl font-mono text-foreground font-bold tracking-[0.25em] my-4">{inviteToken}</p>
          <div className="flex justify-center items-center gap-2 text-on-surface-variant text-xs">
            <Clock className="w-4 h-4" />
            Expires in exactly 24 hours. Instruct the driver to input this code during mobile registration.
          </div>
        </div>
      )}

      <div className="bg-surface border border-outline-variant shadow-sm rounded-lg border border-outline-variant overflow-hidden">
        <table className="w-full text-left border-collapse">
          <thead>
            <tr className="bg-background/50 border-b border-outline-variant text-xs uppercase tracking-wider text-on-surface-variant">
              <th className="p-4">Personnel</th>
              <th className="p-4">Role</th>
              <th className="p-4">Status</th>
              <th className="p-4 text-right">Structural Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-700">
            {team.map((member) => (
              <tr key={member.id} className={member.status === 'INACTIVE' ? 'opacity-50' : 'hover:bg-slate-750'}>
                <td className="p-4">
                  <div className="font-bold text-foreground">{member.full_name || 'Unknown Operator'}</div>
                  <div className="text-xs text-outline font-mono mt-1">ID: {member.id.substring(0, 8)}</div>
                </td>
                <td className="p-4">
                  <span className={`text-xs font-bold px-2 py-1 rounded bg-background border ${
                    member.role === 'SUPER_ADMIN' ? 'border-purple-500 text-purple-400' : 
                    member.role === 'FLEET_MANAGER' ? 'border-blue-500 text-primary' :
                    member.role === 'BUILDER' ? 'border-emerald-500 text-emerald-400' :
                    'border-outline text-on-surface-variant'
                  }`}>
                    {member.role}
                  </span>
                </td>
                <td className="p-4">
                  {member.status === 'ACTIVE' ? (
                    <span className="flex items-center gap-1 text-emerald-500 text-xs font-bold">
                      <CheckCircle className="w-4 h-4" /> ACTIVE
                    </span>
                  ) : (
                    <span className="flex items-center gap-1 text-red-500 text-xs font-bold">
                      <ShieldAlert className="w-4 h-4" /> INACTIVE
                    </span>
                  )}
                </td>
                <td className="p-4 text-right">
                  {canManage && member.id !== currentProfile.id && member.role === 'DRIVER' && member.status === 'ACTIVE' && (
                    <button 
                      onClick={() => handleRevokeAccess(member.id)}
                      className="text-xs bg-red-900/30 hover:bg-red-600 text-red-400 hover:text-white font-bold px-3 py-1.5 rounded transition-colors border border-red-800"
                    >
                      KILL SWITCH (Revoke Access)
                    </button>
                  )}
                  {member.status === 'INACTIVE' && (
                    <span className="text-xs text-outline italic">Terminated</span>
                  )}
                </td>
              </tr>
            ))}
            {team.length === 0 && (
              <tr>
                <td colSpan={4} className="p-8 text-center text-outline">
                  No personnel found in this fleet.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
};

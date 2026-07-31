import React, { useState } from 'react';

interface Profile {
  id: string;
  full_name: string;
  role: string;
  status: string;
  updated_at: string;
}

interface Invite {
  id: string;
  token: string;
  role: string;
  expires_at: string;
  consumed_at: string | null;
}

interface CrewManagementProps {
  crew: Profile[];
  invites: Invite[];
  isGenerating: boolean;
  onGenerateInvite: (role: string) => void;
  onDisableMember: (id: string) => void;
  onRevokeInvite: (token: string) => void;
}

export const CrewManagementPresenter: React.FC<CrewManagementProps> = ({
  crew,
  invites,
  isGenerating,
  onGenerateInvite,
  onDisableMember,
  onRevokeInvite
}) => {
  const [selectedRole, setSelectedRole] = useState<string>('driver');
  const [copiedToken, setCopiedToken] = useState<string | null>(null);

  const getInviteUrl = (token: string) => {
    return `${window.location.origin}/invite?token=${token}`;
  };

  const handleCopyUrl = (token: string) => {
    navigator.clipboard.writeText(getInviteUrl(token));
    setCopiedToken(token);
    setTimeout(() => setCopiedToken(null), 3000);
  };

  return (
    <div className="w-full">
      <div className="mb-8">
        <h1 className="text-3xl font-black text-white uppercase tracking-widest flex items-center gap-3">
          <span className="bg-emerald-600 p-2 rounded-lg text-white">👥</span> 
          Human Resources
        </h1>
        <p className="text-slate-400 mt-2 font-mono text-sm">Manage your crew, assign roles, and generate cryptographic onboarding links.</p>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
        {/* Active Crew */}
        <div className="bg-slate-900 border border-slate-800 rounded-xl p-6">
          <h2 className="text-xl font-bold text-white mb-4">Active Crew</h2>
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm text-slate-300">
              <thead className="bg-slate-950 text-slate-400 font-mono uppercase">
                <tr>
                  <th className="px-4 py-3 rounded-tl-lg">Name</th>
                  <th className="px-4 py-3">Role</th>
                  <th className="px-4 py-3">Status</th>
                  <th className="px-4 py-3 rounded-tr-lg text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {crew.filter(m => m.status !== 'INACTIVE').length === 0 ? (
                  <tr>
                    <td colSpan={4} className="px-4 py-8 text-center text-slate-500 font-mono">No active crew members found.</td>
                  </tr>
                ) : (
                  crew.filter(m => m.status !== 'INACTIVE').map((member) => (
                    <tr key={member.id} className="border-b border-slate-800/50 hover:bg-slate-800/50 transition-colors">
                      <td className="px-4 py-3 font-medium text-white">{member.full_name}</td>
                      <td className="px-4 py-3">
                        <span className="bg-slate-800 px-2 py-1 rounded text-xs uppercase tracking-wider text-slate-300">
                          {member.role}
                        </span>
                      </td>
                      <td className="px-4 py-3">
                        <span className={`px-2 py-1 rounded text-xs font-bold uppercase tracking-wider ${
                          member.status === 'ACTIVE' ? 'bg-emerald-900/50 text-emerald-400' : 'bg-slate-900/50 text-slate-500'
                        }`}>
                          {member.status}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-right">
                        {member.status === 'ACTIVE' && member.role !== 'account_owner' && (
                          <button 
                            onClick={() => {
                              if (window.confirm(`¿Está seguro de inhabilitar a ${member.full_name}?`)) {
                                onDisableMember(member.id);
                              }
                            }}
                            className="text-red-400 hover:text-red-300 font-mono text-xs uppercase transition-colors"
                          >
                            Dar de baja
                          </button>
                        )}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>

        {/* Invite Generator */}
        <div className="bg-slate-900 border border-slate-800 rounded-xl p-6 flex flex-col">
          <h2 className="text-xl font-bold text-white mb-4">Pending Invitations</h2>
          
          <div className="flex gap-2 mb-6">
            <select 
              value={selectedRole}
              onChange={(e) => setSelectedRole(e.target.value)}
              className="bg-slate-950 border border-slate-700 text-white rounded-lg px-4 py-2 flex-1 focus:ring-2 focus:ring-blue-500 focus:outline-none uppercase text-sm font-bold tracking-wider"
            >
              <option value="driver">Driver (Camionero)</option>
              <option value="fitter">Fitter (Mecánico)</option>
              <option value="dispatcher">Dispatcher (Romana)</option>
              <option value="supervisor">Supervisor</option>
              <option value="fleet_manager">Fleet Manager</option>
            </select>
            <button
              onClick={() => onGenerateInvite(selectedRole)}
              disabled={isGenerating}
              className="bg-blue-600 hover:bg-blue-500 text-white font-bold py-2 px-6 rounded-lg uppercase tracking-wider transition-colors disabled:opacity-50"
            >
              {isGenerating ? 'GENERATING...' : 'NEW INVITE'}
            </button>
          </div>

          <div className="overflow-x-auto flex-1">
            <table className="w-full text-left text-sm text-slate-300">
              <thead className="bg-slate-950 text-slate-400 font-mono uppercase">
                <tr>
                  <th className="px-4 py-3 rounded-tl-lg">Role</th>
                  <th className="px-4 py-3">Status</th>
                  <th className="px-4 py-3 rounded-tr-lg">Action</th>
                </tr>
              </thead>
              <tbody>
                {invites.length === 0 ? (
                  <tr>
                    <td colSpan={3} className="px-4 py-8 text-center text-slate-500 font-mono">No pending invitations.</td>
                  </tr>
                ) : (
                  invites.map((invite) => {
                    const isConsumed = !!invite.consumed_at;
                    const isExpired = new Date(invite.expires_at) < new Date();
                    return (
                      <tr key={invite.id} className="border-b border-slate-800/50 hover:bg-slate-800/50 transition-colors">
                        <td className="px-4 py-3 font-mono text-white text-xs">
                          {invite.token}
                          {isExpired && !isConsumed && (
                            <span className="ml-2 text-[10px] text-rose-500 bg-rose-500/10 px-2 py-0.5 rounded">EXPIRED</span>
                          )}
                        </td>
                        <td className="px-4 py-3">
                          <span className="bg-slate-800 px-2 py-1 rounded text-xs uppercase tracking-wider text-slate-300">
                            {invite.role}
                          </span>
                        </td>
                        <td className="px-4 py-3">
                          {isConsumed ? (
                            <span className="text-slate-500 font-bold text-xs uppercase">Consumed</span>
                          ) : isExpired ? (
                            <span className="text-rose-500 font-bold text-xs uppercase">Expired</span>
                          ) : (
                            <span className="text-amber-500 font-bold text-xs uppercase animate-pulse">Pending</span>
                          )}
                        </td>
                        <td className="px-4 py-3 text-right">
                          {!isConsumed && !isExpired && (
                            <button
                              onClick={() => handleCopyUrl(invite.token)}
                              className="text-xs bg-slate-800 hover:bg-slate-700 text-white px-3 py-1.5 rounded transition-colors uppercase font-bold mr-2"
                            >
                              {copiedToken === invite.token ? 'COPIED!' : 'COPY URL'}
                            </button>
                          )}
                          {!isConsumed && (
                            <button 
                              onClick={() => {
                                if (window.confirm('¿Está seguro de revocar esta invitación?')) {
                                  onRevokeInvite(invite.token);
                                }
                              }}
                              className="text-red-400 hover:text-red-300 font-mono text-xs uppercase transition-colors"
                            >
                              Revocar
                            </button>
                          )}
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
          
        </div>
      </div>
    </div>
  );
};

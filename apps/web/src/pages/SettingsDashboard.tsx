import React from 'react';
import { supabase } from '../lib/supabase';
import { useCurrentProfile } from '../hooks/useCurrentProfile';
import { Settings, LogOut, Shield } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

export const SettingsDashboard = () => {
  const { data: profile } = useCurrentProfile();
  const navigate = useNavigate();

  const handleLogout = async () => {
    await supabase.auth.signOut();
    navigate('/login');
  };

  return (
    <div className="flex-1 p-8 bg-slate-900 text-slate-200 h-full overflow-y-auto">
      <div className="flex items-center gap-3 border-b border-slate-700 pb-6 mb-8">
        <Settings className="w-8 h-8 text-blue-500" />
        <div>
          <h1 className="text-2xl font-bold">System Settings</h1>
          <p className="text-sm text-slate-400">Manage your account and preferences.</p>
        </div>
      </div>

      <div className="max-w-2xl space-y-6">
        <div className="bg-slate-800 rounded-lg p-6 border border-slate-700">
          <h2 className="text-lg font-bold flex items-center gap-2 mb-4 text-white">
            <Shield className="w-5 h-5 text-emerald-500" /> Account Security
          </h2>
          <div className="space-y-4">
            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase mb-1">Email</label>
              <input 
                type="text" 
                disabled 
                className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-slate-500 cursor-not-allowed"
                value="[Secured by Supabase Auth]" 
              />
            </div>
            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase mb-1">Role</label>
              <input 
                type="text" 
                disabled 
                className="w-full bg-slate-900 border border-slate-700 rounded p-2 text-slate-500 cursor-not-allowed"
                value={profile?.role || 'Loading...'} 
              />
            </div>
          </div>
        </div>

        <div className="bg-slate-800 rounded-lg p-6 border border-slate-700">
          <h2 className="text-lg font-bold mb-4 text-red-500">Danger Zone</h2>
          <p className="text-sm text-slate-400 mb-4">Logging out will terminate your current active session on this device.</p>
          <button 
            onClick={handleLogout}
            className="bg-red-900/40 hover:bg-red-600 text-red-400 hover:text-white font-bold py-2 px-6 rounded transition-colors border border-red-800 flex items-center gap-2"
          >
            <LogOut className="w-4 h-4" /> Terminate Session
          </button>
        </div>
      </div>
    </div>
  );
};

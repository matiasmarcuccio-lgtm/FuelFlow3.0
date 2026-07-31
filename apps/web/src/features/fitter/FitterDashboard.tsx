import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';
import { Wrench, ShieldAlert, LogOut, CheckCircle2 } from 'lucide-react';
import { toast } from 'sonner';

interface FitterDashboardProps {
  onPurgeDevice?: () => void;
}

export const FitterDashboard: React.FC<FitterDashboardProps> = ({ onPurgeDevice }) => {
  const queryClient = useQueryClient();
  const [selectedAsset, setSelectedAsset] = useState<{ id: string; code: string; isLocking: boolean } | null>(null);
  const [description, setDescription] = useState('');

  // 1. OBTENER MAQUINARIA
  const { data: assets, isLoading } = useQuery({
    queryKey: ['fitter_assets'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('assets')
        .select('id, internal_code, status, category')
        .order('internal_code', { ascending: true });
      
      if (error) throw error;
      return data;
    },
    refetchInterval: 10000 // Polling para mantener al mecánico actualizado
  });

  // 2. MUTACIÓN: BLOQUEAR ACTIVO (LOTO)
  const lockMutation = useMutation({
    mutationFn: async ({ id, desc }: { id: string; desc: string }) => {
      const { error } = await supabase.rpc('fitter_lock_asset', {
        p_asset_id: id,
        p_description: desc
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => {
      toast.success('Candado LOTO aplicado correctamente.');
      queryClient.invalidateQueries({ queryKey: ['fitter_assets'] });
      setSelectedAsset(null);
      setDescription('');
    },
    onError: (err: any) => toast.error(err.message || 'Error al aplicar LOTO')
  });

  // 3. MUTACIÓN: LIBERAR ACTIVO
  const releaseMutation = useMutation({
    mutationFn: async ({ id, desc }: { id: string; desc: string }) => {
      const { error } = await supabase.rpc('fitter_release_asset', {
        p_asset_id: id,
        p_resolution_notes: desc
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => {
      toast.success('Maquinaria liberada y operativa.');
      queryClient.invalidateQueries({ queryKey: ['fitter_assets'] });
      setSelectedAsset(null);
      setDescription('');
    },
    onError: (err: any) => toast.error(err.message || 'Error al liberar maquinaria')
  });

  const handleAction = () => {
    if (!selectedAsset || !description.trim()) return;
    
    if (selectedAsset.isLocking) {
      lockMutation.mutate({ id: selectedAsset.id, desc: description });
    } else {
      releaseMutation.mutate({ id: selectedAsset.id, desc: description });
    }
  };

  const logout = async () => {
    await supabase.auth.signOut();
    window.location.reload();
  };

  if (isLoading) {
    return <div className="h-screen bg-slate-950 flex items-center justify-center text-emerald-500 font-mono animate-pulse">CARGANDO TELEMETRÍA...</div>;
  }

  return (
    <div className="min-h-screen bg-slate-950 text-slate-200 font-sans p-4 pb-20">
      
      {/* HEADER MÓVIL */}
      <header className="flex justify-between items-center mb-6 border-b border-slate-800 pb-4">
        <div>
          <h1 className="text-xl font-black uppercase tracking-tight text-white flex items-center gap-2">
            <Wrench className="text-emerald-500" /> WHS Fitter Portal
          </h1>
          <p className="text-[10px] text-slate-500 font-mono uppercase tracking-widest mt-1">Authorized Maintenance Only</p>
        </div>
        <button onClick={logout} className="p-2 bg-slate-900 border border-slate-800 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition-colors">
          <LogOut size={20} />
        </button>
      </header>

      {/* LISTADO DE ACTIVOS */}
      <div className="space-y-4">
        {assets?.map((asset: any) => {
          const isOperational = asset.status === 'OPERATIONAL';
          const isMaintenance = asset.status === 'MAINTENANCE';
          
          return (
            <div key={asset.id} className={`p-5 rounded-2xl border-2 shadow-xl ${isMaintenance ? 'bg-red-950/20 border-red-900/50' : 'bg-slate-900 border-slate-800'}`}>
              <div className="flex justify-between items-start mb-4">
                <div>
                  <h2 className="text-3xl font-black tracking-tighter text-white">{asset.internal_code}</h2>
                  <span className="text-[10px] font-mono text-slate-500 uppercase">{asset.category}</span>
                </div>
                <div className={`px-3 py-1 rounded font-mono text-[10px] font-bold uppercase tracking-widest ${isOperational ? 'bg-emerald-950/50 text-emerald-400 border border-emerald-900' : isMaintenance ? 'bg-red-950 text-red-500 border border-red-900' : 'bg-orange-950/50 text-orange-400 border border-orange-900'}`}>
                  {asset.status}
                </div>
              </div>

              {isOperational && (
                <button 
                  onClick={() => setSelectedAsset({ id: asset.id, code: asset.internal_code, isLocking: true })}
                  className="w-full py-4 bg-red-600 hover:bg-red-500 text-white font-black uppercase tracking-widest text-sm rounded-xl flex justify-center items-center gap-2 shadow-[0_0_20px_rgba(220,38,38,0.3)] transition-all active:scale-95"
                >
                  <ShieldAlert size={18} /> APPLY LOTO LOCK
                </button>
              )}

              {isMaintenance && (
                <button 
                  onClick={() => setSelectedAsset({ id: asset.id, code: asset.internal_code, isLocking: false })}
                  className="w-full py-4 bg-emerald-600 hover:bg-emerald-500 text-white font-black uppercase tracking-widest text-sm rounded-xl flex justify-center items-center gap-2 shadow-[0_0_20px_rgba(52,211,153,0.2)] transition-all active:scale-95"
                >
                  <CheckCircle2 size={18} /> RELEASE TO DISPATCH
                </button>
              )}
            </div>
          );
        })}
      </div>

      {/* BOTTOM ACTION - HARDWARE PURGE */}
      {onPurgeDevice && (
        <div className="mt-12 text-center">
          <button onClick={onPurgeDevice} className="text-[10px] font-mono text-slate-700 hover:text-slate-500 uppercase tracking-widest">
            [ DEBUG: PURGAR CERROJO ]
          </button>
        </div>
      )}

      {/* MODAL DE ACCIÓN (LOTO / RELEASE) */}
      {selectedAsset && (
        <div className="fixed inset-0 z-50 bg-black/90 backdrop-blur-sm flex flex-col justify-end p-4 pb-8">
          <div className="bg-slate-900 border-2 border-slate-700 rounded-3xl p-6 shadow-2xl animate-in slide-in-from-bottom-10">
            <h3 className="text-2xl font-black uppercase tracking-tight text-white mb-2">
              {selectedAsset.isLocking ? 'Lock Asset' : 'Release Asset'} <span className={selectedAsset.isLocking ? 'text-red-500' : 'text-emerald-500'}>{selectedAsset.code}</span>
            </h3>
            <p className="text-xs font-mono text-slate-400 mb-6">
              {selectedAsset.isLocking ? 'Por favor describa la falla detectada. La máquina será aislada de la cola JIT inmediatamente.' : 'Por favor ingrese las notas de resolución. La máquina volverá a estar disponible para despacho.'}
            </p>

            <textarea 
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder={selectedAsset.isLocking ? "Ej: Falla en frenos hidráulicos..." : "Ej: Bomba hidráulica reemplazada. Pruebas exitosas."}
              className="w-full h-32 bg-slate-950 border border-slate-700 rounded-xl p-4 text-white text-sm font-sans focus:outline-none focus:border-emerald-500 transition-colors mb-4 resize-none"
            />

            <div className="flex gap-3">
              <button 
                onClick={() => { setSelectedAsset(null); setDescription(''); }}
                className="flex-1 py-4 bg-slate-800 text-slate-300 font-bold uppercase rounded-xl"
              >
                Cancel
              </button>
              <button 
                onClick={handleAction}
                disabled={!description.trim() || lockMutation.isPending || releaseMutation.isPending}
                className={`flex-1 py-4 text-white font-black uppercase rounded-xl disabled:opacity-50 disabled:active:scale-100 active:scale-95 transition-all shadow-lg ${selectedAsset.isLocking ? 'bg-red-600 shadow-red-600/20' : 'bg-emerald-600 shadow-emerald-600/20'}`}
              >
                {lockMutation.isPending || releaseMutation.isPending ? 'PROCESANDO...' : 'CONFIRMAR'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

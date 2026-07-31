import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';
import { FitterReleaseModal } from '../maintenance/FitterReleaseModal';
import { TokenGeneratorModal } from './TokenGeneratorModal';
import { EmergencyOverrideModal } from './EmergencyOverrideModal';
import { CreateAssetModal } from './CreateAssetModal';

interface AssetRow {
  id: string;
  name: string;
  asset_type: string;
  status: 'AVAILABLE' | 'OUT_OF_SERVICE' | 'IN_MAINTENANCE' | 'DISPATCHED';
  last_prestart_at: string | null;
  active_lockout_reason?: string;
}

interface FleetAssetRosterProps {
  userRole: 'super_admin' | 'fleet_manager' | 'fitter' | 'dispatcher' | 'driver';
  fleetId: string;
}

export const FleetAssetRoster: React.FC<FleetAssetRosterProps> = ({ userRole, fleetId }) => {
  const queryClient = useQueryClient();
  const [filter, setFilter] = useState<string>('ALL');
  
  // Estado para controlar qué activo se inyecta en el Modal del Mecánico
  const [selectedAssetForRelease, setSelectedAssetForRelease] = useState<AssetRow | null>(null);

  // Estado para el Break-Glass Gerencial
  const [overrideModalOpen, setOverrideModalOpen] = useState(false);
  const [selectedAssetForOverride, setSelectedAssetForOverride] = useState<AssetRow | null>(null);

  // Estado para el provisionamiento de tablets (Zero-Trust Token)
  const [isTokenModalOpen, setIsTokenModalOpen] = useState(false);

  // Estado para crear nuevos activos (Conducto 2)
  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false);

  // Mutación SSOT para crear un activo
  const createAssetMutation = useMutation({
    mutationFn: async (payload: { name: string; category: string }) => {
      const { data: profile, error: profileErr } = await supabase
        .from('profiles')
        .select('fleet_id')
        .eq('id', (await supabase.auth.getUser()).data.user?.id)
        .single();
        
      if (profileErr || !profile?.fleet_id) {
        throw new Error('Identidad gerencial no validada. Imposible matricular maquinaria.');
      }

      const { data, error } = await supabase.from('assets').insert([{
        fleet_id: profile.fleet_id,
        internal_code: payload.name,
        category: payload.category,
        status: 'OPERATIONAL'
      }]).select();

      if (error) throw new Error(`Fallo en el registro de motor: ${error.message}`);
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['fleet_assets_roster', fleetId] });
      setIsCreateModalOpen(false);
    }
  });

  // 1. CONSULTA DE ACTIVOS EN CAPA 0 (Con join relacional a la etiqueta de peligro activa)
  const { data: assets = [], isLoading, error } = useQuery<AssetRow[]>({
    queryKey: ['fleet_assets_roster', fleetId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('assets')
        .select(`
          id,
          internal_code,
          category,
          status,
          last_prestart_at,
          asset_lockouts!left(lockout_reason, status)
        `)
        .eq('fleet_id', fleetId)
        .order('internal_code', { ascending: true });

      if (error) throw new Error(error.message);

      // Aplanamos el arreglo para extraer la razón exacta del bloqueo activo
      return data.map((item: any) => {
        const activeLock = item.asset_lockouts?.find((l: any) => l.status === 'ACTIVE');
        return {
          id: item.id,
          name: item.internal_code,
          asset_type: item.category,
          status: item.status,
          last_prestart_at: item.last_prestart_at,
          active_lockout_reason: activeLock ? activeLock.lockout_reason : 'BLOQUEO NO ESPECIFICADO EN HISTORIAL',
        };
      });
    },
    refetchInterval: 10000, // Telemetría en vivo cada 10 segundos
  });

  // Filtrado reactivo en memoria
  const filteredAssets = assets.filter((asset) => {
    if (filter === 'ALL') return true;
    return asset.status === filter;
  });

  // Evaluación de soberanía para renderizar botones técnicos
  const canAuthorizeRelease = ['fitter', 'fleet_manager', 'super_admin'].includes(userRole);

  const handleReleaseSuccess = (releaseData: any) => {
    console.debug('⚡ Indulto ejecutado con éxito en Capa 0:', releaseData);
    // Invalidamos la caché de React Query para forzar que la fila mutada cambie a verde en 10ms
    queryClient.invalidateQueries({ queryKey: ['fleet_assets_roster', fleetId] });
  };

  if (isLoading) {
    return (
      <div className="p-12 text-center font-mono text-slate-500 uppercase animate-pulse">
        [CARGANDO TELEMETRÍA DE LA FLOTA EN HOBART...]
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-950/40 border-2 border-red-800 p-6 rounded-2xl font-mono text-xs text-red-400 uppercase">
        ⚠️ ERROR DE ADUANA EN EL ROSTER: {error.message}
      </div>
    );
  }

  return (
    <div className="bg-slate-950 border border-slate-800 rounded-3xl p-6 md:p-8 font-sans select-none shadow-2xl">
      
      {/* Cabecera de Control Operativo */}
      <header className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 border-b border-slate-800 pb-6 mb-6">
        <div>
          <div className="flex items-center gap-3">
            <span className="w-3 h-3 bg-blue-500 rounded-full animate-ping"></span>
            <h2 className="text-2xl font-black text-white uppercase tracking-tight">
              Roster de Maquinaria • Command Center
            </h2>
          </div>
          <p className="text-xs font-mono text-slate-500 uppercase mt-1">
            JURISDICCIÓN: FLOTA ID #{fleetId.slice(0, 8)} | ROL ACTIVO: <strong className="text-blue-400">{userRole.toUpperCase()}</strong>
          </p>
          
          {/* Botón de Emisión de Tokens de Flota y Crear Activo (Solo Gerencia) */}
          {['fleet_manager', 'super_admin', 'account_owner'].includes(userRole) && (
            <div className="flex flex-wrap gap-2 mt-4">
              <button
                onClick={() => setIsTokenModalOpen(true)}
                className="bg-emerald-600/10 hover:bg-emerald-600/20 text-emerald-400 border border-emerald-500/30 hover:border-emerald-500 px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-widest transition-all flex items-center gap-2"
              >
                <span>📲 EMITIR TOKEN DE TABLET</span>
              </button>
              
              <button
                onClick={() => setIsCreateModalOpen(true)}
                className="bg-blue-600/10 hover:bg-blue-600/20 text-blue-400 border border-blue-500/30 hover:border-blue-500 px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-widest transition-all flex items-center gap-2"
              >
                <span className="material-symbols-outlined text-[14px]">add</span>
                <span>MATRICULAR ACTIVO</span>
              </button>
            </div>
          )}
        </div>

        {/* Botonera de Filtrado Táctico */}
        <div className="flex flex-wrap gap-2 font-mono text-xs">
          {[
            { label: 'TODOS', value: 'ALL' },
            { label: '🟢 DISPONIBLES', value: 'operational' },
            { label: '🛑 INHABILITADOS / TALLER', value: 'maintenance' },
          ].map((btn) => (
            <button
              key={btn.value}
              onClick={() => setFilter(btn.value)}
              className={`px-4 py-2 rounded-xl font-bold uppercase tracking-wider transition-all border ${
                filter === btn.value
                  ? 'bg-blue-600 text-black border-blue-400 shadow-lg shadow-blue-600/20'
                  : 'bg-slate-900 text-slate-400 border-slate-800 hover:text-white hover:border-slate-700'
              }`}
            >
              {btn.label}
            </button>
          ))}
        </div>
      </header>

      {/* Tabla General de Maquinaria */}
      <div className="overflow-x-auto">
        <table className="w-full text-left border-collapse font-mono text-xs">
          <thead>
            <tr className="border-b border-slate-800 text-slate-500 uppercase tracking-widest text-[10px]">
              <th className="py-4 px-4">Maquinaria (Asset ID)</th>
              <th className="py-4 px-4">Tipo</th>
              <th className="py-4 px-4">Estado WHS</th>
              <th className="py-4 px-4">Último Pre-Start</th>
              <th className="py-4 px-4 text-right">Acción de Taller</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-900">
            {filteredAssets.length === 0 ? (
              <tr>
                <td colSpan={5} className="py-12 text-center text-slate-600 uppercase">
                  No hay maquinaria que coincida con el filtro seleccionado.
                </td>
              </tr>
            ) : (
              filteredAssets.map((asset) => {
                const isLocked = asset.status === 'maintenance';
                return (
                  <tr
                    key={asset.id}
                    className={`transition-colors ${
                      isLocked ? 'bg-red-950/10 hover:bg-red-950/20' : 'hover:bg-slate-900/50'
                    }`}
                  >
                    {/* Columna 1: Nombre e ID */}
                    <td className="py-4 px-4">
                      <span className="font-sans font-black text-white text-sm block">
                        {asset.name}
                      </span>
                      <span className="text-[10px] text-slate-600 uppercase">
                        #{asset.id.slice(0, 8)}
                      </span>
                    </td>

                    {/* Columna 2: Tipo de Vehículo */}
                    <td className="py-4 px-4 text-slate-400 uppercase">
                      {asset.asset_type || 'EXCAVADORA / HDV'}
                    </td>

                    {/* Columna 3: Estado con Alto Contraste */}
                    <td className="py-4 px-4">
                      {isLocked ? (
                        <div className="inline-block">
                          <span className="bg-red-600/20 text-red-500 border border-red-500/40 px-3 py-1 rounded font-black uppercase text-[10px] animate-pulse">
                            🛑 OUT OF SERVICE
                          </span>
                          <p className="text-[9px] text-red-400 mt-1 max-w-xs break-words">
                            MOTIVO: "{asset.active_lockout_reason}"
                          </p>
                        </div>
                      ) : (
                        <span className="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-3 py-1 rounded font-bold uppercase text-[10px]">
                          🟢 {asset.status}
                        </span>
                      )}
                    </td>

                    {/* Columna 4: Marca de tiempo del Pre-Start */}
                    <td className="py-4 px-4 text-slate-500">
                      {asset.last_prestart_at
                        ? new Date(asset.last_prestart_at).toLocaleTimeString('en-AU', {
                            hour: '2-digit',
                            minute: '2-digit',
                            timeZone: 'Australia/Hobart',
                          }) + ' AEST'
                        : 'SIN REGISTRO'}
                    </td>

                    {/* CELDA DE ACCIÓN LEGAL WHS EN EL ROSTER */}
                    <td className="p-4 text-right">
                      {isLocked && (
                        <>
                          {userRole === 'fitter' ? (
                            <button
                              onClick={() => setSelectedAssetForRelease(asset)}
                              className="px-3 py-1.5 bg-sky-600 hover:bg-sky-500 text-white font-semibold rounded text-xs transition-colors shadow"
                            >
                              🔧 LIBERAR WHS
                            </button>
                          ) : userRole === 'fleet_manager' ? (
                            <button
                              onClick={() => {
                                setSelectedAssetForOverride(asset);
                                setOverrideModalOpen(true);
                              }}
                              className="px-3 py-1.5 bg-rose-600 hover:bg-rose-500 text-white font-bold rounded text-xs transition-colors shadow-lg animate-pulse"
                            >
                              ⚠️ RUPTURA WHS
                            </button>
                          ) : (
                            <span className="text-[10px] font-mono text-slate-500 uppercase bg-slate-950 px-2 py-1 rounded border border-slate-800">
                              🔒 Bloqueado por Taller
                            </span>
                          )}
                        </>
                      )}
                      {!isLocked && (
                        <span className="text-[10px] text-slate-700 uppercase">
                          — SIN ACCIÓN —
                        </span>
                      )}
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      {/* Pie de Tabla Forense */}
      <footer className="mt-6 pt-4 border-t border-slate-900 flex justify-between items-center font-mono text-[10px] text-slate-600 uppercase">
        <span>Total Activos en Jurisdicción: {assets.length}</span>
        <span>Sistema de Enclavamiento WHS de Tasmania Activo</span>
      </footer>

      {/* INYECCIÓN DEL MODAL DE INDULTO DEL MECÁNICO */}
      {selectedAssetForRelease && (
        <FitterReleaseModal
          isOpen={Boolean(selectedAssetForRelease)}
          onClose={() => setSelectedAssetForRelease(null)}
          assetId={selectedAssetForRelease.id}
          assetName={selectedAssetForRelease.name}
          lockoutReason={selectedAssetForRelease.active_lockout_reason || 'INHABILITACIÓN WHS'}
          onReleasedSuccess={handleReleaseSuccess}
        />
      )}

      {/* INYECCIÓN DEL MODAL DE RUPTURA WHS (BREAK-GLASS) */}
      {selectedAssetForOverride && (
        <EmergencyOverrideModal
          isOpen={overrideModalOpen}
          onClose={() => setOverrideModalOpen(false)}
          assetId={selectedAssetForOverride.id}
          assetCode={selectedAssetForOverride.name}
          onSuccess={(data) => {
            console.log('Break-Glass exitoso:', data);
            queryClient.invalidateQueries({ queryKey: ['fleet_assets_roster'] });
          }}
        />
      )}

      {/* INYECCIÓN DEL GENERADOR DE TOKENS DE FLOTA */}
      <TokenGeneratorModal
        isOpen={isTokenModalOpen}
        onClose={() => setIsTokenModalOpen(false)}
        fleetId={fleetId}
      />
      {/* Modal Creador de Activos */}
      <CreateAssetModal
        isOpen={isCreateModalOpen}
        onClose={() => setIsCreateModalOpen(false)}
        onConfirm={(payload) => createAssetMutation.mutate(payload)}
        isSubmitting={createAssetMutation.isPending}
      />
    </div>
  );
};

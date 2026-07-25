import React from 'react';

// Tipos simplificados para el contrato de props
type AssetStatus = 'available' | 'maintenance' | 'in_use';
type ShiftStatus = 'pending_prestart' | 'in_progress';

interface Asset {
  id: string;
  internal_code: string;
  status: AssetStatus;
  current_shift?: {
    id: string;
    driver_name: string;
    status: ShiftStatus;
  };
}

interface CommandCenterProps {
  assets: Asset[];
  onInitiateDispatch: (assetId: string) => void;
  onRevokeDispatch: (shiftId: string) => void;
  isMutating: boolean;
}

export const CommandCenterPresenter: React.FC<CommandCenterProps> = ({
  assets,
  onInitiateDispatch,
  onRevokeDispatch,
  isMutating
}) => {
  return (
    <div className="min-h-screen bg-slate-950 p-6 font-sans select-none">
      <div className="mb-8">
        <h1 className="text-3xl font-black text-white uppercase tracking-widest flex items-center gap-3">
          <span className="bg-blue-600 p-2 rounded-lg text-white">📡</span> 
          Tactical Dispatch
        </h1>
        <p className="text-slate-400 mt-2 font-mono text-sm">Assign shifts and override WHS fatigue thresholds for active assets.</p>
      </div>

      {/* Matriz de Activos */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
        {assets.map((asset) => (
          <div 
            key={asset.id} 
            className={`p-5 rounded-xl border flex flex-col justify-between h-48 transition-colors
              ${asset.status === 'available' ? 'bg-slate-900 border-slate-700' : ''}
              ${asset.status === 'maintenance' ? 'bg-red-950 border-red-800' : ''}
              ${asset.status === 'in_use' ? 'bg-blue-950 border-blue-800' : ''}
            `}
          >
            <div className="flex justify-between items-start">
              <h2 className="text-2xl font-black text-white">{asset.internal_code}</h2>
              
              {/* Badges de Estado del Activo */}
              {asset.status === 'maintenance' ? (
                <span className="bg-red-600 text-white text-[10px] font-bold px-2 py-1 rounded uppercase tracking-wider">MAINTENANCE</span>
              ) : (
                <span className="bg-slate-700 text-slate-300 text-[10px] font-bold px-2 py-1 rounded uppercase tracking-wider">
                  {asset.status === 'available' ? 'AVAILABLE' : (asset.status || 'AVAILABLE').toUpperCase()}
                </span>
              )}
            </div>

            {/* Lógica Renderizada según el Estado del Turno */}
            <div className="mt-auto">
              {asset.status !== 'maintenance' && !asset.current_shift && (
                <button
                  onClick={() => onInitiateDispatch(asset.id)}
                  disabled={isMutating}
                  className="w-full bg-blue-600 hover:bg-blue-500 text-white font-bold py-3 rounded-lg uppercase transition-colors disabled:opacity-50"
                >
                  ASSIGN SHIFT
                </button>
              )}

              {asset.status === 'maintenance' && (
                <div className="text-red-400 text-sm font-mono bg-red-900/50 p-2 rounded">
                  MECHANICAL LOCKDOWN. CONTACT WORKSHOP.
                </div>
              )}

              {asset.current_shift && (
                <div className="bg-slate-950/50 p-3 rounded-lg border border-slate-800/50">
                  <div className="text-sm font-bold text-slate-300 mb-1">
                    Operator: <span className="text-white">{asset.current_shift.driver_name}</span>
                  </div>
                  
                  {asset.current_shift.status === 'pending_prestart' && (
                    <div className="flex justify-between items-center mt-2">
                      <span className="text-amber-500 text-xs font-bold uppercase animate-pulse">AWAITING PRE-START</span>
                      <button 
                        onClick={() => onRevokeDispatch(asset.current_shift!.id)}
                        disabled={isMutating}
                        className="text-xs font-bold bg-slate-800 hover:bg-red-700 text-slate-300 hover:text-white px-2 py-1 rounded transition-colors disabled:opacity-50"
                      >
                        {isMutating ? 'REVOKING...' : 'REVOKE'}
                      </button>
                    </div>
                  )}

                  {asset.current_shift.status === 'in_progress' && (
                    <div className="flex justify-between items-center mt-2">
                      <span className="text-green-400 text-xs font-bold uppercase">OPERATING (ACTIVE IOT)</span>
                    </div>
                  )}
                </div>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

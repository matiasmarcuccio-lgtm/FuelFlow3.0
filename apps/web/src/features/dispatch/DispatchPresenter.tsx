import React from 'react';
import type { Database } from '@fuelflow/shared-types';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

type Asset = Database['public']['Tables']['assets']['Row'];
type Assignment = Database['public']['Tables']['asset_assignments']['Row'];
type Profile = Database['public']['Tables']['profiles']['Row'];

interface DispatchPresenterProps {
  assets: Asset[];
  assignments: Assignment[];
  drivers: Profile[]; // Needed to show who is driving
  onAssignClick: (asset: Asset) => void;
  onForceCloseClick: (assignmentId: string) => void;
  onRevokeClick: (assignmentId: string) => void;
  isPending: boolean;
}

export const DispatchPresenter = ({
  assets,
  assignments,
  drivers,
  onAssignClick,
  onForceCloseClick,
  onRevokeClick,
  isPending,
}: DispatchPresenterProps) => {
  // Helper to find the active assignment for an asset
  const getActiveAssignment = (assetId: string) => {
    return assignments.find((a) => a.asset_id === assetId && a.shift_end === null);
  };

  const getDriverName = (driverId: string) => {
    return drivers.find(d => d.id === driverId)?.full_name || driverId.substring(0, 8);
  };

  return (
    <div className="p-6 h-full flex flex-col bg-slate-950 text-slate-50">
      <div className="mb-6 border-b border-slate-800 pb-4">
        <h1 className="text-3xl font-bold tracking-tight flex items-center gap-3">
          <span className="w-3 h-3 rounded-full bg-emerald-500 animate-pulse"></span>
          Command & Control
        </h1>
        <p className="text-slate-400 mt-1 font-mono text-sm">
          Deterministic Dispatch Matrix | Realtime Engaged
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4 overflow-y-auto pb-10">
        {assets.map((asset) => {
          const activeShift = getActiveAssignment(asset.id);
          const isAvailable = !activeShift;

          return (
            <Card key={asset.id} className="bg-slate-900 border-slate-800 flex flex-col justify-between">
              <CardHeader className="pb-2">
                <CardTitle className="flex justify-between items-start">
                  <span className="text-xl font-bold font-mono">{asset.internal_code}</span>
                  <span className={`px-2 py-1 text-xs font-semibold rounded uppercase tracking-wider ${
                    isAvailable ? 'bg-emerald-950 text-emerald-400' : 'bg-amber-950 text-amber-400'
                  }`}>
                    {isAvailable ? 'Available' : 'Dispatched'}
                  </span>
                </CardTitle>
                <div className="text-sm text-slate-400 uppercase tracking-widest mt-1">
                  {asset.category.replace('_', ' ')}
                </div>
              </CardHeader>
              <CardContent className="pt-2 flex-1 flex flex-col justify-end">
                {isAvailable ? (
                  <Button
                    onClick={() => onAssignClick(asset)}
                    disabled={isPending || asset.status !== 'operational'}
                    className="w-full h-14 text-lg font-bold bg-emerald-600 hover:bg-emerald-500 text-white shadow-lg shadow-emerald-900/20 active:scale-95 transition-transform"
                  >
                    ASSIGN SHIFT
                  </Button>
                ) : (
                  <div className="space-y-3">
                    <div className={`p-3 rounded-md border ${
                      activeShift.status === 'pending_prestart' 
                        ? 'bg-amber-950/40 border-amber-800/50' 
                        : 'bg-slate-950 border-slate-800'
                    }`}>
                      <div className={`text-xs font-mono mb-1 ${
                        activeShift.status === 'pending_prestart' ? 'text-amber-500' : 'text-slate-500'
                      }`}>
                        {activeShift.status === 'pending_prestart' ? 'PENDING PRE-START' : 'OPERATOR IN CABIN'}
                      </div>
                      <div className="font-semibold">{getDriverName(activeShift.driver_id)}</div>
                    </div>
                    {activeShift.status === 'pending_prestart' ? (
                      <Button
                        variant="outline"
                        onClick={() => onRevokeClick(activeShift.id)}
                        disabled={isPending}
                        className="w-full h-12 font-bold text-amber-500 border-amber-900 hover:bg-amber-950 active:scale-95 transition-transform"
                      >
                        REVOKE DISPATCH
                      </Button>
                    ) : (
                      <Button
                        variant="destructive"
                        onClick={() => onForceCloseClick(activeShift.id)}
                        disabled={isPending}
                        className="w-full h-12 font-bold shadow-lg bg-red-900 hover:bg-red-800 text-red-100 active:scale-95 transition-transform border border-red-700"
                      >
                        FORCE CLOSE (AUDIT)
                      </Button>
                    )}
                  </div>
                )}
              </CardContent>
            </Card>
          );
        })}
      </div>
    </div>
  );
};

import React, { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { toast } from 'sonner';

import { DispatchPresenter } from './DispatchPresenter';
import { DispatchDialogPresenter } from './DispatchDialogPresenter';
import type { Database } from '@fuelflow/shared-types';

type Asset = Database['public']['Tables']['assets']['Row'];
type Assignment = Database['public']['Tables']['asset_assignments']['Row'];
type Profile = Database['public']['Tables']['profiles']['Row'];

export const DispatchContainer = () => {
  const queryClient = useQueryClient();

  const [selectedAsset, setSelectedAsset] = useState<Asset | null>(null);
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [assignmentError, setAssignmentError] = useState<{ code: string; message: string } | null>(null);

  // 1. Fetching base data (Assets and Drivers)
  const { data: assets = [], isLoading: isLoadingAssets } = useQuery({
    queryKey: ['assets'],
    queryFn: async () => {
      const { data, error } = await supabase.from('assets').select('*').order('internal_code');
      if (error) throw error;
      return data as Asset[];
    },
  });

  const { data: drivers = [], isLoading: isLoadingDrivers } = useQuery({
    queryKey: ['drivers'],
    queryFn: async () => {
      // Obtenemos a todos los profiles que puedan conducir
      const { data, error } = await supabase.from('profiles').select('*');
      if (error) throw error;
      return data as Profile[];
    },
  });

  const { data: assignments = [], isLoading: isLoadingAssignments } = useQuery({
    queryKey: ['asset_assignments'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('asset_assignments')
        .select('*')
        .is('shift_end', null); // Solo necesitamos los turnos activos
      if (error) throw error;
      return data as Assignment[];
    },
  });

  // 2. Realtime WebSocket Sincronización innegociable
  useEffect(() => {
    const channel = supabase
      .channel('dispatch_realtime')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'asset_assignments' },
        (payload) => {
          // Forzamos un refetch inmediato para asegurar consistencia
          queryClient.invalidateQueries({ queryKey: ['asset_assignments'] });
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [queryClient]);

  // 3. Mutación de Asignación (HTTP)
  const assignMutation = useMutation({
    mutationFn: async (payload: { assetId: string; driverId: string; fatigueOverride?: string }) => {
      // Necesitamos el fleet_id del asset o del driver.
      // Asumiremos que viene en el JWT, pero la tabla requiere fleet_id explicitly.
      // Como SSOT, extraemos el fleet_id del driver.
      const driver = drivers.find(d => d.id === payload.driverId);
      if (!driver) throw new Error('Driver no encontrado localmente');

      // 1. Obtener la sesión actual para el assigned_by
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) throw new Error('No activo');

      const { data, error } = await supabase.from('asset_assignments').insert({
        fleet_id: driver.fleet_id,
        asset_id: payload.assetId,
        driver_id: payload.driverId,
        assigned_by: session.user.id,
        fatigue_override_reason: payload.fatigueOverride || null,
        override_approved_by: payload.fatigueOverride ? session.user.id : null,
      }).select().single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      toast.success('Shift assigned successfully');
      setIsDialogOpen(false);
      setAssignmentError(null);
      queryClient.invalidateQueries({ queryKey: ['asset_assignments'] });
    },
    onError: (err: any) => {
      // Parsear error del backend
      setAssignmentError({
        code: err.code || 'UNKNOWN',
        message: err.message || 'An unknown error occurred',
      });
      if (err.code !== 'P0001' || !err.message.includes('WHS_FATIGUE_LIMIT')) {
          toast.error(`Dispatch failed: ${err.message || 'Unknown collision'}`);
      }
    },
  });

  // 4. Mutación de Cierre Forzado (RPC)
  const forceCloseMutation = useMutation({
    mutationFn: async (assignmentId: string) => {
      const reason = window.prompt('Auditable Reason for Forced Closure:');
      if (!reason) throw new Error('Reason required for forced closure');
      
      const { error } = await supabase.rpc('force_close_shift', {
        p_assignment_id: assignmentId,
        p_reason: reason,
      });

      if (error) throw error;
      return true;
    },
    onSuccess: () => {
      toast.success('Shift forcibly closed and audited.');
      queryClient.invalidateQueries({ queryKey: ['asset_assignments'] });
    },
    onError: (err: any) => {
      toast.error(`Closure failed: ${err.message}`);
    },
  });

  // 5. Mutación de Revocación de Pre-Start (RPC)
  const revokeMutation = useMutation({
    mutationFn: async (assignmentId: string) => {
      const reason = window.prompt('Auditable Reason for Revocation:');
      if (!reason) throw new Error('Reason required for revocation');
      
      const { error } = await supabase.rpc('revoke_pending_shift', {
        p_assignment_id: assignmentId,
        p_reason: reason,
      });

      if (error) throw error;
      return true;
    },
    onSuccess: () => {
      toast.success('Shift revoked. Asset released.');
      queryClient.invalidateQueries({ queryKey: ['asset_assignments'] });
    },
    onError: (err: any) => {
      toast.error(`Revocation failed: ${err.message}`);
    },
  });

  const handleAssignClick = (asset: Asset) => {
    setSelectedAsset(asset);
    setAssignmentError(null);
    setIsDialogOpen(true);
  };

  const handleForceCloseClick = (assignmentId: string) => {
    forceCloseMutation.mutate(assignmentId);
  };

  const handleRevokeClick = (assignmentId: string) => {
    revokeMutation.mutate(assignmentId);
  };

  const isPending = assignMutation.isPending || forceCloseMutation.isPending || revokeMutation.isPending;
  const isLoading = isLoadingAssets || isLoadingDrivers || isLoadingAssignments;

  if (isLoading) {
    return (
      <div className="h-full flex items-center justify-center bg-slate-950 text-emerald-500 font-mono">
        INITIALIZING TACTICAL MATRIX...
      </div>
    );
  }

  return (
    <>
      <DispatchPresenter
        assets={assets}
        assignments={assignments}
        drivers={drivers}
        onAssignClick={handleAssignClick}
        onForceCloseClick={handleForceCloseClick}
        onRevokeClick={handleRevokeClick}
        isPending={isPending}
      />
      <DispatchDialogPresenter
        asset={selectedAsset}
        drivers={drivers}
        isOpen={isDialogOpen}
        onClose={() => {
          setIsDialogOpen(false);
          setAssignmentError(null);
        }}
        onSubmit={async (data) => {
          await assignMutation.mutateAsync(data);
        }}
        isPending={assignMutation.isPending}
        error={assignmentError}
      />
    </>
  );
};

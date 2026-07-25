import React, { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { toast } from 'sonner';
import type { Database } from '@fuelflow/shared-types';

import { PrestartKioskPresenter } from './PrestartKioskPresenter';

type Assignment = Database['public']['Tables']['asset_assignments']['Row'];
type Asset = Database['public']['Tables']['assets']['Row'];

export const OperatorContainer = () => {
  const queryClient = useQueryClient();
  const [currentUser, setCurrentUser] = useState<string | null>(null);

  // 1. Get current session
  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (session) setCurrentUser(session.user.id);
    });
  }, []);

  // 2. Fetch pending pre-starts for this operator
  const { data: activeAssignment, isLoading } = useQuery({
    queryKey: ['operator_assignment', currentUser],
    queryFn: async () => {
      if (!currentUser) return null;
      // We look for any shift that is pending OR in progress for this operator
      const { data, error } = await supabase
        .from('asset_assignments')
        .select('*, assets(*)')
        .eq('driver_id', currentUser)
        .in('status', ['pending_prestart', 'in_progress'])
        .maybeSingle();

      if (error) throw error;
      return data as (Assignment & { assets: Asset }) | null;
    },
    enabled: !!currentUser,
  });

  // 3. Realtime WebSocket for the operator
  useEffect(() => {
    if (!currentUser) return;
    const channel = supabase
      .channel('operator_realtime')
      .on(
        'postgres_changes',
        { 
          event: '*', 
          schema: 'public', 
          table: 'asset_assignments',
          filter: `driver_id=eq.${currentUser}` 
        },
        () => {
          queryClient.invalidateQueries({ queryKey: ['operator_assignment', currentUser] });
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [currentUser, queryClient]);

  // 4. Mutation to submit the pre-start via RPC
  const certifyMutation = useMutation({
    mutationFn: async (payload: {
      assignmentId: string;
      brakes: boolean;
      fluids: boolean;
      structural: boolean;
      isSafe: boolean;
      defectNotes: string | null;
    }) => {
      const { error } = await supabase.rpc('certify_prestart', {
        p_assignment_id: payload.assignmentId,
        p_brakes: payload.brakes,
        p_fluids: payload.fluids,
        p_structural: payload.structural,
        p_is_safe: payload.isSafe,
        p_defect_notes: payload.defectNotes,
      });

      if (error) throw error;
      return true;
    },
    onSuccess: (_, variables) => {
      if (variables.isSafe) {
        toast.success('Pre-Start Certified. Asset is safe to operate.');
      } else {
        toast.error('Defect Reported. Asset locked out. Please return keys to Dispatch.');
      }
      queryClient.invalidateQueries({ queryKey: ['operator_assignment', currentUser] });
    },
    onError: (err: any) => {
      toast.error(`Certification failed: ${err.message}`);
    },
  });

  if (isLoading) {
    return (
      <div className="h-screen w-full flex items-center justify-center bg-slate-950 text-slate-400 font-mono text-xl">
        SYNCING ASSET DATA...
      </div>
    );
  }

  if (!activeAssignment) {
    return (
      <div className="h-screen w-full flex items-center justify-center bg-slate-950 text-slate-400 p-6 text-center">
        <div>
          <div className="text-6xl mb-4 text-emerald-900/50">☕</div>
          <h1 className="text-3xl font-bold tracking-tight text-slate-100 mb-2">No Active Shifts</h1>
          <p className="text-xl">You do not have any pending or active asset assignments.</p>
          <p className="text-sm mt-4 font-mono opacity-50">WAITING FOR DISPATCHER...</p>
        </div>
      </div>
    );
  }

  if (activeAssignment.status === 'in_progress') {
    return (
      <div className="h-screen w-full flex flex-col items-center justify-center bg-emerald-950 text-emerald-50 p-6 text-center">
        <div className="text-6xl mb-6">✅</div>
        <h1 className="text-4xl font-bold tracking-tight mb-2">Pre-Start Complete</h1>
        <p className="text-2xl font-mono text-emerald-400">
          OPERATING ASSET: {activeAssignment.assets.internal_code}
        </p>
        <p className="mt-8 text-emerald-600 font-mono text-sm uppercase tracking-widest">
          Drive Safely. The WHS Fatigue Guardian is active.
        </p>
      </div>
    );
  }

  // 5. Trigger server-side clock when entering pending_prestart
  useEffect(() => {
    if (activeAssignment?.status === 'pending_prestart') {
      supabase.rpc('mark_prestart_commenced', { 
        p_assignment_id: activeAssignment.id 
      });
    }
  }, [activeAssignment?.status, activeAssignment?.id]);

  // Si está en pending_prestart, mostramos el kiosco interactivo
  return (
    <PrestartKioskPresenter
      assetCode={activeAssignment.assets.internal_code}
      onCertify={() => certifyMutation.mutate({
        assignmentId: activeAssignment.id,
        brakes: true,
        fluids: true,
        structural: true,
        isSafe: true,
        defectNotes: null,
      })}
      onReportDefect={(defectNotes) => certifyMutation.mutate({
        assignmentId: activeAssignment.id,
        brakes: false,
        fluids: false,
        structural: false,
        isSafe: false,
        defectNotes,
      })}
      isPending={certifyMutation.isPending}
    />
  );
};

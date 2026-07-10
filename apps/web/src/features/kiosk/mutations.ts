import { useMutation } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';

export const useJoinJitQueue = () => {
    return useMutation({
        networkMode: 'offlineFirst', // Persistencia Offline Outbox
        mutationFn: async (assetId: string) => {
            const { error } = await supabase.rpc('join_jit_queue', {
                p_asset_id: assetId
            });
            if (error) throw error;
        }
    });
};

export const useLeaveJitQueue = () => {
    return useMutation({
        networkMode: 'offlineFirst',
        mutationFn: async (assetId: string) => {
            const { error } = await supabase.rpc('leave_jit_queue', {
                p_asset_id: assetId
            });
            if (error) throw error;
        }
    });
};

export const useSubmitPassiveTelemetry = () => {
    return useMutation({
        networkMode: 'offlineFirst',
        mutationFn: async (telemetryLog: any) => {
            let recorded_by = telemetryLog.recorded_by;
            if (!recorded_by) {
                const { data } = await supabase.auth.getUser();
                recorded_by = data.user?.id;
            }
            if (!recorded_by) return; // Silent discard if not authenticated

            const { error } = await supabase.from('telemetry_inbox').insert({
                asset_id: telemetryLog.asset_id,
                recorded_by,
                payload: telemetryLog.payload,
                client_timestamp: telemetryLog.client_timestamp
            });
            if (error) throw error;
        }
    });
};

export interface ShiftManifestPayload {
    project_id: string;
    asset_id: string;
    operator_id: string;
    shift_start_time: string;
    shift_end_time: string;
    total_tonnage: number;
    total_cycles: number;
    fatigue_alerts_count: number;
    mechanic_overrides_count: number;
}

export const useSubmitManifest = () => {
    return useMutation({
        networkMode: 'offlineFirst',
        mutationFn: async (manifest: ShiftManifestPayload) => {
            const { error } = await supabase.from('webhook_events').insert({
                event_type: 'end_of_shift_manifest',
                payload: manifest as any
            });
            if (error) throw error;
        }
    });
};

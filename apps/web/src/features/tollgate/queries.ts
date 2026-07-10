import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';
import { useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';

export interface InTransitCycle {
    id: string;
    asset_id: string;
    material_type: string;
    transit_started_at: string;
    geological_block: string | null;
    assets: {
        asset_code: string;
    };
}

export const useInTransitCycles = (projectId: string) => {
    const queryClient = useQueryClient();

    // Data Fetching
    const query = useQuery({
        queryKey: ['in_transit_cycles', projectId],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('load_cycles')
                .select(`
                    id,
                    asset_id,
                    material_type,
                    transit_started_at,
                    geological_block,
                    assets ( asset_code )
                `)
                .eq('project_id', projectId)
                .eq('status', 'in_transit')
                .order('transit_started_at', { ascending: true });

            if (error) throw error;
            return data as InTransitCycle[];
        },
        staleTime: 1000 * 60, // 1 minute (realtime updates will invalidate)
    });

    // Supabase Realtime Subscription for Live Radar
    useEffect(() => {
        if (!projectId) return;

        const channel = supabase.channel(`tollgate-radar-${projectId}`)
            .on(
                'postgres_changes',
                {
                    event: '*',
                    schema: 'public',
                    table: 'load_cycles',
                    filter: `project_id=eq.${projectId}`
                },
                (payload) => {
                    // Si un camión entra en tránsito o se reconcilia, invalidamos el radar
                    // para forzar un re-fetch fresco y ordenado
                    queryClient.invalidateQueries({ queryKey: ['in_transit_cycles', projectId] });
                }
            )
            .subscribe();

        return () => {
            supabase.removeChannel(channel);
        };
    }, [projectId, queryClient]);

    return query;
};

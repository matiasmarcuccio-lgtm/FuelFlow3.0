import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';
import { useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';

export interface ActiveDefect {
    id: string;
    asset_id: string;
    defect_description: string;
    reported_at: string;
    assets: {
        asset_code: string;
        asset_type: string;
    };
}

export const useActiveDefects = (projectId: string) => {
    const queryClient = useQueryClient();

    const query = useQuery({
        queryKey: ['active_defects', projectId],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('plant_defects')
                .select(`
                    id,
                    asset_id,
                    defect_description,
                    reported_at,
                    assets ( asset_code, asset_type )
                `)
                .eq('project_id', projectId)
                .eq('status', 'reported')
                .order('reported_at', { ascending: false });

            if (error) throw error;
            return data as ActiveDefect[];
        },
        staleTime: 1000 * 60, // 1 minute
    });

    // Supabase Realtime Subscription para el Triaje Board
    useEffect(() => {
        if (!projectId) return;

        const channel = supabase.channel(`diagnostics-triage-${projectId}`)
            .on(
                'postgres_changes',
                {
                    event: '*',
                    schema: 'public',
                    table: 'plant_defects',
                    filter: `project_id=eq.${projectId}`
                },
                () => {
                    // Refrescar el board si un operador reporta un defecto o si se rectifica
                    queryClient.invalidateQueries({ queryKey: ['active_defects', projectId] });
                }
            )
            .subscribe();

        return () => {
            supabase.removeChannel(channel);
        };
    }, [projectId, queryClient]);

    return query;
};

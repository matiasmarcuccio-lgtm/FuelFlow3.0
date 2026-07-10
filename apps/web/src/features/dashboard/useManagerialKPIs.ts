import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';

export const useManagerialKPIs = (projectId: string, daysLookback = 7) => {
    // Calcular fecha de corte
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - daysLookback);

    return useQuery({
        queryKey: ['managerial_kpis', projectId, daysLookback],
        queryFn: async () => {
            const [efficiency, production, downtime] = await Promise.all([
                supabase.from('secure_daily_cycle_efficiency').select('*').eq('project_id', projectId).gte('date', cutoffDate.toISOString().split('T')[0]),
                supabase.from('secure_daily_production_tonnage').select('*').eq('project_id', projectId).gte('date', cutoffDate.toISOString().split('T')[0]),
                supabase.from('secure_daily_fleet_downtime').select('*').eq('project_id', projectId).gte('date', cutoffDate.toISOString().split('T')[0])
            ]);

            return {
                efficiency: efficiency.data || [],
                production: production.data || [],
                downtime: downtime.data || []
            };
        },
        staleTime: 1000 * 60 * 5, // 5 minutos de caché en el cliente
    });
};

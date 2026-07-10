import React, { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';
import { WeighbridgeUI } from './WeighbridgeUI';
import { toast } from 'sonner';

interface WeighbridgeContainerProps {
    projectId: string;
}

export const WeighbridgeContainer: React.FC<WeighbridgeContainerProps> = ({ projectId }) => {
    const queryClient = useQueryClient();
    const [selectedCycleId, setSelectedCycleId] = useState<string | null>(null);

    // Fetch in_transit load cycles
    const { data: loadCycles, isLoading } = useQuery({
        queryKey: ['load_cycles', 'in_transit', projectId],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('load_cycles')
                .select(`
                    id, 
                    status, 
                    transit_started_at,
                    material_type,
                    assets ( id, label )
                `)
                .eq('project_id', projectId)
                .eq('status', 'in_transit')
                .order('transit_started_at', { ascending: true });
                
            if (error) throw error;
            return data;
        },
        refetchInterval: 30000 // Polling backup
    });

    // Realtime subscription for load cycles
    useEffect(() => {
        const channel = supabase.channel(`public:load_cycles:${projectId}`)
            .on('postgres_changes', { 
                event: '*', 
                schema: 'public', 
                table: 'load_cycles',
                filter: `project_id=eq.${projectId}`
            }, (payload) => {
                queryClient.invalidateQueries({ queryKey: ['load_cycles', 'in_transit', projectId] });
                
                // Active cleanup for ghost states (Rule 5)
                if (payload.eventType === 'UPDATE' && payload.new.status !== 'in_transit' && payload.new.id === selectedCycleId) {
                    setSelectedCycleId(null);
                    toast.warning('El ciclo de carga fue abortado o cerrado remotamente.');
                }
                if (payload.eventType === 'DELETE' && payload.old.id === selectedCycleId) {
                    setSelectedCycleId(null);
                }
            })
            .subscribe();

        return () => {
            supabase.removeChannel(channel);
        };
    }, [projectId, queryClient, selectedCycleId]);

    // Zero-Trust UI Mutation (Rule 3)
    const handleSubmitWeight = async (cycleId: string, grossWeight: number, tareWeight: number) => {
        // Optimistic UX feedback
        toast.promise(
            supabase.from('load_cycles').update({
                gross_weight: grossWeight,
                tare_weight: tareWeight,
                status: 'dumped',
                completed_at: new Date().toISOString()
            }).eq('id', cycleId).select(),
            {
                loading: 'Registrando tonelaje de forma inmutable...',
                success: (data) => {
                    if (data.error) throw data.error;
                    setSelectedCycleId(null);
                    return '✅ Docket Digital cerrado exitosamente (CoR Compliant).';
                },
                error: (err) => {
                    console.error(err);
                    return '❌ Error de red o permisos RLS insuficientes. Los datos se retienen.';
                }
            }
        );
    };

    return (
        <WeighbridgeUI 
            cycles={loadCycles || []} 
            isLoading={isLoading} 
            selectedCycleId={selectedCycleId}
            onSelectCycle={setSelectedCycleId}
            onSubmitWeight={handleSubmitWeight}
        />
    );
};

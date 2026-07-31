import { useEffect } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import { toast } from 'sonner';
import { JITQueueSidebarPresenter } from './JITQueueSidebarPresenter';

interface JITQueueSidebarProps {
    projectId: string;
}

export const JITQueueSidebar: React.FC<JITQueueSidebarProps> = ({ projectId }) => {
    const queryClient = useQueryClient();
    const navigate = useNavigate();

    // 1. Fetch de la Tabla de Estado Activa
    const { data: queue, isLoading } = useQuery({
        queryKey: ['jit_queue', projectId],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('jit_active_queues')
                .select(`
                    id, 
                    joined_queue_at, 
                    status,
                    assets ( id, internal_code, category )
                `)
                .eq('project_id', projectId)
                .eq('status', 'waiting')
                .order('joined_queue_at', { ascending: true });
                
            if (error) throw error;
            return data;
        },
        refetchInterval: 60000 // Polling de backup cada minuto
    });

    // 2. Suscripción Reactiva de Baja Frecuencia
    useEffect(() => {
        const channel = supabase.channel(`public:jit_active_queues:${projectId}`)
            .on('postgres_changes', { 
                event: '*', 
                schema: 'public', 
                table: 'jit_active_queues',
                filter: `project_id=eq.${projectId}`
            }, () => {
                // Invalidar caché para forzar un re-fetch en el hilo principal
                queryClient.invalidateQueries({ queryKey: ['jit_queue', projectId] });
            })
            .subscribe();

        return () => {
            supabase.removeChannel(channel);
        };
    }, [projectId, queryClient]);

    const handleDispatch = (id: string, assetLabel: string) => {
        toast.info(`Iniciando despacho manual para ${assetLabel}...`);
        supabase
            .from('jit_active_queues')
            .update({ status: 'dispatched' })
            .eq('id', id)
            .then(({ error }) => {
                if (error) toast.error('Error al despachar');
            });
    };

    return (
        <JITQueueSidebarPresenter 
            queue={queue || []} 
            isLoading={isLoading} 
            onDispatch={handleDispatch} 
            onNewDispatch={() => navigate('/fleet')}
        />
    );
};

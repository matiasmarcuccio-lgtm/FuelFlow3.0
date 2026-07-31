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

    const { data: masterOrders } = useQuery({
        queryKey: ['master_orders'],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('master_orders')
                .select('id, material_type')
                .eq('status', 'OPEN');
            if (error) throw error;
            return data;
        }
    });

    const { data: drivers } = useQuery({
        queryKey: ['drivers'],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('profiles')
                .select('id, full_name')
                .eq('role', 'driver');
            if (error) throw error;
            return data;
        }
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

    const handleDispatch = async (queueId: string, assetId: string, driverId: string, orderId: string, assetLabel: string) => {
        toast.info(`Iniciando despacho táctico para ${assetLabel}...`);
        
        try {
            const { data, error } = await supabase.rpc('fn_dispatch_shift', {
                p_master_order_id: orderId,
                p_driver_id: driverId,
                p_asset_id: assetId
            });

            if (error) {
                // El Frontend escupirá el error WHS exacto si la máquina está en MAINTENANCE
                throw new Error(error.message);
            }

            // Si el RPC pasa, liberamos el camión de la cola local
            await supabase
                .from('jit_active_queues')
                .update({ status: 'dispatched' })
                .eq('id', queueId);

            toast.success(`Despacho asignado (Turno: ${data})`);
            queryClient.invalidateQueries({ queryKey: ['jit_queue', projectId] });
        } catch (err: any) {
            toast.error(err.message || 'Error durante el despacho');
        }
    };

    return (
        <JITQueueSidebarPresenter 
            queue={queue || []} 
            isLoading={isLoading}
            drivers={drivers || []}
            masterOrders={masterOrders || []}
            onDispatch={handleDispatch} 
            onNewDispatch={() => navigate('/fleet')}
        />
    );
};

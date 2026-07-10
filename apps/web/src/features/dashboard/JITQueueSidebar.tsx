import React, { useEffect } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';
import { Clock, Truck, Play } from 'lucide-react';
import { toast } from 'sonner';

interface JITQueueSidebarProps {
    projectId: string;
}

export const JITQueueSidebar: React.FC<JITQueueSidebarProps> = ({ projectId }) => {
    const queryClient = useQueryClient();

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
                    assets ( id, label, category )
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

    return (
        <div className="w-96 bg-background border-l border-outline-variant flex flex-col h-full z-10 relative shadow-2xl">
            <div className="p-6 border-b border-outline-variant bg-slate-950">
                <h2 className="text-2xl font-black text-foreground uppercase tracking-wider flex items-center gap-3">
                    <Truck className="text-primary" />
                    JIT Queue
                </h2>
                <p className="text-on-surface-variant text-sm mt-2 font-medium">Asignación FIFO en Tiempo Real</p>
            </div>

            <div className="flex-1 overflow-y-auto p-4 space-y-3">
                {isLoading && (
                    <div className="animate-pulse flex space-x-4">
                        <div className="flex-1 space-y-4 py-1">
                            <div className="h-20 bg-surface border border-outline-variant shadow-sm rounded"></div>
                            <div className="h-20 bg-surface border border-outline-variant shadow-sm rounded"></div>
                        </div>
                    </div>
                )}
                
                {queue?.length === 0 && (
                    <div className="text-center p-8 text-outline font-bold border-2 border-dashed border-outline-variant rounded-xl">
                        NO HAY VEHÍCULOS EN ESPERA
                    </div>
                )}

                {queue?.map((item, index) => {
                    const waitTimeMs = Date.now() - new Date(item.joined_queue_at).getTime();
                    const waitTimeMins = Math.floor(waitTimeMs / 60000);
                    const isStagnant = waitTimeMins >= 15;
                    
                    const assetLabel = (item.assets as any)?.label || 'Camión';

                    return (
                        <div 
                            key={item.id} 
                            className={`p-4 rounded-xl border-l-4 shadow-lg transition-all hover:-translate-y-1 hover:shadow-2xl ${
                                index === 0 
                                    ? 'bg-gradient-to-r from-blue-900/50 to-slate-800 border-blue-500 hover:border-blue-400' 
                                    : isStagnant 
                                        ? 'bg-gradient-to-r from-red-950 to-slate-900 border-red-500 shadow-[0_0_15px_rgba(239,68,68,0.2)]'
                                        : 'bg-surface border border-outline-variant shadow-sm/40 border-outline-variant hover:bg-surface border border-outline-variant shadow-sm/60'
                            } backdrop-blur-md relative overflow-hidden`}
                        >
                            {/* Glowing overlay for first item */}
                            {index === 0 && <div className="absolute top-0 left-0 w-1 h-full bg-primary text-on-primary shadow-[0_0_20px_5px_rgba(59,130,246,0.5)]"></div>}
                            
                            <div className="flex justify-between items-start mb-2 relative z-10">
                                <span className="font-bold text-lg text-foreground">#{index + 1} {assetLabel}</span>
                                {index === 0 && (
                                    <button 
                                        onClick={() => {
                                            toast.info(`Iniciando despacho manual para ${assetLabel}...`);
                                            // In a real scenario, this would call an RPC or update the queue row
                                            supabase
                                                .from('jit_active_queues')
                                                .update({ status: 'dispatched' })
                                                .eq('id', item.id)
                                                .then(({ error }) => {
                                                    if (error) toast.error('Error al despachar');
                                                });
                                        }}
                                        className="bg-primary text-on-primary hover:bg-primary text-on-primary transition-colors text-white text-xs font-black px-3 py-1.5 rounded uppercase flex items-center gap-2 shadow-[0_0_15px_rgba(59,130,246,0.5)]"
                                    >
                                        <Play size={12} fill="currentColor" /> Despachar
                                    </button>
                                )}
                            </div>
                            
                            <div className={`flex items-center gap-2 text-sm font-medium ${isStagnant ? 'text-red-400' : 'text-amber-500'}`}>
                                <Clock size={16} />
                                {waitTimeMins} min en espera
                            </div>
                        </div>
                    );
                })}
            </div>
        </div>
    );
};

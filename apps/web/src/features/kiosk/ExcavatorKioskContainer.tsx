import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { toast } from 'sonner';

interface ExcavatorState {
    operational_status: 'ready_to_load' | 'relocating' | 'rock_breaking' | 'standby';
    current_material: string;
    geological_block: string;
}

export const ExcavatorKioskContainer = ({ assetId }: { assetId: string }) => {
    const [state, setState] = useState<ExcavatorState | null>(null);
    const [isMutating, setIsMutating] = useState(false);

    useEffect(() => {
        // Fetch initial state
        const fetchState = async () => {
            const { data } = await supabase
                .from('excavator_states')
                .select('*')
                .eq('asset_id', assetId)
                .single();
            if (data) setState(data as ExcavatorState);
        };
        fetchState();

        // Suscripción en tiempo real a su propio estado operativo
        const channel = supabase.channel(`item:excavator_state:${assetId}`)
            .on('postgres_changes', { 
                event: 'UPDATE', 
                schema: 'public', 
                table: 'excavator_states',
                filter: `asset_id=eq.${assetId}`
            }, (payload) => {
                setState(payload.new as ExcavatorState);
            })
            .subscribe();

        return () => { supabase.removeChannel(channel); };
    }, [assetId]);

    const updateExcavatorPayload = async (updates: Partial<ExcavatorState>) => {
        setIsMutating(true);
        try {
            const { error } = await supabase
                .from('excavator_states')
                .update(updates)
                .eq('asset_id', assetId);

            if (error) throw error;
            navigator.vibrate?.(100); // Feedback háptico industrial
        } catch (err) {
            toast.error('Fallo de consistencia: Estado operativo no sincronizado');
        } finally {
            setIsMutating(false);
        }
    };

    if (!state) return <div className="bg-black w-screen h-screen flex items-center justify-center text-foreground"><span className="animate-pulse">Synchronizing Nodo de Origen...</span></div>;

    return (
        <div className="w-screen h-screen bg-neutral-950 p-6 flex flex-col justify-between text-foreground select-none">
            {/* Cabecera de Control Geológico */}
            <div className="flex justify-between items-center border-b border-neutral-800 pb-4">
                <div className="font-mono">
                    <p className="text-sm text-neutral-500">EXCAVATOR NODE ACTIVE</p>
                    <h2 className="text-xl font-bold tracking-tight text-neutral-300">BLOCK_ID: {state.geological_block || 'UNZONED'}</h2>
                </div>
                <div className="flex items-center gap-3">
                    <span className={`h-4 w-4 rounded-full animate-pulse ${state.operational_status === 'ready_to_load' ? 'bg-emerald-500' : 'bg-amber-500'}`} />
                    <span className="font-mono text-sm tracking-widest uppercase">{state.operational_status.replace('_', ' ')}</span>
                </div>
            </div>

            {/* Matriz de Selección Táctica de Materiales */}
            <div className="grid grid-cols-3 gap-4 my-6 flex-1">
                {[
                    { name: 'Topsoil', color: 'border-orange-900 bg-orange-950/20 text-orange-400' },
                    { name: 'Type 1 Fill', color: 'border-blue-900 bg-blue-950/20 text-primary' },
                    { name: 'Hard Rock', color: 'border-purple-900 bg-purple-950/20 text-purple-400' }
                ].map((material) => (
                    <button
                        key={material.name}
                        disabled={isMutating}
                        onClick={() => updateExcavatorPayload({ current_material: material.name })}
                        className={`border-4 rounded-2xl flex flex-col items-center justify-center p-6 active:scale-95 transition-all ${
                            state.current_material === material.name 
                                ? `${material.color} border-white ring-4 ring-offset-4 ring-offset-black ring-white` 
                                : 'border-neutral-800 bg-neutral-900/40 text-neutral-500 hover:bg-neutral-800/40'
                        }`}
                    >
                        <span className="text-3xl font-black tracking-tight uppercase">{material.name}</span>
                    </button>
                ))}
            </div>

            {/* Semáforo del Despacho JIT (Controles de Flujo) */}
            <div className="grid grid-cols-2 gap-4 border-t border-neutral-800 pt-4">
                <button
                    disabled={isMutating || state.operational_status === 'ready_to_load'}
                    onClick={() => updateExcavatorPayload({ operational_status: 'ready_to_load' })}
                    className={`p-6 rounded-2xl font-black text-2xl tracking-wider uppercase border-4 transition-all ${
                        state.operational_status === 'ready_to_load'
                            ? 'bg-emerald-600 border-emerald-400 text-white shadow-[0_0_30px_rgba(16,185,129,0.3)]'
                            : 'bg-neutral-900 border-neutral-800 text-neutral-600 hover:bg-neutral-800'
                    }`}
                >
                    LLAMAR CAMIÓN (READY)
                </button>
                <button
                    disabled={isMutating || state.operational_status === 'relocating'}
                    onClick={() => updateExcavatorPayload({ operational_status: 'relocating' })}
                    className={`p-6 rounded-2xl font-black text-2xl tracking-wider uppercase border-4 transition-all ${
                        state.operational_status === 'relocating'
                            ? 'bg-amber-600 border-amber-400 text-white shadow-[0_0_30px_rgba(245,158,11,0.3)]'
                            : 'bg-neutral-900 border-neutral-800 text-neutral-600 hover:bg-neutral-800'
                    }`}
                >
                    MOVIENDO FRENTE (PAUSA JIT)
                </button>
            </div>
        </div>
    );
};

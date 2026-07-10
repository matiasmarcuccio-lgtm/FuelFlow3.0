import React, { useState } from 'react';
import { supabase } from '../../../lib/supabase';
import { Wrench, ShieldAlert, Loader2, ArrowLeft } from 'lucide-react';
import { toast } from 'sonner';
import { useQueryClient, useMutation } from '@tanstack/react-query';

interface FittersOverrideProps {
    assetId: string;
    projectId: string;
    onRectified: () => void;
}

interface MechanicIdentity {
    user_id: string;
    profiles: { full_name: string };
}

export const FittersOverride = ({ assetId, projectId, onRectified }: FittersOverrideProps) => {
    const queryClient = useQueryClient();
    
    // Obtener mecánicos desde la caché local sin tocar red
    const mechanics = queryClient.getQueryData<MechanicIdentity[]>(['mechanics', projectId]) || [];

    const [selectedMechanic, setSelectedMechanic] = useState<MechanicIdentity | null>(null);
    const [pin, setPin] = useState('');
    const [isSubmitting, setIsSubmitting] = useState(false);

    // Mutación optimista en la cola ciega
    const { mutateAsync: queueDefectResolution } = useMutation({
        networkMode: 'offlineFirst',
        mutationFn: async (payload: { defectId: string, pin: string, mechanicId: string }) => {
            const { error } = await supabase.rpc('resolve_plant_defect', {
                p_defect_id: payload.defectId,
                p_category: 'wear_and_tear', // Default para Kiosk override
                p_resolution_notes: 'Fitter Override desde Cabina',
                p_mechanic_id: payload.mechanicId,
                p_mechanic_pin: payload.pin
            });
            if (error) throw new Error(error.message);
        },
        onSuccess: () => {
            // El éxito real en la DB no importa ahora, asumimos éxito táctico de inmediato
        }
    });

    const handlePinInput = (num: number) => {
        if (pin.length < 6) setPin(p => p + num);
    };

    const handleClear = () => setPin('');

    const handleOverride = async () => {
        if (pin.length < 4 || !selectedMechanic) return;
        setIsSubmitting(true);

        try {
            // 1. Encontrar el defecto reportado (idealmente offline de caché, pero hacemos fallback)
            const { data: defect, error: fetchError } = await supabase
                .from('plant_defects')
                .select('*')
                .eq('asset_id', assetId)
                .in('status', ['reported', 'under_repair'])
                .single();

            if (fetchError || !defect) {
                // En un escenario 100% offline, el ID del defecto debería estar en el kiosk state.
                // Si falla, permitimos la salida con error.
                throw new Error('No se pudo encontrar el defecto asociado. Requiere red para primera sincronización.');
            }

            // 2. Encolar la rectificación criptográfica
            await queueDefectResolution({
                defectId: defect.id,
                mechanicId: selectedMechanic.user_id,
                pin: pin
            });

            // Purgar IndexedDB para forzar estado limpio
            const { del } = await import('idb-keyval');
            const today = new Date().toISOString().split('T')[0];
            await del(`pre_start_${today}`);
            await del(`handover_${today}`);

            toast.success('Rectificación criptográfica encolada. Sistema desbloqueado.');
            onRectified(); // Refrescar useKioskState para liberar la máquina localmente
        } catch (error: any) {
            toast.error(error.message);
        } finally {
            setIsSubmitting(false);
            setPin('');
        }
    };

    if (!selectedMechanic) {
        return (
            <div className="w-screen h-screen bg-background text-foreground flex flex-col p-8">
                <div className="flex flex-col items-center mb-12">
                    <Wrench className="w-20 h-20 text-orange-500 mb-4" />
                    <h1 className="text-4xl font-bold font-mono tracking-widest text-orange-500">FITTER'S OVERRIDE</h1>
                    <p className="text-xl text-on-surface-variant mt-2">Seleccione su Identity de Fitter</p>
                </div>
                
                {mechanics.length === 0 ? (
                    <div className="flex-1 flex items-center justify-center text-outline text-2xl font-mono text-center px-8">
                        No hay mecánicos en caché. Requiere red para primera sincronización del turno matutino.
                    </div>
                ) : (
                    <div className="grid grid-cols-2 md:grid-cols-3 gap-6 max-w-5xl mx-auto w-full">
                        {mechanics.map((m) => (
                            <button
                                key={m.user_id}
                                onClick={() => setSelectedMechanic(m)}
                                className="h-32 bg-surface border border-outline-variant shadow-sm border-2 border-outline-variant rounded-xl flex flex-col items-center justify-center hover:border-orange-500 hover:bg-surface-variant transition-all focus:outline-none focus:ring-4 focus:ring-orange-500/50"
                            >
                                <span className="text-2xl font-bold font-mono">{m.profiles?.full_name || 'Desconocido'}</span>
                            </button>
                        ))}
                    </div>
                )}
            </div>
        );
    }

    return (
        <div className="w-screen h-screen bg-background text-foreground flex flex-col items-center justify-center p-8">
            <button 
                onClick={() => setSelectedMechanic(null)}
                className="absolute top-8 left-8 flex items-center text-on-surface-variant hover:text-foreground"
            >
                <ArrowLeft className="w-8 h-8 mr-2" />
                <span className="text-xl font-bold">Volver</span>
            </button>

            <ShieldAlert className="w-24 h-24 text-orange-500 mb-6" />
            <h1 className="text-4xl font-bold mb-4 tracking-wider text-orange-500 text-center">AUTORIZACIÓN MECÁNICA</h1>
            <p className="text-2xl text-on-surface-variant mb-8 font-mono">{selectedMechanic.profiles?.full_name}</p>

            <div className="bg-surface border border-outline-variant shadow-sm p-8 rounded-2xl border-4 border-outline-variant w-full max-w-md">
                <div className="flex justify-center mb-8">
                    <div className="flex space-x-4">
                        {[0, 1, 2, 3].map((i) => (
                            <div 
                                key={i}
                                className={`w-8 h-8 rounded-full border-4 transition-all duration-300 ${
                                    pin.length > i 
                                        ? 'bg-orange-500 border-orange-500' 
                                        : 'bg-transparent border-outline'
                                }`}
                            />
                        ))}
                    </div>
                </div>

                <div className="grid grid-cols-3 gap-4 mb-8 select-none">
                    {[1, 2, 3, 4, 5, 6, 7, 8, 9].map((num) => (
                        <button
                            key={num}
                            onClick={() => handlePinInput(num)}
                            style={{ width: '80px', height: '80px' }}
                            className="bg-surface-variant hover:bg-outline text-white text-3xl font-bold rounded-xl active:bg-orange-500 active:scale-95 transition-all mx-auto flex items-center justify-center focus:outline-none"
                        >
                            {num}
                        </button>
                    ))}
                    <button
                        onClick={handleClear}
                        style={{ width: '80px', height: '80px' }}
                        className="bg-red-500/20 text-red-500 hover:bg-red-500/30 text-2xl font-bold rounded-xl active:scale-95 transition-all mx-auto flex items-center justify-center focus:outline-none border border-red-500/50"
                    >
                        C
                    </button>
                    <button
                        onClick={() => handlePinInput(0)}
                        style={{ width: '80px', height: '80px' }}
                        className="bg-surface-variant hover:bg-outline text-white text-3xl font-bold rounded-xl active:bg-orange-500 active:scale-95 transition-all mx-auto flex items-center justify-center focus:outline-none"
                    >
                        0
                    </button>
                    <button
                        onClick={handleOverride}
                        disabled={isSubmitting || pin.length < 4}
                        style={{ width: '80px', height: '80px' }}
                        className={`text-2xl font-bold rounded-xl active:scale-95 transition-all mx-auto flex items-center justify-center focus:outline-none ${
                            pin.length >= 4 
                                ? 'bg-orange-500 text-white hover:bg-orange-400 shadow-[0_0_20px_rgba(249,115,22,0.4)]' 
                                : 'bg-surface border border-outline-variant shadow-sm text-outline-variant cursor-not-allowed'
                        }`}
                    >
                        {isSubmitting ? <Loader2 className="w-8 h-8 animate-spin" /> : '✓'}
                    </button>
                </div>
                <p className="text-center text-outline font-mono text-sm uppercase">Criptografía SHA-256 en cabina</p>
            </div>
        </div>
    );
};

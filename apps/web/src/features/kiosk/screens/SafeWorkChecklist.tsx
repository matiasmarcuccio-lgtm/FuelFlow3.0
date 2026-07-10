import { useState, useRef, useEffect } from 'react';
import { set } from 'idb-keyval';

import { supabase } from '../../../lib/supabase';

interface ChecklistItem {
    id: string;
    label: string;
}

const ITEMS: ChecklistItem[] = [
    { id: 'tires', label: 'Neumáticos y Presión' },
    { id: 'brakes', label: 'Frenos y Dirección' },
    { id: 'hydraulics', label: 'Fugas Hidráulicas' },
    { id: 'fluids', label: 'Niveles de Fluidos' }
];

interface SafeWorkChecklistProps {
    onComplete: () => void;
    projectId?: string;
    assetId?: string;
}

export const SafeWorkChecklist = ({ onComplete, projectId, assetId }: SafeWorkChecklistProps) => {
    const [currentIndex, setCurrentIndex] = useState(0);
    const [isHolding, setIsHolding] = useState(false);
    const [progress, setProgress] = useState(0);
    
    const startTimeRef = useRef<number>(Date.now());
    const holdTimerRef = useRef<NodeJS.Timeout | null>(null);
    const recordsRef = useRef<Array<{ item: string; status: string; timestamp: number }>>([]);
    const HOLD_DURATION_MS = 1200; // 1.2 segundos de fricción intencional

    const currentItem = ITEMS[currentIndex];

    // Lógica para mantener presionado (Hold to Pass)
    const startHold = () => {
        setIsHolding(true);
        setProgress(0);
        
        let start = Date.now();
        holdTimerRef.current = setInterval(() => {
            const elapsed = Date.now() - start;
            const percentage = Math.min((elapsed / HOLD_DURATION_MS) * 100, 100);
            setProgress(percentage);

            if (elapsed >= HOLD_DURATION_MS) {
                if (holdTimerRef.current) clearInterval(holdTimerRef.current);
                handlePass();
            }
        }, 50);
    };

    const stopHold = () => {
        setIsHolding(false);
        setProgress(0);
        if (holdTimerRef.current) {
            clearInterval(holdTimerRef.current);
            holdTimerRef.current = null;
        }
    };

    const handlePass = async () => {
        stopHold();
        recordsRef.current.push({
            item: currentItem.id,
            status: 'PASS',
            timestamp: Date.now()
        });

        if (currentIndex < ITEMS.length - 1) {
            setCurrentIndex(prev => prev + 1);
        } else {
            await finalizeChecklist('PASS');
        }
    };

    const handleFail = async () => {
        stopHold();
        recordsRef.current.push({
            item: currentItem.id,
            status: 'FAIL',
            timestamp: Date.now()
        });
        await finalizeChecklist('LOCKOUT');
    };

    const finalizeChecklist = async (status: 'PASS' | 'LOCKOUT') => {
        const today = new Date().toISOString().split('T')[0];
        const now = Date.now();
        
        const payload = {
            date: today,
            started_at: startTimeRef.current,
            completed_at: now,
            duration_seconds: Math.round((now - startTimeRef.current) / 1000),
            status,
            checklist: recordsRef.current
        };

        if (status === 'LOCKOUT' && projectId && assetId) {
            const { data: { user } } = await supabase.auth.getUser();
            if (user) {
                const failedItem = recordsRef.current.find(r => r.status === 'FAIL')?.item || 'unknown';
                await supabase.from('plant_defects').insert({
                    project_id: projectId,
                    asset_id: assetId,
                    reported_by: user.id,
                    defect_description: `Pre-Start Falló en comprobación: ${failedItem}`,
                    status: 'reported'
                });
            }
        }

        await set(`pre_start_${today}`, payload);
        
        // Forzamos la re-evaluación del Estado Derivado en useKioskState
        onComplete();
    };

    // Cleanup timers
    useEffect(() => {
        return () => stopHold();
    }, []);

    return (
        <div className="flex flex-col items-center justify-center h-screen bg-background text-foreground p-8">
            <div className="w-full max-w-2xl text-center space-y-12">
                
                <div className="space-y-4">
                    <h1 className="text-5xl font-black tracking-tight">PRE-START CHECK</h1>
                    <p className="text-on-surface-variant text-xl font-medium tracking-widest uppercase">
                        Paso {currentIndex + 1} de {ITEMS.length}
                    </p>
                </div>

                <div className="bg-surface border border-outline-variant shadow-sm p-12 rounded-3xl border border-outline-variant shadow-2xl">
                    <h2 className="text-4xl font-bold mb-4">{currentItem.label}</h2>
                    <p className="text-on-surface-variant text-lg">
                        Inspeccione visualmente y confirme el estado operativo.
                    </p>
                </div>

                <div className="grid grid-cols-2 gap-8 w-full mt-12">
                    <button 
                        onClick={handleFail}
                        className="h-32 text-2xl font-bold bg-red-600/10 text-red-500 border-2 border-red-600 rounded-2xl active:bg-red-600 active:text-white transition-colors"
                    >
                        Fallo Crítico
                    </button>

                    <button
                        onPointerDown={startHold}
                        onPointerUp={stopHold}
                        onPointerLeave={stopHold}
                        className="relative h-32 text-2xl font-bold bg-surface border border-outline-variant shadow-sm text-emerald-500 border-2 border-emerald-600 rounded-2xl overflow-hidden select-none touch-none"
                    >
                        <div 
                            className="absolute top-0 left-0 h-full bg-emerald-600/30 transition-all duration-75 ease-linear"
                            style={{ width: `${progress}%` }}
                        />
                        <span className="relative z-10 flex flex-col items-center justify-center">
                            {isHolding ? 'Mantenga Presionado...' : 'Mantener para Aprobar'}
                        </span>
                    </button>
                </div>

            </div>
        </div>
    );
};

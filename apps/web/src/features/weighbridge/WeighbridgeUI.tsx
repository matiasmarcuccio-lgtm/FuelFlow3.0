import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Truck, Scale, CheckCircle2, X } from 'lucide-react';
import { toast } from 'sonner';

export interface LoadCycle {
    id: string;
    status: string;
    transit_started_at: string;
    material_type: string;
    assets: {
        id: string;
        label: string;
    };
}

interface WeighbridgeUIProps {
    cycles: LoadCycle[];
    isLoading: boolean;
    selectedCycleId: string | null;
    onSelectCycle: (id: string | null) => void;
    onSubmitWeight: (id: string, gross: number, tare: number) => Promise<void>;
}

export const WeighbridgeUI: React.FC<WeighbridgeUIProps> = ({ 
    cycles, 
    isLoading, 
    selectedCycleId, 
    onSelectCycle, 
    onSubmitWeight 
}) => {
    // 5. Prevención de Estado Fantasma
    // Estado interno del formulario
    const [grossWeight, setGrossWeight] = useState<string>('');
    const [tareWeight, setTareWeight] = useState<string>('15.5'); // Tare by default
    const [isSubmitting, setIsSubmitting] = useState(false);

    // Clear estado fantasma si se deselecciona el ciclo
    useEffect(() => {
        if (!selectedCycleId) {
            setGrossWeight('');
            setIsSubmitting(false);
        }
    }, [selectedCycleId]);

    const selectedCycle = cycles.find(c => c.id === selectedCycleId);

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!selectedCycle) return;
        
        const gross = parseFloat(grossWeight);
        const tare = parseFloat(tareWeight);

        if (isNaN(gross) || isNaN(tare) || gross <= tare) {
            toast.error('El peso bruto debe ser un número mayor a la tara.');
            return;
        }

        setIsSubmitting(true);
        try {
            await onSubmitWeight(selectedCycle.id, gross, tare);
            // Si la promesa se resuelve pero la red falla (optimistic fallback), 
            // no limpiamos agresivamente si queremos retener datos. 
            // Pero en este caso, la limpieza ocurre cuando onSelectCycle se llama con null.
        } catch (error) {
            setIsSubmitting(false); // Retenemos datos en caso de error RLS/Red
        }
    };

    return (
        <div className="flex h-screen bg-slate-950 text-foreground overflow-hidden font-sans">
            {/* Sidebar con camiones en tránsito */}
            <div className="w-1/3 bg-background border-r border-outline-variant flex flex-col z-10 shadow-2xl">
                <div className="p-6 border-b border-outline-variant bg-slate-950">
                    <h1 className="text-2xl font-black uppercase tracking-wider flex items-center gap-3 text-emerald-400">
                        <Scale /> Weighbridge
                    </h1>
                    <p className="text-on-surface-variant text-sm mt-2">Dockets Pendientes (In Transit)</p>
                </div>
                
                <div className="flex-1 overflow-y-auto p-4 space-y-3">
                    {isLoading && <div className="text-outline animate-pulse p-4">Cargando telemetría...</div>}
                    {!isLoading && cycles.length === 0 && (
                        <div className="border-2 border-dashed border-outline-variant rounded-xl p-8 text-center text-outline font-bold">
                            NO HAY VEHÍCULOS EN TRÁNSITO
                        </div>
                    )}

                    <AnimatePresence>
                        {cycles.map((cycle) => (
                            <motion.div 
                                key={cycle.id} // 4. El Escrutinio del Ciclo de Vida (El Reciclaje del DOM)
                                layout
                                initial={{ opacity: 0, x: -20 }}
                                animate={{ opacity: 1, x: 0 }}
                                exit={{ opacity: 0, scale: 0.9 }}
                                onClick={() => onSelectCycle(cycle.id)}
                                className={`p-4 rounded-xl border-l-4 cursor-pointer transition-all ${
                                    selectedCycleId === cycle.id
                                        ? 'bg-emerald-900/30 border-emerald-500 shadow-[0_0_15px_rgba(16,185,129,0.2)]'
                                        : 'bg-surface border border-outline-variant shadow-sm/40 border-outline-variant hover:bg-surface border border-outline-variant shadow-sm/60'
                                }`}
                            >
                                <div className="flex items-center gap-3">
                                    <Truck className={selectedCycleId === cycle.id ? 'text-emerald-400' : 'text-on-surface-variant'} />
                                    <div>
                                        <h3 className="font-bold text-lg">{cycle.assets.label}</h3>
                                        <p className="text-xs text-on-surface-variant font-mono truncate">{cycle.material_type}</p>
                                    </div>
                                </div>
                            </motion.div>
                        ))}
                    </AnimatePresence>
                </div>
            </div>

            {/* Panel Principal de Pesaje */}
            <div className="flex-1 flex flex-col relative bg-slate-950">
                {selectedCycle ? (
                    <motion.div 
                        initial={{ opacity: 0, y: 20 }}
                        animate={{ opacity: 1, y: 0 }}
                        className="m-auto w-full max-w-2xl bg-background rounded-3xl p-8 border border-outline-variant shadow-2xl relative"
                    >
                        <button 
                            onClick={() => onSelectCycle(null)}
                            className="absolute top-6 right-6 text-outline hover:text-foreground transition-colors"
                        >
                            <X size={24} />
                        </button>

                        <div className="mb-8">
                            <h2 className="text-4xl font-black text-foreground mb-2">
                                {selectedCycle.assets.label}
                            </h2>
                            <span className="bg-emerald-500/20 text-emerald-400 px-3 py-1 rounded-full text-sm font-bold tracking-wide">
                                ARRIBADO
                            </span>
                        </div>

                        <form onSubmit={handleSubmit} className="space-y-6">
                            <div className="grid grid-cols-2 gap-6">
                                <div className="space-y-2">
                                    <label className="text-sm font-bold text-on-surface-variant uppercase tracking-wider">Tara (t)</label>
                                    <input 
                                        type="number" 
                                        step="0.01"
                                        value={tareWeight}
                                        onChange={(e) => setTareWeight(e.target.value)}
                                        className="w-full bg-slate-950 border border-outline-variant rounded-xl p-4 text-2xl font-mono text-on-surface focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500 outline-none transition-all"
                                        required
                                    />
                                </div>
                                <div className="space-y-2">
                                    <label className="text-sm font-bold text-emerald-400 uppercase tracking-wider">Peso Bruto (t)</label>
                                    <input 
                                        type="number" 
                                        step="0.01"
                                        value={grossWeight}
                                        onChange={(e) => setGrossWeight(e.target.value)}
                                        autoFocus
                                        className="w-full bg-emerald-950/20 border border-emerald-500/50 rounded-xl p-4 text-4xl font-mono text-white focus:border-emerald-400 focus:ring-2 focus:ring-emerald-400 outline-none transition-all shadow-inner"
                                        placeholder="0.00"
                                        required
                                    />
                                </div>
                            </div>

                            <div className="bg-slate-950 p-6 rounded-xl border border-outline-variant flex justify-between items-center">
                                <div>
                                    <p className="text-sm text-on-surface-variant uppercase font-bold tracking-wide mb-1">Masa Neta Calculada</p>
                                    <p className="text-3xl font-mono text-emerald-300">
                                        {grossWeight && !isNaN(parseFloat(grossWeight)) 
                                            ? Math.max(0, parseFloat(grossWeight) - parseFloat(tareWeight)).toFixed(2) 
                                            : '0.00'} t
                                    </p>
                                </div>
                                <div className="text-right">
                                    <p className="text-xs text-outline font-mono mb-1">Material</p>
                                    <p className="font-bold text-on-surface">{selectedCycle.material_type}</p>
                                </div>
                            </div>

                            <button 
                                type="submit" 
                                disabled={isSubmitting}
                                className="w-full bg-emerald-500 hover:bg-emerald-400 disabled:opacity-50 disabled:cursor-not-allowed text-slate-950 text-xl font-black p-5 rounded-xl uppercase tracking-widest transition-all shadow-[0_0_30px_rgba(16,185,129,0.3)] flex items-center justify-center gap-3"
                            >
                                {isSubmitting ? 'Sellando...' : 'Sellar Docket CoR'} <CheckCircle2 />
                            </button>
                        </form>
                    </motion.div>
                ) : (
                    <div className="m-auto text-center space-y-6">
                        <div className="inline-flex p-8 bg-background/50 rounded-full border-2 border-dashed border-outline-variant">
                            <Scale size={64} className="text-slate-700" />
                        </div>
                        <h2 className="text-2xl font-bold text-outline uppercase tracking-widest">
                            Esperando Vehicle
                        </h2>
                        <p className="text-outline-variant max-w-sm mx-auto">
                            Seleccione un camión de la cola lateral para registrar la masa estructural y generar el recibo digital.
                        </p>
                    </div>
                )}
            </div>
        </div>
    );
};

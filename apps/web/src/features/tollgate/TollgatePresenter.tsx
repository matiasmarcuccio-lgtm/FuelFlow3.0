import React, { useState, useEffect } from 'react';
import type { InTransitCycle } from './queries';
import { ShieldCheck, Truck, Clock, AlertTriangle, CheckCircle2 } from 'lucide-react';

interface TollgatePresenterProps {
    inTransitCycles: InTransitCycle[];
    onReconcile: (cycleId: string, gross: number, tare: number) => Promise<void>;
    isReconciling: boolean;
}

export const TollgatePresenter = ({ inTransitCycles, onReconcile, isReconciling }: TollgatePresenterProps) => {
    const [selectedCycleId, setSelectedCycleId] = useState<string | null>(null);
    const [grossWeightStr, setGrossWeightStr] = useState<string>('');
    const [tareWeightStr, setTareWeightStr] = useState<string>('');
    const [activeInput, setActiveInput] = useState<'gross' | 'tare'>('gross');
    const [successMsg, setSuccessMsg] = useState<string | null>(null);

    // Auto-select the first truck in the radar if none is selected
    useEffect(() => {
        if (inTransitCycles.length > 0 && !selectedCycleId) {
            setSelectedCycleId(inTransitCycles[0].id);
        } else if (inTransitCycles.length === 0) {
            setSelectedCycleId(null);
        }
    }, [inTransitCycles, selectedCycleId]);

    const handleKeypadPress = (val: string) => {
        if (val === 'C') {
            activeInput === 'gross' ? setGrossWeightStr('') : setTareWeightStr('');
            return;
        }
        
        const currentVal = activeInput === 'gross' ? grossWeightStr : tareWeightStr;
        // Limit string length to avoid overflow
        if (currentVal.length >= 6) return;

        if (val === '.') {
            if (!currentVal.includes('.')) {
                activeInput === 'gross' ? setGrossWeightStr(currentVal + val) : setTareWeightStr(currentVal + val);
            }
        } else {
            activeInput === 'gross' ? setGrossWeightStr(currentVal + val) : setTareWeightStr(currentVal + val);
        }
    };

    const handleCertify = async () => {
        if (!selectedCycleId) return;
        const gross = parseFloat(grossWeightStr);
        const tare = parseFloat(tareWeightStr);

        if (isNaN(gross) || isNaN(tare) || gross <= tare) {
            alert('Error Financiero: El peso bruto debe ser un número válido mayor a la tara.');
            return;
        }

        try {
            await onReconcile(selectedCycleId, gross, tare);
            setSuccessMsg('Ticket Reconciliado Exitosamente');
            setGrossWeightStr('');
            setTareWeightStr('');
            setActiveInput('gross');
            setTimeout(() => setSuccessMsg(null), 3000);
            
            // Auto-select next after a brief delay
            setTimeout(() => {
                 const remaining = inTransitCycles.filter(c => c.id !== selectedCycleId);
                 if (remaining.length > 0) setSelectedCycleId(remaining[0].id);
                 else setSelectedCycleId(null);
            }, 500);
        } catch (e: any) {
            alert('Fallo de Conciliación: ' + e.message);
        }
    };

    const selectedCycle = inTransitCycles.find(c => c.id === selectedCycleId);
    
    // Calcular tiempo en tránsito (simplificado para UI, normalmente requiere un tick local)
    const getMinutesInTransit = (isoStart: string) => {
        const diff = Date.now() - new Date(isoStart).getTime();
        return Math.floor(diff / 60000);
    };

    return (
        <div className="flex w-full h-full bg-black text-foreground font-sans overflow-hidden">
            {/* PANEL IZQUIERDO: RADAR DE APROXIMACIÓN (35%) */}
            <div className="w-[35%] border-r border-outline-variant bg-[#0f1115] flex flex-col">
                <div className="p-6 bg-background border-b border-outline-variant flex items-center justify-between">
                    <div>
                        <h2 className="text-xl font-bold tracking-tight text-foreground flex items-center gap-2">
                            <Truck className="text-primary" />
                            Radar de Próximos
                        </h2>
                        <p className="text-on-surface-variant text-sm mt-1 uppercase tracking-widest font-semibold">
                            {inTransitCycles.length} En Tránsito
                        </p>
                    </div>
                </div>

                <div className="flex-1 overflow-y-auto p-4 space-y-3">
                    {inTransitCycles.length === 0 ? (
                        <div className="h-full flex flex-col items-center justify-center text-outline-variant">
                            <MapPin className="w-12 h-12 mb-4 opacity-20" />
                            <p className="text-lg font-mono">RADAR DESPEJADO</p>
                        </div>
                    ) : (
                        inTransitCycles.map((cycle, idx) => {
                            const isSelected = selectedCycleId === cycle.id;
                            const mins = getMinutesInTransit(cycle.transit_started_at);
                            
                            return (
                                <button
                                    key={cycle.id}
                                    onClick={() => setSelectedCycleId(cycle.id)}
                                    className={`w-full text-left p-5 rounded-xl border-2 transition-all font-mono relative overflow-hidden ${
                                        isSelected 
                                            ? 'border-blue-500 bg-blue-900/20 shadow-[0_0_15px_rgba(59,130,246,0.15)]' 
                                            : 'border-outline-variant bg-background/50 hover:border-outline-variant'
                                    }`}
                                >
                                    {isSelected && <div className="absolute top-0 left-0 w-1 h-full bg-primary text-on-primary" />}
                                    
                                    <div className="flex justify-between items-start mb-3">
                                        <div className="flex items-center gap-2">
                                            <span className="bg-surface border border-outline-variant shadow-sm text-foreground px-2 py-1 rounded text-sm font-bold tracking-widest">
                                                {cycle.assets.asset_code}
                                            </span>
                                            {idx === 0 && (
                                                <span className="bg-orange-500/20 text-orange-400 px-2 py-1 rounded text-xs font-bold animate-pulse">
                                                    SIGUIENTE
                                                </span>
                                            )}
                                        </div>
                                        <div className={`flex items-center gap-1 text-sm ${mins > 15 ? 'text-red-400 font-bold' : 'text-on-surface-variant'}`}>
                                            <Clock className="w-4 h-4" />
                                            {mins}m
                                        </div>
                                    </div>
                                    <div className="text-xs text-outline uppercase tracking-widest truncate">
                                        {cycle.material_type}
                                    </div>
                                </button>
                            );
                        })
                    )}
                </div>
            </div>

            {/* PANEL DERECHO: ATM PAD MASIVO (65%) */}
            <div className="w-[65%] bg-slate-950 flex flex-col relative">
                {successMsg && (
                    <div className="absolute top-0 left-0 w-full bg-emerald-600 text-white text-center py-3 font-bold z-50 animate-in slide-in-from-top flex justify-center items-center gap-2">
                        <CheckCircle2 className="w-5 h-5" />
                        {successMsg}
                    </div>
                )}
                
                <div className="p-8 border-b border-slate-900 flex justify-between items-center bg-background/50">
                    <div>
                        <h1 className="text-3xl font-bold tracking-tight text-foreground flex items-center gap-3">
                            <ShieldCheck className="w-8 h-8 text-emerald-500" />
                            Aduana Forense
                        </h1>
                        <p className="text-on-surface-variant text-sm mt-1">Certificación Inmutable de Bascula</p>
                    </div>
                </div>

                {selectedCycle ? (
                    <div className="flex-1 p-8 flex flex-col lg:flex-row gap-12 items-start justify-center">
                        
                        {/* Formularios Gigantes */}
                        <div className="flex-1 w-full max-w-md space-y-8">
                            <div className="bg-background p-6 rounded-2xl border border-outline-variant">
                                <h3 className="text-outline text-sm font-bold uppercase tracking-widest mb-4">Vehicle en Weighbridge</h3>
                                <div className="text-4xl font-mono font-bold text-foreground mb-2">{selectedCycle.assets.asset_code}</div>
                                <div className="text-emerald-400 font-mono">{selectedCycle.material_type}</div>
                            </div>

                            <div className="space-y-6">
                                <div 
                                    onClick={() => setActiveInput('gross')}
                                    className={`bg-black p-4 rounded-xl border-2 cursor-pointer transition-colors ${activeInput === 'gross' ? 'border-blue-500 shadow-[0_0_15px_rgba(59,130,246,0.2)]' : 'border-outline-variant'}`}
                                >
                                    <label className="text-on-surface-variant text-sm font-bold uppercase tracking-widest block mb-2">Peso Bruto (T)</label>
                                    <div className="text-5xl font-mono font-bold text-foreground h-12 flex items-center">
                                        {grossWeightStr || '0.00'}
                                        {activeInput === 'gross' && <span className="w-1 h-10 bg-primary text-on-primary animate-pulse ml-1" />}
                                    </div>
                                </div>

                                <div 
                                    onClick={() => setActiveInput('tare')}
                                    className={`bg-black p-4 rounded-xl border-2 cursor-pointer transition-colors ${activeInput === 'tare' ? 'border-blue-500 shadow-[0_0_15px_rgba(59,130,246,0.2)]' : 'border-outline-variant'}`}
                                >
                                    <label className="text-on-surface-variant text-sm font-bold uppercase tracking-widest block mb-2">Tara (T)</label>
                                    <div className="text-5xl font-mono font-bold text-foreground h-12 flex items-center">
                                        {tareWeightStr || '0.00'}
                                        {activeInput === 'tare' && <span className="w-1 h-10 bg-primary text-on-primary animate-pulse ml-1" />}
                                    </div>
                                </div>
                            </div>
                        </div>

                        {/* ATM Pad */}
                        <div className="w-[320px] shrink-0 bg-background p-6 rounded-3xl border border-outline-variant shadow-2xl">
                            <div className="grid grid-cols-3 gap-4 mb-6">
                                {['7','8','9','4','5','6','1','2','3','C','0','.'].map((key) => (
                                    <button
                                        key={key}
                                        onClick={() => handleKeypadPress(key)}
                                        className={`h-20 rounded-2xl text-3xl font-mono font-bold flex items-center justify-center transition-all active:scale-95 ${
                                            key === 'C' 
                                                ? 'bg-red-950/50 text-red-500 border border-red-900/50 hover:bg-red-900/50' 
                                                : 'bg-surface border border-outline-variant shadow-sm text-white border border-outline-variant hover:bg-surface-variant hover:border-outline'
                                        }`}
                                    >
                                        {key}
                                    </button>
                                ))}
                            </div>

                            <button
                                onClick={handleCertify}
                                disabled={isReconciling || !grossWeightStr || !tareWeightStr}
                                className="w-full h-24 bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 disabled:bg-surface border border-outline-variant shadow-sm text-white text-xl font-bold rounded-2xl transition-all active:scale-95 flex flex-col items-center justify-center gap-1 shadow-[0_0_20px_rgba(5,150,105,0.3)]"
                            >
                                {isReconciling ? (
                                    <div className="w-8 h-8 border-4 border-white border-t-transparent rounded-full animate-spin" />
                                ) : (
                                    <>
                                        <span>CONFIRMAR Y CERTIFICAR</span>
                                        <span className="text-xs font-mono opacity-70">Sellar Ticket Legal</span>
                                    </>
                                )}
                            </button>
                        </div>
                    </div>
                ) : (
                    <div className="flex-1 flex flex-col items-center justify-center text-outline">
                        <AlertTriangle className="w-16 h-16 mb-4 opacity-20" />
                        <h2 className="text-2xl font-bold text-outline-variant">Ningún Vehicle Seleccionado</h2>
                        <p className="mt-2 text-outline">Seleccione un camión del radar para habilitar el pad forense.</p>
                    </div>
                )}
            </div>
        </div>
    );
};

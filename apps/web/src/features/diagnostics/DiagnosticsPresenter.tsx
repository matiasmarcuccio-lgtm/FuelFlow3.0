import { useState } from 'react';
import type { ActiveDefect } from './queries';
import { Wrench, AlertOctagon, Lock, Clock, Zap, Droplets, GaugeCircle, ShieldCheck } from 'lucide-react';
import { useQueryClient } from '@tanstack/react-query';

type DefectCategory = 'hydraulic' | 'electrical' | 'engine' | 'wear_and_tear' | 'false_alarm';

interface DiagnosticsPresenterProps {
    defects: ActiveDefect[];
    onResolve: (defectId: string, category: DefectCategory, notes: string, pin: string) => void;
}

const CATEGORIES: { id: DefectCategory; label: string; icon: React.ElementType; color: string }[] = [
    { id: 'hydraulic', label: 'Hidráulica', icon: Droplets, color: 'text-primary border-blue-900/50 hover:bg-blue-900/20 hover:border-blue-500' },
    { id: 'electrical', label: 'Eléctrico', icon: Zap, color: 'text-yellow-400 border-yellow-900/50 hover:bg-yellow-900/20 hover:border-yellow-500' },
    { id: 'engine', label: 'Motor', icon: GaugeCircle, color: 'text-orange-400 border-orange-900/50 hover:bg-orange-900/20 hover:border-orange-500' },
    { id: 'wear_and_tear', label: 'Desgaste', icon: Wrench, color: 'text-on-surface-variant border-outline-variant hover:bg-surface border border-outline-variant shadow-sm hover:border-outline' },
    { id: 'false_alarm', label: 'Falsa Alarma', icon: AlertOctagon, color: 'text-emerald-400 border-emerald-900/50 hover:bg-emerald-900/20 hover:border-emerald-500' }
];

export const DiagnosticsPresenter = ({ defects, onResolve }: DiagnosticsPresenterProps) => {
    const queryClient = useQueryClient();
    const [selectedDefectId, setSelectedDefectId] = useState<string | null>(null);
    const [selectedCategory, setSelectedCategory] = useState<DefectCategory | null>(null);
    const [pinStr, setPinStr] = useState<string>('');
    const [pendingMessage, setPendingMessage] = useState<string | null>(null);

    const handleKeypadPress = (val: string) => {
        if (val === 'C') {
            setPinStr('');
            return;
        }
        if (pinStr.length >= 6) return;
        setPinStr(pinStr + val);
    };

    const handleUnlock = () => {
        if (!selectedDefectId || !selectedCategory || !pinStr) return;
        
        // Ejecutar mutación ciega (offline-first)
        onResolve(selectedDefectId, selectedCategory, 'Liberado en terreno', pinStr);
        
        // Reset state and show optimistic success
        setPendingMessage('Liberación Encolada. Máquina activa.');
        setTimeout(() => setPendingMessage(null), 3000);
        
        setSelectedDefectId(null);
        setSelectedCategory(null);
        setPinStr('');
    };

    const selectedDefect = defects.find(d => d.id === selectedDefectId);

    return (
        <div className="flex w-full h-full bg-black text-foreground font-sans overflow-hidden">
            {/* PANEL IZQUIERDO: BANDEJA DE TRIAJE (40%) */}
            <div className="w-[40%] border-r border-outline-variant bg-[#0a0505] flex flex-col">
                <div className="p-6 bg-red-950/30 border-b border-red-900/50 flex items-center justify-between">
                    <div>
                        <h2 className="text-2xl font-bold tracking-tight text-red-500 flex items-center gap-2">
                            <AlertOctagon className="w-6 h-6" />
                            Defect Triage
                        </h2>
                        <p className="text-red-400/70 text-sm mt-1 uppercase tracking-widest font-semibold">
                            {defects.length} Máquinas Inmovilizadas
                        </p>
                    </div>
                </div>

                <div className="flex-1 overflow-y-auto p-4 space-y-4">
                    {defects.length === 0 ? (
                        <div className="h-full flex flex-col items-center justify-center text-emerald-600/50">
                            <ShieldCheck className="w-16 h-16 mb-4 opacity-50" />
                            <p className="text-xl font-bold tracking-widest">FLEET 100% OPERATIONAL</p>
                        </div>
                    ) : (
                        defects.map((defect) => {
                            const isSelected = selectedDefectId === defect.id;
                            
                            // Visualizamos también mutaciones encoladas como pending (opcional, si hay mutations pending)
                            const isPending = queryClient.isMutating({ mutationKey: ['resolve_plant_defect', defect.id] }) > 0;
                            
                            if (isPending) return null; // Si está optimísticamente resuelto, lo ocultamos

                            return (
                                <button
                                    key={defect.id}
                                    onPointerDown={(e) => { e.preventDefault(); setSelectedDefectId(defect.id); setSelectedCategory(null); setPinStr(''); }}
                                    className={`w-full min-h-[80px] text-left p-5 rounded-xl border-2 transition-all relative overflow-hidden ${
                                        isSelected 
                                            ? 'border-red-500 bg-red-950/40 shadow-[0_0_20px_rgba(239,68,68,0.2)]' 
                                            : 'border-red-900/30 bg-red-950/10 hover:border-red-500/50 hover:bg-red-950/20'
                                    }`}
                                >
                                    {isSelected && <div className="absolute top-0 left-0 w-1.5 h-full bg-red-500" />}
                                    
                                    <div className="flex justify-between items-start mb-3">
                                        <div className="flex items-center gap-2">
                                            <span className="bg-red-900/80 text-white px-3 py-1 rounded text-lg font-bold tracking-widest border border-red-500/50">
                                                {defect.assets.asset_code}
                                            </span>
                                        </div>
                                        <div className="flex items-center gap-1 text-xs text-red-400 font-bold bg-red-950/50 px-2 py-1 rounded">
                                            <Clock className="w-3 h-3" />
                                            {new Date(defect.reported_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                                        </div>
                                    </div>
                                    <div className="text-sm text-red-200/70 font-mono line-clamp-2 leading-relaxed">
                                        "{defect.defect_description}"
                                    </div>
                                </button>
                            );
                        })
                    )}
                </div>
            </div>

            {/* PANEL DERECHO: LA LLAVE (60%) */}
            <div className="w-[60%] bg-slate-950 flex flex-col relative">
                {pendingMessage && (
                    <div className="absolute top-0 left-0 w-full bg-primary text-on-primary text-white text-center py-4 font-bold z-50 animate-in slide-in-from-top flex justify-center items-center gap-2">
                        <Lock className="w-5 h-5" />
                        {pendingMessage}
                    </div>
                )}
                
                <div className="p-8 border-b border-slate-900 flex justify-between items-center bg-background/50">
                    <div>
                        <h1 className="text-3xl font-bold tracking-tight text-foreground flex items-center gap-3">
                            <Wrench className="w-8 h-8 text-on-surface-variant" />
                            Fitter's Override
                        </h1>
                        <p className="text-outline text-sm mt-1 uppercase tracking-widest font-bold">Protocolo de Liberación Mecánica</p>
                    </div>
                </div>

                {selectedDefect ? (
                    <div className="flex-1 p-8 flex flex-col items-center justify-center">
                        
                        {!selectedCategory ? (
                            <div className="w-full h-[60%] max-w-3xl animate-in fade-in zoom-in duration-300 flex flex-col">
                                <h3 className="text-center text-on-surface-variant font-bold uppercase tracking-widest mb-8 text-xl">Seleccione Causa Raíz</h3>
                                <div className="grid gap-6 flex-1" style={{ gridTemplateRows: 'repeat(auto-fit, minmax(80px, 1fr))', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))' }}>
                                    {CATEGORIES.map(cat => {
                                        const Icon = cat.icon;
                                        return (
                                            <button
                                                key={cat.id}
                                                onPointerDown={(e) => { e.preventDefault(); setSelectedCategory(cat.id); }}
                                                className={`rounded-2xl border-2 flex flex-col items-center justify-center gap-4 transition-all active:scale-95 bg-background ${cat.color} min-h-[80px]`}
                                            >
                                                <Icon className="w-12 h-12" />
                                                <span className="text-lg font-bold uppercase tracking-wider">{cat.label}</span>
                                            </button>
                                        );
                                    })}
                                </div>
                            </div>
                        ) : (
                            <div className="w-full max-w-sm animate-in slide-in-from-right duration-300">
                                <button 
                                    onPointerDown={(e) => { e.preventDefault(); setSelectedCategory(null); }}
                                    className="text-outline hover:text-foreground mb-6 uppercase text-sm font-bold tracking-widest flex items-center gap-2 transition-colors min-h-[48px] px-2"
                                >
                                    ← Cambiar Categoría
                                </button>

                                <div className="bg-background p-8 rounded-3xl border border-outline-variant shadow-2xl relative overflow-hidden">
                                    <div className="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-blue-500 to-emerald-500" />
                                    
                                    <h3 className="text-center text-foreground font-bold uppercase tracking-widest mb-8 text-xl">PIN de Autorización</h3>
                                    
                                    <div className="flex justify-center gap-3 mb-10">
                                        {[0, 1, 2, 3].map((_, i) => (
                                            <div 
                                                key={i} 
                                                className={`w-6 h-6 rounded-full border-2 transition-all ${i < pinStr.length ? 'bg-white border-white scale-110 shadow-[0_0_10px_rgba(255,255,255,0.5)]' : 'bg-transparent border-outline-variant'}`} 
                                            />
                                        ))}
                                    </div>

                                    <div className="grid grid-cols-3 gap-4 mb-6">
                                        {['1','2','3','4','5','6','7','8','9','C','0','✓'].map((key) => {
                                            if (key === '✓') {
                                                return (
                                                    <button
                                                        key={key}
                                                        onPointerDown={(e) => { e.preventDefault(); handleUnlock(); }}
                                                        disabled={pinStr.length < 4}
                                                        className="min-h-[80px] min-w-[80px] h-20 rounded-2xl text-2xl font-bold flex items-center justify-center transition-all active:scale-95 bg-emerald-600 hover:bg-emerald-500 text-white disabled:opacity-50 disabled:bg-surface border border-outline-variant shadow-sm border-none shadow-[0_0_15px_rgba(5,150,105,0.3)] disabled:shadow-none"
                                                    >
                                                        {key}
                                                    </button>
                                                )
                                            }
                                            return (
                                                <button
                                                    key={key}
                                                    onPointerDown={(e) => { e.preventDefault(); handleKeypadPress(key); }}
                                                    className={`min-h-[80px] min-w-[80px] h-20 rounded-2xl text-3xl font-mono font-bold flex items-center justify-center transition-all active:scale-95 ${
                                                        key === 'C' 
                                                            ? 'bg-red-950/50 text-red-500 border border-red-900/50 hover:bg-red-900/50' 
                                                            : 'bg-surface border border-outline-variant shadow-sm text-white border border-outline-variant hover:bg-surface-variant hover:border-outline'
                                                    }`}
                                                >
                                                    {key}
                                                </button>
                                            )
                                        })}
                                    </div>
                                </div>
                            </div>
                        )}
                    </div>
                ) : (
                    <div className="flex-1 flex flex-col items-center justify-center text-outline/50">
                        <Wrench className="w-20 h-20 mb-6 opacity-20" />
                        <h2 className="text-3xl font-bold text-slate-700">Awaiting Assignment</h2>
                        <p className="mt-2 text-outline font-medium">Seleccione un equipo del panel de triaje para iniciar el desbloqueo.</p>
                    </div>
                )}
            </div>
        </div>
    );
};

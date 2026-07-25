
import { ShieldAlert } from 'lucide-react';

export const FatigueLockout = () => {
    return (
        <div className="w-screen h-screen bg-red-950 flex flex-col items-center justify-center text-white select-none relative overflow-hidden">
            {/* Background pulsating effect */}
            <div className="absolute inset-0 bg-red-900/20 animate-pulse" />
            
            <div className="z-10 flex flex-col items-center text-center p-8 bg-black/40 backdrop-blur-md border-4 border-red-500 rounded-3xl shadow-[0_0_50px_rgba(239,68,68,0.3)] max-w-2xl">
                <ShieldAlert size={120} className="text-red-500 mb-6 animate-bounce" />
                
                <h1 className="text-6xl font-black uppercase tracking-widest text-red-500 mb-4">
                    BLOQUEO POR FATIGA
                </h1>
                
                <div className="bg-red-900/50 p-4 rounded-xl border border-red-500/50 mb-8 w-full">
                    <p className="text-xl text-red-200 font-mono font-bold">
                        LÍMITE DE SERVICIO NHVR EXCEDIDO (11.5 HORAS)
                    </p>
                </div>
                
                <p className="text-2xl text-on-surface font-medium max-w-lg mb-8 leading-relaxed">
                    Por requerimientos legales de la Cadena de Responsabilidad (CoR), este vehículo ha sido expulsado del orquestador JIT. 
                </p>
                
                <p className="text-lg text-on-surface-variant font-bold uppercase tracking-widest animate-pulse">
                    Debe ejecutar el cierre de turno (Shutdown) inmediatamente.
                </p>
            </div>
            
            {/* Disclaimer at bottom */}
            <div className="absolute bottom-8 text-red-500/50 font-mono text-sm uppercase tracking-widest">
                National Heavy Vehicle Regulator - Fatigue Management Compliance Enforced
            </div>
        </div>
    );
};

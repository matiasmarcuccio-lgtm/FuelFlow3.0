import React from 'react';
import { useInTransitCycles } from './queries';
import { useReconcileLoadCycle } from './mutations';
import { TollgatePresenter } from './TollgatePresenter';
import { Activity, ShieldCheck, WifiOff } from 'lucide-react';
import { useIsRestoring } from '@tanstack/react-query';

export const TollgateContainer = ({ projectId }: { projectId: string }) => {
    const { data: cycles, isLoading, isError } = useInTransitCycles(projectId);
    const { mutateAsync: reconcileCycle, isPending } = useReconcileLoadCycle();
    const isRestoring = useIsRestoring(); // Verifica si TanStack Query está restaurando desde IndexedDB

    // Si la red está caída, bloqueamos completamente la UI para evitar corrupción
    // El operador de báscula no puede trabajar offline porque la facturación requiere sincronía estricta
    if (isRestoring || isError) {
        return (
            <div className="w-screen h-screen flex flex-col items-center justify-center bg-black text-foreground p-8 text-center">
                <WifiOff className="w-24 h-24 text-red-500 mb-6" />
                <h1 className="text-3xl font-bold mb-4">Conexión Segura Interrumpida</h1>
                <p className="text-on-surface-variant max-w-xl text-lg">
                    La aduana forense exige una conexión encriptada y bidireccional con el servidor central para prevenir la doble facturación. 
                    El radar y el ATM Pad están bloqueados hasta que se restablezca la conectividad.
                </p>
            </div>
        );
    }

    if (isLoading || !cycles) {
        return (
            <div className="w-screen h-screen flex flex-col items-center justify-center bg-black text-foreground">
                <Activity className="w-16 h-16 text-primary animate-spin mb-4" />
                <p className="text-on-surface-variant uppercase tracking-widest font-bold">Iniciando Radar de Aproximación...</p>
            </div>
        );
    }

    return (
        <TollgatePresenter 
            inTransitCycles={cycles}
            onReconcile={async (cycleId, gross, tare) => {
                await reconcileCycle({ cycleId, grossWeight: gross, tareWeight: tare });
            }}
            isReconciling={isPending}
        />
    );
};

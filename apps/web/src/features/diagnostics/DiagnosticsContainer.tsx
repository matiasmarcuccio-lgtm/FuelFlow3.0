import React from 'react';
import { useActiveDefects } from './queries';
import { useResolvePlantDefect } from './mutations';
import { DiagnosticsPresenter } from './DiagnosticsPresenter';
import { Activity } from 'lucide-react';

export const DiagnosticsContainer = ({ projectId }: { projectId: string }) => {
    const { data: defects, isLoading, isError } = useActiveDefects(projectId);
    const { mutateAsync: resolveDefect } = useResolvePlantDefect();

    if (isLoading || !defects) {
        return (
            <div className="w-screen h-screen flex flex-col items-center justify-center bg-black text-foreground">
                <Activity className="w-16 h-16 text-red-500 animate-spin mb-4" />
                <p className="text-on-surface-variant uppercase tracking-widest font-bold">Iniciando Triaje Fitter...</p>
            </div>
        );
    }

    if (isError) {
        return (
            <div className="w-screen h-screen flex flex-col items-center justify-center bg-black text-foreground p-8">
                <p className="text-red-500 font-mono text-xl">Error al cargar la bóveda de triaje.</p>
            </div>
        );
    }

    return (
        <DiagnosticsPresenter 
            defects={defects}
            onResolve={async (defectId, category, notes, pin) => {
                const { data: { session } } = await import('../../lib/supabase').then(m => m.supabase.auth.getSession());
                if (!session) return;
                // Mutación ciega optimista
                await resolveDefect({ defectId, category, resolutionNotes: notes, mechanicId: session.user.id, mechanicPin: pin });
            }}
        />
    );
};

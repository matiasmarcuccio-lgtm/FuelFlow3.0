import React, { useState, useEffect } from 'react';
import { HandoverContainer } from '../../handover/HandoverContainer';
import { useSubmitManifest, type ShiftManifestPayload } from '../mutations';
import { supabase } from '../../../lib/supabase';
import { useQueryClient } from '@tanstack/react-query';

export const GracefulShutdown = ({ 
    onComplete,
    projectId,
    assetId 
}: { 
    onComplete: () => void;
    projectId: string;
    assetId: string;
}) => {
    const [pdfUrl, setPdfUrl] = useState<string | null>(null);
    const [isGenerating, setIsGenerating] = useState(false);
    const { mutateAsync: submitManifest } = useSubmitManifest();
    const queryClient = useQueryClient();

    useEffect(() => {
        let isMounted = true;
        
        const generateManifest = async () => {
            setIsGenerating(true);
            try {
                const { data: userData } = await supabase.auth.getUser();
                
                // 1. Calcular toneladas sincronizadas (QueryCache)
                // Esto requeriría que el Kiosk mantenga el estado de los ciclos del turno.
                // Como no está implementado un fetching del turno entero en este boilerplate,
                // extraeremos todo de la mutation cache.
                let syncedTonnage = 0;
                let syncedCycles = 0;

                // 2. Calcular toneladas offline (MutationCache)
                const mutations = queryClient.getMutationCache().getAll();
                let offlineTonnage = 0;
                let offlineCycles = 0;

                mutations.forEach(mutation => {
                    // Si la mutación es para enviar telemetría de carga
                    if (mutation.options.mutationKey && mutation.options.mutationKey.includes('telemetry')) {
                        const payload = (mutation.state.variables as any)?.payload;
                        if (payload && payload.status === 'completed' && payload.tonnage) {
                            offlineTonnage += Number(payload.tonnage);
                            offlineCycles += 1;
                        }
                    }
                });

                const payload: ShiftManifestPayload = {
                    project_id: projectId,
                    asset_id: assetId,
                    operator_id: userData.user?.id || 'unknown',
                    shift_start_time: new Date(Date.now() - 11.5 * 3600000).toISOString(),
                    shift_end_time: new Date().toISOString(),
                    total_tonnage: syncedTonnage + offlineTonnage,
                    total_cycles: syncedCycles + offlineCycles,
                    fatigue_alerts_count: 0,
                    mechanic_overrides_count: 0
                };

                // 1. Enviar el webhook silencioso (Offline First)
                submitManifest(payload).catch(console.error);

                // 2. Importación dinámica del motor de PDF para evitar bloating inicial
                const { pdf } = await import('@react-pdf/renderer');
                const { ShiftManifestPDF } = await import('./ShiftManifestPDF');

                // 3. Generar el Blob
                const doc = <ShiftManifestPDF data={payload} />;
                const asPdf = pdf(doc);
                const blob = await asPdf.toBlob();
                
                if (isMounted) {
                    setPdfUrl(URL.createObjectURL(blob));
                }
            } catch (err) {
                console.error("Error generating manifest:", err);
            } finally {
                if (isMounted) setIsGenerating(false);
            }
        };

        generateManifest();

        return () => {
            isMounted = false;
        };
    }, [projectId, assetId, submitManifest]);

    return (
        <div className="w-screen h-screen flex flex-col bg-[#0a0a0a]">
            {/* Header / Manifest Status */}
            <div className="p-8 border-b border-outline-variant bg-background flex justify-between items-center">
                <div>
                    <h2 className="text-2xl font-bold text-foreground">Fin de Turno (Graceful Shutdown)</h2>
                    <p className="text-on-surface-variant">Generando registro legal y purgando cola JIT...</p>
                </div>
                <div>
                    {isGenerating ? (
                        <div className="text-primary font-semibold animate-pulse">
                            Compilando manifiesto PDF...
                        </div>
                    ) : pdfUrl ? (
                        <a 
                            href={pdfUrl} 
                            download={`Manifest_${assetId}_${new Date().toISOString().split('T')[0]}.pdf`}
                            className="bg-emerald-600 hover:bg-emerald-500 text-white font-bold py-3 px-6 rounded-lg shadow-lg border border-emerald-400 transition-colors inline-block"
                        >
                            📥 DESCARGAR COPIA LOCAL (PDF)
                        </a>
                    ) : (
                        <div className="text-red-400 font-semibold">
                            Fallo al compilar manifiesto local
                        </div>
                    )}
                </div>
            </div>

            {/* Resto de la lógica de Handover */}
            <div className="flex-1 relative">
                <HandoverContainer 
                    projectId={projectId} 
                    assetId={assetId} 
                    onComplete={onComplete}
                    mode="shutdown"
                />
            </div>
        </div>
    );
};

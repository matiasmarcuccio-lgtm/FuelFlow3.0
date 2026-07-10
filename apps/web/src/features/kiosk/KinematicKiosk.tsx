import React from 'react';
import { useParams } from 'react-router-dom';
import { useHardwareTelemetry } from './useHardwareTelemetry';
import { useKioskState } from './useKioskState';
import { AcousticDrivingMode } from './screens/AcousticDrivingMode';
import { SafeWorkChecklist } from './screens/SafeWorkChecklist';
import { ParkedJITHUD } from './screens/ParkedJITHUD';
import { GracefulShutdown } from './screens/GracefulShutdown';
import { IdleSafeScreensaver } from './screens/IdleSafeScreensaver';
import { FatigueLockout } from './screens/FatigueLockout';
import { FittersOverride } from './screens/FittersOverride';
import { HandoverContainer } from '../handover/HandoverContainer';

import { ExcavatorKioskContainer } from './ExcavatorKioskContainer';
import { supabase } from '../../lib/supabase';

export const KinematicKiosk = () => {
    const { projectId, assetId } = useParams();
    const telemetry = useHardwareTelemetry();
    const { sessionState, revalidate } = useKioskState(telemetry, assetId);
    const [assetType, setAssetType] = React.useState<string | null>(null);

    const queryClient = import('@tanstack/react-query').then(m => m.useQueryClient);
    
    React.useEffect(() => {
        if (assetId) {
            supabase.from('assets').select('asset_type').eq('id', assetId).single().then(({ data }) => {
                if (data) setAssetType(data.asset_type);
            });
        }
        if (projectId) {
            // Prefetch escuadrón de mantenimiento
            import('../../lib/queryClient').then(({ queryClient }) => {
                queryClient.prefetchQuery({
                    queryKey: ['mechanics', projectId],
                    queryFn: async () => {
                        const { data } = await supabase
                            .from('project_members')
                            .select('user_id, profiles(full_name)')
                            .eq('project_id', projectId)
                            .eq('role', 'heavy_mechanic');
                        return data || [];
                    }
                });
            });
        }
    }, [assetId, projectId]);

    // 0. Nodo de Origen (Excavator Bypass)
    if (assetType === 'excavator' && assetId) {
        return (
            <>
                <ExcavatorKioskContainer assetId={assetId} />

            </>
        );
    }

    // 1. El Freno Supremo (Hard Override Cinemático)
    if (telemetry.speed > 1.0) {
        return (
            <>
                <AcousticDrivingMode />

            </>
        );
    }

    // 2. Orquestación Determinista
    const renderScreen = () => {
        switch (sessionState) {
            case 'INITIALIZING':
                return <div className="bg-black w-screen h-screen"></div>; // Pantalla negra pura, sin loaders
            case 'PRE_START':
                if (!projectId || !assetId) return <div className="p-8 text-foreground">Missing IDs</div>;
                return <SafeWorkChecklist onComplete={revalidate} projectId={projectId} assetId={assetId} />;
            case 'HANDOVER':
                if (!projectId || !assetId) {
                    return <div className="p-8 text-foreground">Missing Project/Asset ID</div>;
                }
                return <HandoverContainer projectId={projectId} assetId={assetId} />;
            case 'FATIGUE_LOCKOUT':
                return <FatigueLockout />;
            case 'LOCKOUT':
                if (!projectId || !assetId) return <div className="p-8 text-foreground">Missing IDs</div>;
                return <FittersOverride assetId={assetId} projectId={projectId} onRectified={revalidate} />;
            case 'IN_QUEUE':
                return <ParkedJITHUD telemetry={telemetry} />;
            case 'SHUTDOWN':
                if (!projectId || !assetId) {
                    return <div className="p-8 text-foreground">Missing Project/Asset ID</div>;
                }
                return <GracefulShutdown onComplete={revalidate} projectId={projectId} assetId={assetId} />;
            case 'IDLE_SAFE':
            default:
                return <IdleSafeScreensaver />;
        }
    };

    return (
        <>
            {renderScreen()}
        </>
    );
};

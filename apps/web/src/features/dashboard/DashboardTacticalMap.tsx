import { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { TacticalMapPresenter, type AssetLocation } from './TacticalMapPresenter';
import { AlertTriangle } from 'lucide-react';

interface DashboardTacticalMapProps {
    projectId: string;
}

export const DashboardTacticalMap: React.FC<DashboardTacticalMapProps> = ({ projectId }) => {
    // REGLA 2: Aislamiento (Contenedor) - Solo estado y base de datos, 0% UI
    const [assets, setAssets] = useState<Record<string, AssetLocation>>({});
    const [isConnected, setIsConnected] = useState(true);

    useEffect(() => {
        let isMounted = true;
        
        // Fetch inicial (Estado Base)
        supabase.from('assets')
            .select('id, asset_type, status, last_known_location, excavator_states(current_material, operational_status)')
            .eq('current_project_id', projectId)
            .then(({ data }) => {
                if (data && isMounted) {
                    const newAssets: Record<string, AssetLocation> = {};
                    data.forEach((asset: any) => {
                        if (asset.last_known_location) {
                            const lat = Number(asset.last_known_location.lat);
                            const lng = Number(asset.last_known_location.lng);
                            
                            // Prevent AdvancedMarker crash if coordinates are invalid
                            if (isNaN(lat) || isNaN(lng)) return;

                            let resolvedStatus = asset.status;
                            let resolvedMaterial = undefined;

                            if (asset.asset_type === 'excavator' && asset.excavator_states && asset.excavator_states.length > 0) {
                                if (resolvedStatus !== 'out_of_service') {
                                    resolvedStatus = asset.excavator_states[0].operational_status;
                                }
                                resolvedMaterial = asset.excavator_states[0].current_material;
                            }
                            
                            newAssets[asset.id] = {
                                lat,
                                lng,
                                heading: Number(asset.last_known_location.heading) || 0,
                                status: resolvedStatus,
                                material: resolvedMaterial,
                                assetType: asset.asset_type
                            };
                        }
                    });
                    setAssets(newAssets);
                }
            });

        // REGLA 1: Única Fuente de la Verdad (SSOT) 
        // Suscripción de Telemetría (Alta Frecuencia)
        const channelTelemetry = supabase.channel(`public:asset_telemetry_logs:${projectId}`)
            .on('postgres_changes', { 
                event: 'INSERT', 
                schema: 'public', 
                table: 'asset_telemetry_logs' 
            }, (payload) => {
                const { asset_id, payload: telemetryData } = payload.new as any;
                if (!telemetryData || !telemetryData.location) return;
                
                const lat = Number(telemetryData.location.lat);
                const lng = Number(telemetryData.location.lng);
                
                if (isNaN(lat) || isNaN(lng)) return;
                
                setAssets(prev => {
                    if (!prev[asset_id]) {
                        return {
                            ...prev,
                            [asset_id]: {
                                lat,
                                lng,
                                heading: Number(telemetryData.location.heading) || 0,
                                status: telemetryData.status || 'active',
                                assetType: telemetryData.category || 'haul_truck'
                            }
                        };
                    }
                    return {
                        ...prev,
                        [asset_id]: {
                            ...prev[asset_id],
                            lat,
                            lng,
                            heading: Number(telemetryData.location.heading) || prev[asset_id].heading
                        }
                    };
                });
            })
            .subscribe((status) => {
                // Monitoreo de salud de la red (Zero-Trust UI)
                if (status === 'SUBSCRIBED') {
                    setIsConnected(true);
                } else if (status === 'CLOSED' || status === 'CHANNEL_ERROR') {
                    setIsConnected(false);
                }
            });

        // Suscripción de Estados (Baja Frecuencia)
        const channelState = supabase.channel(`asset_states:${projectId}`)
            .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'assets' }, (payload) => {
                const newAsset = payload.new;
                setAssets(prev => {
                    // REGLA 5: Prevención de Estado Fantasma
                    if (newAsset.status === 'archived') {
                        const copy = { ...prev };
                        delete copy[newAsset.id];
                        return copy;
                    }
                    if (!prev[newAsset.id]) {
                         if (!newAsset.last_known_location) return prev;
                         return {
                             ...prev,
                             [newAsset.id]: {
                                 lat: Number(newAsset.last_known_location.lat),
                                 lng: Number(newAsset.last_known_location.lng),
                                 heading: Number(newAsset.last_known_location.heading) || 0,
                                 status: newAsset.status,
                                 assetType: newAsset.asset_type
                             }
                         };
                    }
                    return { ...prev, [newAsset.id]: { ...prev[newAsset.id], status: newAsset.status } };
                });
            })
            .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'excavator_states' }, (payload) => {
                const { asset_id, operational_status, current_material } = payload.new;
                setAssets(prev => {
                    if (!prev[asset_id]) return prev;
                    if (prev[asset_id].status === 'out_of_service') return prev;
                    return { ...prev, [asset_id]: { ...prev[asset_id], status: operational_status, material: current_material } };
                });
            })
            .subscribe();

        return () => {
            isMounted = false;
            supabase.removeChannel(channelTelemetry);
            supabase.removeChannel(channelState);
        };
    }, [projectId]);

    return (
        <div className="w-full h-full relative overflow-hidden">
            {!isConnected && (
                <div className="absolute top-4 left-1/2 -translate-x-1/2 z-[100] bg-orange-500 text-white px-4 py-2 rounded shadow-[0_0_15px_rgba(249,115,22,0.5)] flex items-center gap-2 font-mono font-bold animate-pulse">
                    <AlertTriangle className="w-5 h-5" />
                    TELEMETRY DISCONNECTED
                </div>
            )}
            <TacticalMapPresenter assets={assets} />
        </div>
    );
};

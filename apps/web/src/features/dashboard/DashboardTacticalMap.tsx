import React, { useEffect, useRef } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { supabase } from '../../lib/supabase';

// Geometría visual para las entidades de la flota
const createVehicleIcon = (assetType: string, heading: number, status: string, material?: string) => {
    // Definir la heráldica de la gravedad
    let strokeColor = assetType === 'haul_truck' ? '#2563eb' : '#dc2626'; // Default
    let haloClass = '';

    if (status === 'out_of_service') {
        strokeColor = '#ef4444'; // Red Tag
        haloClass = 'animate-ping shadow-[0_0_15px_red]';
    } else if (status === 'relocating') {
        strokeColor = '#f59e0b'; // Ámbar de precaución
        haloClass = 'animate-pulse shadow-[0_0_10px_orange]';
    }

    const materialBadge = material ? `<div class="absolute -top-6 left-1/2 -translate-x-1/2 bg-black text-white text-[10px] px-1 font-mono rounded border border-neutral-700 whitespace-nowrap z-50">${material}</div>` : '';

    return L.divIcon({
        className: 'jit-vehicle-marker bg-transparent border-none',
        html: `
            ${materialBadge}
            <div class="jit-rotator ${haloClass}" style="transform: rotate(${heading}deg); transition: transform 0.2s ease; width: 32px; height: 32px; display: flex; align-items: center; justify-content: center; filter: drop-shadow(0 0 10px ${strokeColor}80);">
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                    ${assetType === 'haul_truck' 
                        ? `<path d="M12 2L4 20L12 17L20 20L12 2Z" fill="${strokeColor}" stroke="#ffffff" stroke-width="2" stroke-linejoin="round"/>`
                        : `<path d="M4 4h16v16H4V4z" fill="${strokeColor}" stroke="#ffffff" stroke-width="2"/><circle cx="12" cy="12" r="4" fill="#ffffff"/>`
                    }
                </svg>
            </div>
        `,
        iconSize: [32, 32],
        iconAnchor: [16, 16]
    });
};

interface DashboardTacticalMapProps {
    projectId: string;
}

export const DashboardTacticalMap: React.FC<DashboardTacticalMapProps> = ({ projectId }) => {
    const mapRef = useRef<L.Map | null>(null);
    const markersRef = useRef<{ [assetId: string]: L.Marker }>({});
    const containerRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        if (!containerRef.current) return;

        // 1. Inicialización de la física espacial (One-time setup)
        if (!mapRef.current) {
            mapRef.current = L.map(containerRef.current, {
                preferCanvas: true, // Crucial para rendimiento
                zoomControl: false,
                attributionControl: false
            }).setView([-42.8850, 147.3250], 16);

            L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png').addTo(mapRef.current);
            
            // Fetch initial positions
            supabase.from('assets')
                .select('id, asset_type, status, last_known_location, excavator_states(current_material, operational_status)')
                .eq('current_project_id', projectId)
                .then(({ data }) => {
                    if (data) {
                        data.forEach((asset: any) => {
                            if (asset.last_known_location) {
                                const lat = asset.last_known_location.lat;
                                const lng = asset.last_known_location.lng;
                                const heading = asset.last_known_location.heading || 0;
                                
                                let resolvedStatus = asset.status;
                                let resolvedMaterial = undefined;

                                if (asset.asset_type === 'excavator' && asset.excavator_states && asset.excavator_states.length > 0) {
                                    if (resolvedStatus !== 'out_of_service') {
                                        resolvedStatus = asset.excavator_states[0].operational_status;
                                    }
                                    resolvedMaterial = asset.excavator_states[0].current_material;
                                }
                                
                                const icon = createVehicleIcon(asset.asset_type, heading, resolvedStatus, resolvedMaterial);
                                const marker = L.marker([lat, lng], { icon }).addTo(mapRef.current!);
                                
                                // Guarda los metadatos en el marcador para usos futuros
                                (marker as any).assetState = {
                                    assetType: asset.asset_type,
                                    heading,
                                    status: resolvedStatus,
                                    material: resolvedMaterial
                                };

                                markersRef.current[asset.id] = marker;
                            }
                        });
                    }
                });
        }

        // 2. El Bypass de Red (Supabase Realtime -> DOM crudo)
        const channelTelemetry = supabase.channel(`public:asset_telemetry_logs:${projectId}`)
            .on('postgres_changes', { 
                event: 'INSERT', 
                schema: 'public', 
                table: 'asset_telemetry_logs' 
            }, (payload) => {
                const { asset_id, payload: telemetryData } = payload.new as any;
                if (!telemetryData || !telemetryData.location) return;
                
                const { lat, lng, heading } = telemetryData.location;

                requestAnimationFrame(() => {
                    if (markersRef.current[asset_id]) {
                        const marker = markersRef.current[asset_id];
                        marker.setLatLng([lat, lng]);
                        
                        const state = (marker as any).assetState || {};
                        state.heading = heading || 0;

                        const element = marker.getElement();
                        if (element) {
                            const rotator = element.querySelector('.jit-rotator') as HTMLElement;
                            if (rotator) {
                                rotator.style.transform = `rotate(${heading || 0}deg)`;
                            }
                        }
                    }
                });
            })
            .subscribe();

        // 3. Suscripción a Cambios de Estado Maestros (Assets / Excavator States)
        const channelState = supabase.channel(`asset_states:${projectId}`)
            .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'assets' }, (payload) => {
                const { id, status } = payload.new;
                requestAnimationFrame(() => {
                    const marker = markersRef.current[id];
                    if (marker) {
                        const state = (marker as any).assetState;
                        if (state) {
                            state.status = status;
                            marker.setIcon(createVehicleIcon(state.assetType, state.heading, state.status, state.material));
                        }
                    }
                });
            })
            .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'excavator_states' }, (payload) => {
                const { asset_id, operational_status, current_material } = payload.new;
                requestAnimationFrame(() => {
                    const marker = markersRef.current[asset_id];
                    if (marker) {
                        const state = (marker as any).assetState;
                        if (state && state.status !== 'out_of_service') {
                            state.status = operational_status;
                            state.material = current_material;
                            marker.setIcon(createVehicleIcon(state.assetType, state.heading, state.status, state.material));
                        }
                    }
                });
            })
            .subscribe();

        return () => {
            supabase.removeChannel(channelTelemetry);
            supabase.removeChannel(channelState);
            // Destrucción limpia
            if (mapRef.current) {
                mapRef.current.remove();
                mapRef.current = null;
            }
        };
    }, [projectId]);

    return (
        // Contenedor inerte. React lo dibuja una vez y jamás lo vuelve a tocar.
        <div ref={containerRef} className="w-full h-full bg-neutral-900 absolute inset-0 z-0" />
    );
};

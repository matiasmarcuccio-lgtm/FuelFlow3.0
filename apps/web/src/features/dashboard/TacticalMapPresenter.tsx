import React from 'react';
import { APIProvider, Map, Marker } from '@vis.gl/react-google-maps';

export interface AssetLocation {
    lat: number;
    lng: number;
    heading: number;
    status: string;
    material?: string;
    assetType: string;
}

interface TacticalMapPresenterProps {
    assets: Record<string, AssetLocation>;
    center?: { lat: number, lng: number };
}

export const TacticalMapPresenter: React.FC<TacticalMapPresenterProps> = ({ 
    assets, 
    center = { lat: -42.8850, lng: 147.3250 } 
}) => {
    const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY || '';
    
    // REGLA 3: Zero-Trust UI (Fallback visual si no hay API Key)
    if (!apiKey) {
        return (
            <div className="w-full h-full bg-neutral-900 flex items-center justify-center font-mono text-muted-foreground p-4 text-center">
                Missing VITE_GOOGLE_MAPS_API_KEY. Please add it to your .env file.
            </div>
        );
    }

    // Se requiere un MapId (JavaScript) para usar AdvancedMarkers.
    return (
        <div className="w-full h-full relative">
            <APIProvider apiKey={apiKey}>
                <Map
                    defaultZoom={16}
                    defaultCenter={center}
                    disableDefaultUI={true}
                    gestureHandling="greedy"
                >
                    {Object.entries(assets).map(([id, asset]) => {
                        let strokeColor = asset.assetType === 'haul_truck' ? '#2563eb' : '#dc2626';
                        if (asset.status === 'out_of_service') {
                            strokeColor = '#ef4444'; // Red tag
                        } else if (asset.status === 'relocating') {
                            strokeColor = '#f59e0b'; // Amber warning
                        }

                        const svgStr = `
                            <svg width="32" height="32" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
                                <g transform="rotate(${asset.heading || 0} 16 16)">
                                    ${asset.assetType === 'haul_truck' 
                                        ? `<path d="M16 4L8 26L16 22L24 26L16 4Z" fill="${strokeColor}" stroke="#ffffff" stroke-width="2" stroke-linejoin="round"/>`
                                        : `<path d="M6 6h20v20H6V6z" fill="${strokeColor}" stroke="#ffffff" stroke-width="2"/><circle cx="16" cy="16" r="6" fill="#ffffff"/>`
                                    }
                                </g>
                            </svg>
                        `.trim().replace(/\s+/g, ' ');
                        const iconUrl = `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(svgStr)}`;

                        return (
                            <Marker
                                key={id}
                                position={{ lat: asset.lat, lng: asset.lng }}
                                icon={{
                                    url: iconUrl
                                }}
                                title={asset.material || asset.assetType}
                            />
                        );
                    })}
                </Map>
            </APIProvider>
        </div>
    );
};

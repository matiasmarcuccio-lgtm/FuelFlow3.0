import React, { useEffect, useRef } from 'react';
import { Marker } from 'react-leaflet';
import L from 'leaflet';
import { TacticalAsset } from './useTacticalFleetMap';

interface AnimatedMarkerProps {
  asset: TacticalAsset;
  icon: L.DivIcon;
  children?: React.ReactNode;
}

export const AnimatedMarker: React.FC<AnimatedMarkerProps> = ({ asset, icon, children }) => {
  const markerRef = useRef<L.Marker>(null);

  useEffect(() => {
    if (!markerRef.current || !asset.lastKnownLocation) return;
    
    const marker = markerRef.current;
    let requestRef: number;
    const loc = asset.lastKnownLocation;

    // Sincronizar posición base (Rubber-banding correctivo cuando llega nuevo ping de Supabase)
    marker.setLatLng([loc.lat, loc.lng]);

    const animate = () => {
      // Motor de Dead Reckoning
      const timeDeltaMs = Date.now() - loc.timestamp;
      const TTL_MS = 120000; // 2 minutos de tolerancia máxima para la telemetría

      if (loc.speed > 0 && loc.heading !== null && timeDeltaMs < TTL_MS) {
        const timeDeltaSecs = timeDeltaMs / 1000;
        const distanceMeters = loc.speed * timeDeltaSecs;
        
        // Aproximación cartesiana de desplazamiento (válida para zoom nivel táctico)
        const latOffset = (distanceMeters * Math.cos(loc.heading * (Math.PI / 180))) / 111320;
        const lngOffset = (distanceMeters * Math.sin(loc.heading * (Math.PI / 180))) / (40075000 * Math.cos(loc.lat * (Math.PI / 180)) / 360);

        marker.setLatLng([
          loc.lat + latOffset,
          loc.lng + lngOffset
        ]);
        
        // Mantener opacidad de activo vivo
        marker.setOpacity(1.0);
      } else if (timeDeltaMs >= TTL_MS) {
        // Abortar interpolación: El activo es un Nodo Muerto
        marker.setOpacity(0.5); 
        // El vehículo se congela en su última coordenada extrapolada legal
      }
      
      requestRef = requestAnimationFrame(animate);
    };

    requestRef = requestAnimationFrame(animate);

    return () => {
      if (requestRef) cancelAnimationFrame(requestRef);
    };
  }, [asset.lastKnownLocation]); // Re-ejecutar solo cuando llega un nuevo ping real

  if (!asset.lastKnownLocation) return null;

  return (
    <Marker 
      ref={markerRef} 
      position={[asset.lastKnownLocation.lat, asset.lastKnownLocation.lng]} 
      icon={icon}
    >
      {children}
    </Marker>
  );
};

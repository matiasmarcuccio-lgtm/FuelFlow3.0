import { useQueryClient } from '@tanstack/react-query';

export interface TacticalAsset {
  id: string;
  name: string;
  category: string;
  status: string;
  lastKnownLocation: { 
    lat: number; 
    lng: number;
    speed: number;
    heading: number | null;
    timestamp: number;
  } | null;
}

export const useTacticalFleetMap = (projectId: string) => {
  const queryClient = useQueryClient();

  // Extraer Assets de la Caché Global (Hidratada por useRealtimeSync)
  const assetsCache = queryClient.getQueryData<any[]>(['assets', projectId]) || [];
  
  // Transformar al modelo táctico espacial
  const fleet: TacticalAsset[] = assetsCache.map((asset) => ({
    id: asset.id,
    name: asset.name,
    category: asset.category,
    status: asset.status,
    lastKnownLocation: asset.last_known_location || null
  })).filter(a => a.lastKnownLocation && a.lastKnownLocation.lat !== null);

  // Extraer Polígono HRCW (GeoJSON crudo)
  const syncData = queryClient.getQueryData<any>(['crew_hashes', projectId]);
  const hrcwPolygon = syncData?.hrcw_polygon || null;

  return { fleet, hrcwPolygon };
};

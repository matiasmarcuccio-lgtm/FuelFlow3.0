import React from 'react';
import { MapContainer, TileLayer, GeoJSON, Popup } from 'react-leaflet';
import 'leaflet/dist/leaflet.css'; // Vite CSS Bug fix
import { TacticalAsset } from './useTacticalFleetMap';
import { createAssetIcon } from './MapIcons';
import { AnimatedMarker } from './AnimatedMarker';

interface DashboardPresenterProps {
  fleet: TacticalAsset[];
  hrcwPolygon: any;
}

export const DashboardPresenter: React.FC<DashboardPresenterProps> = ({ fleet, hrcwPolygon }) => {
  // Centro aproximado para inicializar el mapa (Hobart)
  const centerPosition: [number, number] = [-42.885, 147.325];

  return (
    <div className="flex flex-col h-screen bg-slate-950 font-sans">
      <div className="p-4 bg-background border-b border-outline-variant flex justify-between items-center shadow-lg z-10 relative">
        <h1 className="text-2xl font-black text-foreground uppercase tracking-widest">
          Sala de Control <span className="text-primary">JIT</span>
        </h1>
        <div className="flex gap-4">
          <div className="bg-emerald-500/20 text-emerald-400 px-4 py-2 rounded-lg font-bold border border-emerald-500/50">
            {fleet.filter(a => a.status === 'in_site').length} Activos en Obra
          </div>
        </div>
      </div>

      <div className="flex-1 relative z-0">
        <MapContainer 
          center={centerPosition} 
          zoom={15} 
          className="w-full h-full"
          zoomControl={false}
        >
          {/* Capa de Satélite Oscura (Maptiler/CartoDB base oscura para contraste) */}
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
            url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
          />

          {/* Topografía: Polígono de Alto Riesgo HRCW */}
          {hrcwPolygon && (
            <GeoJSON 
              data={hrcwPolygon} 
              style={{
                color: '#ef4444', // Red-500
                weight: 3,
                fillColor: '#7f1d1d', // Red-900
                fillOpacity: 0.3,
                dashArray: '10, 10'
              }}
            />
          )}

          {/* Telemetría Dinámica de la Fleet (Dead Reckoning a 60FPS) */}
          {fleet.map((asset) => (
            asset.lastKnownLocation ? (
              <AnimatedMarker
                key={asset.id}
                asset={asset}
                icon={createAssetIcon(asset.category, asset.status)}
              >
                <Popup className="bg-background text-foreground border border-outline-variant rounded-lg shadow-2xl">
                  <div className="p-2">
                    <h3 className="font-bold text-lg mb-1">{asset.name}</h3>
                    <div className="flex items-center gap-2 mb-2">
                      <span className="px-2 py-1 bg-surface border border-outline-variant shadow-sm text-xs rounded text-on-surface-variant uppercase">{asset.category}</span>
                      <span className={`px-2 py-1 text-xs rounded uppercase font-bold ${
                        asset.status === 'in_site' ? 'bg-emerald-900/50 text-emerald-400' : 
                        asset.status === 'maintenance' ? 'bg-amber-900/50 text-amber-400' : 
                        'bg-surface border border-outline-variant shadow-sm text-outline'
                      }`}>
                        {asset.status}
                      </span>
                    </div>
                  </div>
                </Popup>
              </AnimatedMarker>
            ) : null
          ))}
        </MapContainer>
      </div>
    </div>
  );
};

import React, { useEffect, useState } from 'react';
import { MapContainer, TileLayer, CircleMarker, Popup } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import { supabase } from '../../lib/supabase';

interface TelemetryNode {
  id: string;
  lat: number;
  lng: number;
  status: string;
  anomaly_flag?: string;
  contractor_id: string;
}

export const TelemetryMap = () => {
  const [nodes, setNodes] = useState<TelemetryNode[]>([]);

  useEffect(() => {
    fetchNodes();

    const subscription = supabase
      .channel('telemetry-map')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'load_offers' }, () => {
        fetchNodes();
      })
      .subscribe();

    return () => {
      supabase.removeChannel(subscription);
    };
  }, []);

  const fetchNodes = async () => {
    const { data, error } = await supabase
      .from('load_offers')
      .select('id, destination_lat, destination_lng, status, anomaly_flag, contractor_id, anomaly_resolved_at')
      // Solo mostramos camiones que están operando actualmente (no completados y auditados limpios)
      .not('status', 'eq', 'AUDITED');

    if (!error && data) {
      const activeNodes = data.map(d => ({
        id: d.id,
        lat: d.destination_lat,
        lng: d.destination_lng,
        status: d.status,
        anomaly_flag: d.anomaly_resolved_at ? null : d.anomaly_flag,
        contractor_id: d.contractor_id
      }));
      setNodes(activeNodes);
    }
  };

  const getColor = (status: string, hasAnomaly: boolean) => {
    if (hasAnomaly) return '#ef4444'; // Red 500
    if (status === 'LOADING') return '#eab308'; // Yellow 500
    if (status === 'IN_TRANSIT') return '#22c55e'; // Green 500
    return '#64748b'; // Slate 500 for idle/completed
  };

  return (
    <MapContainer 
      center={[-33.8688, 151.2093]} 
      zoom={12} 
      className="w-full h-full"
      zoomControl={false}
    >
      <TileLayer
        url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'
      />
      
      {nodes.map(node => {
        const hasAnomaly = !!node.anomaly_flag;
        const color = getColor(node.status, hasAnomaly);
        
        return (
          <CircleMarker
            key={node.id}
            center={[node.lat, node.lng]}
            radius={hasAnomaly ? 10 : 6}
            pathOptions={{
              color: hasAnomaly ? '#7f1d1d' : color,
              fillColor: color,
              fillOpacity: 0.8,
              weight: hasAnomaly ? 2 : 1
            }}
          >
            <Popup className="bg-slate-800 border border-slate-700">
              <div className="font-mono text-xs">
                <strong>ID:</strong> {node.id.split('-')[0]}<br/>
                <strong>STATUS:</strong> {node.status}<br/>
                {hasAnomaly && <span className="text-red-500 font-bold">ANOMALY: {node.anomaly_flag}</span>}
              </div>
            </Popup>
          </CircleMarker>
        );
      })}
    </MapContainer>
  );
};

import { useState, useEffect, useRef } from 'react';

export type Coordinate = { 
  latitude: number; 
  longitude: number;
  speed: number;
  heading: number | null;
  timestamp: number;
};

// Algoritmo Ray-Casting para detectar si un punto está dentro de un polígono irregular
const isPointInPolygon = (point: Coordinate, polygon: Coordinate[]) => {
  let isInside = false;
  const x = point.longitude, y = point.latitude;

  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const xi = polygon[i].longitude, yi = polygon[i].latitude;
    const xj = polygon[j].longitude, yj = polygon[j].latitude;

    const intersect = ((yi > y) !== (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
    if (intersect) isInside = !isInside;
  }
  return isInside;
};

export const useGeofence = (hrcwPolygon: Coordinate[] | null) => {
  const [isGeolocked, setIsGeolocked] = useState<boolean>(true); // Default a true hasta tener señal
  const [geoMessage, setGeoMessage] = useState<string>('Calculando telemetría GPS...');
  const lastTickRef = useRef<number>(Date.now());
  const lastValidHeading = useRef<number | null>(null);

  const [lastKnownCoord, setLastKnownCoord] = useState<Coordinate | null>(null);

  useEffect(() => {
    if (!hrcwPolygon || hrcwPolygon.length < 3) {
      // Si no hay polígono configurado, asumimos zona segura por defecto o pasamos la validación.
      setIsGeolocked(false);
      setGeoMessage('No hay zona HRCW configurada. Traspaso autorizado.');
      // Si no hay polígono pero queremos ubicación igual, necesitamos un watchPosition separado,
      // pero por ahora dependemos del mismo bloque para HRCW. 
    }

    if (!navigator.geolocation) {
      setIsGeolocked(true);
      setGeoMessage('Hardware GPS no detectado. Traspaso denegado.');
      return;
    }

    const watchId = navigator.geolocation.watchPosition(
      (position) => {
        lastTickRef.current = Date.now(); // Actualizar el Watchdog

        // 1. Filtro de Precisión (Degradación de señal MDM o ambiental)
        if (position.coords.accuracy > 15) {
          setIsGeolocked(true);
          setGeoMessage(`Señal degradada (Precisión: ${Math.round(position.coords.accuracy)}m). Requiere <15m.`);
          return;
        }

        let currentSpeed = position.coords.speed || 0;
        let currentHeading = position.coords.heading;

        if (currentSpeed < 1.0) {
            currentSpeed = 0; // Freno absoluto para el payload
            currentHeading = lastValidHeading.current; // Reutilizar el vector previo
        } else {
            lastValidHeading.current = currentHeading; // Save nuevo vector válido
        }

        const currentCoord: Coordinate = {
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
          speed: currentSpeed,
          heading: currentHeading,
          timestamp: position.timestamp
        };
        
        setLastKnownCoord(currentCoord);

        if (!hrcwPolygon || hrcwPolygon.length < 3) return; // Ya seteamos que está desbloqueado

        const inDangerZone = isPointInPolygon(currentCoord, hrcwPolygon);
        
        setIsGeolocked(inDangerZone);
        setGeoMessage(inDangerZone 
          ? 'PELIGRO: ZONA HRCW. Encienda el motor y abandone el perímetro de excavación.' 
          : 'ZONA SEGURA. Traspaso autorizado.'
        );
      },
      (_error) => {
        setIsGeolocked(true);
        setGeoMessage('Señal GPS perdida. Mueva el vehículo a un área despejada.');
      },
      { enableHighAccuracy: true, maximumAge: 0, timeout: 5000 }
    );

    // 2. Watchdog Asíncrono (Detección de estrangulamiento de CPU/MDM)
    const watchdogId = setInterval(() => {
      const timeSinceLastTick = Date.now() - lastTickRef.current;
      if (timeSinceLastTick > 10000) {
        setIsGeolocked(true);
        setGeoMessage('Señal de hardware degradada. MDM o Antena inactiva. Traspaso bloqueado.');
      }
    }, 2000);

    return () => {
      navigator.geolocation.clearWatch(watchId);
      clearInterval(watchdogId); // Crítico para la resiliencia del Kiosk Mode
    };
  }, [hrcwPolygon]);

  return { isGeolocked, geoMessage, lastKnownCoord };
};


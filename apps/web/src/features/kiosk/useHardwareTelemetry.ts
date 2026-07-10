import { useState, useEffect, useRef } from 'react';

interface TelemetryState {
    speed: number;
    location: { lat: number; lng: number } | null;
    isStale: boolean;
    accuracy: number;
}

export const useHardwareTelemetry = (): TelemetryState => {
    const [telemetry, setTelemetry] = useState<TelemetryState>({
        speed: 0,
        location: null,
        isStale: true,
        accuracy: 999
    });
    
    const lastSpeedRef = useRef<number>(0);
    const ALPHA = 0.2; // Constante de suavizado EMA
    
    useEffect(() => {

        // En un entorno local, esto podria no emitir nada. 
        // Idealmente en produccion esto corre en Kiosk de Tablet (Android/iOS MDM)
        if (!navigator.geolocation) {
            console.error('Geolocation is not supported by this browser.');
            return;
        }

        const watchId = navigator.geolocation.watchPosition(
            (position) => {
                const { latitude, longitude, speed: rawSpeed, accuracy } = position.coords;
                const timestamp = position.timestamp;
                
                // 1. Compuerta de Frescura y Precisión
                const isDataStale = (Date.now() - timestamp) > 5000; // 5 segundos de caducidad
                if (accuracy > 20 || isDataStale) {
                    setTelemetry(prev => prev.isStale ? prev : { ...prev, isStale: true });
                    return; // Descartar lectura envenenada
                }

                // 2. Filtro Matemático (EMA)
                const currentRawSpeed = rawSpeed || 0;
                const smoothedSpeed = (ALPHA * currentRawSpeed) + ((1 - ALPHA) * lastSpeedRef.current);
                lastSpeedRef.current = smoothedSpeed;

                // 3. Empaquetar la verdad física
                setTelemetry({
                    speed: smoothedSpeed,
                    location: { lat: latitude, lng: longitude },
                    isStale: false,
                    accuracy
                });
            },
            (error) => {
                console.error('Fallo de hardware MDM:', error);
                setTelemetry(prev => prev.isStale ? prev : { ...prev, isStale: true, speed: 0 });
                lastSpeedRef.current = 0; // Frenar cinemática por seguridad
            },
            { enableHighAccuracy: true, maximumAge: 0, timeout: 5000 }
        );

        return () => navigator.geolocation.clearWatch(watchId);
    }, []);

    return telemetry;
};

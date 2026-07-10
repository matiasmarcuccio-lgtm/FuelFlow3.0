import { useState, useEffect } from 'react';
import { get } from 'idb-keyval';
import { useHardwareTelemetry } from './useHardwareTelemetry';

export type KinematicState = 
  | 'INITIALIZING'
  | 'ACOUSTIC_DRIVING'
  | 'PRE_START'
  | 'HANDOVER'
  | 'FATIGUE_LOCKOUT'
  | 'LOCKOUT'
  | 'IN_QUEUE'
  | 'SHUTDOWN'
  | 'IDLE_SAFE';

// Algoritmo puro de Ray-Casting para polígonos irregulares (Offline)
// polygon: array de [lng, lat]
const isPointInPolygon = (point: {lat: number, lng: number}, polygon: [number, number][]) => {
    let isInside = false;
    const x = point.lng, y = point.lat;
    
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
        const xi = polygon[i][0], yi = polygon[i][1];
        const xj = polygon[j][0], yj = polygon[j][1];
        
        const intersect = ((yi > y) !== (yj > y))
            && (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
        if (intersect) isInside = !isInside;
    }
    
    return isInside;
};

import { supabase } from '../../lib/supabase';
import * as turf from '@turf/helpers';
import booleanPointInPolygon from '@turf/boolean-point-in-polygon';
import { useJoinJitQueue, useLeaveJitQueue, useSubmitPassiveTelemetry } from './mutations';

export const useKioskState = (telemetry: ReturnType<typeof useHardwareTelemetry>, assetId?: string) => {
    const [state, setState] = useState<KinematicState>('INITIALIZING');
    const [tick, setTick] = useState(0);
    const revalidate = () => setTick(t => t + 1);

    const { mutateAsync: joinQueue } = useJoinJitQueue();
    const { mutateAsync: leaveQueue } = useLeaveJitQueue();
    const { mutateAsync: submitPassiveTelemetry } = useSubmitPassiveTelemetry();

    useEffect(() => {
        let isMounted = true;

        const evaluateHierarchy = async () => {
            // Dispatch pasivo a Layer 0
            if (telemetry.location && assetId) {
                submitPassiveTelemetry({
                    asset_id: assetId,
                    payload: { location: telemetry.location, speed: telemetry.speed },
                    client_timestamp: new Date().toISOString()
                }).catch(console.error);
            }
            // 1. Freno Supremo (Evaluación síncrona en cada tick)
            if (telemetry.speed > 1.0) {
                if (isMounted) setState('ACOUSTIC_DRIVING');
                return;
            }

            // 2. Lectura Asíncrona de la Memoria Legal
            const today = new Date().toISOString().split('T')[0];
            const preStartRecord = await get(`pre_start_${today}`);
            const handoverRecord = await get(`handover_${today}`);
            
            // Geometrías descargadas desde Supabase durante el Handover (Hidratación)
            let strictPad = await get(`loading_pad_strict`);
            let bufferedPad = await get(`loading_pad_buffered`);

            if (!isMounted) return;

            // 3. Jerarquía de Seguridad (Hard Lockouts desde DB)
            if (assetId) {
                const { data: assetData } = await supabase
                    .from('assets')
                    .select('status')
                    .eq('id', assetId)
                    .single();

                if (assetData?.status === 'out_of_service') {
                    if (isMounted) setState('LOCKOUT'); // O FITTERS_OVERRIDE
                    return;
                }
            }

            if (!preStartRecord) {
                setState('PRE_START');
                return;
            }

            if (!handoverRecord || !handoverRecord.isValid) {
                setState('HANDOVER');
                return;
            }

            // FATIGUE GUARDIAN (Layer 1)
            const hoursElapsed = (Date.now() - handoverRecord.timestamp) / (1000 * 60 * 60);
            if (hoursElapsed >= 11.5) {
                if (isMounted) setState('FATIGUE_LOCKOUT');
                return;
            }

            // 4. Jerarquía Táctica (Offline Turf.js + Spatial Hysteresis)
            if (!strictPad || !bufferedPad) {
                const HOBART_MIN_LAT = -42.8850, HOBART_MAX_LAT = -42.8840;
                const HOBART_MIN_LNG = 147.3250, HOBART_MAX_LNG = 147.3260;
                const TOLERANCE = 0.00005;

                strictPad = [
                    [HOBART_MIN_LNG, HOBART_MIN_LAT],
                    [HOBART_MAX_LNG, HOBART_MIN_LAT],
                    [HOBART_MAX_LNG, HOBART_MAX_LAT],
                    [HOBART_MIN_LNG, HOBART_MAX_LAT],
                    [HOBART_MIN_LNG, HOBART_MIN_LAT] // Close polígono
                ];
                
                bufferedPad = [
                    [HOBART_MIN_LNG - TOLERANCE, HOBART_MIN_LAT - TOLERANCE],
                    [HOBART_MAX_LNG + TOLERANCE, HOBART_MIN_LAT - TOLERANCE],
                    [HOBART_MAX_LNG + TOLERANCE, HOBART_MAX_LAT + TOLERANCE],
                    [HOBART_MIN_LNG - TOLERANCE, HOBART_MAX_LAT + TOLERANCE],
                    [HOBART_MIN_LNG - TOLERANCE, HOBART_MIN_LAT - TOLERANCE]
                ];
            }

            if (telemetry.location) {
                const { lat, lng } = telemetry.location;
                const point = turf.point([lng, lat]);
                const strictPoly = turf.polygon([strictPad]);
                const bufferedPoly = turf.polygon([bufferedPad]);
                
                const isInsideStrict = booleanPointInPolygon(point, strictPoly);
                const isInsideBuffer = booleanPointInPolygon(point, bufferedPoly);

                if (state === 'IN_QUEUE') {
                    if (isInsideBuffer) {
                        setState('IN_QUEUE');
                        return;
                    } else {
                        // Cambio de estado de salida
                        if (assetId) {
                            leaveQueue(assetId).catch(console.error);
                        }
                    }
                } else {
                    if (isInsideStrict) {
                        setState('IN_QUEUE');
                        // Cambio de estado de entrada
                        if (assetId) {
                            joinQueue(assetId).catch(console.error);
                        }
                        return;
                    }
                }
            }

            // 5. Estado Inerte
            setState('IDLE_SAFE');
        };

        evaluateHierarchy();

        return () => { isMounted = false; };
    }, [telemetry, tick, assetId, joinQueue, leaveQueue]); // Dependencias de Kiosk y Mutations

    return { sessionState: state, revalidate };
};

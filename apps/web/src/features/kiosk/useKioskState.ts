import { useState, useEffect, useRef } from 'react';
import { get } from 'idb-keyval';
import { useHardwareTelemetry } from './useHardwareTelemetry';
import { supabase } from '../../lib/supabase';
import * as turf from '@turf/helpers';
import booleanPointInPolygon from '@turf/boolean-point-in-polygon';
import { useJoinJitQueue, useLeaveJitQueue, useSubmitPassiveTelemetry } from './mutations';

export type KinematicState = 
  | 'INITIALIZING'
  | 'ACOUSTIC_DRIVING'
  | 'PRE_START'
  | 'HANDOVER'
  | 'FATIGUE_LOCKOUT'
  | 'LOCKOUT'
  | 'SHUTDOWN'
  | 'IDLE_SAFE' // EN_RUTA
  | 'IN_QUEUE'  // EN_COLA_CARGA
  | 'LOADING'   // CARGANDO
  | 'HAULING'   // EN_RUTA_CARGADO
  | 'DUMPING';  // DESCARGANDO

const ENTRY_HYSTERESIS = 3000;
const EXIT_HYSTERESIS = 5000;
const SPOTTING_SPEED_KMH = 5.0; // Velocidad permisiva para spotting

export const useKioskState = (telemetry: ReturnType<typeof useHardwareTelemetry>, assetId?: string) => {
    const [state, setState] = useState<KinematicState>('INITIALIZING');
    const [tick, setTick] = useState(0);
    const revalidate = () => setTick(t => t + 1);

    const { mutateAsync: joinQueue } = useJoinJitQueue();
    const { mutateAsync: leaveQueue } = useLeaveJitQueue();
    const { mutateAsync: submitPassiveTelemetry } = useSubmitPassiveTelemetry();

    // Referencias para la Histéresis Espacial
    const lastInsideStrictRef = useRef<number | null>(null);
    const lastInsideBufferRef = useRef<number | null>(null);
    const lastOutsideStrictRef = useRef<number | null>(null);
    const lastOutsideBufferRef = useRef<number | null>(null);

    // Evitar setState en bucle usando ref
    const stateRef = useRef<KinematicState>('INITIALIZING');

    // Función segura de transición DAG
    const transitionTo = (newState: KinematicState, triggerAction?: () => void) => {
        const current = stateRef.current;
        
        // Reglas estrictas de mutación (DAG)
        let isValid = false;
        
        switch (current) {
            case 'IDLE_SAFE': // EN_RUTA
                isValid = newState === 'IN_QUEUE' || newState === 'LOADING' || newState === 'ACOUSTIC_DRIVING';
                break;
            case 'IN_QUEUE':
                isValid = newState === 'LOADING' || newState === 'IDLE_SAFE' || newState === 'ACOUSTIC_DRIVING';
                break;
            case 'LOADING':
                isValid = newState === 'HAULING'; // Jamás a IDLE_SAFE o IN_QUEUE
                break;
            case 'HAULING':
                isValid = newState === 'DUMPING' || newState === 'ACOUSTIC_DRIVING';
                break;
            case 'DUMPING':
                isValid = newState === 'IDLE_SAFE';
                break;
            case 'INITIALIZING':
            case 'PRE_START':
            case 'HANDOVER':
            case 'FATIGUE_LOCKOUT':
            case 'LOCKOUT':
            case 'ACOUSTIC_DRIVING':
                isValid = true; // Estados maestros/bloqueos absolutos pueden transicionar al estado base o viceversa
                break;
        }

        // Freno supremo (Siempre válido)
        if (newState === 'ACOUSTIC_DRIVING' || newState === 'FATIGUE_LOCKOUT' || newState === 'LOCKOUT') {
            isValid = true;
        }

        if (isValid) {
            stateRef.current = newState;
            setState(newState);
            if (triggerAction) triggerAction();
        }
    };

    useEffect(() => {
        let isMounted = true;

        const evaluateHierarchy = async () => {
            if (telemetry.location && assetId) {
                submitPassiveTelemetry({
                    asset_id: assetId,
                    payload: { location: telemetry.location, speed: telemetry.speed },
                    client_timestamp: new Date().toISOString()
                }).catch(console.error);
            }

            if (telemetry.speed > 30.0) { // Acoustic driving real
                if (isMounted) transitionTo('ACOUSTIC_DRIVING');
                return;
            } else if (stateRef.current === 'ACOUSTIC_DRIVING' && telemetry.speed < 5.0) {
                transitionTo('IDLE_SAFE'); // Regresar a estado seguro
            }

            const today = new Date().toISOString().split('T')[0];
            const preStartRecord = await get(`pre_start_${today}`);
            const handoverRecord = await get(`handover_${today}`);
            
            let strictPad = await get(`loading_pad_strict`);
            let bufferedPad = await get(`loading_pad_buffered`);

            if (!isMounted) return;

            if (assetId) {
                const { data: assetData } = await supabase
                    .from('assets')
                    .select('status')
                    .eq('id', assetId)
                    .single();

                if (assetData?.status === 'out_of_service') {
                    if (isMounted) transitionTo('LOCKOUT');
                    return;
                }
            }

            if (!preStartRecord) {
                transitionTo('PRE_START');
                return;
            }

            if (!handoverRecord || !handoverRecord.isValid) {
                transitionTo('HANDOVER');
                return;
            }

            const hoursElapsed = (Date.now() - handoverRecord.timestamp) / (1000 * 60 * 60);
            if (hoursElapsed >= 11.5) {
                if (isMounted) transitionTo('FATIGUE_LOCKOUT');
                return;
            }

            if (!strictPad || !bufferedPad) {
                const HOBART_MIN_LAT = -42.8850, HOBART_MAX_LAT = -42.8840;
                const HOBART_MIN_LNG = 147.3250, HOBART_MAX_LNG = 147.3260;
                const TOLERANCE = 0.00005;

                strictPad = [
                    [HOBART_MIN_LNG, HOBART_MIN_LAT],
                    [HOBART_MAX_LNG, HOBART_MIN_LAT],
                    [HOBART_MAX_LNG, HOBART_MAX_LAT],
                    [HOBART_MIN_LNG, HOBART_MAX_LAT],
                    [HOBART_MIN_LNG, HOBART_MIN_LAT]
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
                
                const now = Date.now();
                const isInsideStrict = booleanPointInPolygon(point, strictPoly);
                const isInsideBuffer = booleanPointInPolygon(point, bufferedPoly);
                
                // Manejo de Timers (Histéresis Espacial)
                if (isInsideStrict) {
                    if (!lastInsideStrictRef.current) lastInsideStrictRef.current = now;
                    lastOutsideStrictRef.current = null;
                } else {
                    if (!lastOutsideStrictRef.current) lastOutsideStrictRef.current = now;
                    lastInsideStrictRef.current = null;
                }

                if (isInsideBuffer) {
                    if (!lastInsideBufferRef.current) lastInsideBufferRef.current = now;
                    lastOutsideBufferRef.current = null;
                } else {
                    if (!lastOutsideBufferRef.current) lastOutsideBufferRef.current = now;
                    lastInsideBufferRef.current = null;
                }

                const timeInsideStrict = lastInsideStrictRef.current ? now - lastInsideStrictRef.current : 0;
                const timeOutsideStrict = lastOutsideStrictRef.current ? now - lastOutsideStrictRef.current : 0;
                const timeInsideBuffer = lastInsideBufferRef.current ? now - lastInsideBufferRef.current : 0;
                const timeOutsideBuffer = lastOutsideBufferRef.current ? now - lastOutsideBufferRef.current : 0;

                const isSpeedSpotting = telemetry.speed < SPOTTING_SPEED_KMH;

                // Evaluación del DAG con Histéresis
                if (stateRef.current === 'INITIALIZING') {
                    transitionTo('IDLE_SAFE');
                }

                if (stateRef.current === 'IDLE_SAFE') {
                    // Transición a LOADING dinámica On-the-Fly
                    if (isInsideStrict && timeInsideStrict >= ENTRY_HYSTERESIS && isSpeedSpotting) {
                        transitionTo('LOADING', () => {
                            if (assetId) joinQueue(assetId).catch(console.error); // Asumir queue subyacente para DB
                        });
                        return;
                    }
                    // Transición a IN_QUEUE
                    if (isInsideBuffer && timeInsideBuffer >= ENTRY_HYSTERESIS) {
                        transitionTo('IN_QUEUE', () => {
                            if (assetId) joinQueue(assetId).catch(console.error);
                        });
                        return;
                    }
                }

                if (stateRef.current === 'IN_QUEUE') {
                    // Spotting a Carga
                    if (isInsideStrict && timeInsideStrict >= ENTRY_HYSTERESIS && isSpeedSpotting) {
                        transitionTo('LOADING');
                        return;
                    }
                    // Salida por congestión o abandono
                    if (!isInsideBuffer && timeOutsideBuffer >= EXIT_HYSTERESIS) {
                        transitionTo('IDLE_SAFE', () => {
                            if (assetId) leaveQueue(assetId).catch(console.error);
                        });
                        return;
                    }
                }
                
                if (stateRef.current === 'LOADING') {
                    // Una vez completada la carga (el equipo decide su salida)
                    // Transiciona a EN_RUTA_CARGADO. Salida del buffer estricto con tolerancia de histéresis
                    if (!isInsideStrict && timeOutsideStrict >= EXIT_HYSTERESIS) {
                        transitionTo('HAULING', () => {
                            if (assetId) leaveQueue(assetId).catch(console.error);
                        });
                        return;
                    }
                }
            }
        };

        evaluateHierarchy();

        return () => { isMounted = false; };
    }, [telemetry, tick, assetId, joinQueue, leaveQueue]);

    return { sessionState: state, revalidate };
};


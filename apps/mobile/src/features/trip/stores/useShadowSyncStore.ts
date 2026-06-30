import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import AsyncStorage from '@react-native-async-storage/async-storage';

export type SyncEventType = 'ARRIVAL' | 'DEPARTURE' | 'EMERGENCY_OVERRIDE' | 'BREAKDOWN';
export type SyncEventStatus = 'PENDING' | 'SYNCED' | 'DLQ';

export interface SyncEvent {
  eventId: string;
  type: SyncEventType;
  offerId: string;
  localTimestamp: string;
  lat: number;
  lng: number;
  localImageUri?: string;
  loadedGrossMass?: number;
  anomalyFlag?: string; // Para EMERGENCY_OVERRIDE
  status: SyncEventStatus;
  errorMessage?: string;
  retryCount: number;
}

interface ShadowSyncState {
  events: SyncEvent[];
  addEvent: (event: Omit<SyncEvent, 'eventId' | 'status' | 'retryCount'>) => void;
  markAsDLQ: (eventId: string, errorMessage: string) => void;
  incrementRetry: (eventId: string) => void;
  removeEvent: (eventId: string) => void;
  clearDLQ: () => void;
}

export const useShadowSyncStore = create<ShadowSyncState>()(
  persist(
    (set) => ({
      events: [],
      
      addEvent: (event) => set((state) => ({
        events: [
          ...state.events, 
          { 
            ...event, 
            eventId: Math.random().toString(36).substring(2, 15), 
            status: 'PENDING',
            retryCount: 0
          }
        ]
      })),

      markAsDLQ: (eventId, errorMessage) => set((state) => ({
        events: state.events.map(e => 
          e.eventId === eventId ? { ...e, status: 'DLQ', errorMessage } : e
        )
      })),

      incrementRetry: (eventId) => set((state) => ({
        events: state.events.map(e => 
          e.eventId === eventId ? { ...e, retryCount: e.retryCount + 1 } : e
        )
      })),

      removeEvent: (eventId) => set((state) => ({
        events: state.events.filter(e => e.eventId !== eventId)
      })),

      clearDLQ: () => set((state) => ({
        events: state.events.filter(e => e.status !== 'DLQ')
      })),
    }),
    {
      name: 'shadow-sync-storage',
      storage: createJSONStorage(() => AsyncStorage),
    }
  )
);

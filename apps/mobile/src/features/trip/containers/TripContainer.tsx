import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { useIncident } from '../hooks/useIncident';
import { useQueryClient, useQuery } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { ActiveTripDashboard } from '../components/ActiveTripDashboard';
import { LoadingPhaseDashboard } from '../components/LoadingPhaseDashboard';
import { ErrorMessage } from '../../bidding/components/ErrorMessage';
import { useIncident } from '../hooks/useIncident';
import * as Location from 'expo-location';
import { point } from '@turf/helpers';
import booleanPointInPolygon from '@turf/boolean-point-in-polygon';
import { FontAwesome } from '@expo/vector-icons';
import { useShadowSyncStore } from '../stores/useShadowSyncStore';
import { Alert } from 'react-native';

export const TripContainer = () => {
  const queryClient = useQueryClient();
  const { data: activeTrip, isLoading, error, refetch } = useQuery({
    queryKey: ['active_trip'],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error("No autenticado");

      const { data: assignment, error: assignErr } = await supabase
        .from('assignments')
        .select('load_offer_id')
        .eq('operator_id', user.id)
        .order('assigned_at', { ascending: false })
        .limit(1)
        .maybeSingle();

      if (assignErr) throw assignErr;
      if (!assignment) return null;

      const { data: offer, error: offerErr } = await supabase
        .from('load_offers')
        .select('*, staging_area_geojson')
        .eq('id', assignment.load_offer_id)
        .single();

      if (offerErr) throw offerErr;

      if (offer.status === 'COMPLETED' || offer.status === 'AUDITED') {
        return null;
      }

      return offer;
    },
    staleTime: 0
  });

  const { data: activeVehicle } = useQuery({
    queryKey: ['active_vehicle'],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return null;

      const { data, error } = await supabase
        .from('vehicles')
        .select('*')
        .eq('profile_id', user.id)
        .limit(1)
        .maybeSingle();
      
      if (error) {
        console.error("Error fetching vehicle", error);
        return null;
      }
      return data;
    },
    staleTime: 1000 * 60 * 60 // 1 hour cache
  });

  const [hasLocationPermission, setHasLocationPermission] = React.useState<boolean | null>(null);
  const [isGeofenceUnlocked, setIsGeofenceUnlocked] = React.useState(false);
  const consecutivePings = React.useRef(0);
  const REQUIRED_CONSECUTIVE_PINGS = 3;

  React.useEffect(() => {
    let locationSubscription: Location.LocationSubscription | null = null;

    const startLocationTracking = async () => {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') {
        setHasLocationPermission(false);
        return;
      }
      setHasLocationPermission(true);

      // Solo si existe el viaje y la geometría exportada por el webhook
      if (!activeTrip || !activeTrip.staging_area_geojson) return;

      const polygon = activeTrip.staging_area_geojson;

      // Trackear con estrangulamiento táctico dictado por el operador JIT
      locationSubscription = await Location.watchPositionAsync(
        {
          accuracy: Location.Accuracy.Highest,
          timeInterval: 3000,
          distanceInterval: 5,
        },
        (location) => {
          const { latitude, longitude } = location.coords;
          const currentPoint = point([longitude, latitude]);

          try {
            const isInside = booleanPointInPolygon(currentPoint, polygon);

            if (isInside) {
              consecutivePings.current += 1;
              if (consecutivePings.current >= REQUIRED_CONSECUTIVE_PINGS) {
                setIsGeofenceUnlocked(true);
              }
            } else {
              // Reseteo violento ante caída (Debounce espacial)
              consecutivePings.current = 0;
              setIsGeofenceUnlocked(false);
            }
          } catch (e) {
            console.error("Error validando GeoJSON:", e);
          }
        }
      );
    };

    if (activeTrip && activeTrip.status === 'IN_TRANSIT') {
      startLocationTracking();
    }

    return () => {
      if (locationSubscription) {
        locationSubscription.remove();
      }
    };
  }, [activeTrip?.id, activeTrip?.status, activeTrip?.staging_area_geojson]);

  const reportIncidentMutation = useIncident();

  const handleManifestSign = async () => {
    if (!activeTrip) return;
    try {
      const { data: { user } } = await supabase.auth.getUser();
      const { error: corError } = await supabase.from('cor_manifests').insert({
        load_offer_id: activeTrip.id,
        operator_id: user?.id,
        action: 'DEPARTURE',
        loader_signature_hash: 'mock_loader_hash_123',
        driver_signature_hash: 'mock_driver_hash_123',
        gps_location: pointToWKT(-33.8688, 151.2093) // Simulación GPS temporal
      });
      if (corError) throw corError;
      
      const { error: updateErr } = await supabase.from('load_offers')
        .update({ status: 'LOADING' })
        .eq('id', activeTrip.id);
      if (updateErr) throw updateErr;
      
      refetch();
    } catch (e: any) {
      console.error(e);
    }
  };

  const handleLoadingComplete = async (grossMass: number, localImageUri: string) => {
    if (!activeTrip) return;
    try {
      const localLocation = await Location.getLastKnownPositionAsync();
      
      if (localImageUri.startsWith('OVERRIDE_')) {
        addSyncEvent({
          type: 'EMERGENCY_OVERRIDE',
          offerId: activeTrip.id,
          localTimestamp: new Date().toISOString(),
          lat: localLocation?.coords.latitude || 0,
          lng: localLocation?.coords.longitude || 0,
        });
      } else {
        addSyncEvent({
          type: 'DEPARTURE',
          offerId: activeTrip.id,
          localTimestamp: new Date().toISOString(),
          lat: localLocation?.coords.latitude || 0,
          lng: localLocation?.coords.longitude || 0,
          loadedGrossMass: grossMass,
          localImageUri: localImageUri
        });
      }

      await queryClient.setQueryData(['active_trip'], {
        ...activeTrip,
        status: 'IN_TRANSIT'
      });
    } catch (e: any) {
      console.error(e);
    }
  };

  const handleBreakdown = async () => {
    if (!activeTrip) return;
    try {
      const localLocation = await Location.getLastKnownPositionAsync();
      
      addSyncEvent({
        type: 'BREAKDOWN',
        offerId: activeTrip.id,
        localTimestamp: new Date().toISOString(),
        lat: localLocation?.coords.latitude || 0,
        lng: localLocation?.coords.longitude || 0,
      });

      await queryClient.setQueryData(['active_trip'], {
        ...activeTrip,
        status: 'BREAKDOWN'
      });
    } catch (e: any) {
      console.error(e);
    }
  };

  const addSyncEvent = useShadowSyncStore(state => state.addEvent);

  const handleArrival = async () => {
    if (!activeTrip) return;
    try {
      // 1. Mutación Optimista: Encolar en Zustand (Shadow Sync) con Timestamp de Hardware
      const localLocation = await Location.getLastKnownPositionAsync();
      
      addSyncEvent({
        type: 'ARRIVAL',
        offerId: activeTrip.id,
        localTimestamp: new Date().toISOString(),
        lat: localLocation?.coords.latitude || 0,
        lng: localLocation?.coords.longitude || 0,
      });

      // 2. Mentirle a React Query para matar el dashboard inmediatamente sin red
      // Mutamos la caché local optimísticamente
      await queryClient.setQueryData(['active_trip'], null);
      
      // Opcional: También invalidamos para que en background intente refrescar si hay red
      queryClient.invalidateQueries({ queryKey: ['active_trip'] });
      
    } catch (e: any) {
      console.error(e);
    }
  };

  const handleReportIncident = (description: string) => {
    if (!activeTrip) return;
    reportIncidentMutation.mutate({
      offerId: activeTrip.id,
      description,
      lat: -33.8688, // TODO: Reemplazar con geolocalización real
      lng: 151.2093
    });
  };

  const handleRequestDetach = async (reason: string) => {
    try {
      const { error } = await supabase.rpc('fn_request_detach', { p_reason: reason });
      if (error) throw error;
      // Optimistically update the query cache to reflect detach intent if needed
      // Currently handled entirely by ActiveTripDashboard local state before unmounting
    } catch (e) {
      console.error("Failed to request detach", e);
    }
  };

  if (isLoading) {
    return <Text style={styles.loading}>Sincronizando Estado Operativo...</Text>;
  }

  if (error) {
    return <ErrorMessage error={error} />;
  }

  if (hasLocationPermission === false) {
    return (
      <View style={styles.center}>
        <Text style={styles.emptyText}>Acceso GPS Denegado</Text>
        <Text style={styles.subText}>Debe otorgar permisos de ubicación en primer plano para interactuar con cargas.</Text>
      </View>
    );
  }

  if (!activeTrip) {
    return (
      <View style={styles.center}>
        <Text style={styles.emptyText}>No tienes ningún viaje activo en este momento.</Text>
        <Text style={styles.subText}>Ve a la pestaña de Bidding para aceptar cargas.</Text>
      </View>
    );
  }

  if (activeTrip.status === 'BREAKDOWN') {
    return (
      <View style={styles.center}>
        <FontAwesome name="wrench" size={48} color="#e53e3e" />
        <Text style={styles.emptyText}>UNIDAD EN ESTADO DE AVERÍA</Text>
        <Text style={styles.subText}>Se ha notificado al Command Center. Su viaje está bloqueado por seguridad hasta la intervención de un administrador de flota.</Text>
      </View>
    );
  }

  if (activeTrip.status === 'LOADING') {
    return (
      <LoadingPhaseDashboard 
        trip={activeTrip}
        vehicle={activeVehicle}
        onComplete={handleLoadingComplete}
      />
    );
  }

  return (
    <View style={{ flex: 1 }}>
      <ActiveTripDashboard 
        trip={activeTrip} 
        onSignManifest={handleManifestSign}
        onReportArrival={handleArrival}
        onReportIncident={handleReportIncident}
        onRequestDetach={handleRequestDetach}
        isGeofenceUnlocked={isGeofenceUnlocked}
      />
      <TouchableOpacity 
        style={styles.breakdownButton}
        onPress={() => {
          Alert.alert(
            'Reportar Falla Mecánica',
            '¿Confirma que la unidad ha sufrido una falla mecánica y no puede continuar? El viaje quedará bloqueado.',
            [
              { text: 'Cancelar', style: 'cancel' },
              { text: 'Confirmar Avería', style: 'destructive', onPress: handleBreakdown }
            ]
          );
        }}
      >
        <FontAwesome name="warning" size={14} color="white" />
        <Text style={styles.breakdownText}>REPORTAR AVERÍA (BREAKDOWN)</Text>
      </TouchableOpacity>
    </View>
  );
};

const pointToWKT = (lat: number, lng: number) => `(${lng},${lat})`;

const styles = StyleSheet.create({
  center: { flex: 1, justifyContent: 'center', alignItems: 'center', padding: 20, marginTop: 50 },
  loading: { textAlign: 'center', padding: 20, color: '#4a5568' },
  emptyText: { color: '#2d3748', fontSize: 18, fontWeight: 'bold', textAlign: 'center', marginTop: 15 },
  subText: { color: '#718096', fontSize: 14, textAlign: 'center', marginTop: 10, marginBottom: 30 },
  breakdownButton: { backgroundColor: '#e53e3e', flexDirection: 'row', justifyContent: 'center', alignItems: 'center', padding: 15, margin: 20, borderRadius: 8 },
  breakdownText: { color: 'white', fontWeight: 'bold', fontSize: 14, marginLeft: 8 }
});

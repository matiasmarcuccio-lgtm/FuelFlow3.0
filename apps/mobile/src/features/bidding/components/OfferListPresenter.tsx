import React from 'react';
import { View, Text, StyleSheet, FlatList, TouchableOpacity } from 'react-native';
import { FontAwesome } from '@expo/vector-icons';

// Representación pura de UI (Sin estado, sin conocimiento de DB)
export interface LoadOfferData {
  id: string;
  contractor_id: string;
  crane_window_start: string;
  crane_window_end: string;
  destination_lat: number;
  destination_lng: number;
  requires_4x4_traction: boolean;
  max_turn_radius_m: number | null;
  status: string;
}

interface Props {
  offers: LoadOfferData[];
  onAcceptOffer: (id: string) => void;
  isLoading: boolean;
}

export const OfferListPresenter = ({ offers, onAcceptOffer, isLoading }: Props) => {
  if (isLoading) {
    return (
      <View style={styles.center}>
        <Text style={styles.loadingText}>Escaneando el mercado (Zero-Trust)...</Text>
      </View>
    );
  }

  if (offers.length === 0) {
    return (
      <View style={styles.center}>
        <FontAwesome name="inbox" size={48} color="#cbd5e0" />
        <Text style={styles.emptyText}>No hay cargas disponibles compatibles con tu vehículo actual.</Text>
      </View>
    );
  }

  return (
    <FlatList
      data={offers}
      keyExtractor={(item) => item.id}
      contentContainerStyle={styles.listContainer}
      renderItem={({ item }) => (
        <View style={styles.card}>
          <View style={styles.cardHeader}>
            <Text style={styles.statusBadge}>
              {item.status === 'BIDDING_OPEN' ? 'ABIERTA' : 'ASIGNADA'}
            </Text>
            {item.requires_4x4_traction && (
              <View style={styles.tag4x4}>
                <Text style={styles.tagText}>4x4</Text>
              </View>
            )}
          </View>
          
          <Text style={styles.coordinateText}>
            Destino: {item.destination_lat.toFixed(4)}, {item.destination_lng.toFixed(4)}
          </Text>
          
          <Text style={styles.windowText}>
            Ventana: {new Date(item.crane_window_start).toLocaleTimeString()} - {new Date(item.crane_window_end).toLocaleTimeString()}
          </Text>
          
          {item.max_turn_radius_m && (
            <Text style={styles.radiusText}>
              Giro máximo: {item.max_turn_radius_m}m
            </Text>
          )}

          {item.status === 'BIDDING_OPEN' && (
            <TouchableOpacity 
              style={styles.acceptButton}
              onPress={() => onAcceptOffer(item.id)}
            >
              <Text style={styles.acceptButtonText}>Aceptar Carga</Text>
            </TouchableOpacity>
          )}
        </View>
      )}
    />
  );
};

const styles = StyleSheet.create({
  center: { flex: 1, justifyContent: 'center', alignItems: 'center', padding: 20 },
  loadingText: { color: '#4a5568', fontSize: 16, fontWeight: 'bold' },
  emptyText: { color: '#718096', textAlign: 'center', marginTop: 15, fontSize: 16 },
  listContainer: { padding: 15 },
  card: {
    backgroundColor: 'white',
    padding: 16,
    borderRadius: 8,
    marginBottom: 15,
    borderWidth: 1,
    borderColor: '#e2e8f0',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2
  },
  cardHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 },
  statusBadge: { backgroundColor: '#c6f6d5', color: '#22543d', paddingHorizontal: 8, paddingVertical: 4, borderRadius: 4, fontWeight: 'bold', fontSize: 12 },
  tag4x4: { backgroundColor: '#fed7d7', paddingHorizontal: 8, paddingVertical: 4, borderRadius: 4 },
  tagText: { color: '#822727', fontWeight: 'bold', fontSize: 12 },
  coordinateText: { fontSize: 15, fontWeight: 'bold', color: '#2d3748', marginBottom: 5 },
  windowText: { fontSize: 14, color: '#4a5568', marginBottom: 5 },
  radiusText: { fontSize: 14, color: '#dd6b20', fontWeight: 'bold', marginBottom: 10 },
  acceptButton: { backgroundColor: '#2b6cb0', padding: 12, borderRadius: 6, marginTop: 10 },
  acceptButtonText: { color: 'white', textAlign: 'center', fontWeight: 'bold' }
});

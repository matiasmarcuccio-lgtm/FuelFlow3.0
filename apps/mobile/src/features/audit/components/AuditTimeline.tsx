import React from 'react';
import { View, Text, StyleSheet, FlatList, ActivityIndicator } from 'react-native';
import { FontAwesome } from '@expo/vector-icons';
import { AccessLog } from '../hooks/useOfferChronology';

interface Props {
  logs: AccessLog[];
  isLoading: boolean;
}

export const AuditTimeline = ({ logs, isLoading }: Props) => {
  if (isLoading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color="#c53030" />
        <Text style={styles.loadingText}>Recuperando cadena de custodia...</Text>
      </View>
    );
  }

  if (!logs || logs.length === 0) {
    return (
      <View style={styles.center}>
        <FontAwesome name="shield" size={48} color="#e2e8f0" />
        <Text style={styles.emptyText}>No hay registros forenses para este ID.</Text>
      </View>
    );
  }

  const getActionIcon = (action: string) => {
    switch (action) {
      case 'INSERT': return { name: 'plus-circle' as any, color: '#38a169' }; // Verde
      case 'UPDATE': return { name: 'edit' as any, color: '#dd6b20' }; // Naranja
      case 'DELETE': return { name: 'trash' as any, color: '#e53e3e' }; // Rojo
      default: return { name: 'eye' as any, color: '#718096' };
    }
  };

  const getTableFriendlyName = (table: string) => {
    switch (table) {
      case 'load_offers': return 'Subasta / Carga';
      case 'cor_manifests': return 'Manifiesto CoR';
      case 'structural_elements': return 'Elemento BIM';
      default: return table;
    }
  };

  return (
    <FlatList
      data={logs}
      keyExtractor={(item) => item.id}
      contentContainerStyle={styles.listContainer}
      renderItem={({ item, index }) => {
        const iconInfo = getActionIcon(item.action);
        const isLast = index === logs.length - 1;
        
        return (
          <View style={styles.timelineRow}>
            {/* Eje de la línea de tiempo */}
            <View style={styles.timelineAxis}>
              <FontAwesome name={iconInfo.name} size={24} color={iconInfo.color} />
              {!isLast && <View style={styles.timelineLine} />}
            </View>
            
            {/* Contenido de la tarjeta */}
            <View style={styles.card}>
              <View style={styles.cardHeader}>
                <Text style={styles.actionText}>{item.action}</Text>
                <Text style={styles.dateText}>
                  {new Date(item.timestamp).toLocaleString()}
                </Text>
              </View>
              <Text style={styles.tableText}>Dominio: {getTableFriendlyName(item.table_name)}</Text>
              <Text style={styles.uuidText}>Traza: {item.id}</Text>
              <Text style={styles.uuidText}>Usuario: {item.user_id}</Text>
            </View>
          </View>
        );
      }}
    />
  );
};

const styles = StyleSheet.create({
  center: { flex: 1, justifyContent: 'center', alignItems: 'center', padding: 20 },
  loadingText: { color: '#4a5568', marginTop: 10, fontWeight: 'bold' },
  emptyText: { color: '#a0aec0', marginTop: 15, fontSize: 16 },
  listContainer: { padding: 20, paddingBottom: 50 },
  timelineRow: { flexDirection: 'row' },
  timelineAxis: { width: 40, alignItems: 'center', marginRight: 10 },
  timelineLine: { width: 2, flex: 1, backgroundColor: '#e2e8f0', marginTop: 5, marginBottom: 5 },
  card: { flex: 1, backgroundColor: 'white', padding: 15, borderRadius: 8, marginBottom: 20, borderWidth: 1, borderColor: '#e2e8f0', shadowColor: '#000', shadowOffset: { width: 0, height: 1 }, shadowOpacity: 0.1, shadowRadius: 2, elevation: 1 },
  cardHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 },
  actionText: { fontWeight: 'bold', fontSize: 16, color: '#2d3748' },
  dateText: { fontSize: 12, color: '#718096' },
  tableText: { fontSize: 14, color: '#4a5568', fontWeight: 'bold', marginBottom: 5 },
  uuidText: { fontSize: 11, color: '#a0aec0', fontFamily: 'monospace' }
});

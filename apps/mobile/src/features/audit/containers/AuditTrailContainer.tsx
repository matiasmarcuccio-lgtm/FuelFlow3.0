import React, { useRef, useState, useEffect } from 'react';
import { View, Text, ScrollView, StyleSheet, ActivityIndicator, TextInput, TouchableOpacity } from 'react-native';
import { useVirtualizer } from '@tanstack/react-virtual';
import { FontAwesome } from '@expo/vector-icons';
import { useAccessLogs } from '../hooks/useAccessLogs';
import { useOfferChronology } from '../hooks/useOfferChronology';
import { AuditTimeline } from '../components/AuditTimeline';
import { AccessDeniedScreen } from '../components/AccessDeniedScreen';
import { useComplianceStatus } from '../../compliance/hooks/useComplianceStatus';

const AuditRow = ({ data }: { data: any }) => (
  <View style={styles.row}>
    <Text style={styles.time}>{new Date(data.timestamp).toLocaleTimeString()}</Text>
    <Text style={[styles.action, data.action === 'DELETE' ? styles.alertAction : null]}>
      {data.action}
    </Text>
    <Text style={styles.table}>{data.table_name}</Text>
    <Text style={styles.idText} numberOfLines={1} ellipsizeMode="middle">{data.row_id}</Text>
  </View>
);

export const AuditTrailContainer = () => {
  const [searchInput, setSearchInput] = useState('');
  const [debouncedUuid, setDebouncedUuid] = useState('');

  // Efecto de Debounce: Evita espamear la base de datos mientras el usuario teclea
  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedUuid(searchInput);
    }, 500);
    return () => clearTimeout(handler);
  }, [searchInput]);

  // Obtenemos el perfil del usuario para verificación explícita de UI
  const { data: complianceData } = useComplianceStatus();

  // Hook 1: Lista global paginada (Si no hay búsqueda)
  const { data: globalData, isLoading: globalLoading, error: globalError, fetchNextPage, hasNextPage, isFetchingNextPage } = useAccessLogs();
  
  // Hook 2: Motor de búsqueda forense específico (Si hay un UUID válido)
  const { data: chronologyData, isLoading: chronologyLoading, error: chronologyError } = useOfferChronology(debouncedUuid);

  const globalLogs = globalData?.pages.flatMap(page => page) ?? [];
  const parentRef = useRef<ScrollView>(null);
  
  const rowVirtualizer = useVirtualizer({
    count: globalLogs.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 65,
  });

  const clearSearch = () => setSearchInput('');

  // Intercepción Táctica de Errores (Física de Red y Permisos RLS explícitos)
  const isAccessDenied = 
    complianceData?.role !== 'admin' || // Filtro explícito de UI Zero-Trust
    (globalError as any)?.code === 'PGRST116' || (globalError as any)?.code === '42501' || (globalError as any)?.status === 401 || (globalError as any)?.status === 403 ||
    (chronologyError as any)?.code === 'PGRST116' || (chronologyError as any)?.code === '42501' || (chronologyError as any)?.status === 401 || (chronologyError as any)?.status === 403;

  if (isAccessDenied) {
    return <AccessDeniedScreen />;
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Bitácora Forense</Text>
      
      {/* Buscador Forense */}
      <View style={styles.searchContainer}>
        <FontAwesome name="search" size={20} color="#718096" style={styles.searchIcon} />
        <TextInput
          style={styles.searchInput}
          placeholder="Rastrear Load Offer UUID..."
          value={searchInput}
          onChangeText={setSearchInput}
          autoCapitalize="none"
          autoCorrect={false}
        />
        {searchInput.length > 0 && (
          <TouchableOpacity onPress={clearSearch} style={styles.clearButton}>
            <FontAwesome name="times-circle" size={20} color="#a0aec0" />
          </TouchableOpacity>
        )}
      </View>

      {/* Renderizado Condicional: Cronología Específica vs Lista Global */}
      {debouncedUuid ? (
        <AuditTimeline logs={chronologyData || []} isLoading={chronologyLoading} />
      ) : (
        <>
          {globalLoading ? (
            <ActivityIndicator style={{ padding: 20 }} size="large" color="#c53030" />
          ) : (
            <ScrollView 
              ref={parentRef} 
              style={styles.scrollContainer}
              onScroll={(e) => {
                const { layoutMeasurement, contentOffset, contentSize } = e.nativeEvent;
                const isCloseToBottom = layoutMeasurement.height + contentOffset.y >= contentSize.height - 200;
                if (isCloseToBottom && hasNextPage && !isFetchingNextPage) fetchNextPage();
              }}
              scrollEventThrottle={16}
            >
              <View style={{ height: rowVirtualizer.getTotalSize(), position: 'relative' }}>
                {rowVirtualizer.getVirtualItems().map(virtualRow => (
                  <View
                    key={virtualRow.index}
                    style={{
                      position: 'absolute',
                      top: 0, left: 0, width: '100%',
                      height: virtualRow.size,
                      transform: [{ translateY: virtualRow.start }],
                    }}
                  >
                    <AuditRow data={globalLogs[virtualRow.index]} />
                  </View>
                ))}
              </View>
              
              {isFetchingNextPage && (
                <View style={styles.fetchingContainer}>
                  <ActivityIndicator color="#2b6cb0" />
                  <Text style={styles.fetchingText}>Extrayendo registros profundos...</Text>
                </View>
              )}
            </ScrollView>
          )}
        </>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f7fafc', padding: 15 },
  title: { fontSize: 20, fontWeight: 'bold', marginBottom: 15, color: '#1a202c', textAlign: 'center' },
  searchContainer: { flexDirection: 'row', alignItems: 'center', backgroundColor: 'white', borderRadius: 8, paddingHorizontal: 15, marginBottom: 20, borderWidth: 1, borderColor: '#cbd5e0' },
  searchIcon: { marginRight: 10 },
  searchInput: { flex: 1, height: 50, fontSize: 16, color: '#2d3748' },
  clearButton: { padding: 10 },
  scrollContainer: { flex: 1, backgroundColor: '#ffffff', borderRadius: 8, borderWidth: 1, borderColor: '#e2e8f0', elevation: 2 },
  row: { flexDirection: 'row', padding: 15, borderBottomWidth: 1, borderBottomColor: '#edf2f7', alignItems: 'center' },
  time: { fontSize: 12, color: '#718096', width: 70 },
  action: { fontSize: 12, fontWeight: 'bold', color: '#2b6cb0', width: 70 },
  alertAction: { color: '#e53e3e' },
  table: { fontSize: 13, color: '#2d3748', flex: 1, fontWeight: '600' },
  idText: { fontSize: 10, color: '#a0aec0', width: 60, textAlign: 'right' },
  fetchingContainer: { padding: 20, alignItems: 'center' },
  fetchingText: { fontSize: 12, color: 'gray', marginTop: 5 }
});

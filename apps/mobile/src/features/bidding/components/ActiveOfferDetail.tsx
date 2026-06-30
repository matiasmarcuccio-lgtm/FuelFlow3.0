import React from 'react';
import { View, Text, ActivityIndicator, StyleSheet } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { useLoadOfferSubscription } from '../hooks/useLoadOfferSubscription';

export const ActiveOfferDetail = ({ offerId }: { offerId: string }) => {
  // 1. Directiva Táctica: La Suscripción Realtime SOLO VIVE mientras este componente existe en el DOM.
  // Si el usuario vuelve a la lista principal, el useEffect del hook desmonta el WebSocket, salvando ancho de banda y batería.
  useLoadOfferSubscription(offerId);

  // 2. Consulta de Datos Base
  const { data, isLoading } = useQuery({
    queryKey: ['load_offer', offerId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('load_offers')
        .select('*')
        .eq('id', offerId)
        .single();
      
      if (error) throw error;
      return data;
    },
    // La mutabilidad la delegamos al hook de Realtime. El caché puede vivir para siempre a menos que Realtime lo invalide.
    staleTime: Infinity, 
  });

  if (isLoading) return <ActivityIndicator style={{ padding: 20 }} />;

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Oferta JIT #{offerId.slice(0, 8)}</Text>
      
      {/* 3. Reacción Inmediata (Zero-Reload) */}
      {data?.status === 'matched' ? (
        <View style={styles.matchBox}>
          <Text style={styles.matchText}>✅ Match JIT Encontrado</Text>
          <Text style={styles.infoText}>El motor geoespacial ha asignado un operador compatible con la física de tu obra.</Text>
        </View>
      ) : (
        <View style={styles.searchBox}>
          <ActivityIndicator size="small" color="#2b6cb0" />
          <Text style={styles.searchText}>Buscando operadores compatibles...</Text>
        </View>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: { padding: 20, backgroundColor: '#ffffff', flex: 1 },
  title: { fontSize: 18, fontWeight: 'bold', marginBottom: 20, color: '#2d3748' },
  matchBox: { backgroundColor: '#f0fff4', borderColor: '#9ae6b4', borderWidth: 1, padding: 15, borderRadius: 8 },
  matchText: { color: '#276749', fontWeight: 'bold', fontSize: 16 },
  infoText: { color: '#2f855a', marginTop: 8, fontSize: 13 },
  searchBox: { flexDirection: 'row', alignItems: 'center', backgroundColor: '#ebf8ff', borderColor: '#90cdf4', borderWidth: 1, padding: 15, borderRadius: 8 },
  searchText: { color: '#2b6cb0', fontWeight: 'bold', marginLeft: 15, fontSize: 14 }
});

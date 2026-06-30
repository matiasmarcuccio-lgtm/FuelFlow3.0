import React from 'react';
import { View, StyleSheet, ScrollView } from 'react-native';
import { BiddingContainer } from '../../src/features/bidding/containers/BiddingContainer';

export default function DashboardScreen() {
  return (
    <ScrollView style={styles.container}>
      {/* Contenedor de Subasta Logística (Solo accesible si ComplianceGuard lo permitió) */}
      <BiddingContainer />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f7fafc' }
});

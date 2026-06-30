import React from 'react';
import { View, StyleSheet, ScrollView } from 'react-native';
import { TripContainer } from '../../src/features/trip/containers/TripContainer';

export default function TripsScreen() {
  return (
    <ScrollView style={styles.container}>
      <TripContainer />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f7fafc' }
});

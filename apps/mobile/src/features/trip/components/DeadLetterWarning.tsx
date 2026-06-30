import React, { useEffect } from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { FontAwesome } from '@expo/vector-icons';
import { useShadowSyncStore } from '../stores/useShadowSyncStore';

export const DeadLetterWarning = () => {
  const events = useShadowSyncStore(state => state.events);
  const dlqEvents = events.filter(e => e.status === 'DLQ');

  if (dlqEvents.length === 0) return null;

  return (
    <View style={styles.container}>
      <View style={styles.alertRow}>
        <FontAwesome name="warning" size={24} color="white" />
        <View style={styles.textContainer}>
          <Text style={styles.title}>¡Falla de Sincronización (DLQ)!</Text>
          <Text style={styles.message}>
            {dlqEvents.length} reporte(s) bloqueado(s) permanentemente por el servidor. 
            Contacte a administración inmediatamente.
          </Text>
        </View>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    backgroundColor: '#c53030', // Rojo muy agresivo (Check Engine)
    padding: 15,
    margin: 10,
    borderRadius: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    elevation: 5,
  },
  alertRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  textContainer: {
    marginLeft: 15,
    flex: 1,
  },
  title: {
    color: 'white',
    fontWeight: 'bold',
    fontSize: 16,
    textTransform: 'uppercase',
  },
  message: {
    color: '#fed7d7',
    fontSize: 14,
    marginTop: 4,
  }
});

import React from 'react';
import { View, Text, StyleSheet } from 'react-native';

export const ErrorMessage = ({ error }: { error: any }) => {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Error Detectado (Rechazo de Bóveda)</Text>
      <Text style={styles.message}>{error?.message || "La base de datos rechazó la operación."}</Text>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    padding: 15,
    backgroundColor: '#fff5f5',
    borderColor: '#fc8181',
    borderWidth: 1,
    borderRadius: 8,
    marginTop: 15
  },
  title: {
    color: '#c53030',
    fontWeight: 'bold',
    marginBottom: 5
  },
  message: {
    color: '#e53e3e',
    fontSize: 14
  }
});

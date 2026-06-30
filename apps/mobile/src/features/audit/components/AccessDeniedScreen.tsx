import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { FontAwesome } from '@expo/vector-icons';

export const AccessDeniedScreen = () => {
  return (
    <View style={styles.container}>
      <View style={styles.iconContainer}>
        <FontAwesome name="ban" size={64} color="#e53e3e" />
      </View>
      <Text style={styles.title}>Acceso Restringido</Text>
      <Text style={styles.description}>
        Privilegios de Inspector Requeridos
      </Text>
      <Text style={styles.subtext}>
        Tu perfil operativo no tiene autorización legal para visualizar la cadena de custodia forense.
      </Text>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#fff5f5', // Fondo de advertencia suave
    padding: 30,
  },
  iconContainer: {
    marginBottom: 20,
    backgroundColor: '#fed7d7',
    padding: 20,
    borderRadius: 50,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#9b2c2c',
    marginBottom: 10,
    textAlign: 'center',
  },
  description: {
    fontSize: 18,
    color: '#c53030',
    fontWeight: '600',
    marginBottom: 15,
    textAlign: 'center',
  },
  subtext: {
    fontSize: 15,
    color: '#742a2a',
    textAlign: 'center',
    lineHeight: 22,
  },
});

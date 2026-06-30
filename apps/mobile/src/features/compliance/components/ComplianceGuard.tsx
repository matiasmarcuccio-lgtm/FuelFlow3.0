import React from 'react';
import { View, Text, ActivityIndicator, StyleSheet } from 'react-native';
import { useComplianceStatus } from '../hooks/useComplianceStatus';
import { ComplianceScreen } from './ComplianceScreen';

const LoadingScreen = () => (
  <View style={styles.loadingContainer}>
    <ActivityIndicator size="large" color="#2b6cb0" />
    <Text style={styles.loadingText}>Verificando estado de cumplimiento forense...</Text>
  </View>
);

export const ComplianceGuard = ({ children }: { children: React.ReactNode }) => {
  const { data, isLoading, isError } = useComplianceStatus();

  // El sistema bloquea todo hasta que el servidor responde (Zero-Trust UI)
  if (isLoading) return <LoadingScreen />; 
  
  if (isError || !data?.is_verified || !data?.insurance_compliant) {
    const fallbackStatus = data || { is_verified: false, insurance_compliant: false };
    return <ComplianceScreen status={fallbackStatus} />; // Redirección forzada al "Bunker" de documentos
  }

  return <>{children}</>; // Acceso concedido al resto de la aplicación
};

const styles = StyleSheet.create({
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#f7fafc',
    padding: 20
  },
  loadingText: {
    marginTop: 15,
    color: '#4a5568',
    fontSize: 16,
    textAlign: 'center',
    fontWeight: '500'
  }
});

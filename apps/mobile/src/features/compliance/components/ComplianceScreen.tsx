import React, { useState } from 'react';
import { View, Text, Button, TouchableOpacity, StyleSheet } from 'react-native';
import { router } from 'expo-router';
import { DocumentUpload } from './DocumentUpload';
import { supabase } from '@/lib/supabase';

// Tipo inferido para el status
type ComplianceStatus = {
  is_verified: boolean;
  insurance_compliant: boolean;
  hasPendingDoc?: boolean;
};

export const ComplianceScreen = ({ status }: { status: ComplianceStatus }) => {
  const [isUploading, setIsUploading] = useState(false);

  const handleSignOut = async () => {
    await supabase.auth.signOut();
    router.replace('/');
  };

  if (isUploading) {
    return <DocumentUpload onSuccess={() => setIsUploading(false)} />;
  }

  if (status.hasPendingDoc) {
    return (
      <View style={styles.container}>
        <Text style={styles.title}>En Revisión Administrativa</Text>
        
        <View style={[styles.alertBox, { borderColor: '#d69e2e', backgroundColor: '#fffff0' }]}>
          <Text style={[styles.alertTitle, { color: '#b7791f' }]}>Auditoría Pendiente</Text>
          <Text style={[styles.alertText, { color: '#b7791f' }]}>
            Hemos recibido su documento de cumplimiento. Un Administrador o Inspector de FuelFlow está validando la información. 
            Se le otorgará acceso automáticamente cuando se apruebe.
          </Text>
        </View>

        {/* Botón de Emergencia: Purgar JWT Corrupto */}
        <TouchableOpacity style={styles.signOutButton} onPress={handleSignOut}>
          <Text style={styles.signOutText}>Cerrar Sesión (Purgar JWT)</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Acceso Restringido</Text>
      
      {/* Explicación del estado basado en la lógica de negocio */}
      <View style={styles.alertBox}>
        <Text style={styles.alertTitle}>Requisito Pendiente</Text>
        <Text style={styles.alertText}>
          {status.insurance_compliant 
            ? "Su perfil requiere verificación administrativa." 
            : "Su póliza de seguro ha expirado o no existe. Debe cargarla para operar."}
        </Text>
      </View>

      {/* El "Botón de Salida" (Acción Correctiva) */}
      <Button 
        title="Subir Documentación de Seguro" 
        onPress={() => setIsUploading(true)} 
        color="#2b6cb0"
      />
      
      <Text style={styles.helpText}>
        Una vez subido, el sistema procesará su validación en tiempo real.
      </Text>

      {/* Botón de Emergencia: Purgar JWT Corrupto */}
      <TouchableOpacity style={styles.signOutButton} onPress={handleSignOut}>
        <Text style={styles.signOutText}>Cerrar Sesión (Purgar JWT)</Text>
      </TouchableOpacity>
    </View>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, padding: 20, justifyContent: 'center', backgroundColor: '#f7fafc' },
  title: { fontSize: 24, fontWeight: 'bold', color: '#2d3748', marginBottom: 20 },
  alertBox: { marginVertical: 20, padding: 15, backgroundColor: '#ffebe6', borderRadius: 8, borderWidth: 1, borderColor: '#feb2b2' },
  alertTitle: { color: '#c53030', fontWeight: 'bold', fontSize: 16 },
  alertText: { color: '#c53030', marginTop: 5, fontSize: 14 },
  helpText: { marginTop: 20, color: '#718096', textAlign: 'center', marginBottom: 40 },
  signOutButton: { marginTop: 'auto', padding: 15, backgroundColor: '#e2e8f0', borderRadius: 8, alignItems: 'center' },
  signOutText: { color: '#4a5568', fontWeight: 'bold' }
});

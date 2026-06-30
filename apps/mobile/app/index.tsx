import React, { useState, useEffect } from 'react';
import { Redirect } from 'expo-router';
import { View, Text, TextInput, TouchableOpacity, StyleSheet, ActivityIndicator, Alert } from 'react-native';
import { supabase } from '../src/lib/supabase';
import { FontAwesome } from '@expo/vector-icons';
import { useAuth } from '../src/providers/AuthProvider';

export default function IndexScreen() {
  const { session, isReady, setPendingFleetLink } = useAuth();
  const [isLoginMode, setIsLoginMode] = useState(true);
  
  // Phase 1 State (Fleet Token Filter)
  const [fleetToken, setFleetToken] = useState('');
  const [isTokenValidated, setIsTokenValidated] = useState(false);

  // Phase 2 State (Identity)
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [fullName, setFullName] = useState('');
  const [selectedRole, setSelectedRole] = useState('DRIVER_ABN');
  const [isLoading, setIsLoading] = useState(false);

  const handleTokenValidation = async () => {
    if (!fleetToken) {
      Alert.alert('Error', 'Debe ingresar el código de flota proporcionado por su despachador.');
      return;
    }
    setIsLoading(true);
    try {
      // Phase 1: Read-only validation to prevent dead identities
      const { data, error } = await supabase
        .from('fleet_invites')
        .select('id, expires_at, status')
        .eq('invite_token', fleetToken)
        .eq('status', 'ACTIVE')
        .single();

      if (error || !data) {
        throw new Error('El código de flota es inválido o ha caducado. Solicite uno nuevo.');
      }

      if (new Date(data.expires_at) < new Date()) {
        throw new Error('Este código de flota ha caducado.');
      }

      // Valid! Stash it in AuthProvider (SecureStore/AsyncStorage)
      await setPendingFleetLink(fleetToken);
      setIsTokenValidated(true);
    } catch (err: any) {
      Alert.alert('Filtro de Seguridad', err.message);
    } finally {
      setIsLoading(false);
    }
  };

  const handleAuth = async () => {
    if (!email || !password) {
      Alert.alert('Error', 'Por favor ingresa email y contraseña');
      return;
    }
    if (!isLoginMode && !fullName) {
      Alert.alert('Error', 'El nombre completo es obligatorio por requerimientos de auditoría CoR');
      return;
    }

    setIsLoading(true);
    try {
      if (isLoginMode) {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
      } else {
        // Phase 2: Identity Creation. The AuthSyncWorker will automatically pick up the stashed token
        // when the session becomes active and execute fn_consume_fleet_invite
        const { error } = await supabase.auth.signUp({ 
          email, 
          password,
          options: {
            data: { 
              full_name: fullName,
              role: selectedRole
            } 
          }
        });
        if (error) throw error;
        Alert.alert('Éxito', 'Cuenta creada. Su perfil ha sido vinculado a la flota.');
      }
    } catch (err: any) {
      Alert.alert('Error Operativo', err.message);
    } finally {
      setIsLoading(false);
    }
  };

  if (!isReady) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color="#2b6cb0" />
      </View>
    );
  }

  if (session) {
    return <Redirect href="/(app)" />;
  }

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <FontAwesome name="truck" size={48} color="#2b6cb0" />
        <Text style={styles.title}>FuelFlow CoR</Text>
        <Text style={styles.subtitle}>Plataforma Logística y Cadena de Responsabilidad</Text>
      </View>

      <View style={styles.formContainer}>
        {!isLoginMode && !isTokenValidated ? (
          // Phase 1 UI: Token Filter
          <View>
            <Text style={styles.phaseLabel}>Fase 1: Enrolamiento de Flota</Text>
            <TextInput
              style={styles.input}
              placeholder="Código de Flota (Token)"
              placeholderTextColor="#a0aec0"
              value={fleetToken}
              onChangeText={setFleetToken}
              autoCapitalize="characters"
            />
            <TouchableOpacity 
              style={styles.button} 
              onPress={handleTokenValidation}
              disabled={isLoading}
            >
              {isLoading ? (
                <ActivityIndicator color="#fff" />
              ) : (
                <Text style={styles.buttonText}>Validar Token</Text>
              )}
            </TouchableOpacity>
            
            <TouchableOpacity 
              style={styles.switchModeContainer}
              onPress={() => setIsLoginMode(true)}
            >
              <Text style={styles.switchModeText}>
                Ya tengo cuenta y estoy enrolado. Iniciar Sesión.
              </Text>
            </TouchableOpacity>
          </View>
        ) : (
          // Phase 2 UI: Identity or Standard Login
          <View>
            {!isLoginMode && (
              <>
                <Text style={styles.phaseLabel}>Fase 2: Identidad del Conductor</Text>
                <TextInput
                  style={styles.input}
                  placeholder="Nombre Completo"
                  placeholderTextColor="#a0aec0"
                  value={fullName}
                  onChangeText={setFullName}
                  autoCapitalize="words"
                />
                <Text style={styles.roleLabel}>Selecciona tu Rol Operativo:</Text>
                <View style={styles.roleSelector}>
                  <TouchableOpacity 
                    style={[styles.roleButton, selectedRole === 'DRIVER_ABN' && styles.roleButtonActive]}
                    onPress={() => setSelectedRole('DRIVER_ABN')}
                  >
                    <Text style={selectedRole === 'DRIVER_ABN' ? styles.roleButtonTextActive : styles.roleButtonText}>Dueño/Operador (ABN)</Text>
                  </TouchableOpacity>
                  <TouchableOpacity 
                    style={[styles.roleButton, selectedRole === 'DRIVER' && styles.roleButtonActive]}
                    onPress={() => setSelectedRole('DRIVER')}
                  >
                    <Text style={selectedRole === 'DRIVER' ? styles.roleButtonTextActive : styles.roleButtonText}>Conductor Flota (TFN)</Text>
                  </TouchableOpacity>
                </View>
              </>
            )}

            <TextInput
              style={styles.input}
              placeholder="Correo Electrónico"
              placeholderTextColor="#a0aec0"
              value={email}
              onChangeText={setEmail}
              keyboardType="email-address"
              autoCapitalize="none"
            />
            
            <TextInput
              style={styles.input}
              placeholder="Contraseña"
              placeholderTextColor="#a0aec0"
              value={password}
              onChangeText={setPassword}
              secureTextEntry
            />

            <TouchableOpacity 
              style={styles.button} 
              onPress={handleAuth}
              disabled={isLoading}
            >
              {isLoading ? (
                <ActivityIndicator color="#fff" />
              ) : (
                <Text style={styles.buttonText}>
                  {isLoginMode ? 'INICIAR SESIÓN' : 'CREAR CUENTA Y VINCULAR'}
                </Text>
              )}
            </TouchableOpacity>

            <TouchableOpacity 
              style={styles.switchModeContainer}
              onPress={() => {
                setIsLoginMode(!isLoginMode);
                if (isLoginMode) setIsTokenValidated(false); // Reset to Phase 1 if going to sign up
              }}
            >
              <Text style={styles.switchModeText}>
                {isLoginMode 
                  ? '¿No tienes cuenta? Enrólate en una flota' 
                  : 'Cancelar Enrolamiento'}
              </Text>
            </TouchableOpacity>
          </View>
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  container: { flex: 1, backgroundColor: '#f7fafc', padding: 20, justifyContent: 'center' },
  header: { alignItems: 'center', marginBottom: 40 },
  title: { fontSize: 32, fontWeight: 'bold', color: '#2d3748', marginTop: 10 },
  subtitle: { fontSize: 14, color: '#718096', marginTop: 5, textAlign: 'center' },
  formContainer: { backgroundColor: 'white', padding: 20, borderRadius: 10, shadowColor: '#000', shadowOpacity: 0.1, shadowRadius: 10, elevation: 5 },
  input: { backgroundColor: '#edf2f7', padding: 15, borderRadius: 8, marginBottom: 15, fontSize: 16, color: '#2d3748' },
  button: { backgroundColor: '#2b6cb0', padding: 15, borderRadius: 8, alignItems: 'center', marginTop: 10 },
  buttonText: { color: 'white', fontWeight: 'bold', fontSize: 16 },
  switchModeContainer: {
    marginTop: 20,
    alignItems: 'center',
  },
  switchModeText: {
    color: '#a0aec0',
    fontSize: 14,
  },
  phaseLabel: {
    color: '#63b3ed',
    fontWeight: 'bold',
    marginBottom: 10,
    fontSize: 12,
    textTransform: 'uppercase',
  },
  roleLabel: { color: '#4a5568', fontWeight: 'bold', marginBottom: 10, marginTop: 5 },
  roleSelector: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginBottom: 15 },
  roleButton: { paddingVertical: 8, paddingHorizontal: 12, borderRadius: 20, backgroundColor: '#edf2f7', borderWidth: 1, borderColor: '#e2e8f0' },
  roleButtonActive: { backgroundColor: '#ebf8ff', borderColor: '#3182ce' },
  roleButtonText: { color: '#4a5568', fontSize: 12 },
  roleButtonTextActive: { color: '#3182ce', fontWeight: 'bold' }
});

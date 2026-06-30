import React from 'react';
import { useForm, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { LoadOfferSchema, LoadOfferInput } from '../schema';
import { View, TextInput, Text, Switch, StyleSheet, ScrollView, TouchableOpacity } from 'react-native';

interface Props {
  onSubmit: (data: LoadOfferInput) => void;
  disabled: boolean;
}

export const LoadOfferForm = ({ onSubmit, disabled }: Props) => {
  // 1. Inyección de Zod con modo 'onChange' para habilitar Visualización de Estado Inmediato
  const { control, handleSubmit, formState: { errors, isValid } } = useForm<LoadOfferInput>({
    resolver: zodResolver(LoadOfferSchema),
    mode: 'onChange', // CRÍTICO: Permite que 'isValid' reaccione en tiempo real por cada tecla presionada
    defaultValues: {
      contractor_id: '00000000-0000-0000-0000-000000000000', 
      requires_4x4_traction: false,
    }
  });

  return (
    <ScrollView style={styles.container} keyboardShouldPersistTaps="handled">
      
      {/* Visualización de Estado Inmediato (Tu nueva directiva) */}
      <View style={[styles.statusBanner, isValid ? styles.statusLegal : styles.statusIllegal]}>
        <Text style={[styles.statusText, isValid ? styles.textLegal : styles.textIllegal]}>
          {isValid 
            ? "✅ ESQUEMA LEGAL: La carga cumple con la física de la obra." 
            : "⚠️ INVIABLE: Violación estructural o datos faltantes."}
        </Text>
      </View>

      <Text style={styles.title}>Definición Geoespacial</Text>

      {/* Latitud Destino (Oculto en tu snippet, pero requerido por Zod para no fallar) */}
      <Controller
        control={control}
        name="destination_lat"
        render={({ field: { onChange, onBlur, value } }) => (
          <View style={styles.inputGroup}>
            <Text style={styles.label}>Latitud Destino</Text>
            <TextInput 
              style={[styles.input, errors.destination_lat && styles.inputError]}
              keyboardType="numeric"
              onBlur={onBlur}
              onChangeText={val => onChange(parseFloat(val))}
              value={value ? value.toString() : ''}
              editable={!disabled}
            />
          </View>
        )}
      />

      {/* Longitud Destino */}
      <Controller
        control={control}
        name="destination_lng"
        render={({ field: { onChange, onBlur, value } }) => (
          <View style={styles.inputGroup}>
            <Text style={styles.label}>Longitud Destino</Text>
            <TextInput 
              style={[styles.input, errors.destination_lng && styles.inputError]}
              keyboardType="numeric"
              onBlur={onBlur}
              onChangeText={val => onChange(parseFloat(val))}
              value={value ? value.toString() : ''}
              editable={!disabled}
            />
          </View>
        )}
      />

      {/* Táctico: Inyección automática de ventanas de grúa ISO para Zod */}
      <Controller
        control={control}
        name="crane_window_start"
        render={({ field: { onChange, value } }) => {
          if (!value) onChange(new Date().toISOString());
          return <View />;
        }}
      />
      <Controller
        control={control}
        name="crane_window_end"
        render={({ field: { onChange, value } }) => {
          if (!value) {
            const end = new Date(); end.setHours(end.getHours() + 4);
            onChange(end.toISOString());
          }
          return <View />;
        }}
      />

      <Text style={styles.title}>Restricciones de Equipo (HVNL)</Text>

      {/* Tracción 4x4 */}
      <Controller
        control={control}
        name="requires_4x4_traction"
        render={({ field: { onChange, value } }) => (
          <View style={[styles.inputGroup, styles.switchGroup]}>
            <Text style={styles.label}>¿Requiere tracción 4x4?</Text>
            <Switch onValueChange={onChange} value={value} disabled={disabled} />
          </View>
        )}
      />

      {/* Radio de Giro (Destacado en tu directiva) */}
      <Controller
        control={control}
        name="max_turn_radius_m"
        render={({ field: { onChange, onBlur, value } }) => (
          <View style={styles.inputGroup}>
            <Text style={styles.label}>Radio de giro máximo (metros)</Text>
            <TextInput 
              style={[styles.input, errors.max_turn_radius_m && styles.inputError]}
              keyboardType="numeric"
              onBlur={onBlur}
              onChangeText={val => onChange(Number(val))}
              value={value?.toString()}
              editable={!disabled}
            />
            {errors.max_turn_radius_m && <Text style={styles.errorText}>{errors.max_turn_radius_m.message}</Text>}
          </View>
        )}
      />

      {/* Botón Táctico (Reacciona al estado de Red y al estado de Zod) */}
      <TouchableOpacity 
        onPress={handleSubmit(onSubmit)} 
        disabled={disabled || !isValid}
        style={{ 
          backgroundColor: (disabled || !isValid) ? '#a0aec0' : '#2b6cb0', 
          padding: 16, 
          borderRadius: 8,
          marginTop: 10,
          marginBottom: 40,
          shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.2, shadowRadius: 3, elevation: 4 
        }}
      >
        <Text style={{ color: 'white', textAlign: 'center', fontWeight: 'bold', fontSize: 16 }}>
          {disabled ? "Procesando..." : "Validar y Enviar Oferta"}
        </Text>
      </TouchableOpacity>
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: { padding: 20 },
  statusBanner: { padding: 15, borderRadius: 8, marginBottom: 20, borderWidth: 1 },
  statusLegal: { backgroundColor: '#f0fff4', borderColor: '#9ae6b4' },
  statusIllegal: { backgroundColor: '#fff5f5', borderColor: '#feb2b2' },
  statusText: { fontSize: 14, fontWeight: 'bold', textAlign: 'center' },
  textLegal: { color: '#276749' },
  textIllegal: { color: '#c53030' },
  title: { fontSize: 16, fontWeight: 'bold', color: '#2d3748', marginBottom: 15, paddingBottom: 5, borderBottomWidth: 1, borderBottomColor: '#e2e8f0', marginTop: 10 },
  inputGroup: { marginBottom: 15 },
  switchGroup: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', backgroundColor: '#f7fafc', padding: 15, borderRadius: 6, borderWidth: 1, borderColor: '#e2e8f0' },
  label: { fontSize: 13, fontWeight: 'bold', color: '#4a5568', marginBottom: 8 },
  input: { borderWidth: 1, borderColor: '#cbd5e0', padding: 14, borderRadius: 6, backgroundColor: '#ffffff', fontSize: 16 },
  inputError: { borderColor: '#e53e3e', backgroundColor: '#fff5f5' },
  errorText: { color: '#e53e3e', fontSize: 12, marginTop: 6, fontWeight: '500' }
});

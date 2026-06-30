import React, { useState, useCallback } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, TextInput } from 'react-native';
import { FontAwesome } from '@expo/vector-icons';
import { useFocusEffect } from 'expo-router';
import { LoadOfferData } from '../../bidding/components/OfferListPresenter';

interface Props {
  trip: LoadOfferData;
  onSignManifest: () => void;
  onReportArrival: () => void;
  onReportIncident: (description: string) => void;
  onRequestDetach: (reason: string) => void;
  isGeofenceUnlocked: boolean;
  isDetaching?: boolean;
}

export const ActiveTripDashboard = ({ trip, onSignManifest, onReportArrival, onReportIncident, onRequestDetach, isGeofenceUnlocked, isDetaching }: Props) => {
  const [hasSworn, setHasSworn] = useState(false);
  const [incidentText, setIncidentText] = useState('');
  
  // Detach state
  const [showDetachOptions, setShowDetachOptions] = useState(false);
  const [detachReason, setDetachReason] = useState<string>('');

  // Prevención de Estado Fantasma
  useFocusEffect(
    useCallback(() => {
      return () => {
        setHasSworn(false);
        setIncidentText('');
        setShowDetachOptions(false);
        setDetachReason('');
      };
    }, [])
  );

  const handleDetachSubmit = () => {
    if (detachReason) {
      onRequestDetach(detachReason);
      setShowDetachOptions(false);
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <FontAwesome name="truck" size={32} color="#2b6cb0" />
        <Text style={styles.title}>Operación Logística Activa</Text>
      </View>
      
      {isDetaching && (
        <View style={styles.detachWarningBox}>
          <FontAwesome name="info-circle" size={24} color="#dd6b20" />
          <Text style={styles.detachWarningText}>
            Desacople programado. Podrás descansar al completar esta entrega.
          </Text>
        </View>
      )}

      <View style={styles.card}>
        <Text style={styles.label}>Estado Actual</Text>
        <Text style={[styles.statusText, trip.status === 'MANIFEST_PENDING' ? styles.statusWarning : styles.statusActive]}>
          {trip.status === 'MANIFEST_PENDING' ? 'PENDIENTE DE MANIFIESTO CoR' : 'EN TRÁNSITO'}
        </Text>
        
        <View style={styles.separator} />
        
        <Text style={styles.label}>Destino Estratégico</Text>
        <Text style={styles.value}>
          LAT: {trip.destination_lat.toFixed(6)}{'\n'}
          LNG: {trip.destination_lng.toFixed(6)}
        </Text>
      </View>

      <View style={styles.actionContainer}>
        {trip.status === 'MANIFEST_PENDING' ? (
          <View style={styles.corContainer}>
            <TouchableOpacity 
              style={styles.checkboxRow} 
              onPress={() => setHasSworn(!hasSworn)}
              activeOpacity={0.7}
            >
              <FontAwesome 
                name={hasSworn ? "check-square-o" : "square-o"} 
                size={24} 
                color={hasSworn ? "#2b6cb0" : "#a0aec0"} 
              />
              <Text style={styles.corOathText}>
                Declaro bajo juramento que he verificado la carga
              </Text>
            </TouchableOpacity>

            <TouchableOpacity 
              style={[styles.signButton, !hasSworn && styles.disabledButton]} 
              onPress={onSignManifest}
              disabled={!hasSworn}
            >
              <FontAwesome name="pencil-square-o" size={20} color="white" />
              <Text style={styles.buttonText}>Firmar Manifiesto CoR (Salida)</Text>
            </TouchableOpacity>
          </View>
        ) : (
          <View style={styles.transitContainer}>
            {!isGeofenceUnlocked && (
              <View style={styles.geofenceWarning}>
                <FontAwesome name="lock" size={24} color="#718096" />
                <Text style={styles.geofenceText}>Aproximándose a la zona de espera...</Text>
              </View>
            )}

            <TouchableOpacity 
              style={[styles.arriveButton, !isGeofenceUnlocked && styles.disabledButton]} 
              onPress={onReportArrival}
              disabled={!isGeofenceUnlocked}
            >
              <FontAwesome name={isGeofenceUnlocked ? "unlock" : "lock"} size={20} color="white" />
              <Text style={styles.buttonText}>Reportar Llegada a Destino</Text>
            </TouchableOpacity>

            {/* DETACH CONTROLS */}
            {!isDetaching && (
              <View style={styles.detachContainer}>
                {!showDetachOptions ? (
                  <TouchableOpacity 
                    style={styles.detachRequestButton} 
                    onPress={() => setShowDetachOptions(true)}
                  >
                    <FontAwesome name="power-off" size={20} color="#dd6b20" />
                    <Text style={styles.detachRequestText}>Solicitar Desacople al Finalizar Ciclo</Text>
                  </TouchableOpacity>
                ) : (
                  <View style={styles.detachOptionsBox}>
                    <Text style={styles.detachOptionsTitle}>Motivo del Desacople</Text>
                    
                    {['FATIGUE_BREAK', 'END_OF_SHIFT', 'REFUELING'].map(reason => (
                      <TouchableOpacity 
                        key={reason}
                        style={[styles.detachOptionButton, detachReason === reason && styles.detachOptionSelected]}
                        onPress={() => setDetachReason(reason)}
                      >
                        <Text style={[styles.detachOptionText, detachReason === reason && styles.detachOptionTextSelected]}>
                          {reason.replace(/_/g, ' ')}
                        </Text>
                      </TouchableOpacity>
                    ))}

                    <View style={styles.detachActionRow}>
                      <TouchableOpacity 
                        style={styles.detachCancelBtn} 
                        onPress={() => setShowDetachOptions(false)}
                      >
                        <Text style={styles.detachCancelText}>Cancelar</Text>
                      </TouchableOpacity>
                      
                      <TouchableOpacity 
                        style={[styles.detachConfirmBtn, !detachReason && styles.disabledButton]} 
                        onPress={handleDetachSubmit}
                        disabled={!detachReason}
                      >
                        <Text style={styles.buttonText}>Confirmar</Text>
                      </TouchableOpacity>
                    </View>
                  </View>
                )}
              </View>
            )}
            
            <View style={styles.incidentBox}>
              <Text style={styles.incidentTitle}>Registro de Excepciones CoR</Text>
              <TextInput 
                style={styles.incidentInput}
                placeholder="Describa desplazamiento de carga, falla de vehículo..."
                placeholderTextColor="#a0aec0"
                value={incidentText}
                onChangeText={setIncidentText}
                multiline
              />
              <TouchableOpacity 
                style={[styles.incidentButton, !incidentText.trim() && styles.disabledIncidentButton]} 
                onPress={() => {
                  if(incidentText.trim()) {
                    onReportIncident(incidentText);
                    setIncidentText('');
                  }
                }}
                disabled={!incidentText.trim()}
              >
                <FontAwesome name="warning" size={20} color="white" />
                <Text style={styles.buttonText}>REPORTAR INCIDENCIA FORENSE</Text>
              </TouchableOpacity>
            </View>
          </View>
        )}
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: { padding: 20 },
  header: { flexDirection: 'row', alignItems: 'center', marginBottom: 20 },
  title: { fontSize: 22, fontWeight: 'bold', color: '#2d3748', marginLeft: 15 },
  detachWarningBox: { flexDirection: 'row', alignItems: 'center', backgroundColor: '#feebc8', padding: 15, borderRadius: 8, borderWidth: 1, borderColor: '#f6ad55', marginBottom: 15 },
  detachWarningText: { marginLeft: 10, color: '#c05621', fontWeight: 'bold', flex: 1 },
  card: { backgroundColor: 'white', padding: 20, borderRadius: 10, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.1, shadowRadius: 4, elevation: 3 },
  label: { fontSize: 13, color: '#718096', fontWeight: 'bold', textTransform: 'uppercase', marginBottom: 5 },
  value: { fontSize: 16, color: '#2d3748', marginBottom: 15, fontWeight: '500' },
  separator: { height: 1, backgroundColor: '#e2e8f0', marginVertical: 10 },
  statusText: { fontSize: 18, fontWeight: 'bold', marginBottom: 15 },
  statusWarning: { color: '#dd6b20' },
  statusActive: { color: '#38a169' },
  actionContainer: { marginTop: 30 },
  corContainer: { backgroundColor: '#ebf8ff', padding: 15, borderRadius: 8, borderWidth: 1, borderColor: '#bee3f8' },
  checkboxRow: { flexDirection: 'row', alignItems: 'center', marginBottom: 15 },
  corOathText: { flex: 1, fontSize: 14, color: '#2a4365', fontWeight: 'bold', marginLeft: 10 },
  signButton: { backgroundColor: '#ed8936', flexDirection: 'row', padding: 15, borderRadius: 8, justifyContent: 'center', alignItems: 'center' },
  disabledButton: { backgroundColor: '#cbd5e0' },
  transitContainer: { gap: 20 },
  arriveButton: { backgroundColor: '#48bb78', flexDirection: 'row', padding: 15, borderRadius: 8, justifyContent: 'center', alignItems: 'center' },
  geofenceWarning: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', backgroundColor: '#edf2f7', padding: 15, borderRadius: 8, marginBottom: 5 },
  geofenceText: { marginLeft: 10, color: '#4a5568', fontWeight: 'bold' },
  
  // Detach Styles
  detachContainer: { marginTop: 10 },
  detachRequestButton: { flexDirection: 'row', backgroundColor: '#fffaf0', borderColor: '#fbd38d', borderWidth: 2, padding: 15, borderRadius: 8, justifyContent: 'center', alignItems: 'center' },
  detachRequestText: { color: '#dd6b20', fontWeight: 'bold', fontSize: 14, marginLeft: 10, textTransform: 'uppercase' },
  detachOptionsBox: { backgroundColor: '#fffaf0', padding: 15, borderRadius: 8, borderWidth: 1, borderColor: '#fbd38d' },
  detachOptionsTitle: { color: '#dd6b20', fontWeight: 'bold', marginBottom: 10, textAlign: 'center' },
  detachOptionButton: { padding: 10, borderWidth: 1, borderColor: '#cbd5e0', borderRadius: 5, marginBottom: 8, backgroundColor: 'white' },
  detachOptionSelected: { borderColor: '#dd6b20', backgroundColor: '#feebc8' },
  detachOptionText: { textAlign: 'center', color: '#4a5568', fontWeight: '600' },
  detachOptionTextSelected: { color: '#c05621', fontWeight: 'bold' },
  detachActionRow: { flexDirection: 'row', justifyContent: 'space-between', marginTop: 10 },
  detachCancelBtn: { flex: 1, padding: 12, justifyContent: 'center', alignItems: 'center' },
  detachCancelText: { color: '#a0aec0', fontWeight: 'bold' },
  detachConfirmBtn: { flex: 1, backgroundColor: '#dd6b20', padding: 12, borderRadius: 5, justifyContent: 'center', alignItems: 'center' },
  
  incidentBox: { backgroundColor: '#fff5f5', padding: 15, borderRadius: 8, borderWidth: 2, borderColor: '#fc8181', marginTop: 20 },
  incidentTitle: { color: '#c53030', fontWeight: 'bold', marginBottom: 10, fontSize: 14, textTransform: 'uppercase' },
  incidentInput: { backgroundColor: 'white', borderWidth: 1, borderColor: '#feb2b2', borderRadius: 5, padding: 10, minHeight: 80, textAlignVertical: 'top', marginBottom: 10 },
  incidentButton: { backgroundColor: '#e53e3e', flexDirection: 'row', padding: 15, borderRadius: 8, justifyContent: 'center', alignItems: 'center' },
  disabledIncidentButton: { backgroundColor: '#fc8181' },
  buttonText: { color: 'white', fontWeight: 'bold', fontSize: 16, marginLeft: 10 }
});

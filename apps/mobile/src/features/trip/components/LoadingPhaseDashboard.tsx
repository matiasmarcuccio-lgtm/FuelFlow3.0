import React, { useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, TextInput, Image, Alert, Modal } from 'react-native';
import { FontAwesome } from '@expo/vector-icons';
import { EvidenceCamera } from './EvidenceCamera';
import { EvidenceQueue } from '../utils/EvidenceQueue';
import { LoadOfferData } from '../../bidding/components/OfferListPresenter';

interface VehicleData {
  id: string;
  tare_weight: number;
  gvm_limit: number;
  registration_plate: string;
}

interface Props {
  trip: LoadOfferData;
  vehicle: VehicleData | null;
  onComplete: (grossMass: number, localImageUri: string) => void;
}

export const LoadingPhaseDashboard = ({ trip, vehicle, onComplete }: Props) => {
  const [grossMassText, setGrossMassText] = useState('');
  const [imageUri, setImageUri] = useState<string | null>(null);
  const [isCameraActive, setIsCameraActive] = useState(false);

  // Forensic Override State
  const [overridePressStart, setOverridePressStart] = useState<number | null>(null);
  const [showIncidentOverlay, setShowIncidentOverlay] = useState(false);
  const [incidentReason, setIncidentReason] = useState<string | null>(null);

  if (!vehicle) {
    return (
      <View style={styles.center}>
        <Text style={styles.errorText}>No hay vehículo asignado a este perfil.</Text>
        <Text style={styles.subText}>Contacte a su administrador de flota.</Text>
      </View>
    );
  }

  const parsedMass = parseFloat(grossMassText) || 0;
  const isOverloaded = parsedMass > vehicle.gvm_limit;
  const isLegal = parsedMass > vehicle.tare_weight && !isOverloaded;

  const handleCaptureImage = () => {
    setIsCameraActive(true);
  };

  const handleCameraCapture = async (compressedUri: string) => {
    setIsCameraActive(false);
    setImageUri(compressedUri);
    // Automatically enqueue to survival queue
    try {
      await EvidenceQueue.enqueue(trip.id, compressedUri);
    } catch (e) {
      console.error('Queue error:', e);
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <FontAwesome name="balance-scale" size={32} color="#2b6cb0" />
        <Text style={styles.title}>Fase de Carga (Digital Docket)</Text>
      </View>

      <View style={styles.card}>
        <Text style={styles.label}>Vehículo: {vehicle.registration_plate}</Text>
        <View style={styles.statsRow}>
          <View>
            <Text style={styles.statLabel}>Tara</Text>
            <Text style={styles.statValue}>{vehicle.tare_weight} kg</Text>
          </View>
          <View>
            <Text style={styles.statLabel}>GVM Límite</Text>
            <Text style={styles.statValue}>{vehicle.gvm_limit} kg</Text>
          </View>
        </View>
      </View>

      <View style={[styles.card, isOverloaded ? styles.cardError : null]}>
        <Text style={styles.label}>Ingrese Masa Bruta (kg)</Text>
        <TextInput 
          style={[styles.input, isOverloaded ? styles.inputError : null]}
          keyboardType="numeric"
          placeholder="Ej. 42500"
          value={grossMassText}
          onChangeText={setGrossMassText}
        />
        {isOverloaded && (
          <Text style={styles.overloadText}>
            <FontAwesome name="warning" /> SOBRECARGA HVNL DETECTADA
          </Text>
        )}
      </View>

      <View style={styles.cameraSection}>
        <Text style={styles.label}>Evidencia Forense (Tíquet / Visor)</Text>
        {!imageUri ? (
          <TouchableOpacity 
            style={[styles.cameraButton, !isLegal && styles.cameraButtonDisabled]}
            disabled={!isLegal}
            onPress={handleCaptureImage}
          >
            <FontAwesome name="camera" size={24} color={!isLegal ? '#a0aec0' : '#3182ce'} />
            <Text style={[styles.cameraText, !isLegal && {color: '#a0aec0'}]}>
              Capturar Evidencia (Hardware Lock)
            </Text>
          </TouchableOpacity>
        ) : (
          <View style={styles.imagePreviewContainer}>
            <Image source={{ uri: imageUri }} style={styles.imagePreview} />
            <TouchableOpacity style={styles.removeImageButton} onPress={() => setImageUri(null)}>
              <FontAwesome name="times" size={16} color="#fff" />
            </TouchableOpacity>
            <Text style={styles.enqueuedText}>
              <FontAwesome name="check-circle" color="#48bb78" /> Enqueued for Upload
            </Text>
          </View>
        )}
      </View>

      <TouchableOpacity 
        style={[styles.submitButton, (!isLegal || !imageUri) && styles.submitButtonDisabled]}
        disabled={!isLegal || !imageUri}
        onPress={() => onComplete(parsedMass, imageUri!)}
      >
        <Text style={styles.submitButtonText}>SELLAR TÍQUET & CONTINUAR</Text>
      </TouchableOpacity>

      <Modal visible={isCameraActive} animationType="slide" onRequestClose={() => setIsCameraActive(false)}>
        <EvidenceCamera 
          onCapture={handleCameraCapture} 
          onCancel={() => setIsCameraActive(false)} 
        />
      </Modal>

      <TouchableOpacity 
        style={styles.overrideButton}
        onPressIn={() => setOverridePressStart(Date.now())}
        onPressOut={() => {
          if (overridePressStart && (Date.now() - overridePressStart >= 3000)) {
            setShowIncidentOverlay(true);
          }
          setOverridePressStart(null);
        }}
      >
        <FontAwesome name="shield" size={16} color="#9f7aea" />
        <Text style={styles.overrideText}>MANTENER 3s PARA OVERRIDE DE EMERGENCIA</Text>
      </TouchableOpacity>

      {showIncidentOverlay && (
        <View style={styles.overlay}>
          <View style={styles.overlayCard}>
            <Text style={styles.overlayTitle}>Declaración de Incidente CoR</Text>
            <Text style={styles.overlaySub}>Seleccione la naturaleza de la falla operativa que obliga el Override:</Text>
            
            <TouchableOpacity 
              style={[styles.incidentOption, incidentReason === 'MECHANICAL' && styles.incidentOptionSelected]}
              onPress={() => setIncidentReason('MECHANICAL')}
            >
              <Text style={styles.incidentOptionText}>Falla Mecánica (Báscula/Tablet)</Text>
            </TouchableOpacity>

            <TouchableOpacity 
              style={[styles.incidentOption, incidentReason === 'OPERATIONAL' && styles.incidentOptionSelected]}
              onPress={() => setIncidentReason('OPERATIONAL')}
            >
              <Text style={styles.incidentOptionText}>Emergencia Operativa (Sitio)</Text>
            </TouchableOpacity>

            <TouchableOpacity 
              style={[styles.completeButton, !incidentReason && styles.completeButtonDisabled, { marginTop: 20 }]}
              disabled={!incidentReason}
              onPress={() => {
                onComplete(parsedMass, `OVERRIDE_${incidentReason}`);
              }}
            >
              <Text style={styles.buttonText}>FORZAR SALIDA Y ASUMIR RESPONSABILIDAD</Text>
            </TouchableOpacity>
            
            <TouchableOpacity onPress={() => setShowIncidentOverlay(false)} style={{ marginTop: 15 }}>
              <Text style={{ textAlign: 'center', color: '#718096' }}>Cancelar</Text>
            </TouchableOpacity>
          </View>
        </View>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: { padding: 20 },
  header: { flexDirection: 'row', alignItems: 'center', marginBottom: 20 },
  title: { fontSize: 22, fontWeight: 'bold', color: '#2d3748', marginLeft: 15 },
  card: { backgroundColor: 'white', padding: 20, borderRadius: 10, marginBottom: 15, shadowColor: '#000', shadowOpacity: 0.1, shadowRadius: 4, elevation: 3 },
  cardError: { borderWidth: 2, borderColor: '#e53e3e', backgroundColor: '#fff5f5' },
  label: { fontSize: 14, color: '#4a5568', fontWeight: 'bold', marginBottom: 10, textTransform: 'uppercase' },
  statsRow: { flexDirection: 'row', justifyContent: 'space-between', marginTop: 10 },
  statLabel: { fontSize: 12, color: '#718096' },
  statValue: { fontSize: 18, fontWeight: 'bold', color: '#2d3748' },
  input: { borderWidth: 1, borderColor: '#cbd5e0', borderRadius: 8, padding: 15, fontSize: 24, fontWeight: 'bold', textAlign: 'center', backgroundColor: '#f7fafc' },
  inputError: { borderColor: '#e53e3e', color: '#e53e3e' },
  overloadText: { color: '#e53e3e', fontWeight: 'bold', textAlign: 'center', marginTop: 10 },
  cameraSection: { backgroundColor: 'white', padding: 20, borderRadius: 10, marginBottom: 20, alignItems: 'center' },
  cameraButton: { backgroundColor: '#f7fafc', borderWidth: 2, borderStyle: 'dashed', borderColor: '#cbd5e0', padding: 20, borderRadius: 8, width: '100%', justifyContent: 'center', alignItems: 'center' },
  cameraButtonDisabled: { borderColor: '#e2e8f0', backgroundColor: '#f7fafc' },
  cameraText: { color: '#3182ce', fontWeight: 'bold', marginTop: 8 },
  imagePreviewContainer: { width: '100%', position: 'relative' },
  imagePreview: { width: '100%', height: 200, borderRadius: 8 },
  removeImageButton: { position: 'absolute', top: 5, right: 5, backgroundColor: 'rgba(0,0,0,0.6)', padding: 8, borderRadius: 15 },
  enqueuedText: { color: '#48bb78', fontSize: 12, marginTop: 5, fontWeight: 'bold', textAlign: 'center' },
  submitButton: { backgroundColor: '#38a169', padding: 15, borderRadius: 8, alignItems: 'center' },
  submitButtonDisabled: { backgroundColor: '#cbd5e0' },
  submitButtonText: { color: 'white', fontWeight: 'bold', fontSize: 16 },
  completeButton: { backgroundColor: '#38a169', flexDirection: 'row', padding: 15, borderRadius: 8, justifyContent: 'center', alignItems: 'center' },
  completeButtonDisabled: { backgroundColor: '#cbd5e0' },
  buttonText: { color: 'white', fontWeight: 'bold', fontSize: 16, marginLeft: 10 },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center', padding: 20 },
  errorText: { color: '#e53e3e', fontSize: 18, fontWeight: 'bold' },
  subText: { color: '#718096', marginTop: 10 },
  overrideButton: { marginTop: 20, flexDirection: 'row', justifyContent: 'center', alignItems: 'center', padding: 10, borderWidth: 1, borderColor: '#d6bcfa', borderRadius: 8, backgroundColor: '#faf5ff' },
  overrideText: { color: '#805ad5', fontSize: 12, fontWeight: 'bold', marginLeft: 8 },
  overlay: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(0,0,0,0.8)', justifyContent: 'center', alignItems: 'center', padding: 20, zIndex: 100 },
  overlayCard: { backgroundColor: 'white', padding: 20, borderRadius: 12, width: '100%' },
  overlayTitle: { fontSize: 20, fontWeight: 'bold', color: '#e53e3e', marginBottom: 10, textAlign: 'center' },
  overlaySub: { fontSize: 14, color: '#4a5568', marginBottom: 20, textAlign: 'center' },
  incidentOption: { padding: 15, borderWidth: 2, borderColor: '#e2e8f0', borderRadius: 8, marginBottom: 10 },
  incidentOptionSelected: { borderColor: '#3182ce', backgroundColor: '#ebf8ff' },
  incidentOptionText: { fontSize: 16, fontWeight: 'bold', color: '#2d3748', textAlign: 'center' }
});

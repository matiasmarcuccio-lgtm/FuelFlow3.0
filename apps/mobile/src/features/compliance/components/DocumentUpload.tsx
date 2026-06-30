import React, { useState } from 'react';
import { View, Text, TouchableOpacity, ActivityIndicator } from 'react-native';
import DateTimePicker from '@react-native-community/datetimepicker';
import * as DocumentPicker from 'expo-document-picker';
import { useUploadDocument, DocumentFile } from '../hooks/useUploadDocument';

export const DocumentUpload = ({ onSuccess }: { onSuccess: () => void }) => {
  const [date, setDate] = useState(new Date());
  const [showPicker, setShowPicker] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [selectedFile, setSelectedFile] = useState<DocumentFile | null>(null);
  
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  
  const { mutate: upload, isPending } = useUploadDocument();

  const handleFilePick = async () => {
    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: ['application/pdf', 'image/jpeg', 'image/png'],
        copyToCacheDirectory: true
      });
      
      if (!result.canceled && result.assets && result.assets.length > 0) {
        const file = result.assets[0];
        setSelectedFile({
          name: file.name,
          type: file.mimeType || 'application/pdf',
          size: file.size || 0,
          uri: file.uri
        });
        setErrorMsg(null); // Limpiar error previo
      }
    } catch (err) {
      console.error("Error al seleccionar documento:", err);
      setErrorMsg("No se pudo seleccionar el archivo.");
    }
  };

  const handleUpload = () => {
    if (!selectedFile) return;
    
    setIsProcessing(true);
    setErrorMsg(null);
    
    // Enviamos la fecha seleccionada validada a nivel de sistema
    upload(
      { file: selectedFile, docType: 'INSURANCE', expiryDate: date.toISOString() }, 
      {
        onSuccess: () => {
          onSuccess();
        },
        onSettled: () => setIsProcessing(false),
        onError: (err) => {
          console.error("Fallo de subida", err);
          setErrorMsg(err.message || "La transferencia fue rechazada por el servidor forense.");
        }
      }
    );
  };

  // Formato dd/mm/yyyy
  const formattedDate = `${date.getDate().toString().padStart(2, '0')}/${(date.getMonth() + 1).toString().padStart(2, '0')}/${date.getFullYear()}`;

  return (
    <View style={{ flex: 1, justifyContent: 'center', padding: 20 }}>
      <Text style={{ fontSize: 22, fontWeight: 'bold', marginBottom: 20, textAlign: 'center' }}>
        Renovación de Póliza
      </Text>

      {errorMsg && (
        <View style={{ marginBottom: 20, padding: 12, backgroundColor: '#fed7d7', borderRadius: 8, borderWidth: 1, borderColor: '#feb2b2' }}>
          <Text style={{ color: '#c53030', fontWeight: 'bold', textAlign: 'center' }}>{errorMsg}</Text>
        </View>
      )}

      {/* Selector de Fecha de Vencimiento Nativo */}
      <View style={{ marginBottom: 25, padding: 15, backgroundColor: '#edf2f7', borderRadius: 8, borderWidth: 1, borderColor: '#e2e8f0' }}>
        <Text style={{ fontSize: 14, color: '#4a5568', marginBottom: 5 }}>
          Fecha de vencimiento declarada (dd/mm/yyyy):
        </Text>
        <TouchableOpacity 
          onPress={() => setShowPicker(true)} 
          style={{ paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: '#cbd5e0' }}
        >
          <Text style={{ fontSize: 18, color: '#2b6cb0', fontWeight: 'bold' }}>
            {formattedDate}
          </Text>
        </TouchableOpacity>
        
        {showPicker && (
          <DateTimePicker 
            value={date} 
            mode="date" 
            display="default"
            onChange={(event, selectedDate) => {
              setShowPicker(false);
              if (selectedDate) setDate(selectedDate);
            }} 
          />
        )}
      </View>

      {/* Selector de Archivo */}
      <View style={{ marginBottom: 25, padding: 15, backgroundColor: '#edf2f7', borderRadius: 8, borderWidth: 1, borderColor: '#e2e8f0' }}>
        <Text style={{ fontSize: 14, color: '#4a5568', marginBottom: 10 }}>
          Documento Probatorio (PDF/Imagen):
        </Text>
        <TouchableOpacity 
          onPress={handleFilePick}
          style={{ padding: 12, backgroundColor: '#e2e8f0', borderRadius: 6, alignItems: 'center' }}
        >
          <Text style={{ color: '#4a5568', fontWeight: '500' }}>
            {selectedFile ? selectedFile.name : 'Tocar para seleccionar archivo...'}
          </Text>
        </TouchableOpacity>
      </View>

      {isPending || isProcessing ? (
        <View style={{ alignItems: 'center', padding: 20, backgroundColor: '#f7fafc', borderRadius: 8, borderWidth: 1, borderColor: '#e2e8f0' }}>
          <ActivityIndicator size="large" color="#0000ff" />
          <Text style={{ marginTop: 15, fontSize: 16, fontWeight: '600', color: '#2d3748' }}>
            Transfiriendo y validando...
          </Text>
          <Text style={{ fontSize: 11, color: '#718096', marginTop: 8, fontStyle: 'italic', textAlign: 'center' }}>
            El sistema forense está verificando la firma digital y validando la fecha de expiración proporcionada.
          </Text>
        </View>
      ) : (
        <TouchableOpacity 
          style={{ 
            backgroundColor: selectedFile ? '#2b6cb0' : '#cbd5e0', 
            padding: 16, borderRadius: 8, alignItems: 'center', 
            shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, 
            shadowOpacity: selectedFile ? 0.2 : 0, shadowRadius: 3, elevation: selectedFile ? 4 : 0 
          }}
          onPress={handleUpload}
          disabled={isPending || !selectedFile}
        >
          <Text style={{ color: 'white', fontWeight: 'bold', fontSize: 16 }}>
            Confirmar y Subir Documento
          </Text>
        </TouchableOpacity>
      )}
    </View>
  );
};

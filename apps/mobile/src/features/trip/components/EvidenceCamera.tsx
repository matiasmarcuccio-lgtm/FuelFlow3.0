import React, { useState, useEffect, useRef } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, ActivityIndicator } from 'react-native';
import { Camera, CameraType } from 'expo-camera';
import * as ImageManipulator from 'expo-image-manipulator';
import { FontAwesome } from '@expo/vector-icons';

interface Props {
  onCapture: (compressedUri: string) => void;
  onCancel: () => void;
}

export const EvidenceCamera = ({ onCapture, onCancel }: Props) => {
  const [hasPermission, setHasPermission] = useState<boolean | null>(null);
  const [isProcessing, setIsProcessing] = useState(false);
  const cameraRef = useRef<Camera>(null);

  useEffect(() => {
    (async () => {
      const { status } = await Camera.requestCameraPermissionsAsync();
      setHasPermission(status === 'granted');
    })();
  }, []);

  const takePicture = async () => {
    if (!cameraRef.current || isProcessing) return;
    
    try {
      setIsProcessing(true);
      // Take raw high-res picture
      const photo = await cameraRef.current.takePictureAsync({
        quality: 1, // Capture full quality first to ensure crisp text
        skipProcessing: true,
      });

      // Compress aggressively in background using native manipulator
      const compressedImage = await ImageManipulator.manipulateAsync(
        photo.uri,
        [{ resize: { width: 1280 } }], // Resize width, maintaining aspect ratio
        { compress: 0.6, format: ImageManipulator.SaveFormat.JPEG } // 60% quality JPEG
      );

      onCapture(compressedImage.uri);
    } catch (error) {
      console.error('[EvidenceCamera] Capture failed:', error);
      setIsProcessing(false);
    }
  };

  if (hasPermission === null) {
    return <View style={styles.container}><ActivityIndicator color="#fff" /></View>;
  }
  
  if (hasPermission === false) {
    return (
      <View style={styles.container}>
        <Text style={styles.text}>No access to camera. This is required for forensic dockets.</Text>
        <TouchableOpacity style={styles.button} onPress={onCancel}>
          <Text style={styles.buttonText}>Go Back</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Camera style={styles.camera} type={CameraType.back} ref={cameraRef}>
        <View style={styles.overlay}>
          <View style={styles.topBar}>
            <Text style={styles.warningText}>
              <FontAwesome name="lock" /> FORENSIC EVIDENCE VAULT
            </Text>
            <TouchableOpacity onPress={onCancel} style={styles.closeButton}>
              <FontAwesome name="times" size={24} color="#fff" />
            </TouchableOpacity>
          </View>
          
          <View style={styles.reticle}>
            <View style={[styles.reticleCorner, styles.tl]} />
            <View style={[styles.reticleCorner, styles.tr]} />
            <View style={[styles.reticleCorner, styles.bl]} />
            <View style={[styles.reticleCorner, styles.br]} />
            <Text style={styles.reticleText}>ALIGN DOCKET HERE</Text>
          </View>

          <View style={styles.bottomBar}>
            <TouchableOpacity 
              style={[styles.captureButton, isProcessing && styles.captureButtonDisabled]} 
              onPress={takePicture}
              disabled={isProcessing}
            >
              {isProcessing ? (
                <ActivityIndicator color="#2b6cb0" size="large" />
              ) : (
                <View style={styles.captureInner} />
              )}
            </TouchableOpacity>
          </View>
        </View>
      </Camera>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
    justifyContent: 'center',
  },
  camera: {
    flex: 1,
  },
  overlay: {
    flex: 1,
    backgroundColor: 'transparent',
    justifyContent: 'space-between',
  },
  topBar: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    padding: 20,
    paddingTop: 40,
    backgroundColor: 'rgba(0,0,0,0.5)',
  },
  warningText: {
    color: '#fc8181',
    fontWeight: 'bold',
    fontSize: 12,
    letterSpacing: 1,
  },
  closeButton: {
    padding: 5,
  },
  reticle: {
    flex: 1,
    margin: 40,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.2)',
    position: 'relative',
    justifyContent: 'center',
    alignItems: 'center',
  },
  reticleCorner: {
    position: 'absolute',
    width: 20,
    height: 20,
    borderColor: '#4299e1',
  },
  tl: { top: 0, left: 0, borderTopWidth: 3, borderLeftWidth: 3 },
  tr: { top: 0, right: 0, borderTopWidth: 3, borderRightWidth: 3 },
  bl: { bottom: 0, left: 0, borderBottomWidth: 3, borderLeftWidth: 3 },
  br: { bottom: 0, right: 0, borderBottomWidth: 3, borderRightWidth: 3 },
  reticleText: {
    color: 'rgba(255,255,255,0.5)',
    fontWeight: 'bold',
    letterSpacing: 2,
  },
  bottomBar: {
    padding: 30,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.5)',
  },
  captureButton: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: '#fff',
    justifyContent: 'center',
    alignItems: 'center',
  },
  captureButtonDisabled: {
    backgroundColor: '#ccc',
  },
  captureInner: {
    width: 70,
    height: 70,
    borderRadius: 35,
    borderWidth: 2,
    borderColor: '#000',
  },
  text: {
    color: '#fff',
    textAlign: 'center',
    marginBottom: 20,
  },
  button: {
    backgroundColor: '#2b6cb0',
    padding: 15,
    borderRadius: 5,
    alignItems: 'center',
    marginHorizontal: 40,
  },
  buttonText: {
    color: '#fff',
    fontWeight: 'bold',
  }
});

import { Stack } from 'expo-router';
import { RootProvider } from '../src/providers/RootProvider';
import { ShadowSyncDaemon } from '../src/features/trip/components/ShadowSyncDaemon';
import { DeadLetterWarning } from '../src/features/trip/components/DeadLetterWarning';
import { View, StyleSheet } from 'react-native';
import { EvidenceSyncWorker } from '../src/features/trip/utils/EvidenceSyncWorker';
import { useEffect } from 'react';

export default function RootLayout() {
  useEffect(() => {
    // Start the forensic background workers
    EvidenceSyncWorker.startDaemon();
  }, []);

  return (
    <RootProvider>
      <View style={styles.container}>
        <DeadLetterWarning />
        <Stack screenOptions={{ headerShown: false }}>
          {/* El Stack redirige automáticamente a index.tsx o (app) según el estado */}
          <Stack.Screen name="index" options={{ title: 'Login' }} />
          <Stack.Screen name="(app)" options={{ title: 'App' }} />
        </Stack>
        <ShadowSyncDaemon />
      </View>
    </RootProvider>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: 'white'
  }
});

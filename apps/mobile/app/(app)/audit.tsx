import React from 'react';
import { View, StyleSheet } from 'react-native';
import { AuditTrailContainer } from '../../src/features/audit/containers/AuditTrailContainer';

export default function AuditScreen() {
  return (
    <View style={styles.container}>
      <AuditTrailContainer />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#ffffff' }
});

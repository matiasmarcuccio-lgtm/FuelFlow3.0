import React from 'react';
import { Tabs } from 'expo-router';
import { ComplianceGuard } from '../../src/features/compliance/components/ComplianceGuard';
import { FontAwesome } from '@expo/vector-icons';

export default function ProtectedLayout() {
  return (
    // DIRECTIVA TÁCTICA APLICADA: Toda ruta dentro de (app)/ queda sometida a la Física del ComplianceGuard
    <ComplianceGuard>
      <Tabs screenOptions={{ tabBarActiveTintColor: '#2b6cb0' }}>
        <Tabs.Screen 
          name="index" 
          options={{ 
            title: 'Ofertas (Bidding)',
            tabBarIcon: ({ color }) => <FontAwesome name="list-alt" size={24} color={color} />
          }} 
        />
        <Tabs.Screen 
          name="trips" 
          options={{ 
            title: 'Ruta Activa',
            tabBarIcon: ({ color }) => <FontAwesome name="truck" size={24} color={color} />
          }} 
        />
        <Tabs.Screen 
          name="audit" 
          options={{ 
            title: 'Forense', 
            tabBarIcon: ({ color }) => <FontAwesome name="shield" size={24} color={color} />
          }} 
        />
      </Tabs>
    </ComplianceGuard>
  );
}

import React from 'react';
import { View, StyleSheet, Alert } from 'react-native';
import { useLoadOffers } from '../hooks/useLoadOffers';
import { OfferListPresenter, LoadOfferData } from '../components/OfferListPresenter';
import { ErrorMessage } from '../components/ErrorMessage';
import { supabase } from '@/lib/supabase';

export const BiddingContainer = () => {
  const { data: offers, isLoading, error } = useLoadOffers();

  // Función de Mutación Optimizada: Aceptar una carga
  const handleAcceptOffer = async (id: string) => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error("No autenticado");

      // Inserción en la tabla de asignaciones (El State Machine Lock lo validará)
      const { error: assignError } = await supabase.from('assignments').insert({
        load_offer_id: id,
        operator_id: user.id
      });

      if (assignError) throw assignError;
      
      // Actualizamos el estado a ASIGNADA para que el Triger lo valide
      const { error: updateError } = await supabase.from('load_offers')
        .update({ status: 'MANIFEST_PENDING' })
        .eq('id', id);

      if (updateError) throw updateError;
      
      Alert.alert("Éxito", "Carga aceptada. Dirígete a la pestaña de Ruta para operar.");
    } catch (e: any) {
      Alert.alert("Error de Sistema", e.message);
    }
  };
  
  return (
    <View style={styles.container}>
      {error && <ErrorMessage error={error} />}
      <OfferListPresenter 
        offers={(offers as LoadOfferData[]) || []} 
        isLoading={isLoading} 
        onAcceptOffer={handleAcceptOffer}
      />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 16,
    backgroundColor: '#ffffff'
  }
});

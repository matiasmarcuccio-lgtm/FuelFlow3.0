import { useEffect, useRef } from 'react';
import { supabase } from '../../lib/supabase';

export const useAcousticDispatch = (assetId: string) => {
  const queueRef = useRef<string[]>([]);
  const isSpeakingRef = useRef<boolean>(false);

  useEffect(() => {
    const processQueue = () => {
      if (isSpeakingRef.current || queueRef.current.length === 0) return;

      const textToSpeak = queueRef.current.shift();
      if (!textToSpeak) return;

      isSpeakingRef.current = true;
      const utterance = new SpeechSynthesisUtterance(textToSpeak);
      
      // Ajustes tácticos para un entorno de maquinaria ruidosa
      utterance.rate = 0.9; // Hablar un poco más lento
      utterance.pitch = 1.0; 
      utterance.volume = 1.0;

      utterance.onend = () => {
        isSpeakingRef.current = false;
        processQueue(); // Consumir el siguiente mensaje si existe
      };

      utterance.onerror = (e) => {
        console.error('Error de Síntesis de Voz:', e);
        isSpeakingRef.current = false;
        processQueue();
      };

      window.speechSynthesis.speak(utterance);
    };

    // Suscripción al canal de despacho dedicado para esta máquina
    const channel = supabase.channel(`jit_dispatch_${assetId}`)
      .on('broadcast', { event: 'dispatch_alert' }, (payload) => {
        queueRef.current.push(payload.payload.message);
        processQueue();
      })
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
      window.speechSynthesis.cancel(); // Clear motor al desmontar
    };
  }, [assetId]);
};

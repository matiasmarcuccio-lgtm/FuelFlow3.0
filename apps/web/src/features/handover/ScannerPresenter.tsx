import React, { useEffect, useRef, useState } from 'react';
import { Html5Qrcode } from 'html5-qrcode';
import { useNavigate } from 'react-router-dom';
import { Camera, AlertTriangle } from 'lucide-react';

export const ScannerPresenter = () => {
  const navigate = useNavigate();
  const scannerRef = useRef<Html5Qrcode | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // 1. Inicializar el escáner (Hardware de Cámara Trasera)
    scannerRef.current = new Html5Qrcode("reader");

    const startScanner = async () => {
      try {
        await scannerRef.current?.start(
          { facingMode: "environment" },
          {
            fps: 10,
            qrbox: { width: 250, height: 250 }
          },
          (decodedText) => {
            // 2. Escaneo Exitoso: Procesar la URL
            if (navigator.vibrate) navigator.vibrate(100);
            
            // Validar que es una URL de traspaso interna
            try {
              const url = new URL(decodedText);
              if (url.pathname.startsWith('/handover/')) {
                // Detener inmediatamente antes de navegar para evitar fugas
                scannerRef.current?.stop().then(() => {
                  scannerRef.current?.clear();
                  navigate(url.pathname);
                });
              } else {
                setError('QR Inválido: Código no pertenece a maquinaria de FuelFlow.');
              }
            } catch {
              setError('Formato QR irreconocible.');
            }
          },
          (errorMessage) => {
            // Errores de lectura frame a frame (normales, se ignoran)
          }
        );
      } catch (err: any) {
        setError(`Error accediendo a la cámara: ${err.message || err}`);
      }
    };

    startScanner();

    // 3. Desmontaje Estricto (Cleanup) para MDM Memory Leak Prevention
    return () => {
      if (scannerRef.current && scannerRef.current.isScanning) {
        scannerRef.current.stop().then(() => {
          scannerRef.current?.clear();
        }).catch(err => {
          console.error("Error crítico cerrando WebRTC:", err);
        });
      }
    };
  }, [navigate]);

  return (
    <div className="flex flex-col min-h-screen bg-black text-foreground font-sans">
      <div className="p-4 bg-blue-900 flex justify-center items-center gap-2">
        <Camera className="text-blue-300" />
        <h1 className="text-xl font-bold uppercase tracking-widest text-blue-100">Escáner de Maquinaria</h1>
      </div>

      <div className="flex-1 flex flex-col items-center justify-center p-6">
        <div className="w-full max-w-sm aspect-square relative rounded-2xl overflow-hidden border-4 border-outline-variant shadow-[0_0_50px_rgba(0,0,0,0.5)]">
          <div id="reader" className="w-full h-full bg-background flex items-center justify-center">
             {/* html5-qrcode inyectará el video aquí */}
          </div>
          <div className="absolute inset-0 border-2 border-dashed border-blue-500 opacity-50 m-8 rounded-lg pointer-events-none animate-pulse"></div>
        </div>

        {error && (
          <div className="mt-8 p-4 bg-red-900/80 border border-red-500 rounded-xl flex items-start gap-3 w-full max-w-sm">
            <AlertTriangle className="text-red-400 shrink-0" />
            <p className="text-red-100 font-bold">{error}</p>
          </div>
        )}
        
        <p className="mt-8 text-center text-on-surface-variant max-w-sm">
          Apunte la cámara de la tablet al código QR ubicado en el panel del vehículo para iniciar el traspaso seguro.
        </p>
      </div>
    </div>
  );
};

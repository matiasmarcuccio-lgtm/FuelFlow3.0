import { useState } from 'react';
import { Activity, AlertTriangle, CheckCircle2 } from 'lucide-react';
import { useSubmitTelemetry } from '../features/assets/mutations';
import { get } from 'idb-keyval';

export const HealthDashboard = () => {
  const submitTelemetry = useSubmitTelemetry();
  const [testLog, setTestLog] = useState<string[]>([]);
  
  const testAtomicHandover = async () => {
    setTestLog(prev => [...prev, "Iniciando test de atomicidad..."]);
    
    // 1. Forzar mutación offline-first (usamos mutate para no bloquear la ejecución mientras está pausada por TanStack Query)
    submitTelemetry.mutate({
      asset_id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', // Mock UUID para el test
      recorded_by: '00000000-0000-0000-0000-000000000000',
      event_type: 'handover_signature',
      payload: { status: 'in_site' },
      client_timestamp: new Date().toISOString()
    }, {
      onError: (e: any) => {
        // En v5 con offlineFirst y retry infinito, esto solo se dispara si falla por algo distinto a la red.
        setTestLog(prev => [...prev, `Error en mutación: ${e.message}`]);
      }
    });

    setTestLog(prev => [...prev, "Mutación disparada. Esperando sincronización de IndexedDB..."]);
    
    // Esperar a que el persister de TanStack Query escriba en IndexedDB (es asíncrono)
    await new Promise(resolve => setTimeout(resolve, 500));

    // 2. Verificar estado de la cola en IndexedDB
    const cachedQueue = await get('jitsite-offline-cache');
    if (cachedQueue !== undefined && cachedQueue.clientState.mutations.length > 0) {
      setTestLog(prev => [...prev, "Test superado: Mutación persistida con éxito bajo falla de red en IndexedDB."]);
    } else {
      setTestLog(prev => [...prev, "¡FALLO CRÍTICO: La mutación no se encoló en IndexedDB!"]);
    }
  };

  return (
    <div className="flex-1 p-8 bg-background text-foreground">
      <h1 className="text-2xl font-bold mb-6 flex items-center gap-2 text-foreground">
        <Activity className="text-primary" />
        Financial intelligence
      </h1>
      <p className="text-on-surface-variant mb-8">Monitor system latency, stale sync events, and database triggers here.</p>
      
      <div className="bg-card shadow-lg p-6 rounded-lg">
        <h2 className="text-xl font-bold mb-4 flex items-center gap-2">
          <AlertTriangle className="text-yellow-500" />
          Offline-First Mutaton Queue Test
        </h2>
        <p className="text-sm text-on-surface-variant mb-4">
          Este test simula un corte de red durante la firma criptográfica y verifica que TanStack Query y IndexedDB 
          hayan persistido el payload de telemetría de forma atómica para prevenir registros huérfanos. Para ejecutar esto correctamente, desactiva la red en DevTools o desconecta el internet.
        </p>
        <button 
          onClick={testAtomicHandover}
          className="bg-primary text-on-primary hover:bg-primary-container text-on-primary-container text-white font-bold py-2 px-4 rounded transition-colors"
        >
          Ejecutar Test de Inconsistencia
        </button>
        
        {testLog.length > 0 && (
          <div className="mt-6 p-4 bg-black rounded font-mono text-sm text-green-400">
            {testLog.map((log, i) => (
              <div key={i} className="flex items-start gap-2 mb-1">
                <CheckCircle2 size={16} className="mt-0.5 shrink-0" />
                <span>{log}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

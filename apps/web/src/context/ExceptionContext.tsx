import { createContext, useContext, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import type { AnomalyRecord } from '../features/command-center/AnomalyStream';

export type ConnectionStatus = 'SUBSCRIBED' | 'TIMED_OUT' | 'CLOSED' | 'CHANNEL_ERROR' | 'CONNECTING';

interface ExceptionContextType {
  anomalies: AnomalyRecord[];
  removeAnomalyLocally: (id: string) => void;
  connectionStatus: ConnectionStatus;
}

const ExceptionContext = createContext<ExceptionContextType>({
  anomalies: [],
  removeAnomalyLocally: () => {},
  connectionStatus: 'CONNECTING',
});

export const useExceptions = () => useContext(ExceptionContext);

export const ExceptionProvider = ({ children }: { children: React.ReactNode }) => {
  const [anomalies, setAnomalies] = useState<AnomalyRecord[]>([]);
  const [connectionStatus, setConnectionStatus] = useState<ConnectionStatus>('CONNECTING');

  useEffect(() => {
    fetchAnomalies();

    const subscription = supabase
      .channel('global-exception-stream')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'load_offers',
        },
        (payload) => {
          const record = payload.new as AnomalyRecord;
          // Only process unresolved anomalies or breakdowns
          if ((record.anomaly_flag !== null && record.anomaly_resolved_at === null) || record.status === 'BREAKDOWN') {
            fetchAnomalies();
            try {
              // new Audio('/alert-chime.mp3').play();
            } catch (e) {}
          }
        }
      )
      .subscribe((status) => {
        setConnectionStatus(status as ConnectionStatus);
      });

    return () => {
      supabase.removeChannel(subscription);
    };
  }, []);

  const fetchAnomalies = async () => {
    const { data, error } = await supabase
      .from('load_offers')
      .select('id, status, anomaly_flag, loaded_gross_mass, ocr_mass_extracted, docket_image_path, created_at, completed_at_local')
      .or('anomaly_flag.not.is.null,status.eq.BREAKDOWN')
      .is('anomaly_resolved_at', null)
      .order('completed_at_local', { ascending: false });
    
    if (!error && data) {
      setAnomalies(data);
    }
  };

  const removeAnomalyLocally = (id: string) => {
    setAnomalies(prev => prev.filter(a => a.id !== id));
  };

  return (
    <ExceptionContext.Provider value={{ anomalies, removeAnomalyLocally, connectionStatus }}>
      {children}
    </ExceptionContext.Provider>
  );
};


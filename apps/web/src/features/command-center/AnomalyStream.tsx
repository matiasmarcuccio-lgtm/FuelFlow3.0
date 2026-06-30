import React, { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { AlertTriangle, CheckCircle, ShieldAlert } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';

export interface AnomalyRecord {
  id: string;
  status: string;
  anomaly_flag: string;
  loaded_gross_mass: number;
  ocr_mass_extracted: number;
  docket_image_path: string;
  created_at: string;
  completed_at_local: string;
}

const CORRECTIVE_ACTIONS = [
  "Bailment verified",
  "Weight recorded manually",
  "Operational safety checked",
  "Driver override justified",
  "Equipment recalibrated"
];

export const AnomalyStream = () => {
  const [anomalies, setAnomalies] = useState<AnomalyRecord[]>([]);
  const [resolutionText, setResolutionText] = useState<{ [key: string]: string }>({});
  const [selectedTags, setSelectedTags] = useState<{ [key: string]: string[] }>({});

  useEffect(() => {
    fetchAnomalies();

    const subscription = supabase
      .channel('anomaly-stream')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'load_offers',
          filter: 'anomaly_resolved_at=is.null'
        },
        () => {
          fetchAnomalies();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(subscription);
    };
  }, []);

  const fetchAnomalies = async () => {
    const { data, error } = await supabase
      .from('load_offers')
      .select('id, status, anomaly_flag, loaded_gross_mass, ocr_mass_extracted, docket_image_path, created_at, completed_at_local')
      .not('anomaly_flag', 'is', null)
      .is('anomaly_resolved_at', null)
      .order('completed_at_local', { ascending: false });
    
    if (!error) {
      setAnomalies(data || []);
    }
  };

  const handleToggleTag = (anomalyId: string, tag: string) => {
    const currentTags = selectedTags[anomalyId] || [];
    if (currentTags.includes(tag)) {
      setSelectedTags({ ...selectedTags, [anomalyId]: currentTags.filter(t => t !== tag) });
    } else {
      setSelectedTags({ ...selectedTags, [anomalyId]: [...currentTags, tag] });
    }
  };

  const handleForceApprove = async (id: string) => {
    const text = resolutionText[id] || '';
    const tags = selectedTags[id] || [];

    if (text.length < 15 || tags.length === 0) return;

    const { data: { user } } = await supabase.auth.getUser();

    const { error } = await supabase
      .from('load_offers')
      .update({
        anomaly_resolved_at: new Date().toISOString(),
        anomaly_resolved_by: user?.id,
        anomaly_resolution_reason: text,
        anomaly_resolution_tags: tags
      })
      .eq('id', id);
    
    if (!error) {
      setAnomalies(prev => prev.filter(a => a.id !== id));
      // Cleanup state
      const newText = { ...resolutionText };
      delete newText[id];
      setResolutionText(newText);
      const newTags = { ...selectedTags };
      delete newTags[id];
      setSelectedTags(newTags);
    }
  };

  if (anomalies.length === 0) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center p-8 text-slate-500">
        <CheckCircle className="w-16 h-16 mb-4 text-slate-700" />
        <p className="text-center font-medium">All operations nominal.</p>
        <p className="text-sm text-slate-600">No unresolved anomalies in the stream.</p>
      </div>
    );
  }

  return (
    <div className="flex-1 overflow-y-auto p-4 space-y-6">
      {anomalies.map(anomaly => {
        const text = resolutionText[anomaly.id] || '';
        const tags = selectedTags[anomaly.id] || [];
        const isEmergency = anomaly.anomaly_flag === 'DRIVER_EMERGENCY_OVERRIDE';
        const isApproveEnabled = text.length >= 15 && tags.length > 0;

        return (
          <div key={anomaly.id} className={`bg-slate-800 border-l-4 ${isEmergency ? 'border-purple-500 bg-purple-900/10' : 'border-red-500'} rounded-md p-4 shadow-lg`}>
            <div className="flex justify-between items-start mb-2">
              <div className="flex items-center gap-2">
                {isEmergency ? <ShieldAlert className="w-5 h-5 text-purple-500" /> : <AlertTriangle className="w-5 h-5 text-red-500" />}
                <span className={`font-bold ${isEmergency ? 'text-purple-400' : 'text-red-400'}`}>
                  {anomaly.anomaly_flag}
                </span>
              </div>
              <span className="text-xs text-slate-400">
                {anomaly.completed_at_local ? formatDistanceToNow(new Date(anomaly.completed_at_local), { addSuffix: true }) : 'N/A'}
              </span>
            </div>

            {!isEmergency && (
              <div className="space-y-2 mb-4">
                <div className="flex justify-between text-sm bg-slate-900 p-2 rounded">
                  <span className="text-slate-400">Driver Claimed Mass:</span>
                  <span className="font-mono text-white">{anomaly.loaded_gross_mass} kg</span>
                </div>
                <div className="flex justify-between text-sm bg-slate-900 p-2 rounded border border-red-900/50">
                  <span className="text-slate-400">OCR Extracted Mass:</span>
                  <span className="font-mono text-red-400 font-bold">{anomaly.ocr_mass_extracted || 'N/A'} kg</span>
                </div>
              </div>
            )}

            {anomaly.docket_image_path && (
              <div className="mb-4">
                <span className="text-xs text-slate-500 mb-1 block">EVIDENCE CAPTURED:</span>
                <img 
                  src={`${import.meta.env.VITE_SUPABASE_URL}/storage/v1/object/public/docket_evidence/${anomaly.docket_image_path}`} 
                  className="w-full h-32 object-cover rounded border border-slate-700 opacity-80 hover:opacity-100 transition-opacity cursor-pointer"
                  alt="Docket Evidence"
                  onClick={() => window.open(`${import.meta.env.VITE_SUPABASE_URL}/storage/v1/object/public/docket_evidence/${anomaly.docket_image_path}`, '_blank')}
                />
              </div>
            )}

            {/* RESOLUTION AUDIT TRAIL */}
            <div className="mt-4 pt-4 border-t border-slate-700 space-y-3">
              <p className="text-xs font-bold text-slate-300 uppercase">CoR Audit Resolution</p>
              
              <div className="flex flex-wrap gap-2">
                {CORRECTIVE_ACTIONS.map(tag => (
                  <button
                    key={tag}
                    onClick={() => handleToggleTag(anomaly.id, tag)}
                    className={`text-xs px-2 py-1 rounded-full border ${tags.includes(tag) ? 'bg-blue-600 border-blue-500 text-white' : 'bg-slate-900 border-slate-600 text-slate-400 hover:border-slate-400'}`}
                  >
                    {tag}
                  </button>
                ))}
              </div>

              <div className="relative">
                <textarea 
                  className="w-full bg-slate-900 border border-slate-600 rounded p-2 text-sm text-slate-200 placeholder-slate-500 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none"
                  placeholder="Justify this override for NHVR audit..."
                  rows={3}
                  value={text}
                  onChange={(e) => setResolutionText({ ...resolutionText, [anomaly.id]: e.target.value })}
                />
                <span className={`absolute bottom-2 right-2 text-xs ${text.length < 15 ? 'text-red-400' : 'text-green-400'}`}>
                  {text.length}/15 min chars
                </span>
              </div>

              <div className="flex gap-2 pt-2">
                <button 
                  onClick={() => handleForceApprove(anomaly.id)}
                  disabled={!isApproveEnabled}
                  className={`flex-1 text-sm font-medium py-2 rounded transition-colors ${isApproveEnabled ? 'bg-slate-700 hover:bg-slate-600 text-white' : 'bg-slate-900 text-slate-600 cursor-not-allowed'}`}
                >
                  Force Approve & Seal
                </button>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
};

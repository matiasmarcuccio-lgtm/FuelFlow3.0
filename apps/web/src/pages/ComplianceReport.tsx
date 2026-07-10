import React, { useEffect, useState } from 'react';
import { FileText, Download, CheckCircle, ShieldAlert, Activity } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { formatDistanceToNow } from 'date-fns';

// Helper to determine the "effort" of a justification
// Low effort = close to 15 chars, repetitive, generic
// High effort = detailed, varied words
const calculateEffortScore = (text: string) => {
  if (!text) return { label: 'POOR', color: 'text-red-400' };
  
  const length = text.length;
  const wordCount = text.split(/\s+/).filter(w => w.length > 2).length;
  const uniqueWords = new Set(text.toLowerCase().split(/\s+/)).size;
  
  if (length <= 20 || uniqueWords <= 3) {
    return { label: 'MINIMUM COMPLIANCE', color: 'text-red-500' };
  } else if (length > 20 && length < 50 && wordCount > 5) {
    return { label: 'ACCEPTABLE', color: 'text-yellow-400' };
  } else {
    return { label: 'HIGH INTEGRITY', color: 'text-emerald-400' };
  }
};

export const ComplianceReport = () => {
  const [resolvedAnomalies, setResolvedAnomalies] = useState<any[]>([]);

  useEffect(() => {
    fetchResolvedAnomalies();
  }, []);

  const fetchResolvedAnomalies = async () => {
    const { data, error } = await supabase
      .from('load_offers')
      .select('id, status, anomaly_flag, loaded_gross_mass, ocr_mass_extracted, anomaly_resolved_at, anomaly_resolution_reason, anomaly_resolution_tags, completed_at_local')
      .not('anomaly_resolved_at', 'is', null)
      .order('anomaly_resolved_at', { ascending: false })
      .limit(50);
    
    if (!error && data) {
      setResolvedAnomalies(data);
    }
  };

  const poorEffortCount = resolvedAnomalies.filter(a => calculateEffortScore(a.anomaly_resolution_reason).label === 'MINIMUM COMPLIANCE').length;
  const cultureHealthWarning = resolvedAnomalies.length > 0 && (poorEffortCount / resolvedAnomalies.length) > 0.5;

  return (
    <div className="flex-1 p-8 bg-background text-foreground h-full overflow-y-auto">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <FileText className="text-on-surface-variant" />
          CoR Weekly Summary
        </h1>
        <button className="flex items-center gap-2 bg-purple-600 hover:bg-purple-700 text-foreground px-4 py-2 rounded-md transition-colors">
          <Download className="w-4 h-4" />
          Export PDF
        </button>
      </div>

      {cultureHealthWarning && (
        <div className="mb-6 p-4 bg-orange-900/50 border border-orange-700 rounded-lg flex items-center gap-3">
          <Activity className="text-orange-500 w-6 h-6 animate-pulse" />
          <div>
            <h3 className="font-bold text-orange-400">WARNING: CULTURAL FRACTURE DETECTED</h3>
            <p className="text-sm text-orange-200">Over 50% of recent interventions demonstrate minimum compliance effort (pencil-whipping). System is recording data, but failing accountability.</p>
          </div>
        </div>
      )}

      <div className="grid grid-cols-4 gap-4 mb-8">
        <div className="bg-surface border border-outline-variant shadow-sm p-4 rounded-lg border border-outline-variant">
          <p className="text-on-surface-variant text-sm">Total Interventions</p>
          <p className="text-3xl font-bold text-foreground">{resolvedAnomalies.length}</p>
        </div>
        <div className="bg-surface border border-outline-variant shadow-sm p-4 rounded-lg border border-outline-variant">
          <p className="text-on-surface-variant text-sm">Emergency Overrides</p>
          <p className="text-3xl font-bold text-purple-400">
            {resolvedAnomalies.filter(a => a.anomaly_flag === 'DRIVER_EMERGENCY_OVERRIDE').length}
          </p>
        </div>
        <div className="bg-surface border border-outline-variant shadow-sm p-4 rounded-lg border border-outline-variant">
          <p className="text-on-surface-variant text-sm">Mass Mismatches</p>
          <p className="text-3xl font-bold text-red-400">
            {resolvedAnomalies.filter(a => a.anomaly_flag === 'MASS_MISMATCH').length}
          </p>
        </div>
        <div className="bg-surface border border-outline-variant shadow-sm p-4 rounded-lg border border-outline-variant">
          <p className="text-on-surface-variant text-sm">Min-Effort Justifications</p>
          <p className={`text-3xl font-bold ${cultureHealthWarning ? 'text-orange-400' : 'text-emerald-400'}`}>
            {poorEffortCount}
          </p>
        </div>
      </div>

      <div className="bg-surface border border-outline-variant shadow-sm rounded-lg border border-outline-variant overflow-hidden">
        <table className="w-full text-left border-collapse">
          <thead>
            <tr className="bg-background border-b border-outline-variant">
              <th className="p-3 text-sm font-semibold text-on-surface">Timestamp</th>
              <th className="p-3 text-sm font-semibold text-on-surface">Incident Type</th>
              <th className="p-3 text-sm font-semibold text-on-surface">Corrective Action Tags</th>
              <th className="p-3 text-sm font-semibold text-on-surface">Justification (Manager)</th>
              <th className="p-3 text-sm font-semibold text-on-surface text-right">Effort Analysis</th>
            </tr>
          </thead>
          <tbody>
            {resolvedAnomalies.map((record) => {
              const effort = calculateEffortScore(record.anomaly_resolution_reason);
              return (
                <tr key={record.id} className="border-b border-outline-variant hover:bg-surface-variant/50">
                  <td className="p-3 text-xs text-on-surface-variant font-mono">
                    {record.anomaly_resolved_at ? new Date(record.anomaly_resolved_at).toLocaleString() : 'N/A'}
                  </td>
                  <td className="p-3">
                    {record.anomaly_flag === 'DRIVER_EMERGENCY_OVERRIDE' ? (
                      <span className="flex items-center gap-1 text-purple-400 text-xs font-bold">
                        <ShieldAlert className="w-3 h-3" /> OVERRIDE
                      </span>
                    ) : record.status === 'BREAKDOWN' ? (
                      <span className="flex items-center gap-1 text-orange-400 text-xs font-bold">
                        <ShieldAlert className="w-3 h-3" /> BREAKDOWN
                      </span>
                    ) : (
                      <span className="text-red-400 text-xs font-bold">{record.anomaly_flag}</span>
                    )}
                  </td>
                  <td className="p-3">
                    <div className="flex flex-wrap gap-1">
                      {(record.anomaly_resolution_tags || []).map((tag: string) => (
                        <span key={tag} className="text-[10px] px-2 py-0.5 rounded-full bg-blue-900 text-blue-300 border border-blue-800">
                          {tag.replace(/_/g, ' ')}
                        </span>
                      ))}
                    </div>
                  </td>
                  <td className="p-3 text-xs text-on-surface italic">
                    "{record.anomaly_resolution_reason}"
                  </td>
                  <td className="p-3 text-right">
                    <span className={`text-[10px] font-bold px-2 py-1 rounded bg-background border border-outline-variant ${effort.color}`}>
                      {effort.label}
                    </span>
                  </td>
                </tr>
              );
            })}
            {resolvedAnomalies.length === 0 && (
              <tr>
                <td colSpan={5} className="p-8 text-center text-outline">
                  <CheckCircle className="w-8 h-8 mx-auto mb-2 text-outline-variant" />
                  No compliance interventions recorded yet.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
};

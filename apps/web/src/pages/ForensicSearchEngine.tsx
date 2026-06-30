import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Search, Shield, History, Clock } from 'lucide-react';

export const ForensicSearchEngine = () => {
  const [timeline, setTimeline] = useState<any[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [filteredTimeline, setFilteredTimeline] = useState<any[]>([]);

  useEffect(() => {
    fetchTimeline();
  }, []);

  useEffect(() => {
    if (searchQuery.trim() === '') {
      setFilteredTimeline(timeline);
    } else {
      const q = searchQuery.toLowerCase();
      setFilteredTimeline(timeline.filter(t => 
        (t.load_id && t.load_id.toLowerCase().includes(q)) || 
        (t.operator_id && t.operator_id.toLowerCase().includes(q)) ||
        (t.anomaly_flag && t.anomaly_flag.toLowerCase().includes(q)) ||
        (t.status && t.status.toLowerCase().includes(q))
      ));
    }
  }, [searchQuery, timeline]);

  const fetchTimeline = async () => {
    const { data } = await supabase.from('view_cor_audit_timeline').select('*');
    if (data) {
      setTimeline(data);
      setFilteredTimeline(data);
    }
  };

  return (
    <div className="flex-1 p-8 bg-slate-900 text-slate-200 h-full flex flex-col">
      <div className="flex justify-between items-center mb-8 border-b border-slate-700 pb-4">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2 text-slate-200">
            <Shield className="text-slate-400" />
            Forensic Search Engine
          </h1>
          <p className="text-sm text-slate-500 mt-1">Read-only immutable timeline for NHVR Inspectors. Reconstruct operational history.</p>
        </div>
        <div className="relative">
          <Search className="absolute left-3 top-2.5 w-4 h-4 text-slate-500" />
          <input 
            type="text" 
            placeholder="Search UUID, Status, Flag..." 
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
            className="bg-slate-950 border border-slate-700 text-slate-300 rounded pl-9 pr-4 py-2 text-sm focus:border-slate-500 outline-none w-64 font-mono"
          />
        </div>
      </div>

      <div className="flex-1 overflow-y-auto bg-slate-950 p-6 rounded-lg border border-slate-800 shadow-inner">
        <div className="space-y-6 relative before:absolute before:inset-0 before:ml-5 before:-translate-x-px md:before:mx-auto md:before:translate-x-0 before:h-full before:w-0.5 before:bg-gradient-to-b before:from-transparent before:via-slate-700 before:to-transparent">
          {filteredTimeline.map((record, i) => {
            const isResolved = record.resolved_at !== null;
            return (
              <div key={i} className="relative flex items-center justify-between md:justify-normal md:odd:flex-row-reverse group is-active">
                
                {/* Timeline dot */}
                <div className="flex items-center justify-center w-10 h-10 rounded-full border border-slate-700 bg-slate-900 text-slate-500 shrink-0 md:order-1 md:group-odd:-translate-x-1/2 md:group-even:translate-x-1/2 shadow">
                  <History className="w-4 h-4" />
                </div>
                
                {/* Content */}
                <div className={`w-[calc(100%-4rem)] md:w-[calc(50%-2.5rem)] p-4 rounded-lg bg-slate-800 border ${record.digital_bypass ? 'border-dashed border-orange-500 shadow-[0_0_15px_rgba(249,115,22,0.1)]' : 'border-slate-700'}`}>
                  <div className="flex items-center justify-between mb-2">
                    <span className="font-mono text-xs text-blue-400 font-bold">LOAD_ID: {record.load_id.substring(0,8)}</span>
                    <span className="flex items-center gap-1 text-[10px] text-slate-500 font-mono">
                      <Clock className="w-3 h-3" />
                      {new Date(record.created_at).toLocaleString()}
                    </span>
                  </div>
                  
                  {record.digital_bypass ? (
                    <>
                      <div className="mb-3 flex justify-between items-center">
                        <span className="text-xs text-slate-400 uppercase tracking-wider font-bold block">Incident Type</span>
                        <span className="bg-orange-900/40 text-orange-400 text-[10px] px-2 py-0.5 rounded border border-orange-700 uppercase font-bold tracking-widest">
                          PAPER FALLBACK
                        </span>
                      </div>
                      
                      <div className="mb-3">
                        <span className="text-sm font-bold text-orange-400 block mb-1">
                          Manual Override (Device Offline)
                        </span>
                        <div className="text-xs text-slate-300 font-mono space-y-1 mt-2">
                          <p>Docket Ref: <strong className="text-white text-sm">{record.paper_docket_ref}</strong></p>
                          <p>Transcribed By: {record.bypassed_by_name || 'Fleet Manager'}</p>
                        </div>
                      </div>

                      <div className="mt-3 pt-3 border-t border-dashed border-orange-900 bg-orange-950/20 -mx-4 -mb-4 p-4 rounded-b-lg flex justify-between items-center">
                        <div>
                          <span className="text-[10px] text-orange-500 font-bold uppercase tracking-wider block mb-1">Physical Evidence Seal</span>
                          <a 
                            href={`${import.meta.env.VITE_SUPABASE_URL}/storage/v1/object/public/docket_evidence/${record.docket_image_path}`} 
                            target="_blank" 
                            rel="noreferrer" 
                            className="text-blue-400 hover:underline text-xs flex items-center gap-1"
                          >
                            <Shield className="w-3 h-3" />
                            View Vault Scan
                          </a>
                        </div>
                        <div className="text-[10px] text-slate-500 font-mono text-right">
                          <p>Sealed:</p>
                          <p>{new Date(record.completed_at_local || record.created_at).toLocaleString()}</p>
                        </div>
                      </div>
                    </>
                  ) : (
                    <>
                      <div className="mb-3">
                        <span className="text-xs text-slate-400 uppercase tracking-wider font-bold block mb-1">Incident Type</span>
                        <span className={`text-sm font-bold ${record.anomaly_flag === 'DRIVER_EMERGENCY_OVERRIDE' ? 'text-purple-400' : 'text-red-400'}`}>
                          {record.anomaly_flag || record.status}
                        </span>
                      </div>

                      {isResolved && (
                        <div className="mt-3 pt-3 border-t border-slate-700 bg-slate-900/50 -mx-4 -mb-4 p-4 rounded-b-lg">
                          <span className="text-[10px] text-emerald-500 font-bold uppercase tracking-wider block mb-2">Manager Resolution Seal</span>
                          <p className="text-xs text-slate-300 italic mb-2">"{record.anomaly_resolution_reason}"</p>
                          <div className="flex flex-wrap gap-1">
                            {(record.anomaly_resolution_tags || []).map((tag: string) => (
                              <span key={tag} className="text-[9px] px-1.5 py-0.5 rounded border border-slate-600 text-slate-400">
                                {tag}
                              </span>
                            ))}
                          </div>
                          <p className="text-[10px] text-slate-500 font-mono mt-2 text-right">
                            Signed: {new Date(record.resolved_at).toLocaleString()}
                          </p>
                        </div>
                      )}
                      
                      {!isResolved && (
                        <div className="mt-2 text-xs text-orange-400 font-bold uppercase animate-pulse">
                          PENDING REVIEW / UNRESOLVED
                        </div>
                      )}
                    </>
                  )}
                </div>
              </div>
            );
          })}
          {filteredTimeline.length === 0 && (
            <div className="text-center text-slate-500 py-10 font-mono italic">
              No audit records match the search criteria.
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

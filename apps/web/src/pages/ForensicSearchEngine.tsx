import { useState, useEffect } from 'react';
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
    <div className="flex-1 p-8 bg-background text-foreground h-full flex flex-col">
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-8 border-b border-border pb-4">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2 text-foreground">
            <Search className="text-primary" />
            Forensic engine
          </h1>
          <p className="text-sm text-outline mt-1">Read-only immutable timeline for NHVR Inspectors. Reconstruct operational history.</p>
        </div>
        <div className="relative">
          <Search className="absolute left-3 top-2.5 w-4 h-4 text-outline" />
          <input 
            type="text" 
            placeholder="Search UUID, Status, Flag..." 
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
            className="bg-white dark:bg-slate-950 border border-outline-variant text-on-surface rounded pl-9 pr-4 py-2 text-sm focus:border-outline outline-none w-64 font-mono"
          />
        </div>
      </div>

      <div className="flex-1 overflow-y-auto bg-background p-6 rounded-lg shadow-inner">
        <div className="space-y-6 relative before:absolute before:inset-0 before:ml-5 before:-translate-x-px md:before:mx-auto md:before:translate-x-0 before:h-full before:w-0.5 before:bg-gradient-to-b before:from-transparent before:via-slate-300 dark:before:via-slate-700 before:to-transparent">
          {filteredTimeline.map((record, i) => {
            const isResolved = record.resolved_at !== null;
            return (
              <div key={i} className="relative flex items-center justify-between md:justify-normal md:odd:flex-row-reverse group is-active">
                
                {/* Timeline dot */}
                <div className="flex items-center justify-center w-10 h-10 rounded-full border border-outline-variant bg-background text-outline shrink-0 md:order-1 md:group-odd:-translate-x-1/2 md:group-even:translate-x-1/2 shadow">
                  <History className="w-4 h-4" />
                </div>
                
                {/* Content */}
                <div className={`w-[calc(100%-4rem)] md:w-[calc(50%-2.5rem)] p-4 rounded-lg bg-card shadow-lg ${record.digital_bypass ? 'border-2 border-dashed border-orange-500 shadow-[0_0_15px_rgba(249,115,22,0.1)]' : ''}`}>
                  <div className="flex items-center justify-between mb-2">
                    <span className="font-mono text-xs text-primary font-bold">LOAD_ID: {record.load_id.substring(0,8)}</span>
                    <span className="flex items-center gap-1 text-[10px] text-outline font-mono">
                      <Clock className="w-3 h-3" />
                      {new Date(record.created_at).toLocaleString()}
                    </span>
                  </div>
                  
                  {record.digital_bypass ? (
                    <>
                      <div className="mb-3 flex justify-between items-center">
                        <span className="text-xs text-on-surface-variant uppercase tracking-wider font-bold block">Incident Type</span>
                        <span className="bg-orange-900/40 text-orange-400 text-[10px] px-2 py-0.5 rounded border border-orange-700 uppercase font-bold tracking-widest">
                          PAPER FALLBACK
                        </span>
                      </div>
                      
                      <div className="mb-3">
                        <span className="text-sm font-bold text-orange-400 block mb-1">
                          Manual Override (Device Offline)
                        </span>
                        <div className="text-xs text-on-surface font-mono space-y-1 mt-2">
                          <p>Docket Ref: <strong className="text-foreground text-sm">{record.paper_docket_ref}</strong></p>
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
                            className="text-primary hover:underline text-xs flex items-center gap-1"
                          >
                            <Shield className="w-3 h-3" />
                            View Vault Scan
                          </a>
                        </div>
                        <div className="text-[10px] text-outline font-mono text-right">
                          <p>Sealed:</p>
                          <p>{new Date(record.completed_at_local || record.created_at).toLocaleString()}</p>
                        </div>
                      </div>
                    </>
                  ) : (
                    <>
                      <div className="mb-3">
                        <span className="text-xs text-on-surface-variant uppercase tracking-wider font-bold block mb-1">Incident Type</span>
                        <span className={`text-sm font-bold ${record.anomaly_flag === 'DRIVER_EMERGENCY_OVERRIDE' ? 'text-purple-400' : 'text-red-400'}`}>
                          {record.anomaly_flag || record.status}
                        </span>
                      </div>

                      {isResolved && (
                        <div className="mt-3 pt-3 border-t border-outline-variant bg-background/50 -mx-4 -mb-4 p-4 rounded-b-lg">
                          <span className="text-[10px] text-emerald-500 font-bold uppercase tracking-wider block mb-2">Manager Resolution Seal</span>
                          <p className="text-xs text-on-surface italic mb-2">"{record.anomaly_resolution_reason}"</p>
                          <div className="flex flex-wrap gap-1">
                            {(record.anomaly_resolution_tags || []).map((tag: string) => (
                              <span key={tag} className="text-[9px] px-1.5 py-0.5 rounded border border-outline text-on-surface-variant">
                                {tag}
                              </span>
                            ))}
                          </div>
                          <p className="text-[10px] text-outline font-mono mt-2 text-right">
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
            <div className="text-center text-outline py-10 font-mono italic">
              No audit records match the search criteria.
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

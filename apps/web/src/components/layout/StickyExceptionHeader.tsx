import { useState, useMemo } from 'react';
import { useExceptions } from '../../context/ExceptionContext';
import { AlertTriangle, ShieldAlert, ChevronDown, ChevronUp, Scale } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';
import { supabase } from '../../lib/supabase';

const CORRECTIVE_ACTIONS = [
  "Weight_Ticket_Verified",
  "Bailment_Corrected",
  "Axle_Distribution_Safe",
  "Recovery_Asset_Dispatched",
  "Load_Transferred",
  "GPS_Geofence_Drift",
  "Hardware_Scale_Failure"
];

const FORBIDDEN_PHRASES = ["ok", "solucionado", "fixed", "checked", "as per driver", "looks okay", "fine", "approved", "done", "test"];

// Simple hash function for the state snapshot
const generateStateHash = async (stateObj: any) => {
  const msgUint8 = new TextEncoder().encode(JSON.stringify(stateObj));
  const hashBuffer = await crypto.subtle.digest('SHA-256', msgUint8);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('').substring(0, 16);
};

export const StickyExceptionHeader = () => {
  const { anomalies, removeAnomalyLocally, connectionStatus } = useExceptions();
  const [expanded, setExpanded] = useState(false);
  const [resolutionText, setResolutionText] = useState<{ [key: string]: string }>({});
  const [selectedTags, setSelectedTags] = useState<{ [key: string]: string[] }>({});
  const [shakeId, setShakeId] = useState<string | null>(null);
  const [warningMsg, setWarningMsg] = useState<{ [key: string]: string }>({});

  const sortedAnomalies = useMemo(() => {
    return [...anomalies].sort((a, b) => {
      if (a.anomaly_flag === 'DRIVER_EMERGENCY_OVERRIDE' && b.anomaly_flag !== 'DRIVER_EMERGENCY_OVERRIDE') return -1;
      if (b.anomaly_flag === 'DRIVER_EMERGENCY_OVERRIDE' && a.anomaly_flag !== 'DRIVER_EMERGENCY_OVERRIDE') return 1;
      if (a.status === 'BREAKDOWN' && b.status !== 'BREAKDOWN') return -1;
      if (b.status === 'BREAKDOWN' && a.status !== 'BREAKDOWN') return 1;
      return 0;
    });
  }, [anomalies]);

  if (connectionStatus !== 'SUBSCRIBED') {
    return (
      <div className="bg-red-50 dark:bg-red-950/90 border-b border-red-300 dark:border-red-800 p-2 flex justify-center items-center gap-2 z-50 shadow-md">
        <AlertTriangle className="w-5 h-5 text-red-600 dark:text-red-500 animate-pulse" />
        <span className="text-red-900 dark:text-red-200 font-bold text-sm tracking-widest uppercase">
          WARNING: REALTIME CONNECTION LOST - UNVERIFIED DATA
        </span>
      </div>
    );
  }

  if (anomalies.length === 0) {
    return (
      <div className="glass-panel border-b border-border px-6 py-2 flex justify-between items-center z-50 shadow-md">
        <span className="text-muted-foreground text-sm font-medium tracking-wide">SYSTEM NOMINAL</span>
        <span className="flex h-3 w-3">
          <span className="relative inline-flex rounded-full h-3 w-3 bg-emerald-500"></span>
        </span>
      </div>
    );
  }

  const handleToggleTag = (anomalyId: string, tag: string) => {
    const currentTags = selectedTags[anomalyId] || [];
    if (currentTags.includes(tag)) {
      setSelectedTags({ ...selectedTags, [anomalyId]: currentTags.filter(t => t !== tag) });
    } else {
      setSelectedTags({ ...selectedTags, [anomalyId]: [...currentTags, tag] });
    }
    // Clear warning when interacting with tags
    if (warningMsg[anomalyId]) {
      setWarningMsg({ ...warningMsg, [anomalyId]: '' });
    }
  };

  const containsForbiddenPhrase = (text: string) => {
    const lowerText = text.toLowerCase();
    return FORBIDDEN_PHRASES.some(phrase => {
      // Check for exact matches or standalone phrases
      const regex = new RegExp(`\\b${phrase}\\b`, 'i');
      return regex.test(lowerText) || lowerText === phrase;
    });
  };

  const handleForceApprove = async (anomaly: any) => {
    const text = resolutionText[anomaly.id] || '';
    const tags = selectedTags[anomaly.id] || [];

    // 1. Sequential Lock Check (should be disabled by UI, but double check)
    if (tags.length === 0) {
      setWarningMsg({ ...warningMsg, [anomaly.id]: "Debe declarar los hechos (Tags) antes de testificar." });
      triggerShake(anomaly.id);
      return;
    }

    // 2. Cognitive Firewall (Forbidden Phrases)
    if (containsForbiddenPhrase(text) || text.length < 15) {
      setWarningMsg({ ...warningMsg, [anomaly.id]: "Legal Reality Check: Un auditor no aceptará esta justificación vaga. Explique QUÉ verificó." });
      triggerShake(anomaly.id);
      return;
    }

    // 3. Snapshot Hash Generation
    const stateSnapshot = {
      id: anomaly.id,
      flag: anomaly.anomaly_flag,
      status: anomaly.status,
      claimed_mass: anomaly.loaded_gross_mass,
      ocr_mass: anomaly.ocr_mass_extracted,
      tags: tags,
      timestamp: new Date().toISOString()
    };
    
    const hash = await generateStateHash(stateSnapshot);
    const finalResolutionPayload = `${text}\n\n[STATE_HASH:${hash}]`;

    const { data: { user } } = await supabase.auth.getUser();

    const { error } = await supabase
      .from('load_offers')
      .update({
        anomaly_resolved_at: new Date().toISOString(),
        anomaly_resolved_by: user?.id,
        anomaly_resolution_reason: finalResolutionPayload,
        anomaly_resolution_tags: tags,
        status: anomaly.status === 'BREAKDOWN' ? 'COMPLETED' : anomaly.status
      })
      .eq('id', anomaly.id);
    
    if (!error) {
      removeAnomalyLocally(anomaly.id);
      if (anomalies.length <= 1) setExpanded(false);
    }
  };

  const triggerShake = (id: string) => {
    setShakeId(id);
    setTimeout(() => setShakeId(null), 500);
  };

  return (
    <div className="bg-red-50 dark:bg-red-950/90 border-b border-red-300 dark:border-red-800 w-full z-50 shadow-[0_4px_20px_rgba(220,38,38,0.3)] animate-pulse-border">
      <div 
        className="px-6 py-3 flex justify-between items-center cursor-pointer hover:bg-red-100 dark:hover:bg-red-900/50 transition-colors"
        onClick={() => setExpanded(!expanded)}
      >
        <div className="flex items-center gap-3">
          <AlertTriangle className="w-6 h-6 text-red-600 dark:text-red-500 animate-bounce" />
          <span className="text-red-900 dark:text-red-200 font-bold tracking-wider">
            {anomalies.length} CRITICAL EXCEPTION{anomalies.length > 1 ? 'S' : ''} DETECTED
          </span>
        </div>
        <button className="text-red-900 dark:text-red-200">
          {expanded ? <ChevronUp /> : <ChevronDown />}
        </button>
      </div>

      {expanded && (
        <div className="bg-background max-h-[80vh] overflow-y-auto p-4 space-y-4">
          {sortedAnomalies.map(anomaly => {
            const text = resolutionText[anomaly.id] || '';
            const tags = selectedTags[anomaly.id] || [];
            
            const isEmergency = anomaly.anomaly_flag === 'DRIVER_EMERGENCY_OVERRIDE';
            const isBreakdown = anomaly.status === 'BREAKDOWN';
            const isSequentialLocked = tags.length === 0;
            const isShaking = shakeId === anomaly.id;

            let borderColor = 'border-red-500';
            if (isEmergency) borderColor = 'border-purple-500';
            if (isBreakdown && !isEmergency) borderColor = 'border-orange-500';

            return (
              <div key={anomaly.id} className={`bg-card border border-border shadow-sm border-l-4 ${borderColor} rounded-md p-4 transition-transform ${isShaking ? 'translate-x-2' : ''}`}>
                <div className="flex justify-between items-start mb-2">
                  <div className="flex items-center gap-2">
                    {isEmergency ? <ShieldAlert className="w-5 h-5 text-purple-500" /> : <AlertTriangle className={`w-5 h-5 ${isBreakdown ? 'text-orange-500' : 'text-red-500'}`} />}
                    <span className={`font-bold ${isEmergency ? 'text-purple-400' : isBreakdown ? 'text-orange-400' : 'text-red-400'}`}>
                      {isEmergency ? 'DRIVER EMERGENCY OVERRIDE' : isBreakdown ? 'UNIT BREAKDOWN' : anomaly.anomaly_flag}
                    </span>
                  </div>
                  <span className="text-xs text-muted-foreground">
                    {anomaly.completed_at_local ? formatDistanceToNow(new Date(anomaly.completed_at_local), { addSuffix: true }) : 'N/A'}
                  </span>
                </div>

                {!isEmergency && !isBreakdown && anomaly.anomaly_flag === 'MASS_MISMATCH' && (
                  <div className="flex gap-4 mb-4">
                    <div className="flex-1 bg-background p-2 rounded text-sm border border-border">
                      <span className="text-muted-foreground block text-xs">Driver Claimed Mass:</span>
                      <span className="font-mono text-foreground">{anomaly.loaded_gross_mass} kg</span>
                    </div>
                    <div className="flex-1 bg-background p-2 rounded border border-red-900/50 text-sm">
                      <span className="text-muted-foreground block text-xs">OCR Extracted Mass:</span>
                      <span className="font-mono text-red-400 font-bold">{anomaly.ocr_mass_extracted || 'N/A'} kg</span>
                    </div>
                  </div>
                )}

                {anomaly.docket_image_path && (
                  <div className="mb-4">
                    <a href={`${import.meta.env.VITE_SUPABASE_URL}/storage/v1/object/public/docket_evidence/${anomaly.docket_image_path}`} target="_blank" rel="noreferrer" className="text-primary hover:underline text-sm">
                      View Docket Evidence &rarr;
                    </a>
                  </div>
                )}

                {/* WITNESS STAND UI */}
                <div className="mt-4 pt-4 border-t border-border bg-card border shadow-sm/50 p-3 rounded">
                  <div className="flex items-center gap-2 mb-2 text-foreground">
                    <Scale className="w-4 h-4 text-primary" />
                    <p className="text-xs font-bold uppercase">The Witness Stand (CoR Legal Declaration)</p>
                  </div>
                  <p className="text-[10px] text-muted-foreground mb-3 italic">
                    By submitting this resolution, I certify under penalty of perjury that I have investigated this anomaly and assume operational liability for clearing this vehicle.
                  </p>
                  
                  {/* Step 1: Fact Declaration (Tags) */}
                  <div className="mb-3">
                    <p className="text-[10px] font-bold text-muted-foreground uppercase mb-1">Step 1: Declare Verified Facts</p>
                    <div className="flex flex-wrap gap-2">
                      {CORRECTIVE_ACTIONS.map(tag => (
                        <button
                          key={tag}
                          onClick={() => handleToggleTag(anomaly.id, tag)}
                          className={`text-[10px] px-2 py-1 rounded-full border ${tags.includes(tag) ? 'bg-primary text-primary-foreground border-primary' : 'bg-background border-border text-muted-foreground hover:border-slate-400'}`}
                        >
                          {tag.replace(/_/g, ' ')}
                        </button>
                      ))}
                    </div>
                  </div>

                  {/* Step 2: Narrative Construction (Text) */}
                  <div className="relative mb-2">
                    <p className="text-[10px] font-bold text-muted-foreground uppercase mb-1">
                      Step 2: Legal Narrative {isSequentialLocked && <span className="text-red-400">(Locked - Select Facts First)</span>}
                    </p>
                    <textarea 
                      className={`w-full bg-background border ${warningMsg[anomaly.id] ? 'border-red-500 focus:border-red-500' : 'border-border focus:border-primary'} rounded p-2 text-sm text-foreground outline-none transition-colors ${isSequentialLocked ? 'opacity-50 cursor-not-allowed' : ''}`}
                      placeholder={isSequentialLocked ? "Select a Fact Tag above to unlock..." : "Justify this override for NHVR audit..."}
                      rows={2}
                      disabled={isSequentialLocked}
                      value={text}
                      onChange={(e) => {
                        setResolutionText({ ...resolutionText, [anomaly.id]: e.target.value });
                        if (warningMsg[anomaly.id]) setWarningMsg({ ...warningMsg, [anomaly.id]: '' });
                      }}
                    />
                    {!isSequentialLocked && (
                      <span className={`absolute bottom-2 right-2 text-[10px] ${text.length < 15 ? 'text-red-400' : 'text-green-400'}`}>
                        {text.length}/15 min chars
                      </span>
                    )}
                  </div>

                  {/* Warning Injection */}
                  {warningMsg[anomaly.id] && (
                    <div className="mb-2 p-2 bg-red-900/50 border border-red-700 rounded text-xs text-red-200">
                      {warningMsg[anomaly.id]}
                    </div>
                  )}

                  <button 
                    onClick={() => handleForceApprove(anomaly)}
                    className="w-full text-sm font-medium py-2 rounded transition-colors bg-primary text-primary-foreground hover:bg-primary/90 shadow-lg"
                  >
                    Sign & Cryptographically Seal
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};


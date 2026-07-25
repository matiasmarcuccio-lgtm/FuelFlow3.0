import React, { useEffect, useState } from 'react';

export const LockoutScreen: React.FC = () => {
  const [secondsLocked, setSecondsLocked] = useState<number>(0);
  const [lockoutReason, setLockoutReason] = useState<string>('JURISDICTION_REVOKED');

  useEffect(() => {
    // 1. Secondary amputation for security: guarantee memory purge
    localStorage.clear();
    sessionStorage.clear();

    // 2. Forensic extraction of exclusion reason from URL
    const params = new URLSearchParams(window.location.search);
    const reason = params.get('reason');
    if (reason) setLockoutReason(reason);

    // 3. HISTORY TRAP: Block the browser's "Back" button physically and logically
    const trapHistory = () => {
      window.history.pushState(null, '', window.location.href);
    };
    trapHistory();
    window.addEventListener('popstate', trapHistory);

    // 4. Forensic timer of exclusion time
    const timer = setInterval(() => {
      setSecondsLocked((prev) => prev + 1);
    }, 1000);

    return () => {
      window.removeEventListener('popstate', trapHistory);
      clearInterval(timer);
    };
  }, []);

  const getReasonConfig = (code: string) => {
    switch (code) {
      case 'FATIGUE_LOCKOUT':
        return {
          title: 'CRITICAL EXCLUSION FOR FATIGUE',
          subtitle: 'Legal limit of WHS operating hours exceeded.',
          action: 'Turn off the engine immediately. You have exceeded the biometric safety threshold. You must complete a mandatory rest period before initiating a new Pre-Start.',
          border: 'border-amber-500',
          bg: 'bg-amber-950/30',
          text: 'text-amber-500',
        };
      case 'PAYMENT_FROZEN':
        return {
          title: 'COMMERCIAL FLEET SUSPENSION',
          subtitle: 'Operating license frozen by the accounting ledger.',
          action: 'Asset dispatch on this site has been suspended due to non-payment (PAST_DUE). Return machinery to the safe parking area and contact the fleet manager.',
          border: 'border-blue-600',
          bg: 'bg-blue-950/30',
          text: 'text-blue-500',
        };
      case 'JURISDICTION_REVOKED':
      default:
        return {
          title: 'INSTANT LICENSE REVOCATION',
          subtitle: 'Your credentials and AAL2 tokens have been purged by high command.',
          action: 'Intrusion danger or active dismissal. Your session has been eradicated from the real-time server. Cease all mechanical operation immediately.',
          border: 'border-red-600',
          bg: 'bg-red-950/40',
          text: 'text-red-500',
        };
    }
  };

  const config = getReasonConfig(lockoutReason);

  return (
    <div className="min-h-screen bg-black flex flex-col justify-between p-6 select-none font-sans text-white">
      {/* Industrial warning top bar */}
      <header className="border-b-4 border-red-600 pb-4 flex justify-between items-center">
        <div className="flex items-center gap-3">
          <span className="bg-red-600 text-black font-black font-mono text-xs px-2 py-1 uppercase tracking-widest animate-pulse">
            SYSTEM LOCKED
          </span>
          <span className="font-mono text-xs text-slate-500 uppercase">
            WHS Protocol Tasmania • Zero-Trust Enforced
          </span>
        </div>
        <div className="font-mono text-xs text-slate-400">
          LOCKOUT TIME: <span className="text-red-500 font-bold">{secondsLocked}s</span>
        </div>
      </header>

      {/* Core of the operating mandate */}
      <main className="max-w-3xl mx-auto w-full my-auto py-12">
        <div className={`border-4 ${config.border} ${config.bg} p-8 md:p-12 rounded-3xl shadow-2xl relative overflow-hidden`}>
          <div className="text-6xl md:text-7xl mb-6">🛑</div>
          
          <p className={`font-mono text-sm font-bold tracking-widest uppercase mb-2 ${config.text}`}>
            {config.subtitle}
          </p>
          
          <h1 className="text-3xl md:text-5xl font-black uppercase tracking-tight mb-8 leading-none">
            {config.title}
          </h1>

          <div className="bg-black/80 border border-slate-800 p-6 rounded-2xl mb-8">
            <h2 className="text-xs font-mono uppercase text-slate-400 mb-2 border-b border-slate-800 pb-1">
              Mandatory Legal Directive (Physical Custody):
            </h2>
            <p className="text-lg md:text-xl font-bold leading-relaxed text-slate-200">
              {config.action}
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 font-mono text-xs text-slate-400 bg-black/40 p-4 rounded-xl border border-slate-800/80">
            <div>
              <span className="text-slate-500 block">OPERATIONAL BASE:</span>
              <span>Hobart Quarry, TAS (Mine A)</span>
            </div>
            <div>
              <span className="text-slate-500 block">SYSTEM ACTION:</span>
              <span className="text-red-400 font-bold">Session Destroyed / JWTs Invalidated</span>
            </div>
          </div>
        </div>
      </main>

      {/* Footer without escape routes */}
      <footer className="border-t border-slate-900 pt-4 text-center font-mono text-xs text-slate-600 uppercase">
        Do not attempt to reload the browser or restart the mobile device. Your access has been revoked at the database level.
        <br />
        For appeals or emergency assistance, contact the Command Center via VHF radio (Channel 4).
      </footer>
    </div>
  );
};

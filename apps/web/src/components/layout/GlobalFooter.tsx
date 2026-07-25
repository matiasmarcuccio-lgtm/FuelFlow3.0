import { ShieldCheck } from 'lucide-react';

export const GlobalFooter = () => {
  return (
    <footer className="h-8 bg-[#0c0e10] border-t border-outline-variant flex items-center justify-between px-4 shrink-0 text-[10px] text-on-surface-variant uppercase tracking-widest font-mono">
      <div className="flex items-center gap-2">
        <span>JITSite OS v3.0.1</span>
        <span>|</span>
        <span className="flex items-center gap-1"><ShieldCheck className="w-3 h-3 text-emerald-500" /> MDM LOCKED</span>
      </div>
      <div>
        <span>Chain of Custody Active</span>
      </div>
    </footer>
  );
};

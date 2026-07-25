import { Outlet, useLocation } from 'react-router-dom';
import { StickyExceptionHeader } from './StickyExceptionHeader';
import { GlobalHeader } from './GlobalHeader';
import { GlobalFooter } from './GlobalFooter';
import { MobileBottomNav } from './MobileBottomNav';
import { useRealtimeSync } from '../../hooks/useRealtimeSync';
import { AnimatePresence, motion } from 'framer-motion';

export const AppLayout = () => {
  useRealtimeSync();
  const location = useLocation();

  return (
    <div className="flex min-h-[100dvh] w-full bg-background text-foreground font-sans relative pb-24 md:pb-0 overflow-x-hidden selection:bg-primary/30 selection:text-primary">
      {/* Premium Background Elements */}
      <div className="fixed inset-0 pointer-events-none z-[-1] bg-background">
        <div className="absolute top-0 right-0 w-[50vw] h-[50vw] bg-primary/5 rounded-full blur-[120px] -translate-y-1/2 translate-x-1/3"></div>
        <div className="absolute bottom-0 left-0 w-[40vw] h-[40vw] bg-blue-500/5 rounded-full blur-[100px] translate-y-1/3 -translate-x-1/3"></div>
      </div>
      
      {/* Central Content Area */}
      <div className="flex-1 flex flex-col min-w-0 md:mx-6 mt-0 md:mt-6 mb-0 md:mb-6 relative z-10 w-full transition-all duration-300">
        <GlobalHeader />
        <StickyExceptionHeader />
        
        {/* Main Canvas (Glassmorphism & Fluid Routing) */}
        <main className="flex-1 relative flex flex-col bg-card/40 backdrop-blur-xl md:rounded-[2rem] border-y md:border border-border/50 shadow-2xl overflow-hidden mt-4 md:mt-6 transition-all duration-500 ring-1 ring-white/5">
          <AnimatePresence mode="wait">
            <motion.div
              key={location.pathname}
              initial={{ opacity: 0, y: 10, filter: 'blur(4px)' }}
              animate={{ opacity: 1, y: 0, filter: 'blur(0px)' }}
              exit={{ opacity: 0, y: -10, filter: 'blur(4px)' }}
              transition={{ duration: 0.3, ease: "easeOut" }}
              className="flex-1 flex flex-col h-full w-full"
            >
              <Outlet />
            </motion.div>
          </AnimatePresence>
        </main>
        
        <GlobalFooter />
      </div>

      {/* Mobile Bottom Nav (Floating Dock Style) */}
      <div className="md:hidden fixed bottom-6 left-4 right-4 z-50">
        <MobileBottomNav />
      </div>
    </div>
  );
};

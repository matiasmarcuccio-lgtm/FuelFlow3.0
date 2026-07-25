import { useState, useEffect } from 'react';
import { createPortal } from 'react-dom';
import { NavLink, useLocation } from 'react-router-dom';
import { Menu, X, Activity, FileText, Search, Users, Settings, Map, HardHat, Truck } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';

export const MobileHamburgerMenu = () => {
  const [isOpen, setIsOpen] = useState(false);
  const location = useLocation();

  // Close menu on route change (Evita estado fantasma)
  useEffect(() => {
    setIsOpen(false);
  }, [location.pathname]);

  const toggleMenu = () => setIsOpen(!isOpen);

  const allLinks = [
    { to: '/', icon: Map, label: 'Telemetry Map' },
    { to: '/builder', icon: HardHat, label: 'Project Progress' },
    { to: '/analytics', icon: Activity, label: 'Financial Intel' },
    { to: '/fleet', icon: Truck, label: 'Resource Matrix' },
    { to: '/compliance', icon: FileText, label: 'CoR Summary' },
    { to: '/forensic', icon: Search, label: 'Forensic Engine' },
    { to: '/users', icon: Users, label: 'Human Resources' },
    { to: '/settings', icon: Settings, label: 'System Settings' }
  ];

  return (
    <>
      <button 
        onClick={toggleMenu}
        className="md:hidden p-2 text-foreground hover:bg-surface rounded-md transition-colors"
        aria-label="Toggle Menu"
      >
        <Menu className="w-6 h-6" />
      </button>

      {createPortal(
        <AnimatePresence>
          {isOpen && (
            <>
              {/* Backdrop */}
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                onClick={toggleMenu}
                className="fixed inset-0 z-[100] bg-black/60 backdrop-blur-sm md:hidden"
              />
              
              {/* Sidebar Slide */}
              <motion.div
                initial={{ x: '-100%' }}
                animate={{ x: 0 }}
                exit={{ x: '-100%' }}
                transition={{ type: 'spring', damping: 25, stiffness: 200 }}
                className="fixed top-0 left-0 bottom-0 z-[101] w-3/4 max-w-sm bg-background border-r border-border shadow-2xl flex flex-col md:hidden"
              >
                <div className="p-6 border-b border-border flex items-center justify-between">
                  <h1 className="text-xl font-bold text-foreground flex items-center gap-2 font-mono">
                    <Activity className="text-primary" />
                    JITSite
                  </h1>
                  <button onClick={toggleMenu} className="p-2 text-muted-foreground hover:text-foreground">
                    <X className="w-6 h-6" />
                  </button>
                </div>

                <nav className="flex-1 p-4 space-y-2 overflow-y-auto">
                  <p className="text-xs font-mono font-bold text-muted-foreground uppercase tracking-wider mb-4 mt-2 px-2">
                    Herramientas
                  </p>
                  {allLinks.map((item) => (
                    <NavLink
                      key={item.to}
                      to={item.to}
                      className={({ isActive }) =>
                        `flex items-center gap-3 px-3 py-3 font-mono text-sm transition-colors uppercase tracking-widest ${
                          isActive
                            ? 'bg-primary text-primary-foreground font-bold'
                            : 'hover:bg-secondary text-muted-foreground hover:text-foreground'
                        }`
                      }
                    >
                      <item.icon className="w-5 h-5" />
                      {item.label}
                    </NavLink>
                  ))}
                </nav>
              </motion.div>
            </>
          )}
        </AnimatePresence>,
        document.body
      )}
    </>
  );
};

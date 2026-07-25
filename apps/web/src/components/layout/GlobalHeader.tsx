import { MobileHamburgerMenu } from './MobileHamburgerMenu';
import { ThemeToggle } from '../ThemeToggle';
import { NavLink } from 'react-router-dom';
import { Activity, Map, Settings, FileText, HardHat, Truck, Search, Users, Radio } from 'lucide-react';

export const GlobalHeader = () => {
  const navItems = [
    { to: '/', icon: Map, label: 'Telemetry Map' },
    { to: '/dispatch', icon: Radio, label: 'Command Center' },
    { to: '/builder', icon: HardHat, label: 'Project Progress' },
    { to: '/analytics', icon: Activity, label: 'Financial Intel' },
    { to: '/fleet', icon: Truck, label: 'Resource Matrix' },
    { to: '/compliance', icon: FileText, label: 'CoR Summary' },
    { to: '/forensic', icon: Search, label: 'Forensic Engine' },
    { to: '/users', icon: Users, label: 'Human Resources' },
    { to: '/settings', icon: Settings, label: 'System Settings' }
  ];

  return (
    <header className="h-14 bg-card/60 backdrop-blur-xl border border-border/50 shadow-lg flex items-center justify-between px-4 md:px-6 shrink-0 z-40 relative mx-4 md:mx-0 mt-4 md:mt-0 rounded-2xl transition-all duration-300">
      <div className="flex items-center gap-3 md:gap-4 shrink-0">
        <MobileHamburgerMenu />
        <h1 className="text-xl font-bold tracking-widest text-primary md:hidden">JITSite</h1>
        
        {/* En Desktop mostramos la marca JITSite aquí ya que borramos el Sidebar */}
        <h1 className="text-xl font-bold tracking-widest text-primary hidden md:block">JITSite</h1>
        <div className="hidden sm:block h-6 w-px bg-border"></div>
        <span className="text-sm font-medium text-muted-foreground uppercase tracking-widest truncate">
          Sector 7
        </span>
      </div>

      {/* Navegación central con Tooltips */}
      <nav className="hidden md:flex flex-1 items-center justify-center gap-2 px-4">
        {navItems.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.to === '/'}
            className={({ isActive }) => `group relative p-2.5 rounded-lg transition-all duration-200 ${isActive ? 'bg-primary/15 text-primary' : 'hover:bg-accent text-muted-foreground hover:text-foreground'}`}
          >
            <item.icon className="w-5 h-5" />
            <div className="absolute top-full left-1/2 -translate-x-1/2 mt-2 px-2 py-1 bg-foreground text-background text-[10px] font-bold font-mono rounded opacity-0 group-hover:opacity-100 pointer-events-none transition-opacity whitespace-nowrap z-[100]">
              {item.label}
            </div>
          </NavLink>
        ))}
      </nav>
      <div className="flex items-center gap-2 md:gap-4">
        <ThemeToggle />
        <span className="text-[10px] md:text-xs font-mono text-muted-foreground bg-accent p-1 md:p-1.5 rounded border border-border">
          SYS_NOMINAL
        </span>
      </div>
    </header>
  );
};

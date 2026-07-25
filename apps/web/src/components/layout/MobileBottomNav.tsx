import { NavLink } from 'react-router-dom';
import { Map, HardHat, Truck } from 'lucide-react';

export const MobileBottomNav = () => {
  const navItems = [
    { to: '/', icon: Map, label: 'Map' },
    { to: '/builder', icon: HardHat, label: 'Progress' },
    { to: '/fleet', icon: Truck, label: 'Fleet' },
  ];

  return (
    <nav className="flex items-center justify-around h-16 w-full glass-card bg-card/60 backdrop-blur-2xl rounded-full shadow-[0_10px_40px_rgba(0,0,0,0.5)] border border-white/10 px-2 transition-all">
      {navItems.map((item) => (
        <NavLink
          key={item.to}
          to={item.to}
          className={({ isActive }) =>
            `flex flex-col items-center justify-center w-full h-full space-y-1 transition-colors ${
              isActive
                ? 'text-primary'
                : 'text-muted-foreground hover:text-foreground'
            }`
          }
        >
          <item.icon className="w-6 h-6" />
          <span className="text-[10px] uppercase font-semibold tracking-wider">
            {item.label}
          </span>
        </NavLink>
      ))}
    </nav>
  );
};

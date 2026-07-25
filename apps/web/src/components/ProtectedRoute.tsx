import { useState } from 'react';
import { Navigate, Outlet, useLocation, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { Scanner } from '@yudiel/react-qr-scanner';
import { Camera, X, LogOut } from 'lucide-react';
import { supabase } from '../lib/supabase';
import PaymentFrozenScreen from '../pages/PaymentFrozenScreen';
import MFAScreen from '../pages/MFAScreen';

interface ProtectedRouteProps {
  children?: React.ReactNode;
  allowedRoles?: ('super_admin' | 'fleet_manager' | 'supervisor' | 'driver')[];
}

const DriverHoldingScreen = () => {
  const [isScanning, setIsScanning] = useState(false);
  const [scanError, setScanError] = useState('');
  const navigate = useNavigate();

  const handleScan = (result: any) => {
    if (result && result.length > 0) {
      const url = result[0].rawValue;
      try {
        const parsedUrl = new URL(url);
        // Verificar que pertenece a nuestra app
        if (parsedUrl.origin === window.location.origin) {
          navigate(parsedUrl.pathname + parsedUrl.search);
        } else {
          setScanError('Invalid QR: External URL not permitted.');
        }
      } catch {
        setScanError('Invalid QR Code Format');
      }
    }
  };

  const handleLogout = async () => {
    await supabase.auth.signOut();
  };

  return (
    <div className="min-h-screen bg-background flex flex-col items-center justify-center text-foreground p-6 text-center relative overflow-hidden">
      
      {/* Background Dotted Pattern */}
      <div 
        className="absolute inset-0 pointer-events-none opacity-20 dark:opacity-10" 
        style={{ backgroundImage: 'radial-gradient(currentColor 1.5px, transparent 1.5px)', backgroundSize: '24px 24px' }}
      ></div>

      <div className="z-10 max-w-md w-full bg-card border border-border p-8 rounded-xl shadow-2xl flex flex-col items-center">
        
        <div className="p-4 bg-primary/20 rounded-full text-primary mb-6 shadow-[0_0_15px_rgba(var(--primary),0.3)]">
          <svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/></svg>
        </div>
        
        <h2 className="text-xl font-bold uppercase tracking-widest mb-2 text-primary">Node Authenticated</h2>
        <p className="text-sm text-muted-foreground mb-8">
          Access to the central Command Center is restricted by the Zero-Trust perimeter.
        </p>
        
        <button 
          onClick={() => setIsScanning(true)}
          className="w-full py-4 bg-primary text-primary-foreground font-bold uppercase tracking-widest text-sm rounded-md hover:bg-primary/90 transition-all flex items-center justify-center gap-2 shadow-lg mb-4"
        >
          <Camera className="w-5 h-5" />
          Activate Optics (Scan QR)
        </button>

        <button 
          onClick={handleLogout}
          className="text-xs text-muted-foreground hover:text-foreground underline flex items-center gap-1 font-bold uppercase tracking-wider transition-colors"
        >
          <LogOut className="w-3 h-3" /> Terminate Session
        </button>
      </div>

      {/* Pantalla Completa del Escáner QR */}
      {isScanning && (
        <div className="fixed inset-0 z-50 bg-black flex flex-col items-center justify-center">
          
          <div className="absolute top-0 left-0 w-full p-4 flex justify-between items-center bg-gradient-to-b from-black/80 to-transparent z-10">
            <h3 className="text-white font-mono uppercase tracking-widest text-sm font-bold">Optical Targeting Active</h3>
            <button 
              onClick={() => setIsScanning(false)}
              className="bg-white/20 text-white p-2 rounded-full hover:bg-white/30 transition-colors"
            >
              <X className="w-6 h-6" />
            </button>
          </div>

          <div className="w-full max-w-lg aspect-square relative border-2 border-primary/50 overflow-hidden">
             {/* Retícula (HUD visual) */}
             <div className="absolute inset-0 pointer-events-none z-10">
                <div className="w-full h-full border-[1px] border-primary/30 flex items-center justify-center">
                  <div className="w-48 h-48 border-2 border-primary border-dashed opacity-50 animate-pulse rounded"></div>
                </div>
             </div>
             
             <Scanner
                onScan={handleScan}
                onError={(e) => console.error(e)}
                styles={{ container: { width: '100%', height: '100%' } }}
             />
          </div>
          
          {scanError && (
            <div className="absolute bottom-10 bg-destructive/90 text-white px-4 py-2 rounded uppercase font-bold text-xs tracking-widest shadow-lg">
              {scanError}
            </div>
          )}
          
          <div className="absolute bottom-0 left-0 w-full p-4 bg-gradient-to-t from-black to-transparent text-center">
            <p className="text-white/70 font-mono text-xs uppercase tracking-widest">
              Align the Asset QR code within the perimeter.
            </p>
          </div>

        </div>
      )}
    </div>
  );
};

export const ProtectedRoute = ({ children, allowedRoles }: ProtectedRouteProps) => {
  const { session, userRole, fleetStatus, currentAal, loading } = useAuth();
  const location = useLocation();

  if (loading) {
    return <div className="min-h-screen bg-background flex items-center justify-center text-muted-foreground font-mono text-sm uppercase tracking-widest">Validando credenciales...</div>;
  }

  if (!session) {
    return <Navigate to="/login" replace />;
  }

  // 1. Verificar Suscripción Congelada (Orquestador B2B falló)
  if (fleetStatus === 'past_due' || fleetStatus === 'canceled' || fleetStatus === 'suspended') {
    // Si es super_admin le dejamos pasar para que lo arregle, sino bloqueado.
    if (userRole !== 'super_admin') {
      return <PaymentFrozenScreen />;
    }
  }

  // 2. Verificar MFA (AAL2) para roles críticos
  const criticalRoles = ['supervisor', 'fleet_manager', 'fitter', 'super_admin'];
  if (userRole && criticalRoles.includes(userRole)) {
    if (currentAal !== 'aal2') {
      return <MFAScreen />;
    }
  }

  // 3. Enrutador Jurisdiccional Estricto
  // Si el usuario intenta acceder a la raíz ('/') lo escupimos a su búnker.
  if (location.pathname === '/') {
    if (userRole === 'driver') return <DriverHoldingScreen />;
    if (userRole === 'supervisor') return <Navigate to="/dispatch" replace />;
    if (userRole === 'fitter') return <Navigate to="/workshop" replace />;
    if (userRole === 'fleet_manager') return <Navigate to="/fleet" replace />;
    if (userRole === 'super_admin') return <Navigate to="/builder" replace />;
  }

  // Si hay roles permitidos explícitos en la ruta y el usuario no está en ellos, expulsarlo
  if (allowedRoles && userRole && !allowedRoles.includes(userRole)) {
    if (userRole === 'super_admin') return <Navigate to="/builder" replace />;
    if (userRole === 'fleet_manager') return <Navigate to="/fleet" replace />;
    if (userRole === 'supervisor') return <Navigate to="/dispatch" replace />;
    if (userRole === 'fitter') return <Navigate to="/workshop" replace />;
    
    return <DriverHoldingScreen />;
  }

  return children ? <>{children}</> : <Outlet />;
};

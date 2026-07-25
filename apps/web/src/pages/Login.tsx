import { useState } from 'react';
import { supabase } from '../lib/supabase';
import { Navigate, Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { Shield, Eye, EyeOff, ShieldAlert, Lock, Mail, ArrowRight } from 'lucide-react';

export default function Login() {
  const { session, loading: authLoading } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [showPassword, setShowPassword] = useState(false);

  if (authLoading) {
    return <div className="min-h-screen bg-background flex items-center justify-center text-muted-foreground font-mono uppercase tracking-widest text-sm">Verificando Credenciales...</div>;
  }

  if (session) {
    return <Navigate to="/" replace />;
  }

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setErrorMsg('');
    
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      setErrorMsg(error.message);
    }
    setLoading(false);
  };

  return (
    <div className="min-h-screen bg-background flex flex-col items-center justify-center px-6 py-12 text-foreground relative overflow-hidden">
      
      {/* Background Dotted Pattern (Subtle) */}
      <div 
        className="absolute inset-0 pointer-events-none opacity-20 dark:opacity-10" 
        style={{ backgroundImage: 'radial-gradient(currentColor 1.5px, transparent 1.5px)', backgroundSize: '24px 24px' }}
      ></div>

      <div className="z-10 w-full max-w-md flex flex-col items-center">
        {/* Header / Brand */}
        <div className="w-full mb-10 flex items-center justify-center gap-3">
          <div className="p-2 bg-primary rounded-md shadow-lg shadow-primary/20">
            <Shield className="text-primary-foreground w-6 h-6" />
          </div>
          <h1 className="text-3xl font-extrabold tracking-tighter uppercase text-foreground">JITSite</h1>
        </div>

        {/* Main Authentication Card */}
        <div className="w-full bg-card border border-border rounded-xl p-8 shadow-xl glass-panel relative overflow-hidden">
          
          <header className="mb-8">
            <h2 className="text-2xl font-bold tracking-tight mb-2">Secure Access</h2>
            <p className="text-muted-foreground text-sm leading-relaxed">
              Enterprise-grade authentication for industrial management operations.
            </p>
          </header>

          {/* MFA Warning Notification */}
          <div className="mb-6 flex gap-3 p-4 bg-muted/50 border-l-4 border-primary rounded-r-md">
            <ShieldAlert className="w-5 h-5 flex-shrink-0 mt-0.5 text-primary" />
            <div className="text-xs text-muted-foreground">
              <span className="font-bold block uppercase tracking-wider mb-1 text-foreground">MFA Protocol Active</span>
              Hardware keys (FIDO2) or authenticator tokens required for node connection.
            </div>
          </div>

          <form onSubmit={handleLogin} className="space-y-6">
            
            {/* Email Field */}
            <div className="space-y-2">
              <label htmlFor="email" className="text-xs font-bold uppercase tracking-widest text-muted-foreground">
                Corporate Email or ID
              </label>
              <div className="relative group">
                <Mail className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground group-focus-within:text-primary transition-colors" />
                <input
                  id="email"
                  type="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="e.g. FS-4492-AX"
                  className="w-full pl-10 pr-4 py-3 bg-background border border-input rounded-md focus:outline-none focus:ring-1 focus:ring-primary focus:border-primary transition-all text-sm font-medium"
                />
              </div>
            </div>

            {/* Password Field */}
            <div className="space-y-2">
              <div className="flex justify-between items-end">
                <label htmlFor="password" className="text-xs font-bold uppercase tracking-widest text-muted-foreground">
                  Access Key
                </label>
                <button type="button" className="text-[10px] font-bold text-primary hover:underline tracking-tight">
                  FORGOT KEY?
                </button>
              </div>
              <div className="relative group">
                <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground group-focus-within:text-primary transition-colors" />
                <input
                  id="password"
                  type={showPassword ? "text" : "password"}
                  required
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="••••••••••••"
                  className="w-full pl-10 pr-12 py-3 bg-background border border-input rounded-md focus:outline-none focus:ring-1 focus:ring-primary focus:border-primary transition-all text-sm font-mono tracking-widest font-bold"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground p-1 transition-colors"
                  aria-label={showPassword ? "Hide password" : "Show password"}
                >
                  {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                </button>
              </div>
            </div>

            {/* Error Message */}
            {errorMsg && (
              <div className="bg-destructive/10 text-destructive text-xs font-bold p-3 rounded border border-destructive/20 text-center">
                {errorMsg}
              </div>
            )}

            {/* Submit Button */}
            <button
              type="submit"
              disabled={loading}
              className={`w-full py-4 bg-primary text-primary-foreground font-bold uppercase tracking-widest text-xs rounded-md hover:bg-primary/90 active:scale-[0.99] transition-all flex items-center justify-center gap-2 shadow-lg ${loading ? 'opacity-70 cursor-not-allowed' : ''}`}
            >
              {loading ? (
                <span className="flex items-center gap-2">
                  <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none"></circle>
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Processing...
                </span>
              ) : (
                <>
                  Initiate Connection
                  <ArrowRight className="w-4 h-4" />
                </>
              )}
            </button>
          </form>

          <footer className="mt-8 pt-6 border-t border-border text-center">
            <p className="text-[11px] text-muted-foreground">
              Unrecognized Node? <Link to="/register" className="font-bold text-primary hover:underline">Provision Hardware</Link>
            </p>
          </footer>
        </div>

        {/* System Footer Metadata */}
        <div className="mt-8 w-full max-w-sm flex justify-between items-center text-[10px] text-muted-foreground font-bold uppercase tracking-widest">
          <div className="flex items-center gap-2">
            <div className="w-1.5 h-1.5 bg-emerald-500 rounded-full animate-pulse shadow-[0_0_8px_rgba(16,185,129,0.8)]" />
            System Uptime: 99.9%
          </div>
          <div>V4.12.0_STABLE</div>
        </div>
      </div>
    </div>
  );
}

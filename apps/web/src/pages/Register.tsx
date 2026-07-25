import { useState } from 'react';
import { supabase } from '../lib/supabase';
import { Navigate, Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { Shield, Eye, EyeOff, Lock, Mail, ArrowRight, User } from 'lucide-react';

export default function Register() {
  const { session, loading: authLoading } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [fullName, setFullName] = useState('');
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const [showPassword, setShowPassword] = useState(false);

  if (authLoading) {
    return <div className="min-h-screen bg-background flex items-center justify-center text-muted-foreground font-mono uppercase tracking-widest text-sm">Verificando Credenciales...</div>;
  }

  if (session) {
    return <Navigate to="/" replace />;
  }

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setErrorMsg('');
    setSuccessMsg('');
    
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: `${window.location.origin}/auth/callback`,
        data: {
          full_name: fullName, // Inyectado en raw_user_meta_data
        }
      }
    });

    if (error) {
      setErrorMsg(error.message);
    } else {
      setSuccessMsg('Hardware provisioned. Session authorized for strictly restricted zones.');
      // Auto-login happens natively if email confirmation is disabled, 
      // but if enabled, it asks to check email. Let's assume auto-login.
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

        {/* Main Registration Card */}
        <div className="w-full bg-card border border-border rounded-xl p-8 shadow-xl glass-panel relative overflow-hidden">
          
          <header className="mb-8">
            <h2 className="text-2xl font-bold tracking-tight mb-2">Hardware Provisioning</h2>
            <p className="text-muted-foreground text-sm leading-relaxed">
              Register a new rugged node into the command fleet.
            </p>
          </header>

          <form onSubmit={handleRegister} className="space-y-6">
            
            {/* Full Name Field */}
            <div className="space-y-2">
              <label htmlFor="fullName" className="text-xs font-bold uppercase tracking-widest text-muted-foreground">
                Operator Designation
              </label>
              <div className="relative group">
                <User className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground group-focus-within:text-primary transition-colors" />
                <input
                  id="fullName"
                  type="text"
                  required
                  value={fullName}
                  onChange={(e) => setFullName(e.target.value)}
                  placeholder="e.g. John Doe"
                  className="w-full pl-10 pr-4 py-3 bg-background border border-input rounded-md focus:outline-none focus:ring-1 focus:ring-primary focus:border-primary transition-all text-sm font-medium"
                />
              </div>
            </div>

            {/* Email Field */}
            <div className="space-y-2">
              <label htmlFor="email" className="text-xs font-bold uppercase tracking-widest text-muted-foreground">
                Node ID (Email)
              </label>
              <div className="relative group">
                <Mail className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground group-focus-within:text-primary transition-colors" />
                <input
                  id="email"
                  type="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="e.g. tablet.01@mining.com"
                  className="w-full pl-10 pr-4 py-3 bg-background border border-input rounded-md focus:outline-none focus:ring-1 focus:ring-primary focus:border-primary transition-all text-sm font-medium"
                />
              </div>
            </div>

            {/* Password Field */}
            <div className="space-y-2">
              <label htmlFor="password" className="text-xs font-bold uppercase tracking-widest text-muted-foreground">
                Access Key
              </label>
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

            {/* Error / Success Messages */}
            {errorMsg && (
              <div className="bg-destructive/10 text-destructive text-xs font-bold p-3 rounded border border-destructive/20 text-center">
                {errorMsg}
              </div>
            )}
            {successMsg && (
              <div className="bg-emerald-500/10 text-emerald-500 text-xs font-bold p-3 rounded border border-emerald-500/20 text-center">
                {successMsg}
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
                  Register Hardware
                  <ArrowRight className="w-4 h-4" />
                </>
              )}
            </button>
          </form>

          <footer className="mt-8 pt-6 border-t border-border text-center">
            <p className="text-[11px] text-muted-foreground">
              Node Already Provisioned? <Link to="/login" className="font-bold text-primary hover:underline">Initiate Connection</Link>
            </p>
          </footer>
        </div>

        {/* System Footer Metadata */}
        <div className="mt-8 w-full max-w-sm flex justify-between items-center text-[10px] text-muted-foreground font-bold uppercase tracking-widest">
          <div className="flex items-center gap-2">
            <div className="w-1.5 h-1.5 bg-emerald-500 rounded-full animate-pulse shadow-[0_0_8px_rgba(16,185,129,0.8)]" />
            Provisioning Link Active
          </div>
          <div>V4.12.0_STABLE</div>
        </div>
      </div>
    </div>
  );
}

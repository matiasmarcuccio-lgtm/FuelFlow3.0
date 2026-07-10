import { useState } from 'react';
import { supabase } from '../lib/supabase';
import { Navigate, Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { Shield, Key, Eye, EyeOff, AlertCircle, ArrowRight, IdCard } from 'lucide-react';

export default function Login() {
  const { session } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [showPassword, setShowPassword] = useState(false);

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
    <div className="flex min-h-screen flex-col items-center bg-[#f8f9fc] relative overflow-hidden font-sans">
      {/* Background Dotted Pattern */}
      <div 
        className="absolute inset-0 pointer-events-none opacity-40" 
        style={{ backgroundImage: 'radial-gradient(#cbd5e1 1.5px, transparent 1.5px)', backgroundSize: '24px 24px' }}
      ></div>

      {/* Main Content Container */}
      <div className="z-10 w-full max-w-md px-6 pt-12 pb-16 flex flex-col h-full">
        
        {/* Header Logo */}
        <div className="mb-12">
          <h1 className="text-2xl font-extrabold text-blue-800 tracking-tight">JITSite</h1>
        </div>

        {/* Titles */}
        <div className="relative mb-10 text-center">
          <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 text-8xl font-black text-slate-100 -z-10 select-none tracking-tighter">
            FF3.0
          </div>
          <h2 className="text-3xl font-extrabold text-slate-900 mb-3">Secure Access</h2>
          <p className="text-slate-500 text-sm leading-relaxed px-4 max-w-sm mx-auto">
            Enterprise-grade authentication for industrial management operations.
          </p>
        </div>

        {/* Auth Card */}
        <div className="bg-white rounded-2xl border border-slate-200 shadow-[0_8px_30px_rgb(0,0,0,0.04)] overflow-hidden relative z-10 w-full">
          
          {/* Top Encrypted Bar */}
          <div className="bg-[#0b5cff] px-5 py-2.5 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Shield className="w-4 h-4 text-white" />
              <span className="text-white text-xs font-bold tracking-widest">SYSTEM: ENCRYPTED</span>
            </div>
            <div className="w-2 h-2 rounded-full bg-emerald-400 shadow-[0_0_8px_rgba(52,211,153,0.8)]"></div>
          </div>

          <form onSubmit={handleLogin} className="p-6 sm:p-8 flex flex-col gap-6">
            
            {/* Email Field */}
            <div>
              <div className="flex items-center gap-2 mb-2">
                <IdCard className="w-4 h-4 text-slate-500" />
                <label className="text-sm font-bold text-slate-600">Corporate ID or Email</label>
              </div>
              <input
                type="email"
                value={email}
                required
                onChange={(e) => setEmail(e.target.value)}
                placeholder="e.g. FS-4492-AX"
                className="w-full bg-[#f0f4f8] border border-slate-200 rounded-xl px-4 py-3.5 text-slate-900 placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-600/50 focus:border-blue-600 transition-all font-medium"
              />
            </div>

            {/* Password Field */}
            <div>
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-2">
                  <Key className="w-4 h-4 text-slate-500" />
                  <label className="text-sm font-bold text-slate-600">Password</label>
                </div>
                <Link to="#" className="text-sm font-bold text-[#0b5cff] hover:underline">
                  Forgot Access Key?
                </Link>
              </div>
              <div className="relative">
                <input
                  type={showPassword ? "text" : "password"}
                  value={password}
                  required
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="••••••••••••"
                  className="w-full bg-[#f0f4f8] border border-slate-200 rounded-xl px-4 py-3.5 pr-12 text-slate-900 placeholder:text-slate-800 focus:outline-none focus:ring-2 focus:ring-blue-600/50 focus:border-blue-600 transition-all font-mono tracking-widest font-bold"
                />
                <button 
                  type="button" 
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-500 hover:text-slate-700 transition-colors"
                >
                  {showPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
                </button>
              </div>
            </div>

            {/* MFA Warning */}
            <div className="bg-[#eef2ff] border-l-4 border-[#0b5cff] rounded-r-xl p-4 flex gap-3 mt-1">
              <div className="bg-[#0b5cff] w-5 h-5 rounded-full flex items-center justify-center flex-shrink-0 mt-0.5">
                <span className="text-white text-xs font-black">!</span>
              </div>
              <div>
                <h4 className="text-sm font-bold text-[#0b5cff] mb-1">MFA REQUIRED</h4>
                <p className="text-sm text-slate-600 leading-relaxed font-medium">
                  Hardware security keys (FIDO2) or mobile authenticator tokens are mandatory for node connection.
                </p>
              </div>
            </div>

            {/* Error Message */}
            {errorMsg && (
              <div className="bg-red-50 text-red-600 text-sm font-bold p-3 rounded-xl border border-red-200 text-center">
                {errorMsg}
              </div>
            )}

            {/* Submit Button */}
            <button 
              type="submit" 
              disabled={loading} 
              className="w-full bg-[#0047b3] hover:bg-[#003380] text-white rounded-xl py-4 flex items-center justify-center gap-2 font-bold text-lg transition-colors mt-2 disabled:opacity-70 disabled:cursor-not-allowed shadow-md shadow-blue-900/20"
            >
              {loading ? 'Authenticating...' : 'Initiate Connection'}
              {!loading && <ArrowRight className="w-5 h-5" />}
            </button>

          </form>
        </div>

      </div>
    </div>
  );
}

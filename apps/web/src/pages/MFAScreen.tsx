import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { ShieldAlert, ShieldCheck, KeyRound, Loader2, ArrowRight, LogOut } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

export default function MFAScreen() {
  const [loading, setLoading] = useState(true);
  const [errorMsg, setErrorMsg] = useState('');
  const [factorId, setFactorId] = useState<string | null>(null);
  const [qrCode, setQrCode] = useState<string | null>(null);
  const [challengeId, setChallengeId] = useState<string | null>(null);
  const [verifyCode, setVerifyCode] = useState('');
  const [isEnrolling, setIsEnrolling] = useState(false);
  const navigate = useNavigate();

  useEffect(() => {
    const initMfa = async () => {
      try {
        const { data: factorsData, error: factorsError } = await supabase.auth.mfa.listFactors();
        if (factorsError) throw factorsError;

        const totpFactors = factorsData.totp || [];
        const enrolledFactor = totpFactors.find((f: any) => f.status === 'verified');

        if (enrolledFactor) {
          // El usuario ya tiene MFA, iniciamos el desafío
          setIsEnrolling(false);
          setFactorId(enrolledFactor.id);
          const { data: challengeData, error: challengeError } = await supabase.auth.mfa.challenge({
            factorId: enrolledFactor.id,
          });
          if (challengeError) throw challengeError;
          setChallengeId(challengeData.id);
        } else {
          // El usuario necesita configurar MFA
          setIsEnrolling(true);
          const { data: enrollData, error: enrollError } = await supabase.auth.mfa.enroll({
            factorType: 'totp',
          });
          if (enrollError) throw enrollError;
          setFactorId(enrollData.id);
          if (enrollData.totp?.qr_code) {
            setQrCode(enrollData.totp.qr_code);
          }
        }
      } catch (err: any) {
        setErrorMsg(err.message || 'Error initializing MFA');
      } finally {
        setLoading(false);
      }
    };

    initMfa();
  }, []);

  const handleVerify = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!factorId) return;
    setLoading(true);
    setErrorMsg('');

    try {
      if (isEnrolling) {
        // Enrolment require challengeAndVerify together en la V2 de Supabase
        const { error: challengeError } = await supabase.auth.mfa.challengeAndVerify({
          factorId,
          code: verifyCode,
        });
        if (challengeError) throw challengeError;
      } else {
        // Simple verificación para sesión existente
        if (!challengeId) throw new Error('Challenge ID missing');
        const { error: verifyError } = await supabase.auth.mfa.verify({
          factorId,
          challengeId,
          code: verifyCode,
        });
        if (verifyError) throw verifyError;
      }
      
      // Si fue exitoso, AuthContext atrapará el evento MFA_CHALLENGE_VERIFIED
      // y actualizará currentAal, lo que desencadenará el re-render y redirigirá fuera de aquí.
      
    } catch (err: any) {
      setErrorMsg(err.message || 'Invalid authentication code.');
    } finally {
      setLoading(false);
    }
  };

  const handleLogout = async () => {
    await supabase.auth.signOut();
    navigate('/login');
  };

  if (loading && !factorId) {
    return (
      <div className="min-h-screen bg-slate-950 flex flex-col items-center justify-center font-mono text-blue-500">
        <Loader2 className="w-8 h-8 animate-spin mb-4" />
        <p className="uppercase tracking-widest text-sm">Negotiating Crypto Challenge...</p>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-slate-950 flex flex-col items-center justify-center px-6 py-12 text-slate-200 relative overflow-hidden font-sans">
      
      {/* Retícula (HUD visual) */}
      <div 
        className="absolute inset-0 pointer-events-none opacity-20" 
        style={{ backgroundImage: 'radial-gradient(currentColor 1.5px, transparent 1.5px)', backgroundSize: '24px 24px' }}
      ></div>

      <div className="z-10 w-full max-w-md bg-slate-900 border border-slate-800 p-8 rounded-xl shadow-2xl relative overflow-hidden">
        
        {/* Encabezado */}
        <div className="flex flex-col items-center mb-8">
          <div className="p-4 bg-purple-950/50 text-purple-400 rounded-full mb-4 border border-purple-900/50 shadow-[0_0_15px_rgba(168,85,247,0.2)]">
            {isEnrolling ? <ShieldAlert className="w-8 h-8" /> : <ShieldCheck className="w-8 h-8" />}
          </div>
          <h2 className="text-2xl font-black uppercase tracking-widest text-white text-center">
            {isEnrolling ? 'Provision Hardware' : 'AAL2 Challenge'}
          </h2>
          <p className="text-slate-500 font-mono text-xs mt-2 text-center">
            {isEnrolling 
              ? 'Your jurisdiction requires Multi-Factor Authentication.'
              : 'Enter your 6-digit authenticator code.'}
          </p>
        </div>

        {/* QR de Enrolamiento */}
        {isEnrolling && qrCode && (
          <div className="mb-8 flex flex-col items-center">
            <div className="p-2 bg-white rounded-lg shadow-lg">
              <img src={qrCode} alt="TOTP QR Code" className="w-48 h-48" />
            </div>
            <p className="text-[10px] uppercase font-bold tracking-widest text-slate-500 mt-4 text-center max-w-xs">
              Scan this matrix with Google Authenticator or Authy to bind your device.
            </p>
          </div>
        )}

        {/* Formulario de PIN */}
        <form onSubmit={handleVerify} className="space-y-6">
          <div className="space-y-2">
            <label className="text-[10px] font-bold uppercase tracking-widest text-slate-500">
              One-Time Passcode (TOTP)
            </label>
            <div className="relative group">
              <KeyRound className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-600 group-focus-within:text-purple-400 transition-colors" />
              <input
                type="text"
                required
                maxLength={6}
                value={verifyCode}
                onChange={(e) => setVerifyCode(e.target.value.replace(/\D/g, ''))}
                placeholder="000000"
                className="w-full pl-10 pr-4 py-3 bg-slate-950 border border-slate-800 rounded-md focus:outline-none focus:ring-1 focus:ring-purple-500 focus:border-purple-500 transition-all text-center font-mono text-2xl font-bold tracking-[0.5em] text-white"
              />
            </div>
          </div>

          {errorMsg && (
            <div className="bg-red-950/50 text-red-400 text-[10px] font-bold uppercase tracking-widest p-3 rounded border border-red-900/50 text-center">
              {errorMsg}
            </div>
          )}

          <button
            type="submit"
            disabled={loading || verifyCode.length !== 6}
            className={`w-full py-4 bg-purple-600 text-white font-bold uppercase tracking-widest text-xs rounded-md hover:bg-purple-500 active:scale-[0.99] transition-all flex items-center justify-center gap-2 shadow-[0_0_15px_rgba(147,51,234,0.3)] ${
              (loading || verifyCode.length !== 6) ? 'opacity-50 cursor-not-allowed' : ''
            }`}
          >
            {loading ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : (
              <>
                Verify Crypto Signature
                <ArrowRight className="w-4 h-4" />
              </>
            )}
          </button>
        </form>

        {/* Cierre de sesión de emergencia */}
        <div className="mt-8 text-center border-t border-slate-800 pt-6">
          <button 
            onClick={handleLogout}
            className="text-[10px] font-bold uppercase tracking-widest text-slate-600 hover:text-slate-400 transition-colors flex items-center justify-center gap-1 mx-auto"
          >
            <LogOut className="w-3 h-3" /> Abort Session
          </button>
        </div>
      </div>
    </div>
  );
}

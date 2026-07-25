import React, { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { Shield, ShieldAlert, Key, Download, CheckCircle, X, AlertTriangle } from 'lucide-react';

interface MFASetupModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

export const MFASetupModal: React.FC<MFASetupModalProps> = ({ isOpen, onClose, onSuccess }) => {
  const [step, setStep] = useState<'enroll' | 'verify' | 'verify_existing' | 'recovery' | 'done'>('enroll');
  const [qrCodeSvg, setQrCodeSvg] = useState<string>('');
  const [factorId, setFactorId] = useState<string>('');
  const [verifyCode, setVerifyCode] = useState('');
  const [errorMsg, setErrorMsg] = useState('');
  const [loading, setLoading] = useState(false);
  const [recoveryCodes, setRecoveryCodes] = useState<string[]>([]);
  const [downloaded, setDownloaded] = useState(false);

  useEffect(() => {
    if (isOpen && step === 'enroll') {
      initEnrollment();
    }
  }, [isOpen]);

  const initEnrollment = async () => {
    setLoading(true);
    setErrorMsg('');

    try {
      const { data: factors } = await supabase.auth.mfa.listFactors();
      
      // If they already have a verified factor, just challenge it to upgrade the session!
      const verifiedFactor = factors?.totp?.find(f => f.status === 'verified');
      if (verifiedFactor) {
        setFactorId(verifiedFactor.id);
        setStep('verify_existing');
        setLoading(false);
        return;
      }

      if (factors && factors.all) {
        for (const factor of factors.all) {
          if (factor.status === 'unverified') {
            await supabase.auth.mfa.unenroll({ factorId: factor.id });
          }
        }
      }
    } catch (err) {
      console.warn("Could not list or cleanup factors:", err);
    }

    // Use a unique friendly name to definitively bypass the "friendly name '' already exists" error
    const uniqueDeviceName = `Auth Device ${new Date().getTime()}`;

    const { data, error } = await supabase.auth.mfa.enroll({
      factorType: 'totp',
      friendlyName: uniqueDeviceName
    });

    if (error) {
      setErrorMsg(error.message);
      setLoading(false);
      return;
    }

    if (data.type === 'totp') {
      setFactorId(data.id);
      setQrCodeSvg(data.totp.qr_code);
      setStep('verify');
    }
    setLoading(false);
  };

  const handleVerify = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setErrorMsg('');

    const challenge = await supabase.auth.mfa.challenge({ factorId });
    if (challenge.error) {
      setErrorMsg(challenge.error.message);
      setLoading(false);
      return;
    }

    const verify = await supabase.auth.mfa.verify({
      factorId,
      challengeId: challenge.data.id,
      code: verifyCode
    });

    if (verify.error) {
      setErrorMsg(verify.error.message);
      setLoading(false);
      return;
    }

    // Si solo estamos verificando un dispositivo existente, vamos directo a 'done'
    if (step === 'verify_existing') {
      setStep('done');
      setLoading(false);
      setTimeout(() => {
        onSuccess();
      }, 2000);
      return;
    }

    // Generar códigos de recuperación (simulados por ahora, en Fase 2 se guardarán en DB)
    const codes = Array.from({ length: 8 }, () => 
      Math.random().toString(36).substring(2, 6).toUpperCase() + '-' + 
      Math.random().toString(36).substring(2, 6).toUpperCase()
    );
    setRecoveryCodes(codes);
    setStep('recovery');
    setLoading(false);
  };

  const handleDownload = () => {
    const text = `FUELFLOW WHS - MFA RECOVERY CODES\n=================================\n\nStore these codes securely. If you lose your TOTP device, you will need these to bypass the hardware requirement.\n\n${recoveryCodes.join('\n')}\n\nGenerated: ${new Date().toISOString()}`;
    const blob = new Blob([text], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'fuelflow-recovery-codes.txt';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    setDownloaded(true);
  };

  const finishSetup = () => {
    if (!downloaded && step === 'recovery') {
      setErrorMsg('You must download the recovery codes before continuing.');
      return;
    }
    setStep('done');
    setTimeout(() => {
      onSuccess();
    }, 2000);
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm p-4">
      <div className="bg-card w-full max-w-md border border-border rounded-xl shadow-2xl relative overflow-hidden flex flex-col max-h-[90vh]">
        
        {/* Header */}
        <div className="p-6 border-b border-border flex items-center justify-between bg-muted/30">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-primary/20 rounded-md text-primary">
              <Shield className="w-5 h-5" />
            </div>
            <h2 className="text-xl font-bold tracking-tight uppercase">MFA Setup</h2>
          </div>
          {step !== 'recovery' && (
            <button onClick={onClose} className="text-muted-foreground hover:text-foreground transition-colors">
              <X className="w-5 h-5" />
            </button>
          )}
        </div>

        {/* Body */}
        <div className="p-6 overflow-y-auto">
          {errorMsg && (
            <div className="mb-6 flex gap-3 p-3 bg-destructive/10 border-l-4 border-destructive rounded-r-md text-destructive">
              <AlertTriangle className="w-5 h-5 flex-shrink-0" />
              <p className="text-sm font-medium">{errorMsg}</p>
            </div>
          )}

          {step === 'enroll' && (
            <div className="flex flex-col items-center justify-center py-8">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary mb-4"></div>
              <p className="text-muted-foreground font-mono text-sm uppercase">Generating Cryptographic Seed...</p>
            </div>
          )}

          {step === 'verify' && (
            <div className="flex flex-col gap-6">
              <div className="text-sm text-muted-foreground">
                <p className="mb-2">1. Open your authenticator app (Google Authenticator, Authy, etc).</p>
                <p>2. Scan the QR code below to link your device.</p>
              </div>

              <div className="bg-white p-4 rounded-xl flex items-center justify-center self-center" dangerouslySetInnerHTML={{ __html: qrCodeSvg }} />

              <form onSubmit={handleVerify} className="flex flex-col gap-4 mt-2">
                <div>
                  <label className="text-xs font-bold uppercase tracking-widest text-muted-foreground block mb-2">
                    Verification Code (6 digits)
                  </label>
                  <input
                    type="text"
                    required
                    maxLength={6}
                    pattern="\d{6}"
                    value={verifyCode}
                    onChange={(e) => setVerifyCode(e.target.value.replace(/\D/g, ''))}
                    placeholder="000000"
                    className="w-full px-4 py-3 bg-background border border-input rounded-md focus:outline-none focus:ring-1 focus:ring-primary text-center text-2xl tracking-[0.5em] font-mono"
                  />
                </div>
                <button
                  type="submit"
                  disabled={loading || verifyCode.length !== 6}
                  className="w-full flex items-center justify-center gap-2 bg-primary text-primary-foreground hover:bg-primary/90 px-4 py-3 rounded-md font-bold uppercase tracking-wider text-sm transition-all disabled:opacity-50"
                >
                  {loading ? 'Verifying...' : 'Confirm Hardware'}
                </button>
              </form>
            </div>
          )}

          {step === 'verify_existing' && (
            <div className="flex flex-col gap-6">
              <div className="text-sm text-muted-foreground bg-muted p-4 rounded-lg">
                <p className="font-bold text-foreground mb-1">MFA Verification Required</p>
                <p>Your account is already protected by TOTP MFA. Please enter the code from your authenticator app to upgrade your current session to AAL2.</p>
              </div>

              <form onSubmit={handleVerify} className="flex flex-col gap-4 mt-2">
                <div>
                  <label className="text-xs font-bold uppercase tracking-widest text-muted-foreground block mb-2 text-center">
                    Authenticator Code
                  </label>
                  <input
                    type="text"
                    required
                    maxLength={6}
                    pattern="\d{6}"
                    value={verifyCode}
                    onChange={(e) => setVerifyCode(e.target.value.replace(/\D/g, ''))}
                    placeholder="000000"
                    className="w-full px-4 py-3 bg-background border border-input rounded-md focus:outline-none focus:ring-1 focus:ring-primary text-center text-3xl tracking-[0.5em] font-mono"
                  />
                </div>
                <button
                  type="submit"
                  disabled={loading || verifyCode.length !== 6}
                  className="w-full flex items-center justify-center gap-2 bg-primary text-primary-foreground hover:bg-primary/90 px-4 py-3 rounded-md font-bold uppercase tracking-wider text-sm transition-all disabled:opacity-50"
                >
                  {loading ? 'Verifying...' : 'Verify Identity'}
                </button>
              </form>
            </div>
          )}

          {step === 'recovery' && (
            <div className="flex flex-col gap-6">
              <div className="flex gap-3 p-4 bg-amber-500/10 border border-amber-500/20 rounded-lg text-amber-500">
                <ShieldAlert className="w-6 h-6 flex-shrink-0" />
                <div className="text-sm">
                  <p className="font-bold uppercase tracking-wider mb-1">Physical Recovery Codes</p>
                  <p>Store these codes in a secure location. If your device is destroyed or lost in the field, this is the only way to prevent a permanent account lockout.</p>
                </div>
              </div>

              <div className="bg-black/50 border border-border rounded-md p-4 font-mono text-sm tracking-widest text-center grid grid-cols-2 gap-2">
                {recoveryCodes.map(c => (
                  <div key={c} className="bg-background py-2 rounded border border-border/50 text-foreground">{c}</div>
                ))}
              </div>

              <button
                onClick={handleDownload}
                className={`w-full flex items-center justify-center gap-2 px-4 py-3 rounded-md font-bold uppercase tracking-wider text-sm transition-all border ${downloaded ? 'bg-green-500/20 text-green-500 border-green-500/50' : 'bg-background hover:bg-muted border-border text-foreground'}`}
              >
                {downloaded ? <CheckCircle className="w-4 h-4" /> : <Download className="w-4 h-4" />}
                {downloaded ? 'Downloaded' : 'Download Secure File (.txt)'}
              </button>

              <button
                onClick={finishSetup}
                className={`w-full flex items-center justify-center gap-2 px-4 py-3 rounded-md font-bold uppercase tracking-wider text-sm transition-all ${downloaded ? 'bg-primary text-primary-foreground hover:bg-primary/90' : 'bg-muted text-muted-foreground cursor-not-allowed opacity-50'}`}
              >
                Complete Enrollment
              </button>
            </div>
          )}

          {step === 'done' && (
            <div className="flex flex-col items-center justify-center py-10 gap-4 text-green-500">
              <div className="p-4 bg-green-500/20 rounded-full">
                <CheckCircle className="w-12 h-12" />
              </div>
              <p className="text-xl font-bold uppercase tracking-wider">AAL2 Active</p>
              <p className="text-sm text-muted-foreground text-center">Cryptographic security level achieved.<br/>Returning to dashboard...</p>
            </div>
          )}

        </div>
      </div>
    </div>
  );
};

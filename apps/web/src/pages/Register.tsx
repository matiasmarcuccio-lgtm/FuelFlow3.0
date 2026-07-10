import { useState } from 'react';
import { supabase } from '../lib/supabase';
import { Navigate, Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

export default function Register() {
  const { session } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [fullName, setFullName] = useState('');
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [successMsg, setSuccessMsg] = useState('');

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
      setSuccessMsg('¡Cuenta creada exitosamente! Revisa tu correo (o el Inbucket local) para confirmar tu registro antes de iniciar sesión.');
    }
    setLoading(false);
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-50">
      <div style={{ padding: '2rem', maxWidth: '400px', width: '100%', background: 'white', borderRadius: '8px', boxShadow: '0 4px 6px rgba(0,0,0,0.1)' }}>
        <h1 style={{ textAlign: 'center', marginBottom: '2rem' }}>Crear Fleet B2B</h1>
        <form onSubmit={handleRegister} style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
          <div>
            <label>Name de la Empresa o Persona</label>
            <input
              type="text"
              value={fullName}
              required
              onChange={(e) => setFullName(e.target.value)}
              style={{ width: '100%', padding: '0.5rem', marginTop: '0.25rem', border: '1px solid #ccc' }}
            />
          </div>
          <div>
            <label>Correo Electrónico</label>
            <input
              type="email"
              value={email}
              required
              onChange={(e) => setEmail(e.target.value)}
              style={{ width: '100%', padding: '0.5rem', marginTop: '0.25rem', border: '1px solid #ccc' }}
            />
          </div>
          <div>
            <label>Password</label>
            <input
              type="password"
              value={password}
              required
              onChange={(e) => setPassword(e.target.value)}
              style={{ width: '100%', padding: '0.5rem', marginTop: '0.25rem', border: '1px solid #ccc' }}
            />
          </div>
          <button type="submit" disabled={loading} style={{ padding: '0.75rem', background: '#2563eb', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', marginTop: '1rem' }}>
            {loading ? 'Creando cuenta...' : 'Registrar Cuenta'}
          </button>
        </form>
        {errorMsg && <p style={{ color: 'red', marginTop: '1rem', textAlign: 'center' }}>{errorMsg}</p>}
        {successMsg && <p style={{ color: 'green', marginTop: '1rem', textAlign: 'center' }}>{successMsg}</p>}
        
        <div style={{ marginTop: '1.5rem', textAlign: 'center' }}>
          <p>¿Ya tienes cuenta? <Link to="/login" style={{ color: '#2563eb' }}>Inicia Sesión</Link></p>
        </div>
      </div>
    </div>
  );
}

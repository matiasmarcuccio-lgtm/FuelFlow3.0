import { useState } from 'react';
import { supabase } from '../lib/supabase';
import { Navigate, Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

export default function Login() {
  const { session } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');

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
    // Si es exitoso, AuthContext interceptará el onAuthStateChange y el ProtectedRoute hará la magia.
    setLoading(false);
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-50">
      <div style={{ padding: '2rem', maxWidth: '400px', width: '100%', background: 'white', borderRadius: '8px', boxShadow: '0 4px 6px rgba(0,0,0,0.1)' }}>
        <h1 style={{ textAlign: 'center', marginBottom: '2rem' }}>FuelFlow 3 - Fleet Manager</h1>
        <form onSubmit={handleLogin} style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
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
            <label>Contraseña</label>
            <input
              type="password"
              value={password}
              required
              onChange={(e) => setPassword(e.target.value)}
              style={{ width: '100%', padding: '0.5rem', marginTop: '0.25rem', border: '1px solid #ccc' }}
            />
          </div>
          <button type="submit" disabled={loading} style={{ padding: '0.75rem', background: 'black', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', marginTop: '1rem' }}>
            {loading ? 'Entrando...' : 'Iniciar Sesión B2B'}
          </button>
        </form>
        {errorMsg && <p style={{ color: 'red', marginTop: '1rem', textAlign: 'center' }}>{errorMsg}</p>}
        
        <div style={{ marginTop: '1.5rem', textAlign: 'center' }}>
          <p>¿No tienes tu flota registrada? <Link to="/register" style={{ color: '#2563eb' }}>Crea tu cuenta aquí</Link></p>
        </div>
      </div>
    </div>
  );
}

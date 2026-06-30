import { useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { supabase } from '../lib/supabase';

export default function AuthCallback() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();

  useEffect(() => {
    const handleCodeExchange = async () => {
      const code = searchParams.get('code');
      
      if (code) {
        // Intercambio estricto de PKCE
        const { error } = await supabase.auth.exchangeCodeForSession(code);
        if (!error) {
          navigate('/', { replace: true });
        } else {
          console.error("Error en PKCE:", error);
          navigate('/login', { replace: true });
        }
      } else {
        // Fallback si no hay código (quizás el usuario recargó la página)
        supabase.auth.getSession().then(({ data: { session } }) => {
          if (session) {
            navigate('/', { replace: true });
          } else {
            navigate('/login', { replace: true });
          }
        });
      }
    };

    handleCodeExchange();
  }, [navigate, searchParams]);

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-50">
      <div style={{ padding: '2rem', textAlign: 'center' }}>
        <h2>Verificando identidad...</h2>
        <p>Preparando tu flota B2B segura.</p>
      </div>
    </div>
  );
}

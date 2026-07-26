import { createClient } from '@supabase/supabase-js';
import type { Database } from '@fuelflow/shared-types';

// Eliminamos cualquier '/' al final de la URL para evitar redirecciones 301 que destruyen los headers
const rawUrl = import.meta.env.VITE_SUPABASE_URL || import.meta.env.NEXT_PUBLIC_SUPABASE_URL || '';
const supabaseUrl = rawUrl.replace(/\/$/, '');
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || import.meta.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';

// Cortacircuitos Criptográfico: Si Vercel no inyecta las llaves, detenemos la app
// para evitar el bucle infinito de peticiones 400 y 401.
if (!supabaseUrl || !supabaseAnonKey || supabaseAnonKey.trim() === '' || supabaseAnonKey === 'undefined') {
  console.error("🛑 PARADA DE EMERGENCIA: Faltan las variables VITE_SUPABASE_URL o VITE_SUPABASE_ANON_KEY en Vercel.");
}

  // Interceptor JWT original causaba bucles infinitos en errores 42501 (RLS) porque
  // PostgREST devuelve 401 para fallos de permisos, provocando una avalancha de refreshSession.
  // Delegamos el refresco de sesión completamente al motor nativo de supabase-js.
  const customFetch = async (url: RequestInfo | URL, options?: RequestInit) => {
    if (supabaseAnonKey.includes('falsa') || supabaseAnonKey === 'MISSING_KEY') {
      console.error("🛑 BLOQUEO DE RED: Petición abortada porque Vercel no inyectó VITE_SUPABASE_ANON_KEY.");
      return new Response(JSON.stringify({ error: "Missing API Key in Vercel" }), {
        status: 401,
        statusText: "Unauthorized",
        headers: { 'Content-Type': 'application/json' }
      });
    }
  
    return fetch(url, options);
  };

export const supabase = createClient<Database>(
  supabaseUrl || 'https://falsa-url-para-evitar-crash.supabase.co', 
  supabaseAnonKey || 'llave-falsa-para-evitar-crash', 
  {
    global: {
      fetch: customFetch,
      headers: {
        apikey: supabaseAnonKey || 'llave-falsa-para-evitar-crash',
        Authorization: `Bearer ${supabaseAnonKey || 'llave-falsa-para-evitar-crash'}`
      }
    },
});

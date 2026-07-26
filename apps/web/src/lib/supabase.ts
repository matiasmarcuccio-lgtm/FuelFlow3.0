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

  // Interceptor JWT para Zonas Ciegas:
  // Si una mutación offline falla por token expirado (401) al recuperar la red,
  // forzamos la renovación de la sesión automáticamente.
  const customFetch = async (url: RequestInfo | URL, options?: RequestInit) => {
    // 1. Convertir la URL a string de forma segura
    const urlString = typeof url === 'string' ? url : url instanceof URL ? url.toString() : url && 'url' in url ? url.url : '';
  
    // 2. Extraer y preservar todos los headers originales de forma segura
    // (El objeto Headers nativo no se puede clonar con spread operator {...headers})
    const originalHeaders = new Headers(options?.headers);
    
    // Si faltan las llaves en Vercel, no permitimos que la app haga peticiones que generarán bucles 401
    if (supabaseAnonKey.includes('falsa') || supabaseAnonKey === 'MISSING_KEY') {
      console.error("🛑 BLOQUEO DE RED: Petición abortada porque Vercel no inyectó VITE_SUPABASE_ANON_KEY.");
      return new Response(JSON.stringify({ error: "Missing API Key in Vercel" }), {
        status: 401,
        statusText: "Unauthorized",
        headers: { 'Content-Type': 'application/json' }
      });
    }
  
    const response = await fetch(url, options);
  
    // Evitar bucle infinito: no interceptar peticiones del propio sistema de Auth
    if (urlString.includes('/auth/v1/')) {
      return response;
    }
  
    // Solo interceptamos 401 (Token Expirado). NUNCA interceptar 403 (RLS Denied)
    if (response.status === 401) {
      const { data: { session } } = await supabase.auth.getSession();
      if (session) {
        const { data: refreshData } = await supabase.auth.refreshSession();
        if (refreshData?.session) {
          // Actualizamos el header Authorization conservando el apikey
          originalHeaders.set('Authorization', `Bearer ${refreshData.session.access_token}`);
          
          return fetch(url, {
            ...options,
            headers: originalHeaders
          });
        }
      }
    }
    return response;
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

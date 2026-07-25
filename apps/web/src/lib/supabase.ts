import { createClient } from '@supabase/supabase-js';
import type { Database } from '@fuelflow/shared-types';

// Eliminamos cualquier '/' al final de la URL para evitar redirecciones 301 que destruyen los headers
const rawUrl = import.meta.env.VITE_SUPABASE_URL || import.meta.env.NEXT_PUBLIC_SUPABASE_URL || '';
const supabaseUrl = rawUrl.replace(/\/$/, '');
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || import.meta.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';

// Diagnostic check to alert the user if the key is corrupted or missing
if (!supabaseAnonKey || supabaseAnonKey.trim() === '' || supabaseAnonKey === 'undefined') {
  console.error("DIAGNOSTIC: Supabase Anon Key is missing or invalid. Value seen by Vite:", supabaseAnonKey);
  // We don't alert here to not block the UI constantly, but we can throw a clearer error
}

// Interceptor JWT para Zonas Ciegas:
// Si una mutación offline falla por token expirado (401/403) al recuperar la red,
// forzamos la renovación de la sesión automáticamente.
const customFetch = async (url: RequestInfo | URL, options?: RequestInit) => {
  const response = await fetch(url, options);
  
  // Extraer el string de la URL sin importar el tipo
  let urlString = '';
  if (typeof url === 'string') {
    urlString = url;
  } else if (url instanceof URL) {
    urlString = url.toString();
  } else if (url && 'url' in url) {
    urlString = url.url;
  }

  // Evitar bucle infinito: no interceptar peticiones del propio sistema de Auth
  if (urlString.includes('/auth/v1/')) {
    return response;
  }

  if (response.status === 401 || response.status === 403) {
    const { data: { session } } = await supabase.auth.getSession();
    if (session) {
      const { data: refreshData } = await supabase.auth.refreshSession();
      if (refreshData?.session) {
        // Actualizamos el header con el nuevo token
        const newOptions = { ...options };
        newOptions.headers = {
          ...newOptions.headers,
          Authorization: `Bearer ${refreshData.session.access_token}`
        };
        return fetch(url, newOptions);
      }
    }
  }
  return response;
};

export const supabase = createClient<Database>(supabaseUrl, supabaseAnonKey, {
  global: {
    fetch: customFetch,
    headers: {
      apikey: supabaseAnonKey,
      Authorization: `Bearer ${supabaseAnonKey}`
    }
  },
});

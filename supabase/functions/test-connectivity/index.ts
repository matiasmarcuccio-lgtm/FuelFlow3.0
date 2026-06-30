import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  try {
    // 1. Verificación del Pool de Conexiones
    const { data, error } = await supabase.from('access_logs').select('count', { count: 'exact', head: true });
    
    if (error) throw error;

    return new Response(JSON.stringify({ 
      status: "OK", 
      message: "Conectividad establecida con el motor forense",
      log_count: data 
    }), { status: 200, headers: { "Content-Type": "application/json" } });
    
  } catch (err: any) {
    return new Response(JSON.stringify({ 
      status: "ERROR", 
      message: "Fallo en la conectividad", 
      error: err.message 
    }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});

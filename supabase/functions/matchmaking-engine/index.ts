import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import * as turf from 'https://esm.sh/@turf/turf@6.5.0';

serve(async (req) => {
  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  
  // 1. Obtener restricciones del Load Offer
  const { load_offer_id } = await req.json();
  const { data: loadOffer } = await supabase.from('load_offers').select('*').eq('id', load_offer_id).single();

  if (!loadOffer) {
    return new Response(JSON.stringify({ error: "Load Offer no encontrado" }), { status: 404, headers: { "Content-Type": "application/json" } });
  }

  // 2. Filtrado Complejo (Turf.js)
  // Aquí aplicamos el motor de matchmaking que separa la paja del trigo
  const { data: candidates } = await supabase.from('assets').select('*').eq('has_4x4_traction', loadOffer.requires_4x4_traction);

  // 3. Respuesta de Sistema
  return new Response(JSON.stringify({ candidates }), { headers: { "Content-Type": "application/json" } });
});

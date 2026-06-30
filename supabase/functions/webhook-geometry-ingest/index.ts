import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3';
import { GeometryPayloadSchema } from './schema.ts';

serve(async (req) => {
  // 1. Bloqueo de Método HTTP
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  // 2. Bloqueo Zero-Trust (Autenticación x-api-key)
  const clientApiKey = req.headers.get('x-api-key');
  const serverApiKey = Deno.env.get('WEBHOOK_API_KEY');
  
  if (!clientApiKey || clientApiKey !== serverApiKey) {
    return new Response(JSON.stringify({ error: 'Acceso Denegado: Protocolo M2M no autorizado' }), { 
      status: 401, 
      headers: { 'Content-Type': 'application/json' } 
    });
  }

  try {
    // 3. Parseo y Extracción de Geometría (Fail-Fast Matemático)
    const body = await req.json();
    const validPayload = GeometryPayloadSchema.parse(body);

    // 4. Elevación de Privilegios para Inyección Segura
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // 5. Transmisión a PostGIS (Base de Datos Central)
    const { error } = await supabase.rpc('update_project_geometry', {
      p_project_id: validPayload.project_id,
      p_zone_type: validPayload.zone_type,
      p_geojson: validPayload.geometry
    });

    if (error) throw error;

    return new Response(JSON.stringify({ status: 'Topografía JIT actualizada exitosamente' }), {
      headers: { 'Content-Type': 'application/json' },
      status: 200,
    });

  } catch (error: any) {
    // Intercepción de violaciones Zod (Ej: Coordenadas proyectadas inválidas)
    return new Response(JSON.stringify({ error: error.message || 'Payload topográfico corrupto' }), {
      headers: { 'Content-Type': 'application/json' },
      status: 400,
    });
  }
});

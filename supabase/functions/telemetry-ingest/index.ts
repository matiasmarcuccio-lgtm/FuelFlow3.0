import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

serve(async (req) => {
  // 1. Rechazar cualquier método que no sea POST
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405 });
  }

  // 2. Barrera Criptográfica de Hardware (IoT Secret)
  // Las antenas/ECUs deben enviar este token estricto en la cabecera
  const authHeader = req.headers.get("Authorization");
  const iotSecret = Deno.env.get("IOT_INGEST_SECRET");
  
  if (!authHeader || authHeader !== `Bearer ${iotSecret}`) {
    return new Response(JSON.stringify({ error: "WHS_UNAUTHORIZED: Hardware no reconocido" }), { 
      status: 401,
      headers: { "Content-Type": "application/json" }
    });
  }

  try {
    const payload = await req.json();
    
    // 3. Desestructuración y Validación Perimetral
    // Si la trama CAN bus llega corrupta, la aplastamos aquí, no en PostgreSQL.
    const { asset_id, engine_hours, fuel_level, coolant_temp, is_running } = payload;
    
    if (
      typeof asset_id !== "string" ||
      typeof engine_hours !== "number" ||
      engine_hours < 0
    ) {
      return new Response(JSON.stringify({ error: "DATA_CORRUPTION: Payload telemático inválido" }), { 
        status: 400,
        headers: { "Content-Type": "application/json" }
      });
    }

    // 4. Conexión de Alto Privilegio a la Capa 0
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // 5. Inserción Directa
    // Al insertar, el gatillo `process_telemetry_safety_override` evaluará
    // el coolant_temp y secuestrará la máquina si es >= 105°C.
    const { error } = await supabaseAdmin
      .from("telemetry_logs")
      .insert({
        asset_id,
        engine_hours,
        fuel_level_percent: typeof fuel_level === "number" ? fuel_level : null,
        coolant_temp_celsius: typeof coolant_temp === "number" ? coolant_temp : null,
        is_engine_running: Boolean(is_running),
      });

    if (error) {
      throw error;
    }

    return new Response(JSON.stringify({ success: true, timestamp: new Date().toISOString() }), { 
      status: 201,
      headers: { "Content-Type": "application/json" }
    });
    
  } catch (err: any) {
    return new Response(JSON.stringify({ error: `INGEST_FAILURE: ${err.message}` }), { 
      status: 500,
      headers: { "Content-Type": "application/json" }
    });
  }
});

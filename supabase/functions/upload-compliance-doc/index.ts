import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Manejo de preflight CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization')!;
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Falta encabezado de autorización' }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const supabaseUser = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authHeader } } });
    const supabaseService = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    // Validar sesión del usuario (auth.uid())
    const { data: { user }, error: authError } = await supabaseUser.auth.getUser();
    
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Sesión no válida o expirada" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const { doc_type, presigned_url, expiry_date } = await req.json();

    // Verifica que el doc_type sea permitido
    if (!['INSURANCE', 'VEHICLE_REG', 'DRIVER_LICENSE'].includes(doc_type)) {
      return new Response(JSON.stringify({ error: "Tipo de documento no admitido por el protocolo WHS." }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Crea la entrada en compliance_documents con is_verified = false
    const { data: complianceDoc, error: docError } = await supabaseService.from('compliance_documents').insert({
      profile_id: user.id,
      doc_type,
      file_url: presigned_url,
      expiry_date,
      is_verified: false
    }).select().single();

    if (docError) throw docError;

    // Registra el evento en access_logs (Forensics)
    await supabaseService.from('access_logs').insert({
      user_id: user.id,
      table_name: 'compliance_documents',
      row_id: complianceDoc.id,
      action: 'INSERT'
    });

    return new Response(JSON.stringify({ success: true, data: complianceDoc }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});

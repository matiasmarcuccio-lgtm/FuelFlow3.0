import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import Stripe from "https://esm.sh/stripe@14.14.0?target=deno";

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    );

    const authHeader = req.headers.get('Authorization') || req.headers.get('authorization');
    if (!authHeader) {
      const allHeaders = Array.from(req.headers.entries()).map(([k, v]) => `${k}: ${v}`).join(', ');
      throw new Error(`AUTENTICACIÓN REQUERIDA: No se proporcionó token. Headers recibidos: ${allHeaders}`);
    }
    
    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(token);
    
    if (authError || !user) {
      throw new Error(`AUTENTICACIÓN REQUERIDA: Token inválido. Detalles: ${authError?.message || 'No user'}`);
    }

    const { data: profile } = await supabaseClient
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .single();

    if (!profile || profile.role !== 'pending_onboarding') {
      throw new Error('JURISDICCIÓN INVÁLIDA: Su cuenta ya completó el onboarding comercial.');
    }

    const { fleetName } = await req.json();
    if (!fleetName || fleetName.trim().length < 3) {
      throw new Error('DATOS REQUERIDOS: Debe especificar un nombre legal para la flota minera.');
    }

    // 1. Crear o recuperar el Customer de Stripe con anclaje de metadatos
    const customers = await stripe.customers.list({ email: user.email, limit: 1 });
    let customerId = customers.data.length > 0 ? customers.data[0].id : null;

    if (!customerId) {
      const newCustomer = await stripe.customers.create({
        email: user.email,
        name: fleetName,
        metadata: {
          supabase_uid: user.id,
          fleet_name: fleetName
        }
      });
      customerId = newCustomer.id;
    }

    // 2. Crear SetupIntent para autorizar tarjeta sin realizar cobros iniciales ($0 AUD)
    const setupIntent = await stripe.setupIntents.create({
      customer: customerId,
      usage: 'off_session',
      metadata: {
        supabase_uid: user.id,
        fleet_name: fleetName
      }
    });

    return new Response(JSON.stringify({ client_secret: setupIntent.client_secret }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    });

  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    });
  }
});

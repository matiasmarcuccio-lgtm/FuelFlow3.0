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
  // Manejo de preflight CORS para peticiones desde el navegador (React)
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: { headers: { Authorization: req.headers.get('Authorization')! } },
      }
    );

    // 1. Validar la identidad del usuario que invoca la función (Zero-Trust)
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      throw new Error('NO_AUTORIZADO: Debe iniciar sesión para acceder al portal bancario.');
    }

    // 2. Extraer el perfil, el rol comercial y la flota asociada
    const { data: profile, error: profileError } = await supabaseClient
      .from('profiles')
      .select('role, fleet_id, email, fleets(id, name, stripe_customer_id)')
      .eq('id', user.id)
      .single();

    if (profileError || !profile) {
      throw new Error('PERFIL_NO_ENCONTRADO: No se pudo leer la jurisdicción del usuario.');
    }

    if (profile.role !== 'account_owner') {
      throw new Error('JURISDICCIÓN DENEGADA: Solo el Dueño de Cuenta puede abrir el portal de Stripe.');
    }

    const fleet = (profile as any).fleets;
    let customerId = fleet.stripe_customer_id;

    // 3. RUTINA DE RESCATE: Si la flota heredada no tiene cliente en Stripe, lo creamos al vuelo
    if (!customerId) {
      const newCustomer = await stripe.customers.create({
        email: profile.email || user.email,
        name: fleet.name || `Flota Minera ${fleet.id.slice(0, 8)}`,
        metadata: {
          supabase_fleet_id: fleet.id,
          account_owner_uid: user.id
        }
      });

      customerId = newCustomer.id;

      // Anclar retroactivamente el ID bancario en PostgreSQL utilizando el Service Role Key
      const adminClient = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      );

      const { error: updateError } = await adminClient
        .from('fleets')
        .update({ stripe_customer_id: customerId })
        .eq('id', fleet.id);

      if (updateError) {
        console.error('Fallo al guardar stripe_customer_id en BD:', updateError);
      }
    }

    // 4. Leer la URL de retorno desde el cuerpo de la petición de React
    const { returnUrl } = await req.json();

    // 5. Generar la sesión efímera del Stripe Customer Portal (PCI-DSS)
    const session = await stripe.billingPortal.sessions.create({
      customer: customerId,
      return_url: returnUrl || 'https://fuelflow.com.au/dashboard',
    });

    return new Response(JSON.stringify({ url: session.url }), {
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

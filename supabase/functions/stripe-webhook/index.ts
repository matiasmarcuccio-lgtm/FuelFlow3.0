import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import Stripe from "https://esm.sh/stripe@14.14.0?target=deno";

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const cryptoProvider = Stripe.createSubtleCryptoProvider();
const endpointSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET') ?? '';

serve(async (req: Request) => {
  const signature = req.headers.get('Stripe-Signature');
  if (!signature) {
    return new Response('SIN_FIRMA: Petición carece de cabecera criptográfica de Stripe.', { status: 400 });
  }

  try {
    const body = await req.text();
    // 1. Validación estricta PCI-DSS: Verificamos que el payload realmente provenga de Stripe
    const event = await stripe.webhooks.constructEventAsync(body, signature, endpointSecret, undefined, cryptoProvider);

    const adminClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // 2. MÁQUINA DE ESTADOS FINANCIEROS Y LEGALES
    // NOTA CIRUGÍA: Usamos status: 'active', 'past_due' y 'canceled' en minúscula
    switch (event.type) {
      // A. CAPTURA DE TARJETA EXITOSA -> CREAR FLOTA Y ASCENDER A DUEÑO
      case 'setup_intent.succeeded': {
        const setupIntent = event.data.object as Stripe.SetupIntent;
        const customerId = setupIntent.customer as string;
        const paymentMethodId = setupIntent.payment_method as string;
        
        const supabaseUid = setupIntent.metadata?.supabase_uid;
        const fleetName = setupIntent.metadata?.fleet_name;

        if (!supabaseUid || !fleetName) {
          throw new Error(`METADATOS FALTANTES: SetupIntent ${setupIntent.id} carece de anclaje Supabase.`);
        }

        // 1. PASO CRÍTICO: Fijar la tarjeta como método de pago por defecto en el cliente
        await stripe.customers.update(customerId, {
          invoice_settings: { default_payment_method: paymentMethodId },
        });

        // 2. Suscribir al cliente al plan metrado de pago por uso (Flota Operativa) - Opcional para Desarrollo
        const priceId = Deno.env.get('STRIPE_METERED_PRICE_ID');
        let subscriptionId = 'sub_dummy_for_testing';
        
        if (priceId) {
          const subscription = await stripe.subscriptions.create({
            customer: customerId,
            items: [{ price: priceId }],
            metadata: { supabase_uid: supabaseUid }
          });
          subscriptionId = subscription.id;
        }

        // 3. Ejecutar promoción relacional y creación de mina en 1 sola transacción ACID
        const { error: rpcError } = await adminClient.rpc('fn_promote_to_account_owner', {
          p_user_uid: supabaseUid,
          p_fleet_name: fleetName,
          p_stripe_customer_id: customerId,
          p_stripe_subscription_id: subscriptionId
        });

        if (rpcError) {
          console.error(`FALLO FATAL EN PROMOCIÓN SQL PARA UID ${supabaseUid}:`, rpcError.message);
          throw rpcError;
        }

        break;
      }

      // B. EL PAGO FUE EXITOSO (Suscripción al día)
      case 'invoice.payment_succeeded': {
        const invoice = event.data.object as Stripe.Invoice;
        const customerId = invoice.customer as string;

        // Limpiar el período de gracia en la flota y devolverla al estado operativo
        await adminClient
          .from('fleets')
          .update({ 
            status: 'active', 
            grace_period_until: null 
          })
          .eq('stripe_customer_id', customerId);

        // Si pagaron por bóvedas pasivas, restaurar su acceso fiscal para la ATO
        await adminClient
          .from('project_sites')
          .update({ vault_status: 'OPERATIONAL', purge_scheduled_for: null })
          .eq('vault_status', 'VAULT_DELINQUENT')
          .in('fleet_id', (
            await adminClient.from('fleets').select('id').eq('stripe_customer_id', customerId)
          ).data?.map(f => f.id) || []);

        break;
      }

      // B. EL PAGO FRACASÓ (Tarjeta rebotada, sin fondos o cuenta congelada)
      case 'invoice.payment_failed': {
        const invoice = event.data.object as Stripe.Invoice;
        const customerId = invoice.customer as string;

        // 1. Inyectar el amortiguador de gracia de 72 horas para operaciones en terreno
        const graceDate = new Date();
        graceDate.setHours(graceDate.getHours() + 72);

        await adminClient
          .from('fleets')
          .update({ 
            status: 'past_due', 
            grace_period_until: graceDate.toISOString() 
          })
          .eq('stripe_customer_id', customerId);

        // 2. Sellar instantáneamente la Bóveda Pasiva (Sin periodo de gracia para descargas de $29 AUD)
        await adminClient
          .from('project_sites')
          .update({ vault_status: 'VAULT_DELINQUENT' })
          .eq('status', 'ARCHIVED')
          .in('fleet_id', (
            await adminClient.from('fleets').select('id').eq('stripe_customer_id', customerId)
          ).data?.map(f => f.id) || []);

        break;
      }

      // C. LA SUSCRIPCIÓN FUE CANCELADA ABSOLUTAMENTE (Fin de contrato)
      case 'customer.subscription.deleted': {
        const subscription = event.data.object as Stripe.Subscription;
        const customerId = subscription.customer as string;

        await adminClient
          .from('fleets')
          .update({ status: 'canceled', grace_period_until: null })
          .eq('stripe_customer_id', customerId);
          
        break;
      }
    }

    return new Response(JSON.stringify({ received: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });

  } catch (err: any) {
    console.error('Error de validación en Webhook:', err.message);
    return new Response(`Error de Aduana Webhook: ${err.message}`, { status: 400 });
  }
});

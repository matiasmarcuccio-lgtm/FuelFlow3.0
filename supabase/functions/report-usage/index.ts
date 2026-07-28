import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import Stripe from "https://esm.sh/stripe@14.14.0?target=deno";

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

serve(async (req: Request) => {
  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // 1. Obtener todos los registros del fleet_billing_ledger que aún no han sido reportados a Stripe
    // (es decir, stripe_usage_record_id es null)
    const { data: ledgers, error: ledgerError } = await supabaseClient
      .from('fleet_billing_ledger')
      .select(`
        id,
        fleet_id,
        active_asset_count,
        recorded_date,
        fleets (
          stripe_customer_id,
          billing_contracts ( stripe_subscription_item_id, status )
        )
      `)
      .is('stripe_usage_record_id', null);

    if (ledgerError) throw ledgerError;

    const results = [];

    // 2. Iterar sobre las fotografías diarias y transmitirlas a Stripe
    for (const ledger of ledgers || []) {
      const fleet = ledger.fleets as any;
      
      // Buscar el contrato de facturación activo
      const activeContract = fleet?.billing_contracts?.find((c: any) => c.status === 'ACTIVE');
      const subItemId = activeContract?.stripe_subscription_item_id;

      if (!subItemId) {
        console.warn(`Flota ${ledger.fleet_id} no tiene un subscription_item_id activo. Saltando...`);
        continue;
      }

      try {
        // 3. Emitir el Stripe Usage Record
        const usageRecord = await stripe.subscriptionItems.createUsageRecord(
          subItemId,
          {
            quantity: ledger.active_asset_count,
            timestamp: Math.floor(new Date(ledger.recorded_date).getTime() / 1000),
            action: 'set', // Reemplaza cualquier registro previo de este timestamp exacto
          },
          {
            // Idempotency key estricta basada en el fleet y la fecha para no duplicar cobros si hay reintentos
            idempotencyKey: `usage_${ledger.fleet_id}_${ledger.recorded_date}`
          }
        );

        // 4. Marcar el ledger como reportado en PostgreSQL
        await supabaseClient
          .from('fleet_billing_ledger')
          .update({ stripe_usage_record_id: usageRecord.id })
          .eq('id', ledger.id);

        results.push({
          fleet_id: ledger.fleet_id,
          date: ledger.recorded_date,
          usage_record_id: usageRecord.id
        });
      } catch (stripeErr: any) {
        console.error(`Stripe Usage Error para flota ${ledger.fleet_id}:`, stripeErr);
      }
    }

    return new Response(JSON.stringify({ success: true, processed: results.length, details: results }), {
      headers: { 'Content-Type': 'application/json' },
      status: 200,
    });

  } catch (error: any) {
    console.error('Fatal Error en report-usage:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { 'Content-Type': 'application/json' },
      status: 500,
    });
  }
});

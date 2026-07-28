import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import Stripe from "https://esm.sh/stripe@14.14.0?target=deno";

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

// El ID de PRECIO (price_...) del producto metrado que acabas de crear en Stripe
const METERED_PRICE_ID = Deno.env.get('STRIPE_METERED_PRICE_ID') ?? '';

serve(async (req: Request) => {
  try {
    // Esta función se ejecutará como una tarea de sistema aislada (Service Role)
    const adminClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // 1. Extraer los consumos sellados en la sombra o en vivo que aún no se reportan al banco
    // NOTA CIRUGÍA: Usamos 'status' en minúscula para alinearnos con el enum real de PostgreSQL
    const { data: unreportedLedgers, error: ledgerError } = await adminClient
      .from('fleet_billing_ledger')
      .select('id, fleet_id, billing_date, active_asset_count, fleets(stripe_subscription_id, status)')
      .eq('stripe_reported', false)
      .gt('active_asset_count', 0); // No reportamos días con 0 camiones para ahorrar llamadas API

    if (ledgerError) throw ledgerError;
    if (!unreportedLedgers || unreportedLedgers.length === 0) {
      return new Response(JSON.stringify({ message: "No hay consumos pendientes de emisión." }), { status: 200 });
    }

    const reportResults = [];

    // 2. Iterar sobre cada fotografía de consumo diaria por flota
    for (const record of unreportedLedgers) {
      const fleet = (record as any).fleets;
      const subId = fleet?.stripe_subscription_id;

      // Si la flota no tiene suscripción activa en Stripe (o sigue en prueba pura local), la saltamos
      if (!subId || fleet.status !== 'active') {
        reportResults.push({ ledger_id: record.id, status: 'SKIPPED_NO_ACTIVE_SUBSCRIPTION' });
        continue;
      }

      try {
        // A. Consultar a Stripe para encontrar cuál ítem de la suscripción corresponde al precio metrado
        const subscription = await stripe.subscriptions.retrieve(subId);
        const meteredItem = subscription.items.data.find(
          (item) => item.price.id === METERED_PRICE_ID
        );

        if (!meteredItem) {
          throw new Error(`La suscripción ${subId} carece del ítem de cobro metrado (${METERED_PRICE_ID}).`);
        }

        // B. Convertir la fecha de facturación a Unix Timestamp (mediodía AEST de esa fecha para evitar bordes UTC)
        const unixTimestamp = Math.floor(new Date(`${record.billing_date}T12:00:00+10:00`).getTime() / 1000);

        // C. Enviar la telemetría bancaria con acción INCREMENT para que Stripe lo sume al mes
        const usageRecord = await stripe.subscriptionItems.createUsageRecord(
          meteredItem.id,
          {
            quantity: record.active_asset_count,
            timestamp: unixTimestamp,
            action: 'increment',
          }
        );

        // D. Marcar en la base de datos que este día ya fue facturado al banco con éxito
        await adminClient
          .from('fleet_billing_ledger')
          .update({ stripe_reported: true })
          .eq('id', record.id);

        reportResults.push({ 
          ledger_id: record.id, 
          status: 'SUCCESS', 
          stripe_usage_id: usageRecord.id,
          quantity: record.active_asset_count 
        });

      } catch (err: any) {
        console.error(`Fallo emitiendo consumo para ledger ${record.id}:`, err.message);
        reportResults.push({ ledger_id: record.id, status: 'ERROR', error: err.message });
      }
    }

    return new Response(JSON.stringify({ processed: reportResults.length, results: reportResults }), {
      headers: { 'Content-Type': 'application/json' },
      status: 200,
    });

  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { 'Content-Type': 'application/json' },
      status: 500,
    });
  }
});

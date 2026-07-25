import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { createHmac } from "node:crypto";

serve(async (req) => {
  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  );

  const B2B_SECRET = Deno.env.get("B2B_WEBHOOK_SECRET");
  const N8N_URL = Deno.env.get("N8N_WEBHOOK_URL");

  // 1. Extraer mensajes atascados o pendientes
  const { data: messages, error: fetchError } = await supabaseAdmin
    .from("erp_outbox")
    .select("*")
    .in("status", ["pending", "failed"])
    .lte("next_retry_at", new Date().toISOString())
    .limit(10); // Batch de 10 para no saturar n8n

  if (fetchError || !messages || messages.length === 0) {
    return new Response(JSON.stringify({ status: "idle", count: 0 }), { status: 200 });
  }

  for (const msg of messages) {
    try {
      // Bloqueo Optimista: Marcar como procesando para evitar colisiones del cron
      await supabaseAdmin.from("erp_outbox").update({ status: "processing" }).eq("id", msg.id);

      // Criptografía HMAC-SHA256
      const payloadString = JSON.stringify(msg.payload);
      const hmac = createHmac("sha256", B2B_SECRET!).update(payloadString).digest("hex");

      // Asalto HTTP al orquestador externo
      const n8nResponse = await fetch(N8N_URL!, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-FuelFlow-Signature": hmac,
        },
        body: payloadString,
      });

      if (!n8nResponse.ok) throw new Error(`ERP Reject: HTTP ${n8nResponse.status}`);

      // Éxito: Marcar como completado
      await supabaseAdmin.from("erp_outbox").update({ 
        status: "completed", 
        updated_at: new Date().toISOString() 
      }).eq("id", msg.id);

    } catch (err: any) {
      // Fractura de red: Matemática de Retroceso Exponencial (Exponential Backoff)
      const newRetryCount = msg.retry_count + 1;
      
      if (newRetryCount > 5) {
        // Guillotina Final (Dead Letter) - Requiere intervención humana en el Command Center
        await supabaseAdmin.from("erp_outbox").update({
          status: "dead_letter",
          last_error: err.message,
          updated_at: new Date().toISOString()
        }).eq("id", msg.id);
      } else {
        // Calcular próxima resurrección: 2^intentos * 1 minuto (2m, 4m, 8m, 16m, 32m)
        const delayMs = Math.pow(2, newRetryCount) * 60000;
        const nextRetry = new Date(Date.now() + delayMs).toISOString();

        await supabaseAdmin.from("erp_outbox").update({
          status: "failed",
          retry_count: newRetryCount,
          next_retry_at: nextRetry,
          last_error: err.message,
          updated_at: new Date().toISOString()
        }).eq("id", msg.id);
      }
    }
  }

  return new Response(JSON.stringify({ status: "processed", count: messages.length }), { status: 200 });
});

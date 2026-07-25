import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

// 1. Firma Criptográfica HMAC para autenticidad B2B
async function generateHmacSignature(secret: string, payload: string): Promise<string> {
  const encoder = new TextEncoder();
  const keyData = encoder.encode(secret);
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    cryptoKey,
    encoder.encode(payload)
  );
  return Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

serve(async (req) => {
  try {
    // 2. Extraer el evento referencial enviado por PostgreSQL (pg_net)
    const body = await req.json();
    const { event_type, record_id, asset_id } = body;

    if (!record_id || !asset_id) {
      return new Response(JSON.stringify({ error: "Invalid payload parameters" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 3. Inicializar cliente con rol Service Role (para leer la data sin restricciones de RLS)
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // 4. Hidratar la información (Dinámico según evento)
    let queryTable = "maintenance_logs";
    let selectFields = "*, assets(internal_code, fleet_id)";

    if (event_type === "billing.certificate.generated") {
      queryTable = "execution_certificates";
      selectFields = "*, asset_assignments(asset_id, driver_id, assets(internal_code, fleet_id)), billing_contracts(model, currency)";
    }

    if (event_type === "audit.infrastructure.breach") {
      queryTable = "system_audit_logs";
      selectFields = "*"; // Obtenemos el payload_before y payload_after
    }

    const { data: logData, error: logError } = await supabaseAdmin
      .from(queryTable)
      .select(selectFields)
      .eq("id", record_id)
      .single();

    if (logError || !logData) {
      throw new Error(`Record not found in ${queryTable}: ${logError?.message}`);
    }

    // Workaround for typing: Supabase returns foreign tables as single object or array
    let assetInfo: any;
    let fleetId: string;
    
    if (event_type === "billing.certificate.generated") {
      const assignmentInfo = Array.isArray(logData.asset_assignments) ? logData.asset_assignments[0] : logData.asset_assignments;
      assetInfo = Array.isArray(assignmentInfo.assets) ? assignmentInfo.assets[0] : assignmentInfo.assets;
      fleetId = assetInfo.fleet_id;
    } else if (event_type === "audit.infrastructure.breach") {
      // Extraemos el asset_id del contrato de facturación mutado
      const targetAssetId = logData.payload_after?.asset_id || logData.payload_before?.asset_id;
      const { data: assetData } = await supabaseAdmin.from("assets").select("fleet_id").eq("id", targetAssetId).single();
      fleetId = assetData?.fleet_id;
    } else {
      assetInfo = Array.isArray(logData.assets) ? logData.assets[0] : logData.assets;
      fleetId = assetInfo.fleet_id;
    }

    if (!fleetId) throw new Error("Could not resolve fleet jurisdiction for webhook dispatch");

    // 5. Buscar los suscriptores activos para este evento y flota
    const { data: endpoints, error: endpointError } = await supabaseAdmin
      .from("webhook_endpoints")
      .select("target_url, auth_secret")
      .eq("fleet_id", fleetId)
      .eq("event_type", event_type)
      .eq("is_active", true);

    if (endpointError || !endpoints || endpoints.length === 0) {
      return new Response(JSON.stringify({ message: "No active subscribers found" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 6. Construir el Contrato JSON Estándar para Exportación
    let payloadData: any = {};

    if (event_type === "audit.infrastructure.breach") {
      payloadData = {
        audit_id: logData.id,
        actor_uid: logData.actor_uid,
        action: logData.action_type,
        table: logData.target_table,
        diff: {
          before: logData.payload_before,
          after: logData.payload_after
        }
      };
    } else if (event_type === "billing.certificate.generated") {
      const contractInfo = Array.isArray(logData.billing_contracts) ? logData.billing_contracts[0] : logData.billing_contracts;
      payloadData = {
        certificate_id: logData.id,
        assignment_id: logData.assignment_id,
        asset_code: assetInfo.internal_code,
        total_hours: logData.total_hours,
        regular_hours: logData.regular_hours,
        overtime_hours: logData.overtime_hours,
        total_billable: logData.total_billable,
        currency: contractInfo?.currency || 'AUD'
      };
    } else {
      payloadData = {
        log_id: logData.id,
        asset_code: assetInfo.internal_code,
        issue: logData.issue_description,
        locked_by: logData.locked_by_uid,
        locked_at: logData.locked_at,
      };
    }

    const outboundPayload = JSON.stringify({
      event: event_type,
      timestamp: new Date().toISOString(),
      data: payloadData,
    });

    // 7. Emitir las peticiones salientes firmadas
    const dispatchPromises = endpoints.map(async (endpoint) => {
      const headers: Record<string, string> = {
        "Content-Type": "application/json",
        "X-FuelFlow-Event": event_type,
      };

      // Criptografía Zero-Trust: Usamos el secreto del endpoint o el global.
      const secret = endpoint.auth_secret || Deno.env.get("B2B_WEBHOOK_SECRET");
      if (!secret) {
        throw new Error("Falta el secreto criptográfico B2B para firmar el payload");
      }

      const signature = await generateHmacSignature(secret, outboundPayload);
      headers["X-FuelFlow-Signature"] = signature;

      return fetch(endpoint.target_url, {
        method: "POST",
        headers,
        body: outboundPayload,
      });
    });

    await Promise.allSettled(dispatchPromises);

    return new Response(JSON.stringify({ success: true, dispatched_to: endpoints.length }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { PDFDocument, rgb, StandardFonts } from "https://cdn.skypack.dev/pdf-lib";
import { encodeHex } from "https://deno.land/std@0.203.0/encoding/hex.ts";
import { crypto } from "https://deno.land/std@0.203.0/crypto/crypto.ts";

serve(async (req) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

  const authHeader = req.headers.get("Authorization");
  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  );

  try {
    const { certificate_id } = await req.json();
    if (!certificate_id) throw new Error("Missing certificate_id");

    // 1. Extraer los datos blindados de la Capa 0
    const { data: cert, error: fetchError } = await supabaseAdmin
      .from("execution_certificates")
      .select("*, billing_contracts(model, hourly_rate_asset)")
      .eq("id", certificate_id)
      .single();

    if (fetchError || !cert) throw new Error("Certificado no encontrado o corrupto.");
    if (cert.forensic_pdf_hash) throw new Error("Este certificado ya ha sido sellado criptográficamente.");

    // 2. Forjar el Documento PDF (Immutable Layout)
    const pdfDoc = await PDFDocument.create();
    const page = pdfDoc.addPage([600, 400]);
    const font = await pdfDoc.embedFont(StandardFonts.HelveticaBold);
    
    page.drawText("FUELFLOW 3.0 - CERTIFICADO DE EJECUCIÓN FINANCIERA", { x: 50, y: 350, size: 14, font, color: rgb(0, 0, 0) });
    page.drawText(`CERT ID: ${cert.id}`, { x: 50, y: 320, size: 10 });
    page.drawText(`TELEMETRY SOURCE: ${cert.telemetry_source} (CONFIDENCE: ${cert.telemetry_confidence})`, { x: 50, y: 300, size: 10 });
    page.drawText(`TOTAL HOURS: ${cert.total_hours} | BILLABLE AUD: $${cert.total_billable}`, { x: 50, y: 280, size: 12, font });
    page.drawText(`GENERATED AT: ${new Date().toISOString()}`, { x: 50, y: 240, size: 8 });

    const pdfBytes = await pdfDoc.save();

    // 3. Generación del Hash Forense (La Verdad Absoluta)
    const hashBuffer = await crypto.subtle.digest("SHA-256", pdfBytes);
    const forensicHash = encodeHex(new Uint8Array(hashBuffer));
    const fileName = `audit_${cert.id}_${forensicHash.substring(0, 8)}.pdf`;

    // 4. Almacenamiento en Bucket WORM
    const { error: uploadError } = await supabaseAdmin.storage
      .from("audit_certificates")
      .upload(fileName, pdfBytes, {
        contentType: "application/pdf",
        upsert: false // El archivo colisionará si alguien intenta sobrescribirlo
      });

    if (uploadError) throw uploadError;

    // 5. Inyección del Hash en el Libro Mayor (Cierra el Candado)
    const pdfUrl = `${Deno.env.get("SUPABASE_URL")}/storage/v1/object/public/audit_certificates/${fileName}`;
    const { error: sealError } = await supabaseAdmin
      .from("execution_certificates")
      .update({
        forensic_pdf_hash: forensicHash,
        forensic_pdf_url: pdfUrl
      })
      .eq("id", certificate_id);

    if (sealError) throw sealError;

    return new Response(JSON.stringify({ 
      success: true, 
      forensic_hash: forensicHash, 
      url: pdfUrl 
    }), { headers: { "Content-Type": "application/json" } });

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), { status: 400 });
  }
});

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { decode } from "https://deno.land/std@0.203.0/encoding/base64.ts";

serve(async (req) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  );

  try {
    const { shift_id, base64_image, category } = await req.json();
    const token = req.headers.get("Authorization")?.replace("Bearer ", "");
    
    // 1. Verificar identidad del operador (Validación estricta)
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token);
    if (authError || !user) throw new Error("Firma biométrica no válida.");

    // 2. Almacenamiento Inmutable (WORM) de la prueba física
    const imageBuffer = decode(base64_image.replace(/^data:image\/\w+;base64,/, ""));
    const fileName = `${shift_id}_${Date.now()}.jpg`;
    
    const { error: uploadError } = await supabaseAdmin.storage
      .from("analog_receipts")
      .upload(fileName, imageBuffer, { contentType: "image/jpeg" });
    
    if (uploadError) throw uploadError;
    const rawImageUrl = `${Deno.env.get("SUPABASE_URL")}/storage/v1/object/public/analog_receipts/${fileName}`;

    // 3. Extracción Probabilística (Llamada al Motor OCR de Visión)
    // Conectamos a OpenAI GPT-4o Vision para extracción real determinista-limitada
    const openAiKey = Deno.env.get("OPENAI_API_KEY");
    let extracted_amount = 0;
    let extracted_vendor = "DESCONOCIDO";
    let ocr_confidence = 0;

    if (openAiKey) {
      const openAiPayload = {
        model: "gpt-4o",
        messages: [
          {
            role: "user",
            content: [
              {
                type: "text",
                text: "Extract the following from this receipt image: The vendor name, the total amount as a number, and your confidence level from 0 to 100. Return only a JSON object like {\"vendor\": \"string\", \"total_amount\": number, \"confidence\": number}."
              },
              {
                type: "image_url",
                image_url: {
                  url: base64_image
                }
              }
            ]
          }
        ],
        response_format: { type: "json_object" },
        max_tokens: 300
      };

      const openAiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${openAiKey}`
        },
        body: JSON.stringify(openAiPayload)
      });

      if (openAiResponse.ok) {
        const aiData = await openAiResponse.json();
        const contentStr = aiData.choices?.[0]?.message?.content;
        if (contentStr) {
          try {
            const parsed = JSON.parse(contentStr);
            extracted_vendor = parsed.vendor || "DESCONOCIDO";
            extracted_amount = parseFloat(parsed.total_amount) || 0;
            ocr_confidence = parseFloat(parsed.confidence) || 0;
          } catch (e) {
            console.error("Error parsing OpenAI response:", e);
          }
        }
      } else {
        console.error("OpenAI Error:", await openAiResponse.text());
        ocr_confidence = 0; // Fallback to 0 if API fails, user has to manual entry
      }
    }

    // 4. Encierro en la Celda de Cuarentena (Capa 0)
    const { error: quarantineError } = await supabaseAdmin
      .from("expense_quarantine")
      .insert({
        shift_id: shift_id,
        driver_uid: user.id,
        raw_image_url: rawImageUrl,
        expense_category: category,
        extracted_amount: extracted_amount,
        extracted_vendor: extracted_vendor,
        ocr_confidence: ocr_confidence
      });

    if (quarantineError) throw quarantineError;

    return new Response(JSON.stringify({ success: true, message: "Aislado en cuarentena." }), { status: 200 });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), { status: 400 });
  }
});

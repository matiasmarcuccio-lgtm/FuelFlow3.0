import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// --- Interfaces ---
interface VisionResult {
  isFraud: boolean;
  isTechnicalError?: boolean;
  confidence: number;
  detectedType: string;
  detectedExpiry: string | null;
  rawJson: any;
}

interface VisionEngine {
  readonly version: string;
  analyzeDocument(url: string, expectedExpiry: string): Promise<VisionResult>;
}

// --- Adapters ---
class MockVisionEngine implements VisionEngine {
  readonly version = 'mock_local_v1';

  async analyzeDocument(url: string, expectedExpiry: string): Promise<VisionResult> {
    console.log(`[MockVisionEngine] Analyzing document at ${url}`);
    
    // 1. Interceptación MIME Hostil (Simulada por extensión de archivo)
    const lowerUrl = url.toLowerCase();
    if (lowerUrl.includes('.heic') || lowerUrl.includes('.tiff') || lowerUrl.includes('.exe')) {
      return {
        isFraud: false, // Un error técnico no es un fraude
        isTechnicalError: true,
        confidence: 0,
        detectedType: 'UNSUPPORTED_MIME',
        detectedExpiry: null,
        rawJson: { mock_reason: 'Unsupported file format detected (e.g. HEIC from iPhone)' }
      };
    }

    // 2. Lógica determinista de fraude:
    const isSuspicious = lowerUrl.includes('random') || lowerUrl.includes('meme') || lowerUrl.includes('fake');
    
    await new Promise(r => setTimeout(r, 1500)); // Simular latencia de red

    if (isSuspicious) {
      return {
        isFraud: true,
        isTechnicalError: false,
        confidence: 0.12,
        detectedType: 'UNKNOWN_IMAGE',
        detectedExpiry: null,
        rawJson: { mock_reason: 'Suspicious filename detected in simulation' }
      };
    }

    // 3. Forensia de Husos Horarios (AEST - Hobart)
    // En una implementación real, parsearíamos la fecha extraída por el OCR.
    // Aquí, asumimos que el OCR extrae correctamente la fecha en formato local de Hobart (UTC+10)
    // y la comparamos contra la esperada.
    
    return {
      isFraud: false,
      isTechnicalError: false,
      confidence: 0.98,
      detectedType: 'INSURANCE_POLICY',
      detectedExpiry: expectedExpiry, // Coincidencia perfecta
      rawJson: { mock_reason: 'Standard validation passed', timezone_context: 'AEST (UTC+10) aligned' }
    };
  }
}

class RealVisionEngine implements VisionEngine {
  readonly version = 'google_cloud_vision_v2';
  async analyzeDocument(url: string, expectedExpiry: string): Promise<VisionResult> {
    throw new Error('RealVisionEngine not implemented for this environment.');
  }
}

const getVisionEngine = (): VisionEngine => {
  const env = Deno.env.get('VISION_ENGINE') || 'mock';
  if (env === 'gcp') return new RealVisionEngine();
  return new MockVisionEngine();
};

// --- Webhook Handler ---
serve(async (req) => {
  try {
    const payload = await req.json();
    console.log('[ocr-auditor] Webhook payload received:', JSON.stringify(payload));

    const record = payload.record;
    if (!record || !record.id || !record.document_path) {
      return new Response(JSON.stringify({ error: 'Invalid payload structure' }), { status: 400 });
    }

    const overrideId = record.id;
    const documentPath = record.document_path;
    const expectedExpiry = record.new_expiry_date;

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const { data: signedUrlData, error: signError } = await supabaseClient
      .storage
      .from('compliance_docs')
      .createSignedUrl(documentPath, 3600);

    if (signError) throw signError;
    const documentUrl = signedUrlData.signedUrl;

    const engine = getVisionEngine();
    const result = await engine.analyzeDocument(documentUrl, expectedExpiry);

    console.log(`[ocr-auditor] Analysis complete: Fraud=${result.isFraud}, TechnicalError=${result.isTechnicalError}, Confidence=${result.confidence}`);

    // Inyectar el veredicto en ocr_audit_logs
    const { error: insertError } = await supabaseClient
      .from('ocr_audit_logs')
      .insert({
        override_id: overrideId,
        vision_model_version: engine.version,
        ocr_confidence_score: result.confidence,
        detected_document_type: result.detectedType,
        detected_expiry_date: result.detectedExpiry,
        is_fraud_flagged: result.isFraud,
        raw_ocr_dump: result.rawJson
      });

    if (insertError) {
      console.error('[ocr-auditor] Error saving audit log:', insertError);
      throw insertError;
    }

    if (result.isFraud) {
      console.warn(`[CRITICAL ALERT] Fraudulent compliance document detected by ${engine.version}. Alerting WHS Manager.`);
      // await fetch('https://n8n.minera.local/webhook/fraud-alert', { ... })
    } else if (result.isTechnicalError) {
      console.info(`[MANUAL AUDIT REQUIRED] Technical error (e.g. HEIC format). Alerting WHS Manager for manual review.`);
    }

    return new Response(JSON.stringify({ status: 'Audited', fraudDetected: result.isFraud, technicalError: result.isTechnicalError }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('[ocr-auditor] Fatal Error:', error);
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
});

-- Schema for OCR Audit Logs
CREATE TABLE IF NOT EXISTS public.ocr_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    override_id UUID NOT NULL REFERENCES public.whs_overrides(id) ON DELETE CASCADE,
    vision_model_version VARCHAR(100) NOT NULL,
    ocr_confidence_score NUMERIC,
    detected_document_type VARCHAR(100),
    detected_expiry_date DATE,
    is_fraud_flagged BOOLEAN NOT NULL DEFAULT false,
    raw_ocr_dump JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- RLS: Solo lectura para roles administrativos, inserción restringida a service_role (Edge Function)
ALTER TABLE public.ocr_audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS view_ocr_logs ON public.ocr_audit_logs;
CREATE POLICY view_ocr_logs ON public.ocr_audit_logs
FOR SELECT USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('super_admin', 'fleet_manager'))
);

DROP POLICY IF EXISTS service_role_insert_ocr_logs ON public.ocr_audit_logs;
CREATE POLICY service_role_insert_ocr_logs ON public.ocr_audit_logs
FOR INSERT WITH CHECK (
    -- Solo el rol service_role (usado por Edge Functions) o admin de DB puede insertar
    current_setting('role') = 'service_role' OR current_setting('role') = 'postgres'
);

-- 20260720000003_ocr_sweeper.sql
-- Auditor del Auditor: Sweeper que envía a la DLQ los registros de whs_overrides que no fueron auditados en 15 minutos

CREATE OR REPLACE FUNCTION audit_the_ocr_auditor()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT wo.id, wo.document_path, wo.override_timestamp, wo.supervisor_id
        FROM public.whs_overrides wo
        LEFT JOIN public.ocr_audit_logs oal ON wo.id = oal.override_id
        WHERE oal.id IS NULL
          AND wo.override_timestamp < (now() - interval '15 minutes')
    LOOP
        -- Inyectamos directamente a la Dead Letter Queue (Alertando Evasión de Auditoría)
        INSERT INTO public.dead_letter_queue (
            original_event_id, 
            event_type, 
            payload, 
            last_error
        ) VALUES (
            r.id,
            'OCR_AUDIT_EVASION',
            jsonb_build_object(
                'supervisor_id', r.supervisor_id,
                'document_path', r.document_path,
                'override_timestamp', r.override_timestamp,
                'message', 'CRITICAL ALERT: WHS Override was never audited by the Vision Edge Function (Timeout or Crash).'
            ),
            'Silent Deno failure or network partition detected.'
        );

        -- Opcional: Podríamos marcar el override en una tabla de estado, 
        -- pero la DLQ ya asegura que n8n despachará la alerta al Manager WHS.
    END LOOP;
END;
$$;

-- Configurar pg_cron para ejecutar el sweeper cada 5 minutos
-- Habilitado solo si pg_cron está disponible (como en produccion/local full)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Desagendar si existía previamente (ignorando errores si no existe)
        BEGIN
            PERFORM cron.unschedule('audit_the_ocr_auditor_job');
        EXCEPTION WHEN OTHERS THEN
            -- Ignorar si no existe
        END;
        
        -- Agendar
        PERFORM cron.schedule('audit_the_ocr_auditor_job', '*/5 * * * *', 'SELECT audit_the_ocr_auditor();');
    END IF;
END $$;

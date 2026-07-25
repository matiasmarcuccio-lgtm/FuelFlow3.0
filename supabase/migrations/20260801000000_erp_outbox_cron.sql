-- 1. Despertar extensiones de red y cron
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- 2. Forjar la Cola de Mensajes Muertos (DLQ / Outbox)
CREATE TABLE public.erp_outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    certificate_id UUID REFERENCES public.execution_certificates(id) NOT NULL UNIQUE,
    payload JSONB NOT NULL,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'dead_letter')),
    retry_count INT DEFAULT 0,
    next_retry_at TIMESTAMPTZ DEFAULT now(),
    last_error TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Inyectar facturas al Outbox en el momento de creación del certificado
CREATE OR REPLACE FUNCTION public.queue_erp_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.erp_outbox (certificate_id, payload)
    VALUES (
        NEW.id,
        jsonb_build_object(
            'event', 'billing.certificate.generated',
            'certificate_id', NEW.id,
            'total_billable', NEW.total_billable,
            'total_hours', NEW.total_hours,
            'forensic_hash', NEW.forensic_pdf_hash,
            'timestamp', now()
        )
    );
    RETURN NEW;
END;
$$;

-- Disparar solo cuando el certificado es sellado criptográficamente por Deno
CREATE TRIGGER trg_enqueue_outbox
AFTER UPDATE OF forensic_pdf_hash ON public.execution_certificates
FOR EACH ROW
WHEN (OLD.forensic_pdf_hash IS NULL AND NEW.forensic_pdf_hash IS NOT NULL)
EXECUTE FUNCTION public.queue_erp_outbox();

-- 4. El Marcapasos: pg_cron ejecutando cada 1 minuto
SELECT cron.schedule(
    'process_erp_outbox_heartbeat',
    '* * * * *',
    $$
    SELECT net.http_post(
        url := current_setting('app.settings.edge_function_outbox_url'),
        headers := jsonb_build_object(
            'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
            'Content-Type', 'application/json'
        ),
        body := '{}'::jsonb
    );
    $$
);
